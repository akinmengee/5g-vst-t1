"""AracBilgisi.plaka normalizasyonu — bkz. FTR dokümanı bölüm 5.3 ("boşlukların
normalize edilmesi... gerekmektedir") ve regex'i (`\\s?[a-zA-Z]\\s?`, boşluk +
küçük harfe izin veriyor). Backend'in eski regex'i bundan daha sıkıydı
(bitişik + yalnızca büyük harf) — AI'nin OCR çıktısı "34 tc 8532" gibi
gelirse reddedip canlı demo'da 500 döndürüyordu, halbuki AI doğru çalışmıştı.
"""

import pytest
from pydantic import ValidationError

from app.schemas.detection import AracBilgisi


def _arac(plaka: str) -> AracBilgisi:
    return AracBilgisi(tip="suv", plaka=plaka, renk="siyah", confidence_score=0.9)


@pytest.mark.parametrize(
    "girdi,beklenen",
    [
        ("34ABC123", "34ABC123"),  # zaten temiz — no-op
        ("34 tc 8532", "34TC8532"),  # gerçek AI OCR çıktısı gibi: boşluklu + küçük harf
        ("34tc8532", "34TC8532"),  # boşluksuz küçük harf
        ("34 ABC 123", "34ABC123"),  # boşluklu büyük harf
        ("34a1234", "34A1234"),  # tek harf + 4 rakam
    ],
)
def test_plaka_normalize_edilir(girdi: str, beklenen: str) -> None:
    assert _arac(girdi).plaka == beklenen


def test_bos_plaka_tespit_edilemedi_olarak_kalir() -> None:
    # main.py'nin "tespit edilemedi" fallback'iyle uyumlu — normalize edilmez.
    assert _arac("").plaka == ""


def test_gecersiz_plaka_hala_reddedilir() -> None:
    # Normalizasyon regex'i gevşetmiyor, yalnızca boşluk/büyük-küçük harf
    # toleransı ekliyor — il kodu aralığı dışı ya da yanlış desen hâlâ hata.
    with pytest.raises(ValidationError):
        _arac("99ABC123")  # 99 geçerli il kodu değil
    with pytest.raises(ValidationError):
        _arac("34ABCD1234")  # 4 harf — desen dışı
