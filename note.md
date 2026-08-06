# Kod İnceleme Notları — 5 Ağustos 2026

Bu dosya `/code-review` ile (10 paralel arama ajanı + kaynak kodu okuyarak
tek tek doğrulama) tespit edilen, **kodda hiçbir değişiklik yapılmadan**
bırakılmış bulguları listeliyor. `ai/` ve `mobile/` üzerinde aktif paralel
geliştirme sürdüğü için düzeltme kararı bilerek ilgili geliştiriciye
bırakıldı — burada sadece "şu satırda şu oluyor, kök nedeni bu" anlatılıyor.

## Bu notu okuyan Claude'a

Aşağıdaki her madde kaynak dosya okunarak doğrulandı (varsayım/iddia değil,
"CONFIRMED"). Bu repo üzerinde çalışan bir sonraki Claude Code oturumu için:

1. Bir maddeyi ele almadan önce ilgili dosya/satırı yeniden oku — kod bu not
   yazıldıktan sonra değişmiş olabilir, madde hâlâ geçerli mi doğrula.
2. Burada **hiçbir düzeltme uygulanmadı** — geliştirici onayı almadan kod
   değiştirme. Özellikle `ai/src/predict.py` aktif olarak AI ekibi tarafından
   geliştiriliyor; oradaki bulgular önce onlarla konuşulmalı.
3. Kök neden + somut başarısızlık senaryosu her maddede var; "bug var" değil
   "şu girdide şu çıktı yanlış olur" formatında — tekrar üretmek için yeterli.

---

## AI tarafı — `ai/src/predict.py`, `ai/main.py` (puanlamayı doğrudan etkiler)

### 1. Emniyet kemeri ihlali, bir kez "kemer var" görülünce kalıcı olarak kapanıyor
**Dosya:** `ai/src/predict.py:1206-1242`

Kod iki adımlı çalışıyor: (1) `yolo_kayit["kemer"]` listesinin **tamamını**
baştan sona tarayıp videoda herhangi bir yerde 2 kez "Kemer Var" (cls_id==1)
görülür görülmez `kemer_onaylandi = True` yapıp döngüden çıkıyor (satır
1213-1221). (2) Gerçek ihlal detektörü — ardışık 5 kare "Kemer Yok" arayan
mantık — yalnızca `if not kemer_onaylandi:` bloğunun içinde (satır 1224).

**Kök neden:** `kemer_onaylandi` video boyunca sadece bir kez True olabilen,
bir daha asla False'a dönmeyen global bir bayrak. "Sürücü başta kemer taktı"
bilgisi, videonun geri kalanında kemer çıkarılsa bile ihlal aramayı tamamen
susturuyor.

**Somut senaryo:** Sürücü videonun ilk 10 saniyesinde kemer takılı, sonraki
4-5 dakika kemersiz sürüyor (gerçek hayatta en yaygın ihlal deseni). Adım 1
`kemer_onaylandi=True` yapıyor, adım 2 hiç çalışmıyor, `emniyet_kemeri_ihlali`
results.json'a asla yazılmıyor — halbuki gerçek, uzun süreli bir ihlal var.

### 2. Video sonunda "etiket başına maksimum 1" filtresi gerçek tekrar ihlalleri siliyor
**Dosya:** `ai/src/predict.py:1270-1286` (özellikle satır 1277: `max_allowed = 1`)

Kararlar zaten 5 saniyelik cooldown'dan geçip `vehicle_events`'e yazıldıktan
sonra (satır 1262-1268), post-processing'in son adımı her `etiket` için
video genelinde **koşulsuz** en fazla 1 kayıt bırakıyor. Yorum satırı
("İçi/dışı olarak etiketlenmiş… maksimum 1 kez") bunun yalnızca
teknocan/bilgisayar için düşünüldüğünü gösteriyor, ama kod ayrım yapmadan
`sigara_icme`, `telefonla_konusma`, `esneme`, `su_icme`, `arkaya_bakma`,
`etrafa_bakinma`, `emniyet_kemeri_ihlali` dahil her etikete uygulanıyor.

**Somut senaryo:** Sürücü videonun 10. ve 90. saniyelerinde iki ayrı kez
sigara içiyor (cooldown'u ikisi de geçiyor, ikisi de `vehicle_events`'e
giriyor). Bu son filtre ikinci olayı sessizce atıyor; results.json'da tek bir
`sigara_icme` kalıyor.

