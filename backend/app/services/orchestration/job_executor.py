"""Job'ı arka planda çalıştıran ince katman — routes_videos'un HTTP katmanından ayrık.

Upload endpoint'i spawn() ile hemen döner (202); asıl çalıştırma aynı event
loop'ta bir asyncio task'ı olarak sürer. GPU tek olduğu için process genelinde
tek izinli semaphore ile aynı anda en fazla bir AI çalıştırması yapılır —
kuyruğa giren job'lar registry'de zaten PROCESSING göründüğünden ayrı bir
QUEUED durumuna gerek yoktur.
"""

import asyncio
import logging
from pathlib import Path

logger = logging.getLogger(__name__)

# asyncio.create_task()'in ürettiği Task GC'lenmesin diye referans tutulur
# (asyncio dokümantasyonu: "Save a reference to the result of this function").
_background_tasks: set[asyncio.Task] = set()


def spawn(job_id: str, input_video_path: Path, output_dir: Path) -> None:
    task = asyncio.create_task(_execute(job_id, input_video_path, output_dir))
    _background_tasks.add(task)
    task.add_done_callback(_background_tasks.discard)


async def _execute(job_id: str, input_video_path: Path, output_dir: Path) -> None:
    # runtime import'u fonksiyon içinde: job_executor ↔ runtime döngüsel
    # import'unu önler.
    from app.services.orchestration.runtime import (
        get_ai_runner,
        get_ai_semaphore,
        get_job_registry,
    )

    job_registry = get_job_registry()
    try:
        async with get_ai_semaphore():
            await get_ai_runner().run(job_id, input_video_path, output_dir)
        job_registry.mark_done(job_id, output_dir / "results.json")
    except Exception as exc:
        logger.exception("AI çalıştırma başarısız (job=%s)", job_id)
        job_registry.mark_failed(job_id, str(exc))
