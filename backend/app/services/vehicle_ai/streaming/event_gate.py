"""Olay kapısı: dedektörlerden çıkan ham olayları nihai tespitlere dönüştürür.

FTR'deki `predict.py` bu üç adımı video bittikten sonra topluca uyguluyordu:
  1. Çakışma önleme — `etrafa_bakinma`, ±1.5 sn içinde sigara/su içme varsa silinir.
  2. Sıralama + 3 saniyelik cooldown (aynı etiketin tekrarları bastırılır).
  3. Etiket başına maksimum olay sayısı sınırı.

Canlı akışta "gelecek" bilinmediği için çakışma önleme **sınırlı ileri-bakış**
(bounded lookahead) ile yapılır: `etrafa_bakinma` olayları kısa süre tamponda
bekletilir; bu pencerede çakışan bir olay gelirse yayınlanmaz. Diğer olaylar
beklemeden geçer, böylece gereksiz gecikme oluşmaz.

Ayrıca dedektörler olayları blok kapanınca ürettiği için olaylar zaman sırasında
gelmeyebilir; tampon bunları yayınlamadan önce zamana göre sıralar.
"""

from app.services.vehicle_ai.streaming.events import DetectedEvent

CAKISMAYA_TABI = {"etrafa_bakinma"}
CAKISMA_KAYNAKLARI = {"sigara_icme", "su_icme"}


class EventGate:
    def __init__(
        self,
        cooldown_saniye: float,
        cakisma_marji_saniye: float,
        etiket_basina_max_olay: int = 1,
        ek_bekleme_payi: float = 1.0,
    ) -> None:
        self._cooldown = cooldown_saniye
        self._cakisma_marji = cakisma_marji_saniye
        self._max_olay = etiket_basina_max_olay
        self._lookahead = cakisma_marji_saniye + ek_bekleme_payi

        self._pending: list[DetectedEvent] = []
        self._cakisma_zamanlari: list[float] = []
        self._son_yayin: dict[str, float] = {}
        self._yayin_sayisi: dict[str, int] = {}

    def submit(self, event: DetectedEvent) -> None:
        """Ham olayı kapıya verir. Yayına hazır olduğunda `drain` ile alınır."""
        if event.etiket in CAKISMA_KAYNAKLARI:
            # Batch versiyonda çakışma kontrolü cooldown'dan ÖNCE, ham kararlar
            # üzerinde yapılıyordu — bu yüzden cooldown'da elenecek olaylar da
            # burada kaynak sayılır.
            self._cakisma_zamanlari.append(event.zaman_saniye)
        self._pending.append(event)

    def drain(self, simdiki_zaman: float) -> list[DetectedEvent]:
        """Olgunlaşmış olayları zaman sırasında, filtrelerden geçirerek yayınlar."""
        hazir: list[DetectedEvent] = []
        bekleyen: list[DetectedEvent] = []

        for event in self._pending:
            if event.etiket in CAKISMAYA_TABI and simdiki_zaman < event.zaman_saniye + self._lookahead:
                bekleyen.append(event)
            else:
                hazir.append(event)

        self._pending = bekleyen
        hazir.sort(key=lambda e: e.zaman_saniye)
        return [e for e in (self._admit(e) for e in hazir) if e is not None]

    def flush(self) -> list[DetectedEvent]:
        """Akış bitti: bekleyen tüm olayları değerlendirip yayınlar."""
        hazir = sorted(self._pending, key=lambda e: e.zaman_saniye)
        self._pending = []
        return [e for e in (self._admit(e) for e in hazir) if e is not None]

    def _admit(self, event: DetectedEvent) -> DetectedEvent | None:
        if event.etiket in CAKISMAYA_TABI and self._cakisiyor(event.zaman_saniye):
            return None

        son = self._son_yayin.get(event.etiket)
        if son is not None and (event.zaman_saniye - son) < self._cooldown:
            return None

        if self._yayin_sayisi.get(event.etiket, 0) >= self._max_olay:
            return None

        self._son_yayin[event.etiket] = event.zaman_saniye
        self._yayin_sayisi[event.etiket] = self._yayin_sayisi.get(event.etiket, 0) + 1
        return event

    def _cakisiyor(self, zaman_saniye: float) -> bool:
        return any(
            abs(zaman_saniye - kaynak) <= self._cakisma_marji
            for kaynak in self._cakisma_zamanlari
        )
