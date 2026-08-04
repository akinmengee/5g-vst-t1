"""QoD (Quality on Demand) endpoint'i — Bölüm I tasarımı.

NV'de alınan access_token yeniden kullanılır (tek /authorize isteğinde iki
scope birden istendiği için). Tek, senkron çağrı: 201+REQUESTED başarı sayılır,
AVAILABLE beklenmez (bilinçli karar — 5 dakikalık streaming penceresinden zaman
çalmamak için; video zaten ABR ile gerçek bant genişliğine adapte olur).

QoD başarısızlığı puan kaybettirmez → hiçbir Turkcell hatası HTTP hatasına
çevrilmez, yalnızca {success:false} döner; mobil akışa devam eder.
"""

import logging

from fastapi import APIRouter, HTTPException

from app.schemas.qod import QodStartRequest, QodStartResponse
from app.services.network.interface import OpenGatewayError
from app.services.network.runtime import get_gateway_client
from app.services.orchestration.runtime import get_flow_registry

logger = logging.getLogger(__name__)
router = APIRouter()


@router.post("/api/qod/start")
async def start_qod(body: QodStartRequest) -> QodStartResponse:
    flow = get_flow_registry().get(body.flow_id)
    if flow is None:
        raise HTTPException(status_code=404, detail="flow_id bulunamadı")

    if not flow.token_valid():
        # Token 5 dakikalık ömrünü doldurmuş (ya da NV hiç tamamlanmamış).
        # Refresh token yok — yeniden almak tüm login akışını gerektirir.
        logger.warning("QoD: access_token yok/süresi dolmuş (flow=%s)", body.flow_id)
        return QodStartResponse(success=False)

    try:
        result = await get_gateway_client().start_qod_session(flow.access_token)
        flow.qod_status = result.qos_status
        flow.qod_session_id = result.session_id
        return QodStartResponse(
            success=True, session_id=result.session_id, qos_status=result.qos_status
        )
    except OpenGatewayError as exc:
        if exc.status_code == 409:
            # Aynı cihaz için zaten aktif oturum — hata değil, başarı.
            return QodStartResponse(success=True, already_active=True)
        logger.warning("QoD başarısız (flow=%s): %s", body.flow_id, exc)
        return QodStartResponse(success=False)
    except Exception:
        logger.exception("QoD beklenmeyen hata (flow=%s)", body.flow_id)
        return QodStartResponse(success=False)
