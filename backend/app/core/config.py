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

    # QoD oturum süresi (saniye) — TALEP EDİLEN değer. ÖLÇÜLDÜ (7 Ağustos,
    # 3 bağımsız oturum): Turkcell tarafında QoD oturumu sona erdiği ANDA
    # cihazın veri oturumu resetleniyor — public IP değişiyor ve açık TÜM
    # TCP bağlantıları ölüyor.
    #
    # KESİNLEŞTİ (7 Ağustos, tekrarlanan canlı testler): "teknofest2026"
    # profili GERÇEK TAVANI HER ZAMAN 360 SN'YE KIRPIYOR — 1200 (ya da başka
    # bir değer) talep etsek de fark etmiyor, Turkcell yanıtı hep 360
    # döndürüyor. Yani gerçek bütçe kayıt+yükleme için 360 sn, 1200 değil;
    # 1200 talep etmek zararsız (kırpılıyor) ama yanıltıcı bir güven vermesin.
    # Gerçekte verilen süre yanıttan okunup loglanıyor/mobile taşınıyor.
    #
    # AYRICA KESİNLEŞTİ: Turkcell aynı cihaz için üst üste /start
    # çağrılarını 409 ile REDDETMİYOR — her çağrıda bağımsız, yeni bir 360
    # sn'lik oturum veriyor. routes_qod.py bu yüzden zaten süresi dolmamış
    # bir oturum takip ediyorsa Turkcell'e YENİ istek göndermiyor (bkz.
    # FlowState.qod_remaining_seconds) — aksi halde art arda /start çağrıları
    # (çift dokunma, mobildeki RetryInterceptor) üst üste binen oturumlar
    # açtırıp QoD'nin saatlerce açık kalmasına yol açabiliyordu.
    #
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
