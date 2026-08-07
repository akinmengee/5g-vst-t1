"""OpenGatewayClient'ın tekil (singleton) yaşam döngüsü.

orchestration/runtime.py'deki desenle aynı: modül seviyesinde global, lazy,
kilitsiz. FastAPI lifespan başlangıcında bir kez çağrılır — böylece eksik
Turkcell konfigürasyonu uygulama açılışında anında görünür, ilk istekte değil.

Tek bir implementasyon vardır: [TurkcellOpenGatewayClient]. Alternatif bir
istemci YOKTUR — seçim yapan bir fabrika katmanına da bu yüzden gerek yok.
"""

from app.services.network.interface import OpenGatewayClient
from app.services.network.turkcell_client import TurkcellOpenGatewayClient

_gateway_client: OpenGatewayClient | None = None


def get_gateway_client() -> OpenGatewayClient:
    global _gateway_client
    if _gateway_client is None:
        _gateway_client = TurkcellOpenGatewayClient()
    return _gateway_client
