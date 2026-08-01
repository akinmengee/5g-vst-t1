"""Servis örneklerinin tekil (singleton) yaşam döngüsü.

Modeller ağırdır ve yüklenmesi zaman alır; her istekte yeniden yüklenmemeleri için
burada bir kez oluşturulup paylaşılırlar. Yükleme uygulama açılışında
(`app.main` lifespan) tetiklenir, böylece ilk WebSocket mesajı gecikmez ve
eksik model varsa sorun anında loglanır.
"""

import logging

from app.services.network.factory import get_open_gateway_client
from app.services.network.interface import OpenGatewayClient
from app.services.vehicle_ai.current_model_service import CurrentModelService

logger = logging.getLogger(__name__)

_analysis_service: CurrentModelService | None = None
_gateway_client: OpenGatewayClient | None = None


def get_analysis_service() -> CurrentModelService:
    global _analysis_service
    if _analysis_service is None:
        logger.info("Modeller yükleniyor...")
        _analysis_service = CurrentModelService()
    return _analysis_service


def get_gateway_client() -> OpenGatewayClient:
    global _gateway_client
    if _gateway_client is None:
        _gateway_client = get_open_gateway_client()
    return _gateway_client
