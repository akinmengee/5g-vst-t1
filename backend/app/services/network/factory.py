from app.core.config import settings
from app.services.network.interface import OpenGatewayClient
from app.services.network.mock_client import MockOpenGatewayClient
from app.services.network.turkcell_client import TurkcellOpenGatewayClient


def get_open_gateway_client() -> OpenGatewayClient:
    if settings.use_mock_5g:
        return MockOpenGatewayClient()
    return TurkcellOpenGatewayClient()
