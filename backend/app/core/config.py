from pathlib import Path

from pydantic_settings import BaseSettings, SettingsConfigDict

BACKEND_DIR = Path(__file__).resolve().parents[2]


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8")

    # Model ağırlıklarının bulunduğu klasör. Script konumuna göre sabit varsayılan;
    # cwd'ye bağımlı değil (predict.py'deki WEIGHTS_DIR sorununun çözümü).
    model_dir: Path = BACKEND_DIR / "weights"

    # 5G Open Gateway (Number Verification, QoD) gerçek API'ler yarışma günü verilecek.
    # True iken MockOpenGatewayClient, False iken TurkcellOpenGatewayClient kullanılır.
    # Bu bir "ortam tespiti" değil, deploy zamanında bilinçli seçilen bir konfigürasyondur.
    use_mock_5g: bool = True

    turkcell_api_base_url: str = ""
    turkcell_api_key: str = ""

    log_level: str = "INFO"


settings = Settings()
