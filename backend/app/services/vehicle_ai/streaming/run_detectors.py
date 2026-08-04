"""Zamansal dedektörlerin streaming (incremental) karşılıkları.

FTR'deki `predict.py` bu işi video bittikten sonra, birikmiş tüm kayıt üzerinde
tek seferde yapıyordu (`ardisik_seg`, `esneme_seg`, `bakinma_seg`). Burada aynı
mantık, her yeni örnek geldikçe durumu güncelleyen ve şart sağlanınca olayı
anında yayınlayan durum makinelerine (state machine) dönüştürüldü.

Ortak desen: her dedektör bir "run" (kesintisiz blok) biriktirir; run kapandığında
blok yeterince uzunsa bir `DetectedEvent` üretir. Olayın zamanı bloğun ortasıdır
(batch versiyondaki gibi), bu yüzden olay gerçekleştiği andan biraz sonra
yayınlanır — sıralama `EventGate` tarafından düzeltilir.
"""

from bisect import insort

from app.services.vehicle_ai.streaming.events import DetectedEvent


class ConsecutiveRunDetector:
    """`ardisik_seg` karşılığı: art arda `gerek` kadar pozitif örnek → olay.

    Sigara / telefon / su içme tespitleri için kullanılır.
    """

    def __init__(self, kategori: str, etiket: str, gerek: int) -> None:
        self._kategori = kategori
        self._etiket = etiket
        self._gerek = gerek
        self._reset()

    def _reset(self) -> None:
        self._start: float = 0.0
        self._last: float = 0.0
        self._peak: float = 0.0
        self._count: int = 0

    def observe(self, zaman_saniye: float, confidence: float | None) -> DetectedEvent | None:
        if confidence is None:
            return self._close()
        if self._count == 0:
            self._start = zaman_saniye
            self._peak = confidence
        else:
            self._peak = max(self._peak, confidence)
        self._last = zaman_saniye
        self._count += 1
        return None

    def finalize(self) -> DetectedEvent | None:
        return self._close()

    def _close(self) -> DetectedEvent | None:
        if self._count == 0:
            return None
        event = None
        if self._count >= self._gerek:
            event = DetectedEvent(
                zaman_saniye=(self._start + self._last) / 2,
                kategori=self._kategori,
                etiket=self._etiket,
                confidence_score=self._peak,
            )
        self._reset()
        return event


class YawnDetector:
    """`esneme_seg` karşılığı: MAR oranı kişisel tabanın `oran_esik` katını
    `plato_gerek` örnek boyunca aşarsa → esneme.

    **Batch'ten kaçınılmaz fark:** Orijinal kod, kişisel MAR tabanını videonun
    TAMAMININ medyanından hesaplıyordu. Canlı akışta gelecek bilinemediği için
    burada o ana kadarki örneklerin medyanı (running median) kullanılır ve
    `baseline_min_ornek` kadar örnek toplanmadan hiç olay üretilmez.
    Test amacıyla `fixed_baseline` verilerek batch davranışı birebir taklit
    edilebilir.
    """

    def __init__(
        self,
        oran_esik: float,
        plato_gerek: int,
        hareket_esik: float,
        baseline_min_ornek: int,
        fixed_baseline: float | None = None,
    ) -> None:
        self._oran_esik = oran_esik
        self._plato_gerek = plato_gerek
        self._hareket_esik = hareket_esik
        self._baseline_min_ornek = baseline_min_ornek
        self._fixed_baseline = fixed_baseline

        self._sorted_mars: list[float] = []
        self._onceki_oran: float | None = None
        self._reset_run()

    def _reset_run(self) -> None:
        self._start: float = 0.0
        self._last: float = 0.0
        self._peak: float = 0.0
        self._count: int = 0
        self._giris_orani: float = 0.0
        self._son_oran: float = 0.0

    def _baseline(self) -> float:
        if self._fixed_baseline is not None:
            return self._fixed_baseline
        n = len(self._sorted_mars)
        if n == 0:
            return 0.0
        mid = n // 2
        if n % 2 == 1:
            return self._sorted_mars[mid]
        return (self._sorted_mars[mid - 1] + self._sorted_mars[mid]) / 2

    def observe(self, zaman_saniye: float, mar: float | None) -> DetectedEvent | None:
        if mar is None:
            return None

        insort(self._sorted_mars, mar)
        if self._fixed_baseline is None and len(self._sorted_mars) < self._baseline_min_ornek:
            self._onceki_oran = None
            return None

        taban = self._baseline()
        oran = mar / taban if taban > 1e-6 else 0.0

        event = None
        if oran >= self._oran_esik:
            if self._count == 0:
                self._start = zaman_saniye
                self._peak = oran
                self._giris_orani = self._onceki_oran if self._onceki_oran is not None else oran
            else:
                self._peak = max(self._peak, oran)
            self._last = zaman_saniye
            self._son_oran = oran
            self._count += 1
        else:
            event = self._close(cikis_orani=oran)

        self._onceki_oran = oran
        return event

    def finalize(self) -> DetectedEvent | None:
        # Blok açıkken akış bitti: batch versiyonda `cikis`, bloğun son oranıydı.
        return self._close(cikis_orani=self._son_oran)

    def _close(self, cikis_orani: float) -> DetectedEvent | None:
        if self._count == 0:
            return None
        event = None
        if self._count >= self._plato_gerek:
            cikis = cikis_orani
            if self._peak - min(self._giris_orani, cikis) >= self._hareket_esik:
                event = DetectedEvent(
                    zaman_saniye=(self._start + self._last) / 2,
                    kategori="sofor_eylemi",
                    etiket="esneme",
                    confidence_score=min(0.99, 0.5 + self._peak / 20),
                )
        self._reset_run()
        return event


