"""`CurrentModelService`'in ROI akışı mantığını sahte modellerle uçtan uca doğrular.

Gerçek modellerle yapılan bir testte "tespit yok" sonucu belirsizdir (mantık mı
bozuk, görüntüde gerçekten bir şey mi yok?). Burada modeller sabit sonuç döndüren
stub'larla değiştirilir, böylece beklenen tespitin ÇIKMASI gerektiği kesindir.
"""

import base64
import time
import uuid

import cv2
import numpy as np
import pytest

from app.schemas.mobile_contract import BBox, MobileRoiPayload
from app.services.vehicle_ai.current_model_service import CurrentModelService
from app.services.vehicle_ai.thresholds import DetectionThresholds
from tests import stubs


def _payload(session_id: str, seq: int, timestamp: float, x_kayma: int = 0) -> tuple:
    img = np.full((200, 300, 3), 128, dtype=np.uint8)
    ok, buf = cv2.imencode(".jpg", img)
    assert ok
    image_bytes = buf.tobytes()
    payload = MobileRoiPayload(
        session_id=session_id,
        sequence_number=seq,
        timestamp=timestamp,
        bbox=BBox(
            x1=500 + x_kayma, y1=300, x2=800 + x_kayma, y2=500,
            frame_width=1280, frame_height=720,
        ),
        mobile_confidence=0.9,
        image_format="jpeg",
        image_base64=base64.b64encode(image_bytes).decode("ascii"),
    )
    return payload, image_bytes


def _servis(models: dict, **registry_kwargs) -> CurrentModelService:
    registry = stubs.StubRegistry(models=models, **registry_kwargs)
    return CurrentModelService(registry=registry, detection_thresholds=DetectionThresholds())


def test_telefon_ardisik_iki_karede_tespit_edilir():
    """`ardisik_gerek=2`: telefon iki ardışık ROI'de görülür, üçüncüde kaybolur →
    blok kapanır ve `telefonla_konusma` tespiti yayınlanır."""
    telefon_var = stubs.StubDetectionModel(stubs.StubResult(boxes=[stubs.StubBox(0.88, cls=0)]))
    telefon_yok = stubs.StubDetectionModel(stubs.StubResult(boxes=[]))

    servis = _servis({"detector": stubs.kisi_iceren_detector(), "telefon": telefon_var})
    sid = str(uuid.uuid4())
    t0 = time.time()

    tespitler = []
    for seq in (1, 2):
        payload, img = _payload(sid, seq, t0 + seq * 0.25)
        tespitler.extend(servis.process_roi(payload, img).tespitler)

    # Telefon artık görünmüyor → blok kapanır ve olay bu ROI'nin cevabında yayınlanır
    servis._models._models["telefon"] = telefon_yok
    payload, img = _payload(sid, 3, t0 + 0.75)
    tespitler.extend(servis.process_roi(payload, img).tespitler)
    tespitler.extend(servis.finalize_session(sid).tespitler)

    assert "telefonla_konusma" in [t.etiket for t in tespitler]

    tespit = next(t for t in tespitler if t.etiket == "telefonla_konusma")
    assert tespit.kategori == "sofor_eylemi"
    assert tespit.confidence_score == pytest.approx(0.88, abs=0.01)


def test_tek_karelik_tespit_olay_uretmez():
    """Tek karelik gürültü (`ardisik_gerek=2` altında) tespit sayılmamalı."""
    telefon_var = stubs.StubDetectionModel(stubs.StubResult(boxes=[stubs.StubBox(0.9, cls=0)]))
    telefon_yok = stubs.StubDetectionModel(stubs.StubResult(boxes=[]))

    servis = _servis({"detector": stubs.kisi_iceren_detector(), "telefon": telefon_var})
    sid = str(uuid.uuid4())
    t0 = time.time()

    tespitler = []
    payload, img = _payload(sid, 1, t0)
    tespitler.extend(servis.process_roi(payload, img).tespitler)

    servis._models._models["telefon"] = telefon_yok
    payload, img = _payload(sid, 2, t0 + 0.25)
    tespitler.extend(servis.process_roi(payload, img).tespitler)
    tespitler.extend(servis.finalize_session(sid).tespitler)

    assert "telefonla_konusma" not in [t.etiket for t in tespitler]


def test_renk_oylamasi_kesinlesince_arac_bilgisi_doner():
    """Renk modeli `renk_oy_sayisi`den fazla tutarlı oy verince renk kesinleşir."""
    servis = _servis(
        {
            "detector": stubs.bos_detector(),
            "renk": stubs.StubClassifierModel("kirmizi", 0.93),
        }
    )
    sid = str(uuid.uuid4())
    t0 = time.time()

    sonuc = None
    for seq in range(1, 25):
        payload, img = _payload(sid, seq, t0 + seq * 0.25)
        sonuc = servis.process_roi(payload, img)

    assert sonuc.arac_bilgisi_guncelleme is not None
    assert sonuc.arac_bilgisi_guncelleme.renk == "kirmizi"


