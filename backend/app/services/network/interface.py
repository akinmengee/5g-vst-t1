"""OpenGatewayClient arayüzü — Mimari Kararlar madde 3 ve 6.

Turkcell 5G Open Gateway (Number Verification, QoD) API'leri yarışma günü
verilecek, önceden test edilemiyor. Bu yüzden gerçek ve mock implementasyon
aynı arayüzü uygular; hangisinin kullanılacağı `settings.use_mock_5g` ile
(deploy zamanında bilinçli seçilerek, "ortam tespiti" yaparak DEĞİL) seçilir.
"""

from typing import Protocol


class OpenGatewayClient(Protocol):
    async def verify_number(self) -> bool:
        """Number Verification API — oturum başında şebeke seviyesinde sessiz kimlik doğrulama."""
        ...

    async def request_quality_on_demand(self, session_id: str) -> bool:
        """QoD API — araç tespit edildiğinde bant genişliği/gecikme önceliği talep eder."""
        ...
