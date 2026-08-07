"""NV (Number Verification) endpoint testleri — routes_auth.py.

Gateway, tests/network_stubs.py'deki FakeOpenGatewayClient ile değiştirilir;
Turkcell'e hiçbir gerçek çağrı yapılmaz.
"""

from tests.network_stubs import FakeOpenGatewayClient
from tests.route_helpers import flow_yarat, taze_ortam


def test_login_flow_id_ve_authorize_url_doner(monkeypatch, tmp_path):
    """Login, flow_id üretir ve authorize_url'de state olarak taşır."""
    client = taze_ortam(monkeypatch, tmp_path, gateway=FakeOpenGatewayClient())
    resp = client.post("/api/auth/login", json={"phoneNumber": "+905390000020"})
    assert resp.status_code == 200
    body = resp.json()
    assert body["flow_id"]
    assert f"state={body['flow_id']}" in body["authorize_url"]


def test_gecersiz_telefon_numarasi_422_doner(monkeypatch, tmp_path):
    """E.164 formatına uymayan numara pydantic validasyonuna takılır."""
    client = taze_ortam(monkeypatch, tmp_path, gateway=FakeOpenGatewayClient())
    resp = client.post("/api/auth/login", json={"phoneNumber": "05551234567"})
    assert resp.status_code == 422


def test_callback_basarili_dogrulamada_flow_verified_olur(monkeypatch, tmp_path):
    """code → token → verify zinciri başarılıysa status verified olur."""
    client = taze_ortam(monkeypatch, tmp_path, gateway=FakeOpenGatewayClient(verified=True))
    fid = flow_yarat(client)
    resp = client.get(f"/api/auth/callback?state={fid}&code=abc123")
    assert resp.status_code == 200
    durum = client.get(f"/api/auth/status/{fid}").json()
    assert durum["status"] == "verified"


def test_callback_reddedilince_flow_rejected_olur(monkeypatch, tmp_path):
    """Turkcell devicePhoneNumberVerified=false dönerse status rejected olur."""
    client = taze_ortam(monkeypatch, tmp_path, gateway=FakeOpenGatewayClient(verified=False))
    fid = flow_yarat(client)
    client.get(f"/api/auth/callback?state={fid}&code=abc123")
    durum = client.get(f"/api/auth/status/{fid}").json()
    assert durum["status"] == "rejected"
    assert durum["devicePhoneNumberVerified"] is False


def test_callback_gateway_hata_atarsa_flow_error_olur(monkeypatch, tmp_path):
    """OpenGatewayError (örn. WiFi 403) status=error + error_code'a yansır."""
    client = taze_ortam(
        monkeypatch, tmp_path, gateway=FakeOpenGatewayClient(raise_on_verify=True)
    )
    fid = flow_yarat(client)
    resp = client.get(f"/api/auth/callback?state={fid}&code=abc123")
    assert resp.status_code == 200  # WebView'e her durumda düzgün HTML döner
    durum = client.get(f"/api/auth/status/{fid}").json()
    assert durum["status"] == "error"
    assert durum["error_code"] == "NUMBER_VERIFICATION.USER_NOT_AUTHENTICATED_BY_MOBILE_NETWORK"


def test_callback_code_eksikse_flow_error_olur_ve_crash_etmez(monkeypatch, tmp_path):
    """Turkcell OAuth hatasıyla (?error=..., code yok) dönerse 422 yerine düzgün işlenir."""
    client = taze_ortam(monkeypatch, tmp_path, gateway=FakeOpenGatewayClient())
    fid = flow_yarat(client)
    resp = client.get(f"/api/auth/callback?state={fid}&error=access_denied")
    assert resp.status_code == 200
    durum = client.get(f"/api/auth/status/{fid}").json()
    assert durum["status"] == "error"
    assert durum["error_code"] == "access_denied"


def test_status_bilinmeyen_flow_404_doner(monkeypatch, tmp_path):
    """FlowRegistry bilinmeyen id'de otomatik oturum YARATMAZ, 404 döner."""
    client = taze_ortam(monkeypatch, tmp_path, gateway=FakeOpenGatewayClient())
    resp = client.get("/api/auth/status/boyle-bir-flow-yok")
    assert resp.status_code == 404


def test_status_dogrulanan_flow_devicePhoneNumberVerified_true_doner(monkeypatch, tmp_path):
    """Mobil sözleşmedeki camelCase alan adı yanıtta birebir görünür."""
    client = taze_ortam(monkeypatch, tmp_path, gateway=FakeOpenGatewayClient(verified=True))
    fid = flow_yarat(client)
    client.get(f"/api/auth/callback?state={fid}&code=abc123")
    durum = client.get(f"/api/auth/status/{fid}").json()
    assert durum["devicePhoneNumberVerified"] is True


def test_sahte_onay_sayfasi_endpointi_ARTIK_YOK(monkeypatch, tmp_path):
    """Mock tamamen kaldırıldı: backend kendi başına doğrulama üretemez.

    Eskiden `/api/auth/mock-consent`, Turkcell'in onay sayfasının yerine geçip
    callback'i backend'in kendisi tetikliyordu. Gerçek credential/SIM geldikten
    sonra kaldırıldı — hem gereksiz hem de FTR'nin anti-cheat maddesi açısından
    (kodda "ortama göre farklı davranış" izlenimi veren hiçbir şey kalmasın)
    riskli. Bu test kalıcı bir bekçi: endpoint geri gelirse kırmızıya döner.
    """
    client = taze_ortam(monkeypatch, tmp_path, gateway=FakeOpenGatewayClient())
    resp = client.get("/api/auth/mock-consent?state=deneme-flow", follow_redirects=False)
    assert resp.status_code == 404


def test_authorize_url_turkcelle_gider_kendi_backendimize_degil(monkeypatch, tmp_path):
    """WebView'in açtığı adres GERÇEK Turkcell olmalı — kendi sunucumuz değil.

    Mock döneminde bu URL backend'in kendi sahte onay sayfasını gösteriyordu.
    Bu test, o davranışın hiçbir şekilde geri sızmadığının kanıtı: mobil
    kullanıcı hücresel ağ üzerinden Turkcell'e çıkmazsa NV zaten geçersizdir.
    """
    client = taze_ortam(monkeypatch, tmp_path, gateway=FakeOpenGatewayClient())
    login = client.post("/api/auth/login", json={"phoneNumber": "+905390000020"}).json()

    url = login["authorize_url"]
    assert "/api/auth/mock-consent" not in url
    assert "testserver" not in url, "authorize_url kendi backend'imizi işaret edemez"
    assert "/oauth2/authorize" in url


def test_status_hatada_error_code_ve_message_doner(monkeypatch, tmp_path):
    """status=error iken mobil, error_code + message ile anlamlı mesaj gösterebilir."""
    client = taze_ortam(
        monkeypatch, tmp_path, gateway=FakeOpenGatewayClient(raise_on_exchange=True)
    )
    fid = flow_yarat(client)
    client.get(f"/api/auth/callback?state={fid}&code=suresi-dolmus-kod")
    durum = client.get(f"/api/auth/status/{fid}").json()
    assert durum["status"] == "error"
    assert durum["error_code"] == "invalid_grant"
    assert durum["message"]
