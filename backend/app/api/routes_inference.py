import base64

from fastapi import APIRouter, WebSocket, WebSocketDisconnect
from pydantic import ValidationError

from app.schemas.mobile_contract import MobileRoiPayload
from app.services.network.factory import get_open_gateway_client
from app.services.vehicle_ai.current_model_service import CurrentModelService

router = APIRouter()

# Süreç ömrü boyunca tek örnek yeterli (bkz. plan Mimari Kararlar madde 5:
# tek canlı demo senaryosu için Redis'e gerek yok, basit process-içi state yeterli).
_analysis_service = CurrentModelService()
_gateway_client = get_open_gateway_client()


@router.websocket("/ws/stream")
async def stream_endpoint(websocket: WebSocket) -> None:
    """Mobilin (edge yolov8n tespiti sonrası) kırpılmış araç ROI'lerini gönderdiği uç.

    Protokol: her mesaj, `MobileRoiPayload` şemasına uyan tek bir JSON nesnesidir
    (görüntü base64 olarak gömülü). Sunucu her mesaja, o ana kadar kesinleşen yeni
    tespitleri içeren bir JSON ile cevap verir.
    """
    await websocket.accept()
    await _gateway_client.verify_number()

    try:
        while True:
            raw = await websocket.receive_json()

            try:
                payload = MobileRoiPayload.model_validate(raw)
            except ValidationError as exc:
                await websocket.send_json({"error": "gecersiz_payload", "detay": exc.errors()})
                continue

            try:
                image_bytes = base64.b64decode(payload.image_base64)
            except (ValueError, TypeError):
                await websocket.send_json({"error": "gecersiz_image_base64"})
                continue

            await _gateway_client.request_quality_on_demand(payload.session_id)

            result = _analysis_service.process_roi(payload, image_bytes)
            await websocket.send_json(result.model_dump())
    except WebSocketDisconnect:
        pass