def test_kasa_kesinlesince_model_bir_daha_calistirilmaz():
    """Erken çıkış: öznitelik kesinleştikten sonra ilgili model çağrılmamalı."""
    kasa_model = stubs.StubClassifierModel("suv", 0.95)
    servis = _servis({"detector": stubs.bos_detector(), "kasa": kasa_model})
    sid = str(uuid.uuid4())
    t0 = time.time()

    for seq in range(1, 90):
        payload, img = _payload(sid, seq, t0 + seq * 0.25)
        servis.process_roi(payload, img)

    session = servis._sessions.get(sid)
    assert session.oylama.kasa == "suv"
    # 5 oy toplandıktan sonra çağrı durmalı (frekans 15 → en fazla 5 çağrı)
    assert kasa_model.cagri_sayisi == 5


def test_yolcu_tespiti_yayinlanir():
    """ROI'de şoför dışında ikinci bir kişi varsa yolcu tespiti üretilir."""
    h, w = 200, 300
    sofor = stubs.StubBox(0.9, cls=0, xyxy=(w * 0.55, h * 0.2, w * 0.95, h * 0.95))
    yolcu = stubs.StubBox(0.7, cls=0, xyxy=(w * 0.05, h * 0.1, w * 0.30, h * 0.45))
    detector = stubs.StubDetectionModel(stubs.StubResult(boxes=[sofor, yolcu]))

    servis = _servis({"detector": detector})
    sid = str(uuid.uuid4())
    payload, img = _payload(sid, 1, time.time())
    sonuc = servis.process_roi(payload, img)

    yolcu_tespitleri = [t for t in sonuc.tespitler if t.kategori == "yolcular"]
    assert len(yolcu_tespitleri) == 1
    assert yolcu_tespitleri[0].etiket in {"arka_koltuk_1", "arka_koltuk_2", "on_koltuk"}


def test_ayni_etiket_yalnizca_bir_kez_yayinlanir():
    """Etiket başına maksimum olay sınırı (FTR çıktı kuralı) korunmalı."""
    h, w = 200, 300
    sofor = stubs.StubBox(0.9, cls=0, xyxy=(w * 0.55, h * 0.2, w * 0.95, h * 0.95))
    yolcu = stubs.StubBox(0.7, cls=0, xyxy=(w * 0.05, h * 0.1, w * 0.30, h * 0.45))
    detector = stubs.StubDetectionModel(stubs.StubResult(boxes=[sofor, yolcu]))

    servis = _servis({"detector": detector})
    sid = str(uuid.uuid4())
    t0 = time.time()

    toplam = []
    for seq in range(1, 20):
        payload, img = _payload(sid, seq, t0 + seq * 0.5)
        toplam.extend(servis.process_roi(payload, img).tespitler)

    yolcu_olaylari = [t for t in toplam if t.kategori == "yolcular"]
    assert len(yolcu_olaylari) == 1


def test_bozuk_goruntu_cokmeye_yol_acmaz():
    servis = _servis({"detector": stubs.bos_detector()})
    payload, _ = _payload(str(uuid.uuid4()), 1, time.time())
    sonuc = servis.process_roi(payload, b"bu-gecerli-bir-jpeg-degil")
    assert sonuc.tespitler == []


def test_eksik_modeller_servisi_dusurmez():
    """Hiçbir model yüklenememişse bile servis çalışmaya devam etmeli
    (Kod İncelemesi Bulguları madde 2)."""
    servis = _servis({})
    sid = str(uuid.uuid4())
    payload, img = _payload(sid, 1, time.time())
    sonuc = servis.process_roi(payload, img)
    assert sonuc.tespitler == []
    assert servis.finalize_session(sid).tespitler == []


def test_oturum_ttl_ile_dusurulur():
    """Sessiz kalan oturumlar hafızadan düşürülmeli (bellek sızıntısı düzeltmesi)."""
    esikler = DetectionThresholds(oturum_ttl_saniye=0.05)
    servis = CurrentModelService(
        registry=stubs.StubRegistry(models={"detector": stubs.bos_detector()}),
        detection_thresholds=esikler,
    )
    sid = str(uuid.uuid4())
    payload, img = _payload(sid, 1, time.time())
    servis.process_roi(payload, img)
    assert len(servis._sessions) == 1

    time.sleep(0.1)
    yeni_sid = str(uuid.uuid4())
    payload, img = _payload(yeni_sid, 1, time.time())
    servis.process_roi(payload, img)

    assert len(servis._sessions) == 1  # eski oturum düşürüldü
