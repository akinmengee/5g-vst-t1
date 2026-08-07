"""TurkcellOpenGatewayClient testleri — httpx.MockTransport ile.

Gerçek Turkcell'e hiçbir çağrı yapılmaz; istek şekillerinin (URL, header,
body) resmi spec'lere birebir uyduğu doğrulanır. Özellikle
`test_qod_session_body_device_alani_icermiyor`, 422 UNNECESSARY_IDENTIFIER
tuzağına karşı kalıcı regresyon korumasıdır.
"""

import asyncio
import base64
import json

import httpx
import pytest

from app.core.config import settings
from app.services.network.interface import OpenGatewayError
from app.services.network.turkcell_client import TurkcellOpenGatewayClient

_BASE = "https://opengateway.turkcell.com.tr"


def _ayarlar(monkeypatch):
    monkeypatch.setattr(settings, "turkcell_api_base_url", _BASE)
    monkeypatch.setattr(settings, "turkcell_client_id", "test-client-id")
    monkeypatch.setattr(settings, "turkcell_client_secret", "test-secret")
    monkeypatch.setattr(settings, "turkcell_redirect_uri", "http://1.2.3.4:8080/api/auth/callback")


def _istemci(monkeypatch, handler) -> TurkcellOpenGatewayClient:
    _ayarlar(monkeypatch)
    http = httpx.AsyncClient(transport=httpx.MockTransport(handler), base_url=_BASE)
    return TurkcellOpenGatewayClient(http_client=http)


def test_eksik_ayarlarla_kurulum_hemen_hata_verir(monkeypatch):
    """Fail-fast: eksik client_id/secret ilk istekte değil kurulumda patlar."""
    monkeypatch.setattr(settings, "turkcell_api_base_url", _BASE)
    monkeypatch.setattr(settings, "turkcell_client_id", "")
    monkeypatch.setattr(settings, "turkcell_client_secret", "")
    monkeypatch.setattr(settings, "turkcell_redirect_uri", "")
    with pytest.raises(RuntimeError, match="eksik ayarlar"):
        TurkcellOpenGatewayClient()


def test_authorize_url_scope_encoding_dogru(monkeypatch):
    """Scope'ta '#' %23 olmalı, ':' encode edilmemeli (Postman örneğiyle aynı biçim)."""
    client = _istemci(monkeypatch, lambda req: httpx.Response(200))
    url = client.build_authorize_url("flow-123", "+905390000020")
    assert url.startswith(f"{_BASE}/oauth2/authorize?")
    assert "state=flow-123" in url
    assert "prompt=none" in url
    assert "response_type=code" in url
    assert (
        "scope=openid+dpv:RequestedServiceProvision%23quality-on-demand:sessions:create"
        "+dpv:FraudPreventionAndDetection%23number-verification:verify" in url
    )


def test_token_exchange_basic_auth_header_dogru(monkeypatch):
    """client_id:client_secret, Basic Auth header'ında base64 taşınır (query'de değil)."""
    beklenen = base64.b64encode(b"test-client-id:test-secret").decode()

    def handler(request: httpx.Request) -> httpx.Response:
        assert request.url.path == "/oauth2/token"
        assert request.headers["Authorization"] == f"Basic {beklenen}"
        govde = request.content.decode()
        assert "grant_type=authorization_code" in govde
        assert "code=op-auth-code" in govde
        return httpx.Response(200, json={"access_token": "tok-1", "expires_in": 300})

    client = _istemci(monkeypatch, handler)
    sonuc = asyncio.run(client.exchange_code_for_token("op-auth-code"))
    assert sonuc.access_token == "tok-1"
    assert sonuc.expires_in == 300


def test_verify_bearer_token_ve_telefon_gonderir(monkeypatch):
    """NV verify, Bearer token + E.164 phoneNumber body'siyle çağrılır."""

    def handler(request: httpx.Request) -> httpx.Response:
        assert request.url.path == "/number-verification/v1/verify"
        assert request.headers["Authorization"] == "Bearer tok-1"
        assert json.loads(request.content) == {"phoneNumber": "+905390000020"}
        return httpx.Response(200, json={"devicePhoneNumberVerified": True})

    client = _istemci(monkeypatch, handler)
    assert asyncio.run(client.verify_number("tok-1", "+905390000020")) is True


