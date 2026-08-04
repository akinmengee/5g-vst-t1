"""VehicleAnalysisService'in gerçek implementasyonu — canlı ROI akışı üzerinde çalışır.

FTR'deki `predict.py` bir video dosyasını baştan sona okuyup **sonunda** tek bir
JSON üretiyordu. Burada aynı yapay zekâ mantığı, mobilden gelen her ROI'de durumu
güncelleyen ve kesinleşen tespitleri **anında** yayınlayan bir akışa dönüştürüldü.

Girdi, tam kare değil; mobilin (edge `yolov8n`) tespit edip kırptığı araç ROI'sidir.
Bu yüzden buradaki modeller doğrudan ROI üzerinde çalışır — FTR'de araç kutusunu
bulmak için harcanan tam-kare taraması artık uçta yapılmış durumdadır.

Slalom bir istisnadır: aracın gerçek yatay hareketini ölçtüğü için kırpılmış
görüntüden hesaplanamaz; mobilin gönderdiği **tam kareye göre bbox koordinatları**
kullanılır.
"""

import logging

import cv2
import numpy as np

from app.schemas.detection import AracBilgisi, Tespit
from app.schemas.mobile_contract import MobileRoiPayload
from app.services.vehicle_ai import vision_ops
from app.services.vehicle_ai.interface import VehicleAnalysisResult
from app.services.vehicle_ai.model_registry import ModelRegistry
from app.services.vehicle_ai.session import SessionRegistry, SessionState
from app.services.vehicle_ai.streaming.events import DetectedEvent
from app.services.vehicle_ai.thresholds import DetectionThresholds, thresholds

logger = logging.getLogger(__name__)

VARSAYILAN_TIP = "sedan"
VARSAYILAN_RENK = "beyaz"


