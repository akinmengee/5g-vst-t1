"""VST T1 backend — mobil-yüzlü NV/QoD/video orkestrasyon API'si.

AI çıkarımı bu process'te ÇALIŞMAZ: backend, videoyu diske yazıp ayrı bir
Docker imajını (teknofest-2026/vst-t1) tetikleyen ince bir katmandır. Bu
yüzden torch/opencv/ultralytics bağımlılığı yoktur — AI çekirdeği tamamen
`ai/` imajına taşındı (VM'de doğrulandı, bkz. PLAN.md Faz C).
"""

import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI

from app.api.routes_auth import router as auth_router
from app.api.routes_health import router as health_router
from app.api.routes_qod import router as qod_router
from app.api.routes_videos import router as videos_router
from app.core.config import settings
from app.services.network.runtime import get_gateway_client
from app.services.orchestration.runtime import (
    get_ai_runner,
    get_flow_registry,
    get_job_registry,
)

logging.basicConfig(level=settings.log_level)


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Fail-fast: eksik Turkcell konfigürasyonu (gerçek client seçiliyken) veya
    # docker modunda docker'ın PATH'te olmaması ilk istekte değil açılışta patlasın.
    get_gateway_client()
    get_flow_registry()
    get_job_registry()
    get_ai_runner()
    yield


app = FastAPI(title="VST T1 - Akıllı Yol Güvenliği Backend", lifespan=lifespan)
app.include_router(health_router)
app.include_router(auth_router)
app.include_router(qod_router)
app.include_router(videos_router)
