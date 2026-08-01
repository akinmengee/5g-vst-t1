from dataclasses import dataclass


@dataclass(frozen=True)
class DetectedEvent:
    """Bir dedektörün ürettiği ham olay (henüz cooldown/çakışma filtresinden geçmemiş).

    `zaman_saniye` olayın gerçekleştiği an; dedektörler bunu genelde bir olay
    bloğunun ortası olarak hesaplar. Bu yüzden olaylar, gerçekleştikleri andan
    biraz SONRA üretilir — sıralama `EventGate` tarafından düzeltilir.
    """

    zaman_saniye: float
    kategori: str
    etiket: str
    confidence_score: float
