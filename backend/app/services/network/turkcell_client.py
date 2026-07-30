"""Gerçek Turkcell Open Gateway implementasyonu.

Yarışma günü SIM kart ve API credential'ları verildiğinde doldurulacak
(bkz. plan "Yarışma günü" bölümü). Şu an sadece arayüz iskeleti — kasıtlı
olarak NotImplementedError fırlatır, sessizce mock'a düşmez.
"""

from app.core.config import settings


class TurkcellOpenGatewayClient:
    def __init__(self) -> None:
        if not settings.turkcell_api_base_url:
            raise RuntimeError(
                "TurkcellOpenGatewayClient kullanmak için TURKCELL_API_BASE_URL ve "
                "TURKCELL_API_KEY ortam değişkenleri set edilmelidir."
            )

    async def verify_number(self) -> bool:
        raise NotImplementedError(
            "Yarışma günü Turkcell Number Verification API entegrasyonu buraya eklenecek."
        )

    async def request_quality_on_demand(self, session_id: str) -> bool:
        raise NotImplementedError(
            "Yarışma günü Turkcell QoD API entegrasyonu buraya eklenecek."
        )
