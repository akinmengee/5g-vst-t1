"""Gerçek Turkcell Open Gateway implementasyonu (httpx).

Resmi kaynaklara birebir uygundur:
- OGW_Teknofest.pdf: 3-legged Authorization Code Flow (adım 3-8: authorize URL,
  Basic Auth ile token exchange), NV verify (adım 9), QoD sessions (adım 14).
- number-verification.yaml / quality-on-demand.yaml (CAMARA OpenAPI spec'leri).
- Postman koleksiyonu: gerçek endpoint yolları (/oauth2/authorize, /oauth2/token,
  /number-verification/v1/verify, /quality-on-demand/v1/sessions).

client_id/client_secret yalnızca backend'de tutulur, mobil uygulamaya asla
gömülmez (OGW_Teknofest.pdf "Önemli Notlar").
"""

import base64
import logging
from urllib.parse import urlencode

import httpx

from app.core.config import settings
from app.services.network.interface import OpenGatewayError, QodResult, TokenResult

logger = logging.getLogger(__name__)

# /oauth2/authorize'daki ilk istekte HEM NV HEM QoD scope'u birlikte istenir —
# böylece NV sırasında alınan tek access_token (5 dk içinde) QoD için de
# yeniden kullanılabilir (OGW_Teknofest.pdf "Önemli Notlar" scope tablosu).
_SCOPE = (
    "openid dpv:RequestedServiceProvision#quality-on-demand:sessions:create "
    "dpv:FraudPreventionAndDetection#number-verification:verify"
)


class TurkcellOpenGatewayClient:
    def __init__(self, http_client: httpx.AsyncClient | None = None) -> None:
        missing = [
            name
            for name in (
                "turkcell_api_base_url",
                "turkcell_client_id",
                "turkcell_client_secret",
                "turkcell_redirect_uri",
            )
            if not getattr(settings, name)
        ]
        if missing:
            raise RuntimeError(
                "TurkcellOpenGatewayClient için eksik ayarlar: " + ", ".join(missing)
            )
        # http_client parametresi test edilebilirlik için: testler, isteği ağa
        # çıkarmadan yakalayan bir taşıyıcıya (transport) sahip AsyncClient
        # enjekte eder — böylece istek şekli gerçek Turkcell'e dokunmadan
        # doğrulanabilir (bkz. tests/test_turkcell_client.py).
        self._client = http_client or httpx.AsyncClient(
            base_url=settings.turkcell_api_base_url, timeout=10.0
        )

    def build_authorize_url(self, flow_id: str, phone_number: str) -> str:
        params = {
            "response_type": "code",
            "client_id": settings.turkcell_client_id,
            "redirect_uri": settings.turkcell_redirect_uri,
            "state": flow_id,
            "scope": _SCOPE,
            "prompt": "none",
        }
        # safe=":" — scope içindeki "dpv:...#...:sessions:create" değerlerinde
        # ':' encode edilmemeli, '#' ise %23 olmalı (Postman koleksiyonundaki
        # örnek istekle birebir aynı biçim).
        return f"{settings.turkcell_api_base_url}/oauth2/authorize?{urlencode(params, safe=':')}"

    async def exchange_code_for_token(self, code: str) -> TokenResult:
        basic = base64.b64encode(
            f"{settings.turkcell_client_id}:{settings.turkcell_client_secret}".encode()
        ).decode()
        resp = await self._client.post(
            "/oauth2/token",
            headers={"Authorization": f"Basic {basic}"},
            data={
                "grant_type": "authorization_code",
                "code": code,
                "redirect_uri": settings.turkcell_redirect_uri,
            },
        )
        self._raise_for_status(resp)
        body = resp.json()
        return TokenResult(access_token=body["access_token"], expires_in=body["expires_in"])

    async def verify_number(self, access_token: str, phone_number: str) -> bool:
        resp = await self._client.post(
            "/number-verification/v1/verify",
            headers={"Authorization": f"Bearer {access_token}"},
            json={"phoneNumber": phone_number},
        )
        self._raise_for_status(resp)
        return bool(resp.json()["devicePhoneNumberVerified"])

    async def start_qod_session(self, access_token: str) -> QodResult:
        # ÖNEMLİ: "device" alanı KESİNLİKLE gönderilmiyor — 3-legged token
        # cihazı zaten örtük tanımlar; gönderilirse Turkcell 422
        # UNNECESSARY_IDENTIFIER döner (quality-on-demand.yaml).
        resp = await self._client.post(
            "/quality-on-demand/v1/sessions",
            headers={"Authorization": f"Bearer {access_token}"},
            json={
                # Süre artık sabit değil: oturum bittiği anda cihazın veri
                # bağlantısı kopuyor (7 Ağustos ölçümü), bu yüzden demo
                # süresini kapsayacak kadar uzun olmalı. bkz. config.py.
                "duration": settings.qod_duration_seconds,
                "applicationServer": {"ipv4Address": "0.0.0.0/0"},
                "qosProfile": "teknofest2026",
            },
        )
        self._raise_for_status(resp)  # 409 dahil her non-2xx OpenGatewayError olur
        body = resp.json()
        verilen = body.get("duration")
        if verilen is not None and verilen != settings.qod_duration_seconds:
            # Turkcell talebi kırptı: bağlantı BU süre sonunda kopacak.
            logger.warning(
                "QoD süresi kırpıldı: %s sn istendi, %s sn verildi — "
                "veri bağlantısı %s sn sonra kopabilir.",
                settings.qod_duration_seconds,
                verilen,
                verilen,
            )
        else:
            logger.info("QoD oturumu açıldı: %s sn", verilen)
        return QodResult(
            session_id=body.get("sessionId"),
            qos_status=body.get("qosStatus"),
            duration=verilen,
        )

    async def stop_qod_session(self, access_token: str, session_id: str) -> bool:
        # EN İYİ ÇABA: bu endpoint Turkcell'in paylaştığı spec'te YOK
        # (yalnızca POST /sessions var), ama CAMARA standardında var ve
        # uygulanmış olabilir. Desteklenmiyorsa 404/405 gelir — akışı
        # etkilememesi için hiçbir durumda istisna fırlatmıyoruz.
        try:
            resp = await self._client.delete(
                f"/quality-on-demand/v1/sessions/{session_id}",
                headers={"Authorization": f"Bearer {access_token}"},
            )
        except Exception:
            logger.warning("QoD oturumu kapatılamadı (ağ hatası): %s", session_id)
            return False
        if resp.status_code // 100 == 2:
            logger.info("QoD oturumu kapatıldı: %s", session_id)
            return True
        logger.info(
            "QoD oturumu kapatma desteklenmiyor/başarısız (HTTP %s): %s — "
            "oturum kendi süresi dolunca sonlanacak.",
            resp.status_code,
            session_id,
        )
        return False

    @staticmethod
    def _raise_for_status(resp: httpx.Response) -> None:
        # httpx'in raise_for_status()'u bilerek kullanılmıyor: generic
        # HTTPStatusError, status_code dallanmasını (QoD 409 = zaten aktif) ve
        # Turkcell'in makine-okunur hata kodunu kaybettirirdi.
        if resp.status_code // 100 != 2:
            try:
                body = resp.json()
            except ValueError:
                body = {}
            raise OpenGatewayError(
                status_code=resp.status_code,
                error_code=body.get("code"),
                message=body.get("message", resp.text),
            )
