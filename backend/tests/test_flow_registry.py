"""FlowRegistry birim testleri — TTL deseni SessionRegistry testleriyle aynı
(bkz. test_service_pipeline.py: test_oturum_ttl_ile_dusurulur)."""

import time

from app.services.orchestration.flow_state import FlowRegistry


def test_bilinmeyen_flow_id_none_doner():
    """SessionRegistry'nin aksine FlowRegistry bilinmeyen id'de oturum YARATMAZ."""
    registry = FlowRegistry(ttl_seconds=60.0)
    assert registry.get("hic-olusturulmadi") is None
    assert len(registry) == 0


def test_flow_ttl_ile_dusurulur():
    """TTL süresi boyunca erişilmeyen flow, sonraki erişimde hafızadan düşürülür."""
    registry = FlowRegistry(ttl_seconds=0.05)
    eski = registry.create("+905390000020")
    time.sleep(0.1)
    registry.create("+905390000021")  # eviction'ı tetikler
    assert registry.get(eski.flow_id) is None
    assert len(registry) == 1


def test_erisim_ttl_sayacini_yeniler():
    """get() ile dokunulan flow TTL penceresi içinde canlı kalır."""
    registry = FlowRegistry(ttl_seconds=0.15)
    flow = registry.create("+905390000020")
    for _ in range(3):
        time.sleep(0.08)
        assert registry.get(flow.flow_id) is not None  # her erişim touch eder


def test_token_gecerliligi_suresi_dolunca_false():
    """token_valid, 300sn'lik ömür dolduğunda false döner."""
    registry = FlowRegistry(ttl_seconds=60.0)
    flow = registry.create("+905390000020")
    assert flow.token_valid() is False  # token hiç alınmadı
    flow.access_token = "tok"
    flow.token_expires_at = time.monotonic() + 300
    assert flow.token_valid() is True
    flow.token_expires_at = time.monotonic() - 1
    assert flow.token_valid() is False
