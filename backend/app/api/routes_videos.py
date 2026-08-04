"""Video upload + AI sonuç endpoint'leri — Bölüm J tasarımı.

Desen, Open Gateway Demo UX Kılavuzu adım 05-06 ile birebir: multipart upload →
video paylaşımlı klasöre yazılır → AI tetiklenir → hemen 202 → mobil sonucu
polling ile alır (PROCESSING/DONE/FAILED).
"""

import asyncio
import logging
import shutil
from uuid import uuid4

from fastapi import APIRouter, File, Form, HTTPException, UploadFile

from app.core.config import settings
from app.schemas.detection import SonucJson
from app.schemas.videos import VideoResultResponse, VideoUploadResponse
from app.services.orchestration import job_executor
from app.services.orchestration.runtime import get_flow_registry, get_job_registry

logger = logging.getLogger(__name__)
router = APIRouter()


@router.post("/api/videos/upload", status_code=202)
async def upload_video(
    flow_id: str = Form(...), video: UploadFile = File(...)
) -> VideoUploadResponse:
    # Flow'un VAR olması yeterli, "verified" şartı bilinçli olarak aranmıyor:
    # demo günü NV flaky olursa video→AI→sonuç hattı yine de çalışabilmeli
    # (o adımın puanı zaten ayrıca kaybedilir, akış tümden kilitlenmez).
    if get_flow_registry().get(flow_id) is None:
        raise HTTPException(status_code=404, detail="flow_id bulunamadı")

    job_id = str(uuid4())
    job_dir = settings.job_storage_path / job_id
    input_dir = job_dir / "input"
    output_dir = job_dir / "output"
    input_dir.mkdir(parents=True, exist_ok=True)
    output_dir.mkdir(parents=True, exist_ok=True)
    video_path = input_dir / "video.mp4"

    # Büyük dosya kopyalama event loop'u bloklamasın.
    with open(video_path, "wb") as f:
        await asyncio.to_thread(shutil.copyfileobj, video.file, f)

    get_job_registry().create(job_id)
    job_executor.spawn(job_id, video_path, output_dir)
    return VideoUploadResponse(job_id=job_id)


@router.get("/api/videos/{job_id}/result")
async def get_result(job_id: str) -> VideoResultResponse:
    job = get_job_registry().get(job_id)
    if job is None:
        raise HTTPException(status_code=404, detail="job_id bulunamadı")
    if job.status != "DONE":
        return VideoResultResponse(status=job.status)
    try:
        raw = job.results_path.read_text(encoding="utf-8")
        parsed = SonucJson.model_validate_json(raw)
    except Exception:
        logger.exception("results.json parse edilemedi (job=%s)", job_id)
        raise HTTPException(status_code=500, detail="results.json okunamadı/geçersiz")
    return VideoResultResponse(status="DONE", results=parsed)