class HeadTurnDetector:
    """`bakinma_seg` karşılığı: burun-omuz sapması `donuk_offset`i aşan aynı
    yöndeki kesintisiz blok, süresine göre `etrafa_bakinma` veya `arkaya_bakma`.

    Orijinal koddaki gibi, sürücünün görünmediği örnekler (offset `None`) diziye
    hiç eklenmez — yani bloğu kesmez, blok bir sonraki geçerli örnekle devam eder.
    """

    def __init__(
        self, donuk_offset: float, t_arkaya: float, t_etrafa_min: float, ornekleme_araligi: float
    ) -> None:
        self._donuk_offset = donuk_offset
        self._t_arkaya = t_arkaya
        self._t_etrafa_min = t_etrafa_min
        self._dt = ornekleme_araligi
        self._reset()

    def _reset(self) -> None:
        self._yon: str | None = None
        self._start: float = 0.0
        self._last: float = 0.0

    def observe(self, zaman_saniye: float, offset: float | None) -> DetectedEvent | None:
        if offset is None:
            return None

        yon = None
        if abs(offset) >= self._donuk_offset:
            yon = "L" if offset < 0 else "R"

        if yon is None:
            return self._close()

        if self._yon == yon:
            self._last = zaman_saniye
            return None

        event = self._close()
        self._yon = yon
        self._start = zaman_saniye
        self._last = zaman_saniye
        return event

    def finalize(self) -> DetectedEvent | None:
        return self._close()

    def _close(self) -> DetectedEvent | None:
        if self._yon is None:
            return None
        sure = (self._last - self._start) + self._dt
        etiket = None
        if sure >= self._t_arkaya:
            etiket = "arkaya_bakma"
        elif sure >= self._t_etrafa_min:
            etiket = "etrafa_bakinma"

        event = None
        if etiket is not None:
            event = DetectedEvent(
                zaman_saniye=(self._start + self._last) / 2,
                kategori="sofor_eylemi",
                etiket=etiket,
                confidence_score=min(0.99, 0.5 + sure / 10),
            )
        self._reset()
        return event


class SeatbeltDetector:
    """Emniyet kemeri ihlali — orijinal koddaki özel mantığı korur:

    - Sadece sürücünün göründüğü örnekler değerlendirilir.
    - `kemer_gerek` kadar ardışık "kemer görülmedi" örneği → ihlal, olayın zamanı
      bloğun BAŞLANGICI (ortası değil) ve güven skoru sabit 0.50.
    - Video başına yalnızca ilk ihlal raporlanır.
    - **Global fail-safe:** kemer video boyunca en az `fail_safe_gorulme` kez net
      görülmüşse ihlal hiç bildirilmez. Bu koşul ancak akış ilerledikçe
      kesinleşebildiği için, canlı uyarı anında verilir; nihai JSON üretilirken
      `suppressed` kontrol edilerek batch davranışı korunur.
    """

    def __init__(self, kemer_gerek: int, fail_safe_gorulme: int) -> None:
        self._kemer_gerek = kemer_gerek
        self._fail_safe_gorulme = fail_safe_gorulme
        self._kemer_gorulme = 0
        self._ihlal_bildirildi = False
        self._count = 0
        self._start = 0.0

    @property
    def suppressed(self) -> bool:
        """Kemer yeterince net görüldüyse, üretilmiş ihlal olayı geçersizdir."""
        return self._kemer_gorulme >= self._fail_safe_gorulme

    def observe(
        self, zaman_saniye: float, sofor_var: bool, kemer_conf: float | None
    ) -> DetectedEvent | None:
        if not sofor_var:
            return None

        if kemer_conf is not None:
            self._kemer_gorulme += 1
            self._count = 0
            return None

        if self._count == 0:
            self._start = zaman_saniye
        self._count += 1

        if self._ihlal_bildirildi or self._count != self._kemer_gerek:
            return None
        if self.suppressed:
            return None

        self._ihlal_bildirildi = True
        return DetectedEvent(
            zaman_saniye=self._start,
            kategori="sofor_eylemi",
            etiket="emniyet_kemeri_ihlali",
            confidence_score=0.50,
        )

    def finalize(self) -> DetectedEvent | None:
        return None
