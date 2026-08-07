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

from app.schemas.qod import QodStartRequest, QodStartResponse, QodStopResponse
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

    gateway = get_gateway_client()

    # Bu flow'da zaten bir oturum açtıysak ÖNCE onu kapatmayı dene: aynı cihaz
    # için ikinci oturum 409 veriyor ve 1200 sn'lik süreyle bu 20 dakikalık bir
    # kilit demek. En iyi çaba — Turkcell silmeyi desteklemiyorsa (spec'te yok)
    # sessizce False döner, eski davranışa göre bir kayıp olmaz.
    if flow.qod_session_id:
        await gateway.stop_qod_session(flow.access_token, flow.qod_session_id)
        flow.qod_session_id = None
        flow.qod_status = None

    try:
        result = await gateway.start_qod_session(flow.access_token)
        flow.qod_status = result.qos_status
        flow.qod_session_id = result.session_id
        return QodStartResponse(
            success=True,
            session_id=result.session_id,
            qos_status=result.qos_status,
            duration=result.duration,
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


@router.post("/api/qod/stop")
async def stop_qod(body: QodStartRequest) -> QodStopResponse:
    """Aktif QoD oturumunu erken sonlandırmayı dener (en iyi çaba).

    Mobil bunu çıkışta / yeni bir oturuma başlarken çağırır. Turkcell'in
    paylaştığı spec'te silme operasyonu YOK, dolayısıyla `stopped: false`
    dönmesi normal bir sonuçtur — oturum kendi süresi dolunca sonlanır.
    Hiçbir durumda HTTP hatası dönmez: bu, akışı bloklamaması gereken bir
    temizlik adımı.
    """
    flow = get_flow_registry().get(body.flow_id)
    if flow is None or not flow.qod_session_id or not flow.token_valid():
        return QodStopResponse(stopped=False)

    try:
        stopped = await get_gateway_client().stop_qod_session(
            flow.access_token, flow.qod_session_id
        )
    except Exception:
        logger.exception("QoD kapatma beklenmeyen hata (flow=%s)", body.flow_id)
        stopped = False

    # Kapatma başarısız olsa bile yerel durumu temizliyoruz: elimizdeki
    # session_id'yi tekrar kullanmanın bir faydası yok.
    flow.qod_session_id = None
    flow.qod_status = None
    return QodStopResponse(stopped=stopped)
