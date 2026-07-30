from fastapi import FastAPI

from app.api.routes_health import router as health_router
from app.api.routes_inference import router as inference_router

app = FastAPI(title="VST T1 - Akıllı Yol Güvenliği Backend")
app.include_router(health_router)
app.include_router(inference_router)
