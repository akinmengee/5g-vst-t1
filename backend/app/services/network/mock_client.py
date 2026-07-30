"""Yarışma günü öncesi kullanılan sahte 5G Open Gateway implementasyonu.

Gerçekçi bir gecikme simüle eder ki backend'in davranışı (timeout'lar, eşzamanlılık)
gerçeğe yakın test edilebilsin.

ÖNEMLİ (bkz. plan Kod İncelemesi Bulguları madde 7 / anti-cheat hatırlatması):
Bu implementasyon SADECE geliştirme/test ortamında, `USE_MOCK_5G=true` ile bilinçli
olarak seçilmelidir. Canlı demoda gerçek TurkcellOpenGatewayClient başarısız olursa
BU SINIFA sessizce düşülmemelidir — bu, jüri önünde sahte sonuç üretmek gibi
algılanabilir ve tam da diskalifiye riskini doğurur.
"""

import asyncio
import random


class MockOpenGatewayClient:
    async def verify_number(self) -> bool:
        await asyncio.sleep(0.05)
        return True

    async def request_quality_on_demand(self, session_id: str) -> bool:
        await asyncio.sleep(0.1 + random.uniform(0, 0.05))
        return True