def test_qod_session_body_device_alani_icermiyor(monkeypatch):
    """3-legged token ile 'device' göndermek 422 UNNECESSARY_IDENTIFIER demektir — asla gönderilmez."""

    def handler(request: httpx.Request) -> httpx.Response:
        assert request.url.path == "/quality-on-demand/v1/sessions"
        govde = json.loads(request.content)
        assert "device" not in govde
        assert govde == {
            # Sabit değil: yarışma günü env'den ayarlanabilsin diye
            # config'ten okunuyor (bkz. qod_duration_seconds).
            "duration": settings.qod_duration_seconds,
            "applicationServer": {"ipv4Address": "0.0.0.0/0"},
            "qosProfile": "teknofest2026",
        }
        return httpx.Response(
            201,
            json={
                "sessionId": "qod-1",
                "qosStatus": "REQUESTED",
                "duration": settings.qod_duration_seconds,
            },
        )

    client = _istemci(monkeypatch, handler)
    sonuc = asyncio.run(client.start_qod_session("tok-1"))
    assert sonuc.session_id == "qod-1"
    assert sonuc.qos_status == "REQUESTED"
    assert sonuc.duration == settings.qod_duration_seconds


def test_qod_409_status_code_ile_opengatewayerror_firlatir(monkeypatch):
    """409 Conflict, status_code'u taşıyan OpenGatewayError olarak yükselir."""

    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(
            409, json={"status": 409, "code": "CONFLICT", "message": "aktif oturum var"}
        )

    client = _istemci(monkeypatch, handler)
    with pytest.raises(OpenGatewayError) as exc_info:
        asyncio.run(client.start_qod_session("tok-1"))
    assert exc_info.value.status_code == 409
    assert exc_info.value.error_code == "CONFLICT"


# ---------------------------------------------------------------------------
# QoD oturum süresi ve erken sonlandırma (7 Ağustos bulgusu)
#
# ÖLÇÜM: Turkcell tarafında QoD oturumu sona erdiği ANDA cihazın veri oturumu
# resetleniyor — public IP değişiyor ve açık tüm TCP bağlantıları ölüyor.
# 3 bağımsız oturumda kopma, QoD başlangıcından tam 360 sn sonra gerçekleşti
# (istenen duration da 360'tı). Bu yüzden süre artık yapılandırılabilir ve
# Turkcell'in GERÇEKTEN verdiği süre yanıttan okunuyor.
# ---------------------------------------------------------------------------


def test_qod_verilen_sure_talep_edilenden_farkli_olabilir(monkeypatch):
    """Turkcell süreyi kırparsa bunu bilmeliyiz: bağlantı O ZAMAN kopacak."""

    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(
            201,
            # Spec: "Implementations can grant the requested session duration
            # or set a different duration" — talebimiz 1200 olsa da 360 verildi.
            json={"sessionId": "qod-1", "qosStatus": "REQUESTED", "duration": 360},
        )

    client = _istemci(monkeypatch, handler)
    sonuc = asyncio.run(client.start_qod_session("tok-1"))
    assert sonuc.duration == 360, "kırpılmış süre olduğu gibi raporlanmalı"


def test_qod_yanitinda_duration_yoksa_none_doner(monkeypatch):
    """Alan opsiyonel — yoksa çökmemeli."""

    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(201, json={"sessionId": "qod-1", "qosStatus": "REQUESTED"})

    client = _istemci(monkeypatch, handler)
    assert asyncio.run(client.start_qod_session("tok-1")).duration is None


def test_qod_stop_dogru_endpointe_delete_atar(monkeypatch):
    def handler(request: httpx.Request) -> httpx.Response:
        assert request.method == "DELETE"
        assert request.url.path == "/quality-on-demand/v1/sessions/qod-1"
        assert request.headers["Authorization"] == "Bearer tok-1"
        return httpx.Response(204)

    client = _istemci(monkeypatch, handler)
    assert asyncio.run(client.stop_qod_session("tok-1", "qod-1")) is True


def test_qod_stop_desteklenmiyorsa_istisna_firlatmaz(monkeypatch):
    """Turkcell'in spec'inde DELETE YOK — 404/405 beklenen bir sonuç, hata değil.

    Akışı bloklamaması kritik: bu yalnızca bir temizlik adımı.
    """

    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(405, json={"status": 405, "code": "METHOD_NOT_ALLOWED"})

    client = _istemci(monkeypatch, handler)
    assert asyncio.run(client.stop_qod_session("tok-1", "qod-1")) is False


def test_qod_stop_ag_hatasinda_bile_istisna_sizdirmaz(monkeypatch):
    def handler(request: httpx.Request) -> httpx.Response:
        raise httpx.ConnectError("baglanti yok")

    client = _istemci(monkeypatch, handler)
    assert asyncio.run(client.stop_qod_session("tok-1", "qod-1")) is False
