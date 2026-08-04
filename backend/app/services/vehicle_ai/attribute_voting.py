"""Araç özniteliği (kasa tipi / renk / plaka) oylaması — FTR'deki mantığın korunmuş hali.

Tek bir karedeki tahmine güvenilmez; araç kameradan çıkana kadar tahminler
biriktirilip oylanır. Her öznitelik için oylama yöntemi farklıdır ve bu fark
bilinçlidir (FTR raporunda gerekçelendirilmiş):

- **Kasa tipi:** güven skorlarının KÜMÜLATİF TOPLAMI en yüksek olan kazanır.
- **Renk:** en sık tekrar eden (mod) kazanır.
- **Plaka:** her okuma güven skoruyla ağırlıklandırılıp toplanır; eşik skoru
  aşan ilk plaka kesinleşir ve o araç için okuma durur.

Kesinleşen öznitelik bir daha hesaplanmaz ("erken çıkış") — hem işlem yükünü
azaltır hem de sonradan gelen gürültülü karelerin sonucu bozmasını engeller.
"""

from collections import Counter

from app.services.vehicle_ai.thresholds import DetectionThresholds


class VehicleAttributeVoting:
    def __init__(self, thresholds: DetectionThresholds) -> None:
        self._t = thresholds
        self._kasa_oylari: list[tuple[str, float]] = []
        self._renk_oylari: list[tuple[str, float]] = []
        self._plaka_oylari: dict[str, float] = {}

        self.kasa: str | None = None
        self.renk: str | None = None
        self.plaka: str | None = None
        self.guven: dict[str, float] = {}

    # --- Kesinleşme durumu (erken çıkış kontrolü) ---
    @property
    def kasa_kesinlesti(self) -> bool:
        return self.kasa is not None

    @property
    def renk_kesinlesti(self) -> bool:
        return self.renk is not None

    @property
    def plaka_kesinlesti(self) -> bool:
        return self.plaka is not None

    @property
    def hepsi_kesinlesti(self) -> bool:
        return self.kasa_kesinlesti and self.renk_kesinlesti and self.plaka_kesinlesti

    # --- Oy ekleme ---
    def kasa_oyu_ekle(self, tip: str, confidence: float) -> None:
        if self.kasa_kesinlesti or confidence <= self._t.kasa_min_conf:
            return
        if len(self._kasa_oylari) < self._t.kasa_oy_sayisi:
            self._kasa_oylari.append((tip, confidence))
        if len(self._kasa_oylari) >= self._t.kasa_oy_sayisi:
            skorlar: dict[str, float] = {}
            for t, c in self._kasa_oylari:
                skorlar[t] = skorlar.get(t, 0.0) + c
            kazanan = max(skorlar, key=skorlar.get)
            kazanan_confler = [c for t, c in self._kasa_oylari if t == kazanan]
            self.kasa = kazanan
            self.guven["kasa"] = sum(kazanan_confler) / len(kazanan_confler)

    def renk_oyu_ekle(self, renk: str, confidence: float) -> None:
        if self.renk_kesinlesti or confidence <= self._t.renk_min_conf:
            return
        self._renk_oylari.append((renk, confidence))
        if len(self._renk_oylari) > self._t.renk_oy_sayisi:
            kazanan = Counter(r for r, _ in self._renk_oylari).most_common(1)[0][0]
            kazanan_confler = [c for r, c in self._renk_oylari if r == kazanan]
            self.renk = kazanan
            self.guven["renk"] = sum(kazanan_confler) / len(kazanan_confler)
            self._renk_oylari.clear()

    def plaka_oyu_ekle(self, plaka: str, confidence: float) -> None:
        if self.plaka_kesinlesti:
            return
        self._plaka_oylari[plaka] = self._plaka_oylari.get(plaka, 0.0) + confidence
        en_iyi = max(self._plaka_oylari, key=self._plaka_oylari.get)
        if self._plaka_oylari[en_iyi] >= self._t.plaka_min_skor:
            self.plaka = en_iyi
            self.guven["plaka"] = confidence

    def genel_guven(self) -> float:
        """FTR çıktısındaki `arac_bilgisi.confidence_score` — üç özniteliğin ortalaması."""
        toplam = self.guven.get("kasa", 0.0) + self.guven.get("renk", 0.0) + self.guven.get("plaka", 0.0)
        return round(toplam / 3.0, 2)
