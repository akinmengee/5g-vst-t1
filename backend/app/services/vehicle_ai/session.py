"""Oturum durumu ve oturum kayıt defteri.

Bir "oturum" = mobil istemcinin tek bir araç için açtığı ROI akışı (`session_id`).
Tüm zamansal durum (dedektörler, oylamalar, slalom yörüngesi) burada tutulur.

**Kod İncelemesi Bulguları madde 5'in çözümü:** FTR'deki sözlükler hiç
temizlenmiyordu; tek videoluk çalıştırmada sorun değildi ama sürekli çalışan
serviste bellek sızıntısına dönüşürdü. `SessionRegistry` artık belirli süre
sessiz kalan oturumları düşürür.
"""

import time

from app.services.vehicle_ai.attribute_voting import VehicleAttributeVoting
from app.services.vehicle_ai.streaming.event_gate import EventGate
from app.services.vehicle_ai.streaming.run_detectors import (
    ConsecutiveRunDetector,
    HeadTurnDetector,
    SeatbeltDetector,
    YawnDetector,
)
from app.services.vehicle_ai.thresholds import DetectionThresholds

AKSIYON_ETIKETLERI = {
    "sigara": "sigara_icme",
    "telefon": "telefonla_konusma",
    "su": "su_icme",
}


class SessionState:
    def __init__(self, session_id: str, thresholds: DetectionThresholds, ornekleme_araligi: float) -> None:
        self.session_id = session_id
        self._t = thresholds
        self.son_erisim = time.monotonic()

        self.baslangic_timestamp: float | None = None
        self.roi_sayaci = 0

        self.oylama = VehicleAttributeVoting(thresholds)

        self.aksiyon_dedektorleri = {
            ad: ConsecutiveRunDetector("sofor_eylemi", etiket, thresholds.ardisik_gerek)
            for ad, etiket in AKSIYON_ETIKETLERI.items()
        }
        self.esneme = YawnDetector(
            oran_esik=thresholds.mar_oran_esik,
            plato_gerek=thresholds.mar_plato_gerek,
            hareket_esik=thresholds.mar_hareket_esik,
            baseline_min_ornek=thresholds.mar_baseline_min_ornek,
        )
        self.bakinma = HeadTurnDetector(
            donuk_offset=thresholds.donuk_offset,
            t_arkaya=thresholds.t_arkaya,
            t_etrafa_min=thresholds.t_etrafa_min,
            ornekleme_araligi=ornekleme_araligi,
        )
        self.kemer = SeatbeltDetector(
            kemer_gerek=thresholds.kemer_gerek,
            fail_safe_gorulme=thresholds.kemer_fail_safe_gorulme,
        )
        self.gate = EventGate(
            cooldown_saniye=thresholds.cooldown_saniye,
            cakisma_marji_saniye=thresholds.cakisma_marji_saniye,
        )

        # Slalom: (merkez_x, arac_genisligi) — tam kareye göre koordinatlar
        self.slalom_yorungesi: list[tuple[float, float]] = []
        self.slalom_ardisik = 0
        self.slalom_bildirildi = False

        # Nesne tespitleri (teknocan / bilgisayar) — ardışık görülme sayaçları
        self.nesne_sayaclari: dict[str, int] = {}
        self.nesne_bildirildi: set[str] = set()

        # Yolcular: koltuk → (görülme sayısı, en yüksek güven)
        self.yolcu_gorulme: dict[str, int] = {}
        self.yolcu_guven: dict[str, float] = {}

        self.yayinlanan_olaylar: list = []

    def dokun(self) -> None:
        self.son_erisim = time.monotonic()

    def rolatif_zaman(self, timestamp: float) -> float:
        """Oturum başlangıcına göre saniye — FTR çıktısındaki `zaman_saniye` bununla üretilir."""
        if self.baslangic_timestamp is None:
            self.baslangic_timestamp = timestamp
        return round(timestamp - self.baslangic_timestamp, 2)


class SessionRegistry:
    def __init__(self, thresholds: DetectionThresholds, ornekleme_araligi: float = 0.25) -> None:
        self._t = thresholds
        self._ornekleme_araligi = ornekleme_araligi
        self._sessions: dict[str, SessionState] = {}

    def get(self, session_id: str) -> SessionState:
        self._evict_expired()
        session = self._sessions.get(session_id)
        if session is None:
            session = SessionState(session_id, self._t, self._ornekleme_araligi)
            self._sessions[session_id] = session
        session.dokun()
        return session

    def close(self, session_id: str) -> SessionState | None:
        return self._sessions.pop(session_id, None)

    def _evict_expired(self) -> None:
        simdi = time.monotonic()
        suresi_dolan = [
            sid
            for sid, s in self._sessions.items()
            if simdi - s.son_erisim > self._t.oturum_ttl_saniye
        ]
        for sid in suresi_dolan:
            del self._sessions[sid]

    def __len__(self) -> int:
        return len(self._sessions)
