"""VehicleAnalysisService arayüzü — Mimari Kararlar madde 3.

Değişken/dış bağımlılık: model kalitesi ve model dosyalarının kendisi. Modeller
güncellendiğinde sadece bu arayüzü uygulayan implementasyon (current_model_service.py)
değişir, geri kalan kod etkilenmez.
"""

from typing import Protocol

from pydantic import BaseModel, Field

from app.schemas.detection import AracBilgisi, Tespit
from app.schemas.mobile_contract import MobileRoiPayload


class VehicleAnalysisResult(BaseModel):
    """Bir ROI işlendikten sonra o ana kadar kesinleşen yeni tespitler.

    Incremental tasarım gereği (bkz. plan Mimari Kararlar madde 9) her çağrı sadece
    YENİ kesinleşen tespitleri döner — video sonunu beklemez.
    """

    tespitler: list[Tespit] = Field(default_factory=list)
    arac_bilgisi_guncelleme: AracBilgisi | None = None


class VehicleAnalysisService(Protocol):
    def process_roi(self, payload: MobileRoiPayload, image_bytes: bytes) -> VehicleAnalysisResult:
        """Mobilden gelen kırpılmış araç ROI'sini işler.

        `payload.session_id` ile aynı araca ait ardışık çağrılar arasında iç durum
        (hafıza, oylama, zamansal doğrulama) implementasyon tarafından tutulur.
        """
        ...