class CurrentModelService:
    def __init__(
        self,
        registry: ModelRegistry | None = None,
        detection_thresholds: DetectionThresholds | None = None,
    ) -> None:
        self._t = detection_thresholds or thresholds
        self._models = registry or ModelRegistry()
        self._sessions = SessionRegistry(self._t)

    # ------------------------------------------------------------------ public

    def process_roi(self, payload: MobileRoiPayload, image_bytes: bytes) -> VehicleAnalysisResult:
        frame = self._decode(image_bytes)
        if frame is None:
            logger.warning("ROI görüntüsü çözülemedi (session=%s)", payload.session_id)
            return VehicleAnalysisResult()

        session = self._sessions.get(payload.session_id)
        session.roi_sayaci += 1
        zaman = session.rolatif_zaman(payload.timestamp)

        self._arac_ozellikleri(session, frame)
        self._slalom(session, payload, zaman)
        self._kabin_analizi(session, frame, zaman)
        self._nesneler(session, frame, zaman)
        self._yolcular(session, frame, zaman)

        yayinlananlar = session.gate.drain(zaman)
        session.yayinlanan_olaylar.extend(yayinlananlar)

        return VehicleAnalysisResult(
            tespitler=[self._to_tespit(e) for e in yayinlananlar],
            arac_bilgisi_guncelleme=self._arac_bilgisi(session),
        )

    def finalize_session(self, session_id: str) -> VehicleAnalysisResult:
        """Akış bitti: açık bloklardaki bekleyen olayları boşaltır ve nihai sonucu verir."""
        session = self._sessions.close(session_id)
        if session is None:
            return VehicleAnalysisResult()

        for dedektor in session.aksiyon_dedektorleri.values():
            self._submit(session, dedektor.finalize())
        self._submit(session, session.esneme.finalize())
        self._submit(session, session.bakinma.finalize())

        yayinlananlar = session.gate.flush()
        session.yayinlanan_olaylar.extend(yayinlananlar)

        # Kemer global fail-safe: kemer video boyunca yeterince net görüldüyse,
        # daha önce yayınlanmış ihlal olayı nihai çıktıdan düşülür (FTR davranışı).
        tespitler = [
            self._to_tespit(e)
            for e in yayinlananlar
            if not (e.etiket == "emniyet_kemeri_ihlali" and session.kemer.suppressed)
        ]
        return VehicleAnalysisResult(
            tespitler=tespitler,
            arac_bilgisi_guncelleme=self._arac_bilgisi(session),
        )

    def nihai_arac_bilgisi(self, session: SessionState) -> AracBilgisi:
        """FTR çıktısı için araç bilgisi; kesinleşmeyen alanlar varsayılana düşer."""
        oylama = session.oylama
        return AracBilgisi(
            tip=oylama.kasa or VARSAYILAN_TIP,
            plaka=oylama.plaka or "",
            renk=oylama.renk or VARSAYILAN_RENK,
            confidence_score=oylama.genel_guven(),
        )

    # ------------------------------------------------------------ analiz adımları

    def _arac_ozellikleri(self, session: SessionState, frame: np.ndarray) -> None:
        oylama = session.oylama
        if oylama.hepsi_kesinlesti:
            return  # erken çıkış: tüm öznitelikler kesinleşti, model çalıştırma

        sayac = session.roi_sayaci

        if not oylama.kasa_kesinlesti and sayac % self._t.kasa_analiz_frekansi == 0:
            if frame.shape[1] > self._t.kasa_min_genislik:
                self._siniflandir(frame, "kasa", oylama.kasa_oyu_ekle)

        if not oylama.renk_kesinlesti and sayac % self._t.renk_analiz_frekansi == 0:
            self._siniflandir(frame, "renk", oylama.renk_oyu_ekle)

        if not oylama.plaka_kesinlesti and sayac % self._t.plaka_analiz_frekansi == 0:
            self._plaka_oku(session, frame)

    def _siniflandir(self, frame: np.ndarray, model_adi: str, oy_ekle) -> None:
        model = self._models.yolo(model_adi)
        if model is None:
            return
        try:
            sonuc = model(frame, verbose=False)[0]
            etiket = sonuc.names[sonuc.probs.top1].lower().strip()
            oy_ekle(etiket, float(sonuc.probs.top1conf.item()))
        except Exception:
            logger.exception("%s sınıflandırması başarısız", model_adi)

    def _plaka_oku(self, session: SessionState, frame: np.ndarray) -> None:
        plaka_model = self._models.yolo("plaka")
        karakter_model = self._models.yolo("karakter")
        if plaka_model is None or karakter_model is None:
            return

        try:
            sonuc = plaka_model(frame, conf=self._t.plaka_dedektor_conf, verbose=False)[0]
            for kutu in sonuc.boxes:
                px1, py1, px2, py2 = (int(v) for v in kutu.xyxy[0])
                kirpim = frame[py1:py2, px1:px2]
                if kirpim.size == 0 or kirpim.shape[1] < self._t.plaka_min_genislik:
                    continue

                duzeltilmis = vision_ops.warp_plate(kirpim)
                karakterler = karakter_model(
                    duzeltilmis, conf=self._t.plaka_karakter_conf, iou=0.50, verbose=False
                )[0]

                bulunanlar = [
                    (int(c.xyxy[0][0]), karakterler.names[int(c.cls)].upper(), float(c.conf[0]))
                    for c in karakterler.boxes
                ]
                if len(bulunanlar) < 4:
                    continue

                bulunanlar.sort(key=lambda x: x[0])
                metin = "".join(k[1] for k in bulunanlar)
                metin = metin.replace("EUR", "").replace("BRASIL", "")
                metin = vision_ops.correct_plate(metin)
                ortalama_guven = sum(k[2] for k in bulunanlar) / len(bulunanlar)

                if len(metin) >= 6 and vision_ops.PLATE_PATTERN.fullmatch(metin):
                    session.oylama.plaka_oyu_ekle(metin, ortalama_guven)
        except Exception:
            logger.exception("Plaka okuma başarısız")

    def _slalom(self, session: SessionState, payload: MobileRoiPayload, zaman: float) -> None:
        if session.slalom_bildirildi or self._models.slalom is None:
            return

        bbox = payload.bbox
        merkez_x = (bbox.x1 + bbox.x2) / 2
        genislik = max(bbox.x2 - bbox.x1, 1)
        session.slalom_yorungesi.append((merkez_x, genislik))
        if len(session.slalom_yorungesi) > self._t.slalom_min_ornek * 2:
            session.slalom_yorungesi.pop(0)

        try:
            slalom_var, guven = vision_ops.check_slalom(
                self._models.slalom,
                self._models.device,
                session.slalom_yorungesi,
                min_ornek=self._t.slalom_min_ornek,
                prob_esik=self._t.slalom_prob_esik,
                min_hareket=self._t.slalom_min_hareket,
            )
        except Exception:
            logger.exception("Slalom değerlendirmesi başarısız")
            return

        if not slalom_var:
            return

        session.slalom_ardisik += 1
        if session.slalom_ardisik >= self._t.slalom_gerek:
            session.slalom_bildirildi = True
            self._submit(
                session,
                DetectedEvent(zaman, "sofor_eylemi", "slalom", guven),
            )

    def _kabin_analizi(self, session: SessionState, frame: np.ndarray, zaman: float) -> None:
        kabin = vision_ops.kabin_kirp(
            self._models.yolo("detector"), frame, self._t.kisi_conf
        )
        sofor_var = kabin is not None

        aksiyon_esikleri = {
            "sigara": self._t.sigara_conf,
            "telefon": self._t.telefon_conf,
            "su": self._t.su_conf,
        }
        for ad, dedektor in session.aksiyon_dedektorleri.items():
            guven = None
            if sofor_var:
                skor = vision_ops.yolo_bul(
                    self._models.yolo(ad), kabin, aksiyon_esikleri[ad], tek_sinif0=(ad == "telefon")
                )
                guven = skor if skor > 0 else None
            self._submit(session, dedektor.observe(zaman, guven))

        kemer_guven = None
        if sofor_var:
            skor = vision_ops.yolo_bul(self._models.yolo("kemer"), kabin, self._t.kemer_conf)
            kemer_guven = skor if skor > 0 else None
        self._submit(session, session.kemer.observe(zaman, sofor_var, kemer_guven))

        if not sofor_var:
            return

        mar = vision_ops.esneme_mar(self._models.face_landmarker, kabin)
        self._submit(session, session.esneme.observe(zaman, mar))

        offset = vision_ops.bakinma_olc(self._models.yolo("poz"), kabin)
        self._submit(session, session.bakinma.observe(zaman, offset))

    def _nesneler(self, session: SessionState, frame: np.ndarray, zaman: float) -> None:
        self._nesne_ara(
            session, frame, zaman,
            model=self._models.yolo("teknocan"),
            etiket="teknocan",
            conf=self._t.teknocan_conf,
            gerek=self._t.teknocan_gerek,
        )
        self._laptop_ara(session, frame, zaman)

    def _nesne_ara(self, session, frame, zaman, model, etiket, conf, gerek) -> None:
        if model is None or etiket in session.nesne_bildirildi:
            return
        try:
            sonuc = model(frame, conf=conf, verbose=False)[0]
        except Exception:
            logger.exception("%s tespiti başarısız", etiket)
            return

        if len(sonuc.boxes) == 0:
            session.nesne_sayaclari[etiket] = 0
            return

        en_iyi = max(float(b.conf[0]) for b in sonuc.boxes)
        session.nesne_sayaclari[etiket] = session.nesne_sayaclari.get(etiket, 0) + 1
        if session.nesne_sayaclari[etiket] >= gerek:
            session.nesne_bildirildi.add(etiket)
            self._submit(session, DetectedEvent(zaman, "nesneler", etiket, en_iyi))

    def _laptop_ara(self, session: SessionState, frame: np.ndarray, zaman: float) -> None:
        """Dizüstü bilgisayar, ayrı bir model yerine COCO sınıf 63 ile tespit edilir."""
        etiket = "bilgisayar"
        model = self._models.yolo("detector")
        if model is None or etiket in session.nesne_bildirildi:
            return
        try:
            sonuc = model(frame, classes=[63], conf=self._t.arac_conf, verbose=False)[0]
        except Exception:
            logger.exception("Bilgisayar tespiti başarısız")
            return

        if len(sonuc.boxes) == 0:
            session.nesne_sayaclari[etiket] = 0
            return

        en_iyi = max(float(b.conf[0]) for b in sonuc.boxes)
        session.nesne_sayaclari[etiket] = session.nesne_sayaclari.get(etiket, 0) + 1
        if session.nesne_sayaclari[etiket] >= self._t.bilgisayar_gerek:
            session.nesne_bildirildi.add(etiket)
            self._submit(session, DetectedEvent(zaman, "nesneler", etiket, en_iyi))

    def _yolcular(self, session: SessionState, frame: np.ndarray, zaman: float) -> None:
        model = self._models.yolo("detector")
        if model is None:
            return
        try:
            sonuc = model(frame, classes=[0], conf=0.05, verbose=False)[0]
        except Exception:
            logger.exception("Yolcu tespiti başarısız")
            return

        h, w = frame.shape[:2]
        kisiler = []
        for kutu in sonuc.boxes:
            kx1, ky1, kx2, ky2 = (float(v) for v in kutu.xyxy[0])
            alan = (kx2 - kx1) * (ky2 - ky1)
            if alan <= 0:
                continue
            kisiler.append(
                {
                    "conf": float(kutu.conf[0]),
                    "merkez_x": (kx1 + kx2) / 2,
                    "alt_y": ky2,
                    "alan": alan,
                }
            )
        if not kisiler:
            return

        # ROI aracın kendisi olduğu için araç kutusu = tüm görüntü
        arac_orta = w / 2
        sofor_adaylari = [k for k in kisiler if k["merkez_x"] > arac_orta] or kisiler
        sofor = max(sofor_adaylari, key=lambda k: k["alan"])

        arka_sayac = 0
        for kisi in kisiler:
            if kisi is sofor:
                continue
            ust_oran = kisi["alt_y"] / h if h > 0 else 1.0
            kucuk = kisi["alan"] < sofor["alan"] * 0.6
            if ust_oran < 0.55 and kucuk:
                arka_sayac += 1
                koltuk = f"arka_koltuk_{min(arka_sayac, 2)}"
            else:
                koltuk = "on_koltuk"

            session.yolcu_gorulme[koltuk] = session.yolcu_gorulme.get(koltuk, 0) + 1
            session.yolcu_guven[koltuk] = max(session.yolcu_guven.get(koltuk, 0.0), kisi["conf"])
            if session.yolcu_gorulme[koltuk] == 1:
                self._submit(
                    session, DetectedEvent(zaman, "yolcular", koltuk, session.yolcu_guven[koltuk])
                )

    # ----------------------------------------------------------------- yardımcı

    @staticmethod
    def _decode(image_bytes: bytes) -> np.ndarray | None:
        buffer = np.frombuffer(image_bytes, dtype=np.uint8)
        if buffer.size == 0:
            return None
        return cv2.imdecode(buffer, cv2.IMREAD_COLOR)

    @staticmethod
    def _submit(session: SessionState, event: DetectedEvent | None) -> None:
        if event is not None:
            session.gate.submit(event)

    @staticmethod
    def _to_tespit(event: DetectedEvent) -> Tespit:
        return Tespit(
            zaman_saniye=round(event.zaman_saniye, 1),
            kategori=event.kategori,
            etiket=event.etiket,
            confidence_score=round(event.confidence_score, 2),
        )

    def _arac_bilgisi(self, session: SessionState) -> AracBilgisi | None:
        oylama = session.oylama
        if not (oylama.kasa_kesinlesti or oylama.renk_kesinlesti or oylama.plaka_kesinlesti):
            return None
        return AracBilgisi(
            tip=oylama.kasa or VARSAYILAN_TIP,
            plaka=oylama.plaka or "",
            renk=oylama.renk or VARSAYILAN_RENK,
            confidence_score=oylama.genel_guven(),
        )
