"""QoD endpoint testleri — routes_qod.py.

QoD başarısızlığı puan kaybettirmediği için endpoint hiçbir Turkcell hatasında
HTTP hatası dönmez (bilinmeyen flow_id hariç) — testler bu sözleşmeyi korur.
"""

import time

from app.services.orchestration.runtime import get_flow_registry
from tests.network_stubs import FakeOpenGatewayClient
from tests.route_helpers import flow_yarat, taze_ortam


def _token_ver(flow_id: str, gecerli: bool = True) -> None:
    """Flow'a elle geçerli/süresi dolmuş bir access token yerleştirir."""
    flow = get_flow_registry().get(flow_id)
    flow.access_token = "test-token"
    flow.token_expires_at = time.monotonic() + (300 if gecerli else -1)


def test_basarili_qod_success_true_doner(monkeypatch, tmp_path):
    """201 + REQUESTED alan çağrı success=true ve oturum bilgisiyle döner."""
    client = taze_ortam(monkeypatch, tmp_path, gateway=FakeOpenGatewayClient())
    fid = flow_yarat(client)
    _token_ver(fid)
    body = client.post("/api/qod/start", json={"flow_id": fid}).json()
    assert body["success"] is True
    assert body["already_active"] is False
    assert body["sessionId"] == "fake-session"
    assert body["qosStatus"] == "REQUESTED"


def test_token_suresi_dolmussa_success_false_doner(monkeypatch, tmp_path):
    """300sn'lik token ömrü dolmuşsa Turkcell'e hiç gidilmez, success=false döner."""
    client = taze_ortam(monkeypatch, tmp_path, gateway=FakeOpenGatewayClient())
    fid = flow_yarat(client)
    _token_ver(fid, gecerli=False)
    body = client.post("/api/qod/start", json={"flow_id": fid}).json()
    assert body["success"] is False


def test_409_conflict_already_active_true_doner(monkeypatch, tmp_path):
    """Zaten aktif QoD oturumu hata değil başarıdır (puan kuralı)."""
    client = taze_ortam(
        monkeypatch, tmp_path, gateway=FakeOpenGatewayClient(qod_status_code=409)
    )
    fid = flow_yarat(client)
    _token_ver(fid)
    body = client.post("/api/qod/start", json={"flow_id": fid}).json()
    assert body["success"] is True
    assert body["already_active"] is True


def test_diger_hatalarda_success_false_doner_crash_etmez(monkeypatch, tmp_path):
    """400/401/422/429 hatalarının hepsi sakin bir success=false'a çevrilir."""
    for kod in (400, 401, 422, 429):
        client = taze_ortam(
            monkeypatch, tmp_path, gateway=FakeOpenGatewayClient(qod_status_code=kod)
        )
        fid = flow_yarat(client)
        _token_ver(fid)
        resp = client.post("/api/qod/start", json={"flow_id": fid})
        assert resp.status_code == 200, f"HTTP hatasına düşmemeli (Turkcell {kod})"
        assert resp.json()["success"] is False


def test_bilinmeyen_flow_404_doner(monkeypatch, tmp_path):
    """Var olmayan flow_id ile QoD başlatılamaz."""
    client = taze_ortam(monkeypatch, tmp_path, gateway=FakeOpenGatewayClient())
    resp = client.post("/api/qod/start", json={"flow_id": "yok-boyle-bir-sey"})
    assert resp.status_code == 404
