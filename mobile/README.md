# VST-T1 — TEKNOFEST 2026 5G Yol Güvenliği (mobil)

Final akışının mobil ayağı: Number Verification → Quality on Demand → HLS
stream kaydı (maks. 5 dk, MP4) → backend'e yükleme + Lifebox paylaşımı →
video başına tespit sonuçları. Backend sözleşmesi: `../backend/README.md`
Endpoint'ler listesi ve `../PLAN.md`.

## Çalıştırma

Backend adresi ve HLS stream adresi çalıştırma zamanında verilir, koda
gömülmez — final günü ikisi de değişebilir, kod düzenlemesi gerekmez:

```
flutter pub get
flutter run                                            # localhost:8000 backend + Faz2 test stream'i
flutter run --dart-define=BACKEND_URL=http://192.168.1.50:8000 \
            --dart-define=HLS_URL=https://.../playlist.m3u8
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

Final günü backend/stream adresi değişirse `--dart-define=BACKEND_URL=...`
ve/veya `--dart-define=HLS_URL=...` eklenerek build alınır — kaynak kodu
değişmez.

## Bilinen riskler / henüz doğrulanmadı

- **Gerçek Android cihazda hiç test edilmedi (6 Ağustos'taki 3 düzeltme
  dahil)** — Lifebox zip'leme, HLS bant genişliği seçimi ve AI Sonucu
  listesindeki görüntü düzeltmesi yalnızca `flutter test` ile (Dart VM'de)
  doğrulandı. Final öncesi gerçek bir telefonda denenmesi şart.
- **Cellular network bind** (`android/.../MainActivity.kt`): NV'nin
  `/authorize` isteği hücresel veri üzerinden gitmeli. Gerçek Turkcell +
  gerçek SIM ile hiç denenmedi (erişim 7 Ağustos'ta) — final öncesi
  mutlaka test edilmeli.
- **Lifebox**: resmi API/SDK paylaşılmadı; native share sheet ile Lifebox
  uygulamasına gönderiliyor (`lifebox_service.dart`). 6 Ağustos'tan
  itibaren paylaşılmadan önce ZIP'leniyor (`CompressionType.none` —
  Lifebox ham video/MP4'ü "galeri unsuru" sayıp çözünürlüğünü
  düşürebiliyor; organizasyon Q&A'sinde bu netleşti, ayrıca hakem
  Lifebox'tan inen videoyu kendi sistemimizden geçirip canlı demodan
  farklı sonuç bulursa diskalifiye sebebi — detay `PLAN.md`/`note.md`).
- **HLS varyant seçimi** (`hls_variant_service.dart`, 6 Ağustos eklendi):
  kayıt artık ölçülen bant genişliğine göre doğru çözünürlüğü seçiyor
  (şartname 4.2 gereği — ffmpeg'e master playlist verilirse ağ koşulundan
  bağımsız hep en yükseği seçiyordu). Gerçek sunucuya karşı test edildi,
  Android cihazda ffmpeg_kit'in aynı şekilde davrandığı teyit edilmedi.
