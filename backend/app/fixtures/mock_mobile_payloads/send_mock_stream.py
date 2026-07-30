"""Üretilen mock fixture'ları backend'in /ws/stream endpoint'ine sırayla gönderip
cevapları ekrana basan basit bir test istemcisi (henüz Flutter yok - bkz. plan
Gün 2-3 "Yürüyen İskelet" doğrulama adımı).

Önce backend'i ayrı bir terminalde çalıştırın:
    uvicorn app.main:app --reload

Sonra fixture'lar üretilmediyse üretin:
    python -m app.fixtures.mock_mobile_payloads.generate_fixtures

Sonra bu scripti çalıştırın:
    python -m app.fixtures.mock_mobile_payloads.send_mock_stream
"""

import asyncio
import json
from pathlib import Path

import websockets

FIXTURES_DIR = Path(__file__).resolve().parent
WS_URL = "ws://localhost:8000/ws/stream"


async def main() -> None:
    fixture_files = sorted(FIXTURES_DIR.glob("mock_frame_*.json"))
    if not fixture_files:
        print("Once fixture uretin: python -m app.fixtures.mock_mobile_payloads.generate_fixtures")
        return

    async with websockets.connect(WS_URL) as ws:
        for path in fixture_files:
            payload = json.loads(path.read_text(encoding="utf-8"))
            await ws.send(json.dumps(payload))
            response = await ws.recv()
            print(f"[{path.name}] -> {response}")


if __name__ == "__main__":
    asyncio.run(main())
