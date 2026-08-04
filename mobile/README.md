# teknofest_mobile — VST T1 5G & YZ Akıllı Yol Güvenliği

TEKNOFEST 2026 finali için mobil uygulama. Akış: Number Verification → Quality
on Demand → HLS stream kaydı (maks. 5 dk, MP4) → backend'e yükleme + Lifebox
paylaşımı → AI sonucu gösterimi.

**Backend sözleşmesi: [`docs/mobile-integration.md`](../docs/mobile-integration.md)**
— tek doğruluk kaynağı odur, bu repoda başka kopyası yok.

## Çalıştırma

```bash
flutter pub get
flutter run                     # gerçek backend, http://localhost:8000
flutter build apk --release     # final günü yüklenecek APK
```

Backend adresi ve mock modu `--dart-define` ile verilir (`lib/config/app_config.dart`);
yarışma günü kod düzenlemeye gerek yok:

```bash
# Backend başka bir makinede / telefonla test:
flutter run --dart-define=BACKEND_URL=http://192.168.1.50:8000

# Backend hiç yokken sadece UI denemek:
flutter run --dart-define=USE_MOCK=true
```

> Gerçek telefonda `localhost` **telefonun kendisini** işaret eder, backend'in
> çalıştığı bilgisayarı değil — mutlaka makinenin LAN IP'sini verin. Backend'in
> `PUBLIC_BASE_URL`'i de aynı adres olmalı (mock onay sayfası WebView'i o adres
> üzerinden callback'e yönlendiriyor).

## Testler

```bash
flutter test                                  # birim + widget testleri
flutter test test/backend_integration_test.dart   # backend ayaktayken
```

`backend_integration_test.dart`, uygulamanın **gerçek servis kodunu gerçek
backend'e** karşı çalıştırır (NV → WebView yönlendirmesi → verified → QoD →
upload → DONE). Sözleşmenin iki tarafının da tuttuğunu kanıtlayan test budur.
Backend ayakta değilse testler sessizce atlanır. Backend'i ayağa kaldırmak için:

```bash
cd backend
JOB_STORAGE_PATH=./.local-jobs USE_MOCK_5G=true python -m uvicorn app.main:app --port 8000
```

## Platform notu — Windows masaüstünde neyin çalıştığı

Proje Windows masaüstünde de derlenip çalışıyor (hızlı UI/HTTP denemesi için),
ama **NV akışı orada test EDİLEMEZ**: `webview_flutter` ve `video_player`
Windows'ta kayıtlı değil (bkz. `windows/flutter/generated_plugin_registrant.cc`
— yalnızca ffmpeg_kit, share_plus, url_launcher var). WebView + video önizleme
mutlaka Android cihaz/emülatörde denenmeli.

## Uygulama notları

- `ffmpeg_kit_flutter` 2025'te retire edildi; yerine aktif bakımlı fork olan
  **`ffmpeg_kit_flutter_new`** kullanılıyor (sözleşme § 5 uyarısı karşılandı).
- **SHA256** (sözleşme § 1 adım 8) `results_service.dart` → `_sha256Of`'ta,
  ayrıştırılmış Map'in compact `jsonEncode` hali üzerinden hesaplanıyor. Bu
  hash'i yalnızca mobil üretir — backend karşılık gelen bir hash hesaplamıyor,
  dolayısıyla eşleştirilecek bir referans yok.
- **WiFi hatası** (sözleşme § 2.3 özel durumu) `nv_service.dart`'taki
  `kWifiErrorCode` sabitiyle yakalanıp NV ekranında kırmızı uyarı kutusu olarak
  gösteriliyor. Cihaz mutlaka hücresel veride olmalı.
- **AI sonucu polling'i** upload biter bitmez `SessionController` içinde
  otomatik başlar (sözleşme § 2.6: 1-2 sn arayla, DONE/FAILED'da durur).
  AppBar'daki yenile butonu yalnızca elle tetikleme kolaylığı.

## Henüz gerçek ortamda denenmedi

- **NV WebView + gerçek SIM**: gerçek Turkcell erişimi 7 Ağustos'ta açılıyor.
  O zamana kadar backend `USE_MOCK_5G=true` ile sahte onay sayfası üzerinden
  tüm zincir çalışıyor (yukarıdaki entegrasyon testi bunu doğruluyor).
- **ffmpeg ile HLS→MP4 kaydı** gerçek Android cihazda: `-c copy` remux
  kullanılıyor (transcode yok); segment formatları uyumsuz çıkarsa
  `-c:v copy -c:a aac` gibi bir fallback gerekebilir.
- **Lifebox**: resmi API/SDK yok, şu an native share sheet ile Lifebox
  uygulamasına gönderiliyor (`lifebox_service.dart`). Yarı-manuel bir adım.
