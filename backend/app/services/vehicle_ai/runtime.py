"""Servis örneklerinin tekil (singleton) yaşam döngüsü.

Modeller ağırdır ve yüklenmesi zaman alır; her istekte yeniden yüklenmemeleri için
burada bir kez oluşturulup paylaşılırlar.

NOT: Bu modül artık yeni backend (main.py) tarafından kullanılmıyor — AI
çekirdeği (`vehicle_ai/*`), ayrı bir Docker imajına (teknofest-2026/vst-t1)
taşınana kadar burada, test paketiyle (200+ test) birlikte referans olarak
duruyor. Gateway client singleton'ı app/services/network/runtime.py'ye taşındı.
"""

import logging

from app.services.vehicle_ai.current_model_service import CurrentModelService

logger = logging.getLogger(__name__)

_analysis_service: CurrentModelService | None = None


def get_analysis_service() -> CurrentModelService:
    global _analysis_service
    if _analysis_service is None:
        logger.info("Modeller yükleniyor...")
        _analysis_service = CurrentModelService()
    return _analysis_service
