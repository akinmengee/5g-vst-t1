# VST-T1 — TEKNOFEST 2026 5G Yol Güvenliği (mobil)

Final akışının mobil ayağı: Number Verification → Quality on Demand → HLS
stream kaydı (maks. 5 dk, MP4) → backend'e yükleme + Lifebox paylaşımı →
video başına tespit sonuçları. Backend sözleşmesinin tek doğruluk kaynağı:
`../docs/mobile-integration.md`.

## Çalıştırma

Backend adresi çalıştırma zamanında verilir, koda gömülmez:

```
flutter pub get
flutter run                                            # localhost:8000'deki backend
flutter run --dart-define=BACKEND_URL=http://192.168.1.50:8000
```

Gerçek telefonda `localhost` telefonun kendisidir — bilgisayarın LAN IP'sini
verin ve backend'i aynı adresle (`PUBLIC_BASE_URL`) çalıştırın; mock onay
sayfası WebView'i o adres üzerinden callback'e yönlendirir:

```
cd backend
JOB_STORAGE_PATH=./.local-jobs USE_MOCK_5G=true PUBLIC_BASE_URL=http://192.168.1.50:8000 \
  python -m uvicorn app.main:app --host 0.0.0.0 --port 8000
```

## Test

```
flutter test                                  # birim + widget; backend kapalıysa
                                              # entegrasyon testleri kendini atlar
flutter test test/backend_integration_test.dart   # gerçek servis kodu, gerçek backend
```

## Dağıtım

```
flutter build apk --release              # tüm mimariler tek APK (~220 MB)
flutter build apk --release --split-per-abi   # cihaz başına küçük APK (arm64 ~62 MB)
```

## Bilinen riskler / henüz doğrulanmadı

- **Cellular network bind** (`android/.../MainActivity.kt`): NV'nin
  `/authorize` isteği hücresel veri üzerinden gitmeli. Gerçek Turkcell +
  gerçek SIM ile hiç denenmedi (erişim 7 Ağustos'ta) — final öncesi
  mutlaka test edilmeli.
- **Lifebox**: resmi API/SDK paylaşılmadı; native share sheet ile Lifebox
  uygulamasına gönderiliyor (`lifebox_service.dart`), yarı-manuel adım.
