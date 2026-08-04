"""Route testleri için ortak kurulum yardımcıları.

Kod tabanında Depends() DI yok — servisler modül-seviyesi lazy singleton'lar
(runtime.py dosyalarındaki `_x: X | None = None` global'leri). Testler bu
yüzden o global'leri monkeypatch ile doğrudan değiştirir: get_*()
fonksiyonlarındaki `is None` kontrolü, önceden yerleştirilen sahteyi olduğu
gibi döndürür. Bu örüntü ilk kez burada kullanılıyor; route testlerinin
tamamı bu helper üzerinden geçer.
"""

from fastapi.testclient import TestClient

from app.core.config import settings
from app.services.network import runtime as network_runtime
from app.services.orchestration import runtime as orch_runtime
from app.services.orchestration.flow_state import FlowRegistry
from app.services.orchestration.job_state import JobRegistry
from tests.ai_stubs import BasariliRunner


def taze_ortam(monkeypatch, tmp_path, *, gateway=None, runner=None) -> TestClient:
    """Her test için taze singleton'lar ve tmp job depolama alanı kurar."""
    monkeypatch.setattr(settings, "job_storage_path", tmp_path / "jobs")
    monkeypatch.setattr(network_runtime, "_gateway_client", gateway)
    monkeypatch.setattr(orch_runtime, "_flow_registry", FlowRegistry(ttl_seconds=60.0))
    monkeypatch.setattr(orch_runtime, "_job_registry", JobRegistry(result_ttl_seconds=60.0))
    monkeypatch.setattr(
        orch_runtime,
        "_ai_runner",
        runner if runner is not None else BasariliRunner(),
    )
    # Semaphore her testte sıfırlanır ki farklı event loop'lara bağlanma
    # (asyncio "bound to a different event loop") hatası oluşmasın.
    monkeypatch.setattr(orch_runtime, "_ai_semaphore", None)

    from app.main import app

    return TestClient(app)


def flow_yarat(client: TestClient, phone: str = "+905390000020") -> str:
    """Login endpoint'i üzerinden gerçek bir flow açar, flow_id döner."""
    resp = client.post("/api/auth/login", json={"phoneNumber": phone})
    assert resp.status_code == 200, resp.text
    return resp.json()["flow_id"]
