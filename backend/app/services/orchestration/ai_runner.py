"""AI Docker imajını tetikleyen katman — "video girer, results.json çıkar".

Sözleşme (FTR teslim dokümanı bölüm 6 / Yarışmacı Platformu Rehberi):
imaj `/app/data/input/video.mp4` okur, `/app/data/output/results.json` yazar,
kendi kendine sonlanır. Backend bu imajı host process olarak `docker run` ile
tetikler (S2/G3 kararı — Docker-in-Docker gerekmez).

Mock/docker seçimi AI_RUNNER_MODE ile yapılır — USE_MOCK_5G ile aynı ilke:
bilinçli deploy-zamanı konfigürasyonu, sessiz fallback yok.
"""

import asyncio
import logging
import shutil
from pathlib import Path
from typing import Protocol

logger = logging.getLogger(__name__)


class AiRunnerError(Exception):
    """AI çalıştırma başarısız (timeout, non-zero exit, results.json üretilmedi)."""


class AiRunner(Protocol):
    async def run(self, job_id: str, input_video_path: Path, output_dir: Path) -> None:
        """Videoyu işler; başarıda output_dir/results.json oluşmuş olur.

        Başarısızlıkta AiRunnerError fırlatır — sessiz kısmi başarı yoktur.
        """
        ...


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


class MockAiRunner:
    """AI imajı hazır olmadan backend'i uçtan uca test etmek için.

    Kısa bir gecikme sonrası şema-geçerli bir fixture results.json'ı
    output_dir'e kopyalar.
    """

    def __init__(self, fixture_path: Path, delay_seconds: float = 2.0) -> None:
        self._fixture_path = fixture_path
        self._delay_seconds = delay_seconds

    async def run(self, job_id: str, input_video_path: Path, output_dir: Path) -> None:
        await asyncio.sleep(self._delay_seconds)
        output_dir.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(self._fixture_path, output_dir / "results.json")
