import asyncio
import base64
import logging

from fastapi import APIRouter, WebSocket, WebSocketDisconnect
from pydantic import ValidationError

from app.schemas.mobile_contract import MobileRoiPayload
from app.services.vehicle_ai.interface import VehicleAnalysisResult
from app.services.vehicle_ai.runtime import get_analysis_service, get_gateway_client

logger = logging.getLogger(__name__)
router = APIRouter()


@router.websocket("/ws/stream")
async def stream_endpoint(websocket: WebSocket) -> None:
    """Mobilin (edge yolov8n tespiti sonrası) kırpılmış araç ROI'lerini gönderdiği uç.

    Protokol: her mesaj `MobileRoiPayload` şemasına uyan tek bir JSON nesnesidir
    (görüntü base64 gömülü). Sunucu her mesaja, o ana kadar KESİNLEŞEN yeni
    tespitlerle cevap verir — tespit yoksa liste boş döner.

    Bağlantı kapanınca oturum sonlandırılır: açık bloklarda bekleyen olaylar
    boşaltılır ve nihai araç bilgisi üretilir.
    """
    await websocket.accept()
    gateway = get_gateway_client()
    service = get_analysis_service()
    await gateway.verify_number()

    aktif_session: str | None = None
    try:
        while True:
            raw = await websocket.receive_json()

            try:
                payload = MobileRoiPayload.model_validate(raw)
            except ValidationError as exc:
                await websocket.send_json({"error": "gecersiz_payload", "detay": exc.errors()})
                continue

            try:
                image_bytes = base64.b64decode(payload.image_base64, validate=True)
            except (ValueError, TypeError):
                await websocket.send_json({"error": "gecersiz_image_base64"})
                continue

            if aktif_session is None:
                aktif_session = payload.session_id
                # QoD yalnızca oturum başında, araç ilk tespit edildiğinde talep edilir;
                # her karede tetiklemek şebekeyi gereksiz yorar.
                await gateway.request_quality_on_demand(payload.session_id)

            # Model çıkarımı senkron ve ağırdır; event loop'u bloklamaması için
            # ayrı bir thread'de çalıştırılır (Kod İncelemesi Bulguları madde 6).
            try:
                result = await asyncio.to_thread(service.process_roi, payload, image_bytes)
            except Exception:
                logger.exception("ROI işlenirken hata (session=%s)", payload.session_id)
                await websocket.send_json({"error": "cikarim_hatasi"})
                continue

            await websocket.send_json(result.model_dump())
    except WebSocketDisconnect:
        pass
    finally:
        if aktif_session is not None:
            await _finalize(websocket, service, aktif_session)


async def _finalize(websocket: WebSocket, service, session_id: str) -> None:
    try:
        nihai = await asyncio.to_thread(service.finalize_session, session_id)
    except Exception:
        logger.exception("Oturum sonlandırılamadı (session=%s)", session_id)
        return

    if nihai == VehicleAnalysisResult():
        return
    try:
        await websocket.send_json({"final": True, **nihai.model_dump()})
    except Exception:
        # Bağlantı zaten kapanmış olabilir — nihai sonuç loglanır, akış sonlanır.
        logger.info("Nihai sonuç gönderilemedi (session=%s): %s", session_id, nihai.model_dump())
