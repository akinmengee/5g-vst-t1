"""JobRegistry birim testleri — PROCESSING'in TTL'den muaf olduğu politika."""

import time
from pathlib import Path

from app.services.orchestration.job_state import JobRegistry


def test_processing_job_ttl_gecse_bile_dusurulmez():
    """Aktif (PROCESSING) job asla TTL ile düşürülmez — docker run kaydı kaybolmaz."""
    registry = JobRegistry(result_ttl_seconds=0.05)
    registry.create("aktif-job")
    time.sleep(0.1)
    registry.create("ikinci-job")  # eviction'ı tetikler
    assert registry.get("aktif-job") is not None


def test_done_job_ttl_gecince_dusurulur():
    """Bitmiş (DONE) job, TTL dolunca sonraki erişimde düşürülür."""
    registry = JobRegistry(result_ttl_seconds=0.05)
    registry.create("biten-job")
    registry.mark_done("biten-job", Path("/tmp/results.json"))
    time.sleep(0.1)
    registry.create("yeni-job")  # eviction'ı tetikler
    assert registry.get("biten-job") is None


def test_mark_done_ve_mark_failed_durumu_gunceller():
    """Durum geçişleri ve alanlar (results_path, error, finished_at) doğru işlenir."""
    registry = JobRegistry(result_ttl_seconds=60.0)
    registry.create("j1")
    registry.mark_done("j1", Path("/x/results.json"))
    j1 = registry.get("j1")
    assert j1.status == "DONE"
    assert j1.results_path == Path("/x/results.json")
    assert j1.finished_at is not None

    registry.create("j2")
    registry.mark_failed("j2", "zaman aşımı")
    j2 = registry.get("j2")
    assert j2.status == "FAILED"
    assert j2.error == "zaman aşımı"
