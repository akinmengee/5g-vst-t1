from pathlib import Path

from pydantic_settings import BaseSettings, SettingsConfigDict

BACKEND_DIR = Path(__file__).resolve().parents[2]


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8")

    # Model ağırlıklarının bulunduğu klasör. Script konumuna göre sabit varsayılan;
    # cwd'ye bağımlı değil (predict.py'deki WEIGHTS_DIR sorununun çözümü).
    model_dir: Path = BACKEND_DIR / "weights"

    # 5G Open Gateway (Number Verification, QoD).
    # True iken MockOpenGatewayClient, False iken TurkcellOpenGatewayClient kullanılır.
    # Bu bir "ortam tespiti" değil, deploy zamanında bilinçli seçilen bir konfigürasyondur.
    use_mock_5g: bool = True

    turkcell_api_base_url: str = ""
    # OAuth2 Authorization Code Flow kimlik bilgileri (OGW_Teknofest.pdf adım 7:
    # HTTP Basic Auth = base64(client_id:client_secret)). Yalnızca backend'de tutulur,
    # mobil uygulamaya asla gömülmez.
    turkcell_client_id: str = ""
    turkcell_client_secret: str = ""
    # Turkcell'e önceden kayıtlı callback adresi, örn:
    # http://<VM_IP>:8080/api/auth/callback
    turkcell_redirect_uri: str = ""

    # Backend'e DIŞARIDAN (telefon/emülatör) erişilebilen adres. Yalnızca mock
    # modda kullanılır: MockOpenGatewayClient.build_authorize_url() mobili
    # buradaki sahte onay sayfasına yönlendirir (routes_auth.py::mock_consent).
    # "localhost" fiziksel bir telefonda BACKEND'i değil telefonun kendisini
    # işaret eder — gerçek cihazla test ederken LAN IP'si yazın
    # (örn. http://192.168.1.50:8000).
    public_base_url: str = "http://localhost:8000"

    # Tetiklenecek AI imajı. Sahte bir çalıştırıcı yoktur — AI çıktısı puanlanan
    # şeyin kendisi olduğu için her zaman gerçek imaj çalışır.
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
