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

from app.services.network.interface import QodResult, TokenResult


class MockOpenGatewayClient:
    def build_authorize_url(self, flow_id: str, phone_number: str) -> str:
        return f"https://mock-turkcell.local/oauth2/authorize?state={flow_id}"

    async def exchange_code_for_token(self, code: str) -> TokenResult:
        await asyncio.sleep(0.05)
        return TokenResult(access_token=f"mock-token-{code}", expires_in=300)

    async def verify_number(self, access_token: str, phone_number: str) -> bool:
        await asyncio.sleep(0.05)
        return True

    async def start_qod_session(self, access_token: str) -> QodResult:
        await asyncio.sleep(0.1 + random.uniform(0, 0.05))
        return QodResult(session_id=f"mock-session-{uuid.uuid4()}", qos_status="REQUESTED")
