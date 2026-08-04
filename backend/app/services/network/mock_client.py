"""Yarışma günü öncesi kullanılan sahte 5G Open Gateway implementasyonu.

Gerçekçi bir gecikme simüle eder ki backend'in davranışı (timeout'lar, eşzamanlılık)
gerçeğe yakın test edilebilsin.

ÖNEMLİ (anti-cheat hatırlatması): Bu implementasyon SADECE geliştirme/test
ortamında, `USE_MOCK_5G=true` ile bilinçli olarak seçilmelidir. Canlı demoda
gerçek TurkcellOpenGatewayClient başarısız olursa BU SINIFA sessizce
düşülmemelidir — bu, jüri önünde sahte sonuç üretmek gibi algılanabilir ve
tam da diskalifiye riskini doğurur.
"""

import asyncio
import random
import uuid

from app.core.config import settings
from app.services.network.interface import QodResult, TokenResult


class MockOpenGatewayClient:
    def build_authorize_url(self, flow_id: str, phone_number: str) -> str:
        # Gerçek Turkcell'e değil, backend'in kendi sahte onay sayfasına
        # yönlendirir (routes_auth.py::mock_consent). Böylece mobil, WebView
        # açma/kapatma + status polling mantığını gerçek API olmadan uçtan uca
        # test edebilir; ulaşılamayan bir adres olsaydı WebView boş kalır ve
        # callback hiç tetiklenmezdi.
        return f"{settings.public_base_url}/api/auth/mock-consent?state={flow_id}"

    async def exchange_code_for_token(self, code: str) -> TokenResult:
        await asyncio.sleep(0.05)
        return TokenResult(access_token=f"mock-token-{code}", expires_in=300)

    async def verify_number(self, access_token: str, phone_number: str) -> bool:
        await asyncio.sleep(0.05)
        return True

    async def start_qod_session(self, access_token: str) -> QodResult:
        await asyncio.sleep(0.1 + random.uniform(0, 0.05))
        return QodResult(session_id=f"mock-session-{uuid.uuid4()}", qos_status="REQUESTED")
