"""Mobilin (yolov8n edge tespiti sonrası) göndereceği verileri taklit eden mock
fixture üreticisi. Gerçek bir telefon/Flutter kodu olmadan backend'in WebSocket
akışını uçtan uca test edebilmek için (bkz. plan Gün 2-3 "Yürüyen İskelet").

Çalıştırma:
    python -m app.fixtures.mock_mobile_payloads.generate_fixtures

Bir "araç yaklaşıyor" senaryosunu simüle eden ardışık N adet payload JSON dosyası
üretir (aynı session_id, artan sequence_number, tam kareye göre büyüyen bbox).
"""

import base64
import json
import time
import uuid
from pathlib import Path

import cv2
import numpy as np

OUTPUT_DIR = Path(__file__).resolve().parent
FRAME_WIDTH = 1280
FRAME_HEIGHT = 720
NUM_FRAMES = 8


def _fake_vehicle_crop_jpeg_base64(width: int, height: int, seq: int) -> str:
    """Gerçek bir araç fotoğrafı yerine, boyutu her adımda değişen basit bir
    renkli dikdörtgen üretir (gerçek görüntü yerine geçen bir yer tutucu)."""
    img = np.full((height, width, 3), 40, dtype=np.uint8)
    cv2.rectangle(img, (0, 0), (width - 1, height - 1), (60, 120, 200), thickness=-1)
    cv2.putText(
        img, f"mock-arac #{seq}", (10, max(20, height // 2)),
        cv2.FONT_HERSHEY_SIMPLEX, 0.6, (255, 255, 255), 2,
    )
    ok, buf = cv2.imencode(".jpg", img)
    if not ok:
        raise RuntimeError("Mock goruntu encode edilemedi")
    return base64.b64encode(buf.tobytes()).decode("ascii")


def generate() -> list[Path]:
    session_id = str(uuid.uuid4())
    now = time.time()
    written: list[Path] = []

    for seq in range(1, NUM_FRAMES + 1):
        # Araç kareye girip yaklaştıkça kutu büyüsün (basit doğrusal simülasyon)
        progress = seq / NUM_FRAMES
        box_w = int(150 + progress * 500)
        box_h = int(box_w * 0.75)
        x1 = int(FRAME_WIDTH * 0.5 - box_w / 2)
        y1 = int(FRAME_HEIGHT * 0.5 - box_h / 2)
        x2 = x1 + box_w
        y2 = y1 + box_h

        payload = {
            "session_id": session_id,
            "sequence_number": seq,
            "timestamp": now + seq * 0.2,
            "bbox": {
                "x1": x1, "y1": y1, "x2": x2, "y2": y2,
                "frame_width": FRAME_WIDTH, "frame_height": FRAME_HEIGHT,
            },
            "mobile_confidence": round(min(0.5 + progress * 0.4, 0.95), 2),
            "image_format": "jpeg",
            "image_base64": _fake_vehicle_crop_jpeg_base64(box_w, box_h, seq),
        }

        out_path = OUTPUT_DIR / f"mock_frame_{seq:03d}.json"
        out_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
        written.append(out_path)

    return written


if __name__ == "__main__":
    paths = generate()
    print(f"{len(paths)} mock fixture uretildi:")
    for p in paths:
        print(f"  - {p}")
