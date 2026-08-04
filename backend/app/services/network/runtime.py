"""OpenGatewayClient'ın tekil (singleton) yaşam döngüsü.

vehicle_ai/runtime.py'deki desenle aynı: modül seviyesinde global, lazy, kilitsiz.
FastAPI lifespan başlangıcında bir kez çağrılır — böylece eksik Turkcell
konfigürasyonu (gerçek client seçiliyken) uygulama açılışında anında görünür.
"""

from app.services.network.factory import get_open_gateway_client
from app.services.network.interface import OpenGatewayClient

_gateway_client: OpenGatewayClient | None = None


def get_gateway_client() -> OpenGatewayClient:
    global _gateway_client
    if _gateway_client is None:
        _gateway_client = get_open_gateway_client()
    return _gateway_client
