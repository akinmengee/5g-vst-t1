"""AI Docker imajını tetikleyen katman — "video girer, results.json çıkar".

Sözleşme (FTR teslim dokümanı bölüm 6 / Yarışmacı Platformu Rehberi):
imaj `/app/data/input/video.mp4` okur, `/app/data/output/results.json` yazar,
kendi kendine sonlanır. Backend bu imajı host process olarak `docker run` ile
tetikler (S2/G3 kararı — Docker-in-Docker gerekmez).

Alternatif bir çalıştırıcı YOKTUR: AI çıktısı puanlanan şeyin ta kendisi,
sabit bir fixture döndürmek gerçek davranışı gizler. Tek yol gerçek imajdır.
"""

import asyncio
import logging
import shutil
from pathlib import Path

logger = logging.getLogger(__name__)


class AiRunnerError(Exception):
    """AI çalıştırma başarısız (timeout, non-zero exit, results.json üretilmedi)."""


class DockerAiRunner:
    def __init__(self, image: str, timeout_seconds: int) -> None:
        # Fail-fast: docker yoksa uygulama açılışında (lifespan) hemen görünsün,
        # ilk video upload'unda değil.
        if shutil.which("docker") is None:
            raise RuntimeError("DockerAiRunner için 'docker' komutu PATH'te bulunamadı.")
        self._image = image
        self._timeout = timeout_seconds

    async def run(self, job_id: str, input_video_path: Path, output_dir: Path) -> None:
        cmd = [
            "docker", "run", "--rm", "--gpus", "all",
            "-v", f"{input_video_path.parent}:/app/data/input",
            "-v", f"{output_dir}:/app/data/output",
            self._image,
        ]
        logger.info("AI docker run başlıyor (job=%s): %s", job_id, " ".join(cmd))
        proc = await asyncio.create_subprocess_exec(
            *cmd, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE
        )
        try:
            _, stderr = await asyncio.wait_for(proc.communicate(), timeout=self._timeout)
        except asyncio.TimeoutError:
            proc.kill()
            await proc.wait()
            raise AiRunnerError(
                f"docker run {self._timeout}s zaman aşımına uğradı (job={job_id})"
            )
        if proc.returncode != 0:
            raise AiRunnerError(
                f"docker run çıkış kodu {proc.returncode} (job={job_id}): "
                f"{stderr.decode(errors='replace')[:500]}"
            )
        if not (output_dir / "results.json").exists():
            raise AiRunnerError(
                f"docker run 0 ile bitti ama results.json üretmedi (job={job_id})"
            )
