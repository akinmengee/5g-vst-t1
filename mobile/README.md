# teknofest_mobile — VST T1 5G & YZ Akıllı Yol Güvenliği

TEKNOFEST 2026 finali için mobil uygulama. Akış: Number Verification → Quality
on Demand → HLS stream kaydı (maks. 5 dk, MP4) → backend'e yükleme + Lifebox
paylaşımı → AI sonucu gösterimi. Backend sözleşmesi (Akın): `mobile-integration.md`.

## Ortam

Bu makinede Homebrew ile kuruldu: `flutter`, `android-commandlinetools`,
`openjdk@17`. `~/.zshrc`'ye eklenen PATH/JAVA_HOME satırları yeni terminal
oturumlarında otomatik devreye giriyor. Yeniden kurmak gerekirse:

```
brew install --cask flutter android-commandlinetools
brew install openjdk@17
sdkmanager "platform-tools" "platforms;android-35" "platforms;android-36" \
  "build-tools;35.0.0" "build-tools;28.0.3"
```

## Çalıştırma

```
flutter pub get
flutter run                 # bağlı bir Android cihaz/emülatör gerekir
flutter build apk --debug   # final günü yüklenecek APK için: --release
```

## Mock mod

`lib/config/app_config.dart` içindeki `AppConfig.useMock = true` iken hiçbir
gerçek backend/Turkcell çağrısı yapılmaz; NV/QoD/upload/AI-result akışının
tamamı sahte gecikmeli yanıtlarla simüle edilir. Akın'ın backend'i hazır
olunca `useMock = false` yapıp `backendBaseUrl`'i güncelleyin.

## Bilinen riskler / henüz test edilmedi

- **NV WebView akışı**: `mobile-integration.md` § 2.1'e göre `authorize_url`
  uygulama-içi WebView'de açılıyor (`nv_webview_sheet.dart`), backend
  yönlendirmeleri kendi içinde takip ediyor. Gerçek backend + gerçek SIM ile
  hiç test edilmedi — final öncesi mutlaka denenmeli. Cihaz mutlaka hücresel
  veride olmalı (WiFi'de NV kesin başarısız olur, § 3).
- **SHA256 hash formatı**: backend'in tam serileştirme biçimi belirtilmediği
  için `jsonEncode(jsonDecode(...))` ile hesaplanıyor — Akın'ın hash'iyle
  örtüşmezse `results_service.dart` → `_sha256Of` güncellenmeli.
- **ffmpeg ile HLS→MP4 kaydı** (`video_recording_service.dart`): gerçek
  cihazda hiç çalıştırılmadı. `-c copy` remux kullanıyoruz (transcode yok);
  eğer stream segment formatları uyumsuz çıkarsa `-c:v copy -c:a aac` gibi
  bir fallback gerekebilir.
- **Lifebox**: resmi API/SDK yok, şu an native share sheet ile Lifebox
  uygulamasına gönderiliyor (`lifebox_service.dart`). Yarı-manuel bir adım.
