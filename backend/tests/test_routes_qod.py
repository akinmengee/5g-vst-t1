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


def test_aktif_oturumda_ikinci_start_turkcelle_gitmez(monkeypatch, tmp_path):
    """7 Ağustos, canlı SIM'de kanıtlandı: Turkcell aynı cihaz için üst üste
    /start çağrılarını 409 ile REDDETMİYOR — her seferinde bağımsız, yeni bir
    360 sn'lik oturum veriyor. Art arda çağrılar (çift dokunma, mobildeki
    RetryInterceptor'ın otomatik yeniden denemesi) bu yüzden üst üste binen
    oturumlar açtırıp QoD'nin saatlerce açık kalmasına yol açabiliyordu.

    Süresi dolmamış bir oturum takip ediyorsak ikinci /start Turkcell'e HİÇ
    gitmemeli — aynı session_id + already_active=True dönmeli.
    """
    gateway = FakeOpenGatewayClient(qod_duration=360)
    client = taze_ortam(monkeypatch, tmp_path, gateway=gateway)
    fid = flow_yarat(client)
    _token_ver(fid)

    ilk = client.post("/api/qod/start", json={"flow_id": fid}).json()
    assert ilk["success"] is True
    assert ilk["already_active"] is False
    assert ilk["sessionId"] == "fake-session"

    ikinci = client.post("/api/qod/start", json={"flow_id": fid}).json()
    assert ikinci["success"] is True
    assert ikinci["already_active"] is True
    assert ikinci["sessionId"] == "fake-session"
    # Turkcell'e (start ya da stop) yalnızca İLK çağrıda gidilmiş olmalı.
    assert gateway.start_qod_calls == 1
    assert gateway.stop_qod_calls == 0


def test_suresi_dolmus_oturumda_yeniden_baslatir(monkeypatch, tmp_path):
    """Granted süre geçmişse (Turkcell'in kendi 360 sn'lik zaman aşımı
    dolmuşsa) /start normal akışa döner: önce eski oturumu kapatmayı dener
    (en iyi çaba), sonra Turkcell'den GERÇEKTEN yeni bir oturum ister."""
    gateway = FakeOpenGatewayClient(qod_duration=360)
    client = taze_ortam(monkeypatch, tmp_path, gateway=gateway)
    fid = flow_yarat(client)
    _token_ver(fid)

    client.post("/api/qod/start", json={"flow_id": fid})
    assert gateway.start_qod_calls == 1

    # Oturumun süresinin çoktan dolduğunu simüle et.
    flow = get_flow_registry().get(fid)
    flow.qod_granted_at = time.monotonic() - 400

    ikinci = client.post("/api/qod/start", json={"flow_id": fid}).json()
    assert ikinci["success"] is True
    assert ikinci["already_active"] is False
    assert gateway.start_qod_calls == 2
    assert gateway.stop_qod_calls == 1
