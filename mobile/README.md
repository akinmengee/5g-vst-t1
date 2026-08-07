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
flutter run --dart-define=BACKEND_URL=http://34.55.33.206:8080 \
            --dart-define=HLS_URL=https://.../playlist.m3u8 \
            --dart-define=PHONE=+90...        # NV alanını ön-doldurur (opsiyonel)
```

Gerçek telefonda `localhost` telefonun kendisidir — backend'in gerçek
adresini (yarışma VM'i ya da bilgisayarın LAN IP'si) vermek gerekir.

**NV doğrulaması artık yalnızca gerçek SIM + hücresel veri ile çalışır.**
Sahte onay sayfası kaldırıldı (bkz. `../backend/README.md`); WiFi üzerinden
denenirse Turkcell doğrulamayı reddeder.

**Akış adresi uygulama içinden de değiştirilebilir:** "Akış" sekmesindeki
AKIŞ ADRESİ alanına final günü verilen URL yapıştırılır, "Faz 2 test yayını"
butonu varsayılana döndürür. `--dart-define=HLS_URL` yalnızca başlangıç
değerini belirler.

## Test

```
flutter test                                  # 72 test; backend kapalıysa
                                              # entegrasyon testleri kendini atlar
flutter test test/backend_integration_test.dart   # gerçek servis kodu, gerçek backend
```

## Dağıtım

```
flutter build apk --release              # tüm mimariler tek APK (~223 MB)
flutter build apk --release --split-per-abi   # cihaz başına küçük APK (arm64 ~62 MB)
```

Final günü backend adresi değişirse `--dart-define=BACKEND_URL=...` eklenerek
build alınır. Stream adresi için build gerekmez — uygulama içindeki alandan
girilir.

## Bilinen riskler / henüz doğrulanmadı

- **7 Ağustos düzeltmeleri yarışma SIM'iyle henüz denenmedi** — QoD'ye bağlı
  varyant seçimi, akış adresi alanı, MD5 parmak izi ve Lifebox paket
  paylaşımı yalnızca `flutter test` ile (Dart VM'de) doğrulandı.
- **NV gerçek SIM ile çalıştı** (7 Ağustos gecesi): `MainActivity.kt`'deki
  hücresel bağlama üzerinden doğrulama başarılı oldu. Aynı gece bağlamanın
  bayatlayıp uygulamanın **tüm ağını** öldürebildiği görüldü ve düzeltildi
  (callback sızıntısı + zaman aşımı yarışı + `onLost`); düzeltmenin kendisi
  cihazda henüz test edilmedi.
- **QoD oturumu bitince veri bağlantısı kopuyor** — ölçüldü: 3 bağımsız
  oturumda kopma, QoD başlangıcından saniyesi saniyesine `duration` kadar
  sonra gerçekleşti. Süre 1200 sn'ye çıkarıldı (backend `QOD_DURATION_SECONDS`)
  ki kopma demo bittikten sonraya düşsün. Turkcell süreyi kırparsa QoD kartında
  gerçek değer görünüyor.
- **Kalite seçimi QoD'ye bağlı** (`hls_variant_service.dart`): QoD açıksa
  1080p, kapalıysa 240p. Akış VOD olduğu için (canlı yayın değil) 8 Mbit'lik
  hatta 9.16 Mbps'lik yayın inebiliyor. 240p bir tercih değil — QoD'siz
  256 kbit'te 1080p ~68 dakika sürerdi. Android'de ffmpeg_kit'in aynı
  davrandığı henüz teyit edilmedi.
- **Lifebox**: resmi API/SDK paylaşılmadı; native share sheet ile
  gönderiliyor (`lifebox_service.dart`). Video paylaşılmadan önce ZIP'leniyor
  (`CompressionType.none` — Lifebox ham MP4'ü "galeri unsuru" sayıp
  çözünürlüğünü düşürebiliyor; hakem Lifebox'tan inen videoyu ayrı bir
  inference'a soktuğu için bu doğrudan puan/diskalifiye riski). AI sonucu
  geldikten sonra results.json + MD5 ikinci bir paylaşımla gönderiliyor.
  **Dosyaların Lifebox'ta aynı klasöre düşmesi garanti edilemez** — hedef
  klasörü Lifebox belirliyor, ikisini tek işlemde göndermek elimizdeki en iyi
  güvence.
