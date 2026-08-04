"""Mobil (Flutter, edge yolov8n) <-> Backend veri sözleşmesi.
Bkz. plan "Mimari Kararlar" madde 6: mobil sadece araç tespit edildiğinde,
kırpılmış tek bir ROI görüntüsü + bu metadata'yı gönderir.
"""

from pydantic import BaseModel, Field


class BBox(BaseModel):
    """Aracın TAM KAREYE göre orijinal koordinatları (piksel).

    Kırpılmış görüntüdeki konum değil, bu koordinatlar kullanılır — slalom tespiti
    aracın gerçek karedeki yatay konum değişimine (trajectory) dayandığı için gerekli.
    """

    x1: int
    y1: int
    x2: int
    y2: int
    frame_width: int
    frame_height: int


class MobileRoiPayload(BaseModel):
    """Mobilin (yolov8n edge tespiti sonrası) backend'e WebSocket üzerinden gönderdiği mesaj.

    Araç tespit edilmediği sürece hiç gönderilmez (event-driven). image_base64 şimdilik
    basitlik için JSON içine gömülü; bant genişliği kritikleşirse ayrı bir binary
    WebSocket frame'e taşınabilir (sequence_number ile eşleştirilerek) — bkz. plan Gün 4-7.
    """

    session_id: str
    sequence_number: int
    timestamp: float = Field(description="Unix epoch saniye")
    bbox: BBox
    mobile_confidence: float = Field(ge=0.0, le=1.0)
    image_format: str = "jpeg"
    image_base64: str
