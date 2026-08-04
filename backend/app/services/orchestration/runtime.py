"""FlowRegistry/JobRegistry/AiRunner'ın tekil (singleton) yaşam döngüsü.

network/runtime.py ve vehicle_ai/runtime.py ile AYNI desen: modül seviyesinde
global, lazy, kilitsiz — FastAPI lifespan başlangıcında bir kez çağrılır,
böylece eksik konfigürasyon (örn. docker modunda docker'ın PATH'te olmaması)
açılışta anında görünür.
"""

import asyncio
from pathlib import Path

from app.core.config import settings
from app.services.orchestration.ai_runner import AiRunner, DockerAiRunner, MockAiRunner
from app.services.orchestration.flow_state import FlowRegistry
from app.services.orchestration.job_state import JobRegistry

_flow_registry: FlowRegistry | None = None
_job_registry: JobRegistry | None = None
_ai_runner: AiRunner | None = None
_ai_semaphore: asyncio.Semaphore | None = None


def get_flow_registry() -> FlowRegistry:
    global _flow_registry
    if _flow_registry is None:
        _flow_registry = FlowRegistry(ttl_seconds=settings.flow_ttl_seconds)
    return _flow_registry


def get_job_registry() -> JobRegistry:
    global _job_registry
    if _job_registry is None:
        _job_registry = JobRegistry(result_ttl_seconds=settings.job_result_ttl_seconds)
    return _job_registry


def get_ai_runner() -> AiRunner:
    global _ai_runner
    if _ai_runner is None:
        if settings.ai_runner_mode == "docker":
            _ai_runner = DockerAiRunner(
                image=settings.ai_docker_image,
                timeout_seconds=settings.job_timeout_seconds,
            )
        else:
            fixture = (
                Path(__file__).resolve().parents[2]
                / "fixtures" / "mock_ai_results" / "results.json"
            )
            _ai_runner = MockAiRunner(fixture_path=fixture)
    return _ai_runner


def get_ai_semaphore() -> asyncio.Semaphore:
    """Tek GPU → aynı anda tek AI çalıştırması (docker run)."""
    global _ai_semaphore
    if _ai_semaphore is None:
        _ai_semaphore = asyncio.Semaphore(1)
    return _ai_semaphore
