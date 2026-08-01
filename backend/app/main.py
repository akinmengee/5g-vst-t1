import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI

from app.api.routes_health import router as health_router
from app.api.routes_inference import router as inference_router
from app.core.config import settings
from app.services.vehicle_ai.runtime import get_analysis_service, get_gateway_client

logging.basicConfig(level=settings.log_level)


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Modelleri açılışta yükle: ilk istek gecikmesin, eksik model anında görünsün.
    get_analysis_service()
    get_gateway_client()
    yield


app = FastAPI(title="VST T1 - Akıllı Yol Güvenliği Backend", lifespan=lifespan)
app.include_router(health_router)
app.include_router(inference_router)
