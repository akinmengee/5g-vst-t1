"""OpenGatewayClient arayüzü v2 — 3-legged OIDC Authorization Code Flow + QoD.

Gerçek akış (OGW_Teknofest.pdf): mobil, backend'in ürettiği authorize URL'ine
hücresel veri üzerinden gider → Turkcell, backend'in redirect_uri'sine `code`
ile döner → backend code'u token'a çevirir → token ile NV verify ve QoD
sessions çağrıları yapılır. Eski tek-metotlu "verify_number() -> bool" tasarımı
bu protokolle şekil olarak uyuşmadığı için değiştirildi (plan bulgusu A8).

Bu protokolün TEK implementasyonu vardır: TurkcellOpenGatewayClient. Sahte bir
istemci ya da ona geçiş yapan bir anahtar yoktur — Turkcell çağrısı başarısız
olursa hata olduğu gibi yüzeye çıkar, üretilmiş bir sonuçla maskelenmez.
Protokolün ayrı bir tip olarak durmasının sebebi testlerin gerçek ağa çıkmadan
route davranışını sınayabilmesidir (bkz. `tests/network_stubs.py`).
"""

from typing import Protocol

from pydantic import BaseModel


class OpenGatewayError(Exception):
    """Turkcell'den 2xx dışı bir yanıt geldiğinde fırlatılır.

    `status_code` route katmanındaki dallanma için (örn. QoD 409 = zaten aktif
    oturum, hata değil), `error_code` Turkcell'in makine-okunur hata kodu için
    (örn. NUMBER_VERIFICATION.USER_NOT_AUTHENTICATED_BY_MOBILE_NETWORK —
    cihaz WiFi'deyken NV'nin döndüğü 403).
    """

    def __init__(self, status_code: int, error_code: str | None, message: str) -> None:
        self.status_code = status_code
        self.error_code = error_code
        super().__init__(f"[{status_code}] {error_code}: {message}")


class TokenResult(BaseModel):
    access_token: str
    expires_in: int  # saniye; Turkcell'de sabit 300 (5 dakika)


class QodResult(BaseModel):
    session_id: str | None = None
    qos_status: str | None = None  # 201 yanıtında beklenen değer: "REQUESTED"
    # Turkcell'in GERÇEKTEN verdiği süre (saniye). Talep ettiğimizden farklı
    # olabilir (spec: "Implementations can grant the requested session duration
    # or set a different duration"). Bunu bilmek kritik: oturum bittiği anda
    # cihazın veri bağlantısı kopuyor, yani bu değer "ne zaman kopacağız"
    # sorusunun cevabı.
    duration: int | None = None


class OpenGatewayClient(Protocol):
    def build_authorize_url(self, flow_id: str, phone_number: str) -> str:
        """Turkcell /oauth2/authorize URL'ini üretir (I/O yok, ağ çağrısı yok).

        Mobil bu URL'i bir WebView'de açar; `state` parametresi flow_id taşır.
        """
        ...

    async def exchange_code_for_token(self, code: str) -> TokenResult:
        """POST /oauth2/token — authorization code'u access token'a çevirir."""
        ...

    async def verify_number(self, access_token: str, phone_number: str) -> bool:
        """POST /number-verification/v1/verify — devicePhoneNumberVerified döner."""
        ...

    async def start_qod_session(self, access_token: str) -> QodResult:
        """POST /quality-on-demand/v1/sessions — yalnızca 201'de sonuç döner.

        409 dahil her non-2xx durumda OpenGatewayError fırlatır; "zaten aktif
        oturum başarı sayılır" gibi puanlama kuralları çağıranın (routes_qod)
        sorumluluğundadır.
        """
        ...

    async def stop_qod_session(self, access_token: str, session_id: str) -> bool:
        """DELETE /quality-on-demand/v1/sessions/{id} — EN İYİ ÇABA.

        Turkcell'in paylaştığı `quality-on-demand.yaml` yalnızca `POST
        /sessions` (createSession) içeriyor; silme operasyonu spec'te YOK.
        Yine de CAMARA standardında bu endpoint var ve Turkcell onu
        uygulamış OLABİLİR — desteklenmiyorsa 404/405 döner, o zaman
        sessizce `False` döneriz ve akış etkilenmez.

        Neden gerekli: oturum bitene kadar aynı cihaz için ikinci bir oturum
        açılamıyor (409). 1200 sn'lik süreyle bu 20 dakikalık bir kilit
        demek; uygulamayı kapatıp yeniden denemek isteyen kullanıcı için
        temizlenebilmesi lazım.
        """
        ...
