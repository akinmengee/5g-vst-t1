from pathlib import Path

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8")

    # 5G Open Gateway (Number Verification, QoD). Tek implementasyon vardır:
    # TurkcellOpenGatewayClient. Alternatif bir istemci ya da ona geçiş yapan
    # bir anahtar YOKTUR — çağrılar her zaman gerçek Turkcell'e gider.
    turkcell_api_base_url: str = ""
    # OAuth2 Authorization Code Flow kimlik bilgileri (OGW_Teknofest.pdf adım 7:
    # HTTP Basic Auth = base64(client_id:client_secret)). Yalnızca backend'de tutulur,
    # mobil uygulamaya asla gömülmez.
    turkcell_client_id: str = ""
    turkcell_client_secret: str = ""
    # Turkcell'e önceden kayıtlı callback adresi, örn:
    # http://<VM_IP>:8080/api/auth/callback
    turkcell_redirect_uri: str = ""

    # QoD oturum süresi (saniye). ÖLÇÜLDÜ (7 Ağustos, 3 bağımsız oturum):
    # Turkcell tarafında QoD oturumu sona erdiği ANDA cihazın veri oturumu
    # resetleniyor — public IP değişiyor ve açık TÜM TCP bağlantıları ölüyor.
    # 360 sn ile bağlantı demo'nun tam ortasında (6. dakika) kopuyordu; oysa
    # canlı demo kayıt (≤5 dk) + yükleme + AI (≤10 dk) ile 15+ dk sürebiliyor.
    # 1200 sn, kopmayı demo bittikten SONRAYA öteliyor.
    # Turkcell talep edilen süreyi kırpabilir (quality-on-demand.yaml:
    # "Implementations can grant the requested session duration or set a
    # different duration") — gerçekte verilen süre yanıttan okunup loglanıyor.
    # Env'den ayarlanabilir: yarışma günü backend'i yeniden derlemeden değişir.
    qod_duration_seconds: int = 1200

    # Tetiklenecek AI imajı. Alternatif bir çalıştırıcı yoktur — AI çıktısı
    # puanlanan şeyin kendisi olduğu için her zaman gerçek imaj çalışır.
    ai_docker_image: str = "teknofest-2026/vst-t1:latest"
    job_storage_path: Path = Path("/srv/jobs")
    # Hakem değerlendirmesindeki inference limitiyle tutarlı (Doküman 1 madde 5).
    job_timeout_seconds: int = 600

    # NV login → WebView → QoD → HLS kaydı → upload zincirinin tamamını kapsayacak
    # genişlikte; erişim oldukça touch ile yenilenir.
    flow_ttl_seconds: float = 1200.0
    # DONE/FAILED job'lar bu süre sonra hafızadan düşürülür; PROCESSING asla düşmez.
    job_result_ttl_seconds: float = 3600.0

    log_level: str = "INFO"


settings = Settings()
