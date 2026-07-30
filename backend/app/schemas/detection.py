"""FTR-docker-spec ile birebir aynı çıktı şeması (bkz. `ftr docker.pdf` bölüm 4.3).
Anahtarlar ve etiketler birebir eşleşmeli: zaman_saniye, kategori, etiket, confidence_score.
Tüm etiketler ASCII + küçük harf.
"""

import re
from typing import Literal

from pydantic import BaseModel, Field, field_validator

Kategori = Literal["sofor_eylemi", "nesneler", "yolcular"]

GECERLI_SOFOR_EYLEMI = {
    "arkaya_bakma", "esneme", "sigara_icme", "su_icme",
    "telefonla_konusma", "slalom", "etrafa_bakinma", "emniyet_kemeri_ihlali",
}
GECERLI_NESNELER = {"teknocan", "bilgisayar"}
GECERLI_YOLCULAR = {"arka_koltuk_1", "arka_koltuk_2", "on_koltuk"}

_KATEGORI_ETIKETLERI: dict[str, set[str]] = {
    "sofor_eylemi": GECERLI_SOFOR_EYLEMI,
    "nesneler": GECERLI_NESNELER,
    "yolcular": GECERLI_YOLCULAR,
}

AracTipi = Literal["sedan", "suv", "hatchback", "pickup", "minibus", "panelvan", "kamyon"]
AracRengi = Literal["beyaz", "siyah", "gri", "kirmizi", "mavi", "sari", "yesil", "turuncu", "kahverengi"]

_PLAKA_REGEX = re.compile(
    r"^(0[1-9]|[1-7][0-9]|8[01])(([A-Z])(\d{4,5})|([A-Z]{2})(\d{3,4})|([A-Z]{3})(\d{2,3}))$"
)


class Tespit(BaseModel):
    zaman_saniye: float
    kategori: Kategori
    etiket: str
    confidence_score: float = Field(ge=0.0, le=1.0)

    @field_validator("etiket")
    @classmethod
    def etiket_kategoriye_uygun_mu(cls, v: str, info) -> str:
        kategori = info.data.get("kategori")
        gecerli = _KATEGORI_ETIKETLERI.get(kategori)
        if gecerli is not None and v not in gecerli:
            raise ValueError(
                f"'{v}' etiketi '{kategori}' kategorisi için geçerli değil. "
                f"Geçerli etiketler: {sorted(gecerli)}"
            )
        return v


class AracBilgisi(BaseModel):
    tip: AracTipi
    plaka: str
    renk: AracRengi
    confidence_score: float = Field(ge=0.0, le=1.0)

    @field_validator("plaka")
    @classmethod
    def plaka_formatini_dogrula(cls, v: str) -> str:
        if v == "":
            # Tespit edilemedi durumu (main.py'deki boş-çıktı fallback'iyle uyumlu)
            return v
        if not _PLAKA_REGEX.fullmatch(v):
            raise ValueError(f"'{v}' geçerli bir plaka formatı değil (örn: 34ABC123)")
        return v


class SonucJson(BaseModel):
    """Konsolide çıktı — FTR-docker-spec bölüm 4.3 ile birebir aynı gövde."""

    video_id: str
    arac_bilgisi: AracBilgisi
    tespitler: list[Tespit] = Field(default_factory=list)