### 3. Aynı filtrede sayım sırası hatası teknocan/bilgisayarı duplike edebiliyor
**Dosya:** `ai/src/predict.py:1279-1283`

`seen_counts[etiket]` **ham** etikete (`teknocan_ici` / `teknocan_disi`) göre
tutuluyor, ama etiket **normalize edilmiş isme** (`teknocan`) satır
1282-1283'te — yani sayımdan **sonra** — dönüştürülüyor.

**Somut senaryo:** Bir videoda ayrı bir `teknocan_ici` olayı ve ayrı bir
`teknocan_disi` olayı varsa, ikisi de kendi anahtarında `<= 1` şartını
bağımsız geçiyor, ikisi de `"teknocan"`e yeniden adlandırılıyor — sonuçta
"etiket başına maks 1" niyetine rağmen results.json'da iki `teknocan`
tespiti oluşuyor.

### 4. Ağırlık dosyası eksik/bozuksa results.json hiç yazılmadan çöküyor
**Dosya:** `ai/main.py:19`, `ai/src/predict.py:133-167`

`main.py`'nin kendi docstring'i şunu vaat ediyor: *"Hata durumunda bile
geçerli bir results.json bırakılır."* Ama bu garanti `main()`'in
`try/except`'i (satır 42-59) tarafından sağlanıyor — ve `from src.predict
import run_inference` satırı (main.py:19) bu try/except'in **dışında**,
modül import edilirken çalışıyor. `predict.py`'de ~17 `YOLO(...)`/`torch.load`
çağrısı modül seviyesinde (import anında) çalışıyor (satır 134-167).

**Somut senaryo:** `ai/weights/` klasöründe 19 dosya var, Dockerfile
yalnızca 16'sını isim isim `COPY` ediyor. Bir isim uyuşmazlığı/eksik dosya
durumunda import satırı `FileNotFoundError` ile patlıyor — bu, `main()`'in
try bloğunun dışında olduğu için hiç yakalanmıyor, results.json hiç
yazılmıyor, konteyner non-zero exit ile çöküyor. Hakem tarafında bu "dosya
yok" (program hiç çalışmadı) ile karışabilir — main.py'nin docstring'i tam
olarak bunu önlemeyi hedefliyordu.

---

## Mobil tarafı — `mobile/lib/...`

Not: Daha önce bu repo'da mobil tarafta bir dizi bug (WebView geri-tuşu
tuzağı, çift render, vb.) düzeltilip `mobile/CLAUDE.md`'de belgelenmişti.
`f767960` commit'i ("Mobili telefonda doğrulanmış üretim sürümüyle
değiştir") mobile/'ı arkadaşın kendi geliştirdiği yeni, çoklu-kayıt
destekli üretim sürümüyle değiştirdi — bu süreçte `mobile/CLAUDE.md` da
silindi ve aşağıdaki bug'lardan bazıları (5, 8) geri geldi. Bu **kimsenin
suçu değil** — muhtemelen yeni sürüm, düzeltmelerden önceki bir dala göre
yazıldı.

### 5. WebView geri-tuşu tuzağı geri geldi
**Dosya:** `mobile/lib/screens/nv_screen.dart:43-49`

`_openWebView`, `Navigator.push` dönünce yalnızca yerel `_webViewOpen =
false` yapıyor; `SessionController`'a "kullanıcı iptal etti" diye hiçbir
sinyal gitmiyor (eski `cancelPendingLogin()` / `_nvGeneration` mekanizması
tamamen kalkmış).

**Somut senaryo:** Kullanıcı "Doğrula"ya basar, WebView açılır, doğrulama
tamamlanmadan geri tuşuna basar. `session.status` hâlâ `authorizing`,
`authorizeUrl` hâlâ dolu — bir sonraki frame'de `NvScreen.build()`'deki
postFrameCallback koşulu tekrar true olup WebView'i anında yeniden açıyor.
Kullanıcı 60 saniyelik poll timeout'una kadar giriş ekranından çıkamıyor.

### 6. Kayıt sırasında çıkış yapmak bayat kaydı geri ekliyor (race condition)
**Dosya:** `mobile/lib/state/session_controller.dart:388-406` (`logout`) ve
`228-259` (`startRecording`)

`logout()`, kayıt sürüyorsa `_recordingService.stopRecording()`'i
**beklemeden** (await'siz) tetikliyor, sonra hemen `recordings.clear()`
yapıp yeni oturuma geçiyor. `startRecording()`'in beklediği Future (satır
235) o an hâlâ pending — ffmpeg iptali biraz sonra çözülünce o eski await
devam ediyor ve `recordings.insert(0, item)` (satır 254) çalışarak çıkış
yapılmış/temizlenmiş oturuma ait bir kaydı listeye geri sokuyor.

### 7. Başarısız AI işleri için "yenile" butonu artık hiçbir şey yapmıyor
**Dosya:** `mobile/lib/state/session_controller.dart:334-338`

`refreshAiResults()`, sorgulanacak işleri `r.aiStatus ==
AiResultStatus.processing` filtresiyle seçiyor. Bir iş bir kez `failed`
olduğunda bu filtreden bir daha asla geçmiyor — hiçbir çağrı yolu
(AppBar yenile butonu, pull-to-refresh, otomatik poll) onu tekrar
sorgulamıyor. Ekrandaki "yenile butonuyla tekrar deneyebilirsiniz" mesajı
gerçekte hiçbir şey tetiklemiyor.

### 8. `VideoCard` çift dinleme/çift rebuild geri geldi
**Dosya:** `mobile/lib/widgets/video_card.dart:43-50, 69`

`_VideoCardState.initState()` artık `widget.controller.addListener(...)`
çağırıyor. `HomeScreen` zaten `context.watch<SessionController>()` ile aynı
controller'ı dinleyip `VideoCard`'ı her `notifyListeners()`'da yeniden
kuruyor — bu ikinci abonelik, aynı olayda ikinci bir rebuild yolu açıyor.
Kayıt sırasında saniyede bir tetiklenen `recordingElapsed` güncellemesi
veya 2sn'lik AI-poll bu yüzden her seferinde iki kez render tetikliyor.

### 9. Telefon numarası ekranın kendi ipucu formatıyla girilirse backend'i 422'ye düşürüyor
**Dosya:** `mobile/lib/screens/nv_screen.dart:124`

```dart
final full = '$_countryCode${localNumberController.text.trim()}';
```

Yalnızca baş/son boşluk kırpılıyor, iç boşluklar temizlenmiyor. Alanın
kendi `hintText`'i ise `'555 111 22 33'` — yani kullanıcıyı boşluklu
girmeye teşvik ediyor. Kullanıcı ipucuna uyup boşluklu yazarsa
`full = '+90555 111 22 33'` backend'e gidiyor, `/api/auth/login` 422
dönüyor, kullanıcı "E.164 formatında olmalı" hatası görüyor.

---

## Düşük öncelikli (kozmetik / latent — acil değil ama not düşülsün)

### 10. `DioException` dışı hatalar loading bayraklarını sonsuza kilitliyor
**Dosyalar:** `mobile/lib/services/nv_service.dart`, `qod_service.dart`,
`results_service.dart` — hepsi yalnızca `on DioException catch` kullanıyor.
Backend beklenmedik bir JSON şekli dönerse (örn. cast hatası → `TypeError`,
`DioException` değil), bu hiçbir catch'e girmiyor; çağıran taraftaki
`nvLoading`/`qodLoading`/`item.uploadState` bayrağı sıfırlanmadan sonsuza
kalıyor.

### 11. `backend/README.md` kaldırılmış `AI_RUNNER_MODE` ayarına hâlâ referans veriyor
**Dosya:** `backend/README.md:105` — `MockAiRunner` tamamen kaldırıldığından
bu env değişkeni artık yok; `DockerAiRunner` şu an koşulsuz `docker` CLI'ı
PATH'te bekliyor (bu kasıtlı bir tasarım, sadece doküman güncel değil).

### 12. `NvSession.copyWith` `errorCode`/`errorMessage`'ı sessizce sıfırlıyor
**Dosya:** `mobile/lib/models/nv_session.dart:39-46` — diğer 4 alan `??
this.field` ile korunuyor, bu ikisi parametre verilmezse doğrudan `null`
oluyor. Şu an hiçbir çağrı noktası bunu tetiklemiyor (hepsi ihtiyacı olanı
açıkça geçiyor) ama gelecekte eklenecek bir `copyWith(status: ...)` çağrısı
ekrandaki bir hata mesajını sessizce silebilir.

---

*Bu not `/code-review` çıktısının insan-okur özeti olarak hazırlandı; kaynak
ajan çıktıları ve doğrulama detayları bu oturumun `ReportFindings`
kaydında mevcut.*

---

# 6 Ağustos 2026 — Yapılan değişiklikler + toplantı Q&A çıkarımları

Yukarıdaki 5 Ağustos notunun aksine, buradaki maddeler **uygulandı ve
doğrulandı** (kod + test kanıtıyla), bir backlog değil bir değişiklik
kaydı. Kaynak: 3 Ağustos organizasyon Q&A toplantısının kaydı (27 soru-
cevap incelendi, tam liste `PLAN.md`'ye işlendi) + o sırada ortaya çıkan
iki somut kod açığının düzeltilmesi.

## Kod değişiklikleri (mobile/)

1. **`mobile/lib/services/lifebox_service.dart` — video artık ZIP'lenerek paylaşılıyor.**
   Sebep: Q&A'de "Lifebox ham video yüklerse galeri unsuru sayıp
   çözünürlüğü düşürebilir, canlı demoyla farklı sonuç çıkarsa bu
   DİSKALİFİYE sebebi" denildi. `archive` paketinin `ZipFileEncoder`'ı
   `CompressionType.none` ile kullanıldı (deflate yolu tüm dosyayı
   `OutputMemoryStream`'e alıyor — 100+MB kayıtta bellek riski taşırdı,
   test bunu doğruluyor: `lifebox_zip_test.dart` sıkıştırılabilir 1MB'lık
   içeriğin küçülmediğini kanıtlıyor).

2. **`mobile/lib/services/hls_variant_service.dart` (yeni dosya) — bant
   genişliğine göre HLS varyant seçimi eklendi.** Bu, koddan BAĞIMSIZ
   olarak ampirik biçimde doğrulanmış gerçek bir açıktı: yerel ffmpeg
   8.1.1 ile uygulamanın kullandığı komutun birebir aynısı çalıştırıldı,
   master playlist verildiğinde ffmpeg'in ağ koşulundan bağımsız her
   zaman en yüksek varyantı (1080p) seçtiği kanıtlandı. Şartname 4.2
   açıkça "anlık bant genişliğine en uygun videoyu stream etmesi
   gerekmektedir" diyor — düşük bantta yüksek varyant denenirse 5
   dakikalık kayıt penceresi yetişmez. Düzeltme: `session_controller.dart`
   artık `HlsVariantService.resolveVariant()` ile alt-playlist URL'ini
   doğrudan ffmpeg'e veriyor; bu da gerçek sunucuya karşı test edildi
   (5 Mbps → 240p alt-playlist URL'i üretiliyor, ffmpeg o URL'de gerçekten
   426x240 veriyor — URL'ler birebir eşleşti).

3. **`mobile/test/backend_integration_test.dart` düzeltildi.** Video testi
   önceden sahte (64KB uydurma byte) veri gönderip `DONE`+tespit
   bekliyordu — bu, artık kaldırılmış "sahte AI çalıştırıcı" döneminden
   kalma bir varsayımdı, gerçek GPU imajına karşı hep başarısız oluyordu
   (`status`/`detections` değil, artık yalnızca upload→job→polling
   sözleşmesinin tuttuğu sınanıyor). `@Timeout` 2dk→5dk (gerçek inference
   dakikalar sürüyor). VM backend'ine karşı artık **6/6** geçiyor (önceden 5/6).

4. **`mobile/lib/config/app_config.dart` — `testHlsUrl` artık
   `String.fromEnvironment('HLS_URL', ...)`.** `BACKEND_URL` ile aynı
   desen: final günü stream adresi değişirse kod düzenlenmeden
   `--dart-define=HLS_URL=...` ile build alınabilir (7 Ağustos 21:00
   sonrası kaynağa dokunmama ilkesiyle uyumlu).

5. **`mobile/lib/widgets/video_card.dart`** — kayıt sırasında seçilen
   varyant UI'da gösteriliyor ("Bant genişliğine göre seçilen kalite:
   240p") — hakem canlı demoda adaptif seçimi görebilsin diye.

**Doğrulama:** `dart analyze` temiz (not: bu makinede `flutter analyze`
yol içindeki `Masaüstü` karakteri yüzünden çöküyor, `dart analyze`
kullanılmalı), mobil testler 20/20 (13'ü yeni), backend 39/39, VM
backend'ine karşı entegrasyon 6/6. **Test edilmeyen:** gerçek Android
cihaz — ffmpeg_kit'in alt-playlist URL'ini telefonda da aynı işlemesi,
gerçek boyutlu (100+MB) videonun telefonda zip süresi, ve zip'in Lifebox
uygulamasına share sheet'ten düzgün gitmesi doğrulanmadı.

## Backend containerization (infra, aynı gün ayrıca yapıldı)

`backend/Dockerfile` eklendi, VM'de `vst-t1-backend` container'ı olarak
(Docker-outside-of-Docker: `docker.sock` + `JOB_STORAGE_PATH` host'la
birebir aynı path'te mount) çalıştırıldı, gerçek Faz2 videosuyla 3 kez
(container öncesi, sonrası, kasıtlı çökme+otomatik restart sonrası)
birebir aynı sonuçla doğrulandı. Detaylar `PLAN.md`'de.

## ⚠️ AI ekibine iletilmesi gereken — mevcut bug listesiyle KESİŞEN toplantı bulguları

Yukarıdaki "AI tarafı" bölümündeki bug #1-3 (kemer bayrağının kalıcı
kapanması, "etiket başına video-geneli maks 1" filtresi, teknocan sayım
sırası hatası) **5 Ağustos'ta, bu toplantıdan ÖNCE** yazılmıştı. 3 Ağustos
Q&A'sinden gelen şu bilgiler bu bug'ları doğrudan ilgilendiriyor, AI ekibi
düzeltme kararı alırken birlikte okumalı:

- **"Yaşam döngüsü" kuralı:** dedupe/max-1 kısıtı VİDEO GENELİNDE değil,
  **her araç geçişi/instance başına** olmalı ("2 dakikalık videoda bir
  sürü klip var" — her klip kendi yaşam döngüsü). Bug #2'deki
  `max_allowed = 1` (satır 1277, video geneli) bu kuralla **uyuşmuyor
  olabilir** — eğer bir videoda birden fazla ayrı araç geçişi varsa, bu
  filtre farklı araçlardaki gerçek ihlalleri de silebilir.
- **Fazladan/tekrarlı raporlar artık nötr değil, FALSE POZİTİF SAYILIYOR**
  ve puan kaybettiriyor — bug #1'in tam tersi yönde bir risk oluşturuyor
  olabilir (kemer bayrağı hiç kapanmazsa video boyunca tekrar tekrar
  ihlal raporlanır, her tekrar artık FP).
- **Emniyet kemeri ihlali için kemerin TAKILI OLMADIĞININ görülmesi
  gerekiyor** (varlık tespitinden yokluk çıkarımı da kabul, yöntem
  serbest); kemer hiç görünmüyorsa ihlal sayılabilir.
- **arka_koltuk_1/arka_koltuk_2 koltuk pozisyonu değil, KİŞİ SAYISI
  etiketi** ("arka koltukta 1/2 kişi var"). 6 Ağustos sabahki ground-
  truth karşılaştırmasında (`PLAN.md`) bu ikisi ayrı kategoriler gibi
  yorumlanmıştı — muhtemelen yanlış, gerçek sorun sayım kararlılığı
  (2→1 flicker) olabilir.
- **Aydınlık/parlama karanlıktan daha riskli** deniliyor, "nesneleri
  birden fazla görüyor olabiliriz" uyarısı yapıldı — duplicate tespit
  riski, yukarıdaki max-1 filtresiyle ilişkili olabilir.
- Puanlama netleşti: sapma 0-10 saniye arası lineer düşüş (10 sn'de 0
  puan), erken tespitte %10'a kadar bonus ("look-ahead" penceresi).

Bu maddelerin tam metni ve gerekçesi `PLAN.md`'de.
