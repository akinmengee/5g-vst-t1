"""Video upload / AI sonuç mobil sözleşme şemaları.

`results` alanı, FTR resmi çıktı şemasının (schemas/detection.py: SonucJson)
kendisidir — backend AI imajının ürettiği results.json'ı bu şemayla doğrulayıp
olduğu gibi mobile geçirir, yeniden tanımlamaz.
"""

from typing import Literal

from pydantic import BaseModel

from app.schemas.detection import SonucJson


class VideoUploadResponse(BaseModel):
    job_id: str


class VideoResultResponse(BaseModel):
    status: Literal["PROCESSING", "DONE", "FAILED"]
    results: SonucJson | None = None
