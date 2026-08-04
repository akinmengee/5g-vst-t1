"""OpenGatewayClient v2 için el yazımı sahte sınıf — route testlerinde kullanılır.

tests/stubs.py'deki felsefeyle aynı: mock kütüphanesi yerine davranışı
constructor'dan yapılandırılabilen düz Python sınıfları.
"""

import uuid

from app.services.network.interface import OpenGatewayError, QodResult, TokenResult


class FakeOpenGatewayClient:
    def __init__(
        self,
        *,
        verified: bool = True,
        qod_status_code: int = 201,
        qod_session_id: str = "fake-session",
        raise_on_exchange: bool = False,
        raise_on_verify: bool = False,
    ) -> None:
        self._verified = verified
        self._qod_status_code = qod_status_code
        self._qod_session_id = qod_session_id
        self._raise_on_exchange = raise_on_exchange
        self._raise_on_verify = raise_on_verify

    def build_authorize_url(self, flow_id: str, phone_number: str) -> str:
        return f"https://fake-turkcell.local/oauth2/authorize?state={flow_id}"

    async def exchange_code_for_token(self, code: str) -> TokenResult:
        if self._raise_on_exchange:
            raise OpenGatewayError(401, "invalid_grant", "kod geçersiz/süresi dolmuş")
        return TokenResult(access_token=f"fake-token-{uuid.uuid4()}", expires_in=300)

    async def verify_number(self, access_token: str, phone_number: str) -> bool:
        if self._raise_on_verify:
            raise OpenGatewayError(
                403,
                "NUMBER_VERIFICATION.USER_NOT_AUTHENTICATED_BY_MOBILE_NETWORK",
                "Client must authenticate via the mobile network",
            )
        return self._verified

    async def start_qod_session(self, access_token: str) -> QodResult:
        if self._qod_status_code != 201:
            raise OpenGatewayError(self._qod_status_code, "QOD_HATA", "qod hata")
        return QodResult(session_id=self._qod_session_id, qos_status="REQUESTED")
