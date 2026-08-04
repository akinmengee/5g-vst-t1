"""Video upload + AI sonuç endpoint testleri — routes_videos.py.

DONE/FAILED senaryolarında arka plan task'ının zamanlamasına güvenilmez:
job_executor._execute doğrudan asyncio.run ile çalıştırılır (deterministik,
flaky-timing yok). Upload'ın spawn davranışı 202 ve PROCESSING testlerinde
ayrıca doğrulanır.
"""

import asyncio

from app.core.config import settings
from app.services.orchestration import job_executor
from app.services.orchestration.runtime import get_job_registry
from tests.ai_stubs import BasariliRunner, PatlayanRunner
from tests.network_stubs import FakeOpenGatewayClient
from tests.route_helpers import flow_yarat, taze_ortam


def _job_hazirla(tmp_path, job_id: str):
    """Upload endpoint'ini atlayarak diskte + registry'de bir job kurar."""
    get_job_registry().create(job_id)
    input_dir = tmp_path / "jobs" / job_id / "input"
    output_dir = tmp_path / "jobs" / job_id / "output"
    input_dir.mkdir(parents=True)
    output_dir.mkdir(parents=True)
    video_path = input_dir / "video.mp4"
    video_path.write_bytes(b"sahte video verisi")
    return video_path, output_dir


def test_upload_202_ve_job_id_doner(monkeypatch, tmp_path):
    """Upload hemen 202 döner ve videoyu job klasörüne yazar.

    Not: flow burada yalnızca 'pending' (NV doğrulanmamış) — yine de kabul
    edilir; 'verified' şartı bilinçli olarak aranmıyor (plan Karar 2).
    """
    client = taze_ortam(monkeypatch, tmp_path, gateway=FakeOpenGatewayClient())
    fid = flow_yarat(client)
    resp = client.post(
        "/api/videos/upload",
        data={"flow_id": fid},
        files={"video": ("video.mp4", b"sahte video verisi", "video/mp4")},
    )
    assert resp.status_code == 202
    job_id = resp.json()["job_id"]
    assert job_id
    yazilan = settings.job_storage_path / job_id / "input" / "video.mp4"
    assert yazilan.read_bytes() == b"sahte video verisi"


def test_bilinmeyen_flow_ile_upload_404_doner(monkeypatch, tmp_path):
    """Var olmayan flow_id ile video yüklenemez."""
    client = taze_ortam(monkeypatch, tmp_path, gateway=FakeOpenGatewayClient())
    resp = client.post(
        "/api/videos/upload",
        data={"flow_id": "yok-boyle-bir-flow"},
        files={"video": ("video.mp4", b"x", "video/mp4")},
    )
    assert resp.status_code == 404


def test_sonuc_ai_bitmeden_processing_doner(monkeypatch, tmp_path):
    """AI çalışması sürerken sonuç sorgusu PROCESSING döner."""
    yavas = BasariliRunner(gecikme=30.0)
    client = taze_ortam(monkeypatch, tmp_path, gateway=FakeOpenGatewayClient(), runner=yavas)
    fid = flow_yarat(client)
    job_id = client.post(
        "/api/videos/upload",
        data={"flow_id": fid},
        files={"video": ("video.mp4", b"x", "video/mp4")},
    ).json()["job_id"]
    body = client.get(f"/api/videos/{job_id}/result").json()
    assert body["status"] == "PROCESSING"
    assert body["results"] is None


def test_ai_basarili_bitince_status_done_ve_sonuc_doner(monkeypatch, tmp_path):
    """Başarılı çalıştırma sonrası DONE + şema-doğrulanmış results döner."""
    client = taze_ortam(monkeypatch, tmp_path, gateway=FakeOpenGatewayClient())
    video_path, output_dir = _job_hazirla(tmp_path, "test-job-done")
    asyncio.run(job_executor._execute("test-job-done", video_path, output_dir))
    body = client.get("/api/videos/test-job-done/result").json()
    assert body["status"] == "DONE"
    assert body["results"]["video_id"] == "video.mp4"
    assert body["results"]["arac_bilgisi"]["plaka"] == "34ABC123"


def test_ai_hata_verirse_status_failed_doner(monkeypatch, tmp_path):
    """AiRunnerError job'ı FAILED yapar, endpoint çökmez."""
    client = taze_ortam(
        monkeypatch, tmp_path, gateway=FakeOpenGatewayClient(), runner=PatlayanRunner()
    )
    video_path, output_dir = _job_hazirla(tmp_path, "test-job-fail")
    asyncio.run(job_executor._execute("test-job-fail", video_path, output_dir))
    body = client.get("/api/videos/test-job-fail/result").json()
    assert body["status"] == "FAILED"


def test_bilinmeyen_job_404_doner(monkeypatch, tmp_path):
    """Var olmayan job_id sorgusu 404 döner."""
    client = taze_ortam(monkeypatch, tmp_path, gateway=FakeOpenGatewayClient())
    resp = client.get("/api/videos/yok-boyle-bir-job/result")
    assert resp.status_code == 404
