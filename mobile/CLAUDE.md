# mobile/ — Claude için bağlam

Bu dosyayı otomatik okuyorsun çünkü `mobile/` altında çalışıyorsun. Amacı: bu
klasördeki kodun neden bu şekilde yazıldığını, hangi hataların düzeltildiğini
ve onları tekrar açmamak için nelere dikkat etmen gerektiğini anlatmak.
Genel kurulum/çalıştırma için `mobile/README.md`'ye, backend sözleşmesi için
`../docs/mobile-integration.md`'ye bak — onları burada tekrar etmiyorum.

## Bu branch'in geçmişi

Flutter uygulamasının ilk hâlini bir takım arkadaşı yazdı (`docs/mobile-integration.md`
sözleşmesine göre). Backend tarafını yazan oturum, kodu code review'dan
geçirip kritik hataları düzeltti ve gerçek backend'e karşı uçtan uca doğruladı.
Aşağıdakiler o düzeltmeler — "neden böyle yazılmış" sorusunun cevabı burada.

## Bozmadan önce bil: bu desenler kasıtlı

- **`SessionController._nvGeneration`** (kuşak sayacı): NV login/iptal/çıkış
  her biri bunu artırır; süren `_pollAuthStatus` döngüsü her turda kendi
  kuşağının hâlâ güncel olup olmadığına bakar. Bunu kaldırırsan: kullanıcı
  "İptal"e bastıktan hemen sonra yoldaki bir yanıt `verified` dönerse,
  iptal edilmiş oturum kullanıcıyı sessizce içeri alır. Aynı mekanizma çift
  dokunma yarışlarını da önlüyor — `submitPhoneNumber`/`uploadAndTriggerAi`/
  `startRecording` neden en başta bir `if (zatenSürüyor) return` kontrolü var
  diye sorarsan, cevap bu.
- **WebView kapanışı tek yerden yönetiliyor**: `nv_webview_sheet.dart`'taki
  "İptal" butonu artık `cancelPendingLogin()` ÇAĞIRMIYOR — sadece pop ediyor.
  İptal mantığı `nv_screen.dart`'taki `.then((_) { ... cancelPendingLogin() })`
  bloğunda, çünkü sheet'in kapanma NEDENİ önemli değil (buton/geri tuşu/
  sistem jesti hepsi aynı yoldan geçmeli). Butona tekrar `cancelPendingLogin()`
  eklersen, iptal iki kere çalışır ve bir sonraki login'in kuşak sayacını
  gereksiz artırır (zararsız ama işaret ettiği şey: mantık orada değil burada
  olmalı).
- **AI sonucu polling'i UI'da DEĞİL, `SessionController._startAiPolling()`'de**:
  Sözleşme § 2.6 "1-2 sn arayla polle" diyor — bu, kullanıcı ekranı açık
  tutsun tutmasın çalışmalı. `AiResultTab` artık `StatelessWidget` ve hiçbir
  fetch tetiklemiyor; sadece `controller.aiStatus`'a bakıp gösteriyor. Bu
  ayrımı bozup fetch'i widget'a geri taşırsan, ekran arka plandayken/henüz
  açılmadan polling durur.
- **`RetryInterceptor`, `FormData` gövdeli istekleri retry'lamıyor**
  (`api_client.dart`): dio'da `MultipartFile.fromFile` tek kullanımlık bir
  stream'dir; retry aynı `FormData`'yı tekrar göndermeye çalışır ve sessizce
  başarısız olur. Video upload'ı en çok retry'a ihtiyaç duyan istek olduğu
  için bu kasıtlı bir istisna, unutulmuş bir TODO değil.
- **`backendDetail()` helper'ı `detail`'i `is String` diye kontrol ediyor**
  (`api_client.dart`): FastAPI validasyon hatalarında (422) `detail` bir
  STRING değil, hata nesnelerinden oluşan bir LİSTE döner. Doğrudan
  `as String?` cast'i bunlarda patlar — sözleşmedeki 422 (bozuk telefon
  formatı) senaryosu tam olarak bu.
- **`VideoCard` artık `controller.addListener` çağırmıyor**: `HomeScreen`
  zaten `context.watch<SessionController>()` ile dinliyor ve her
  `notifyListeners()`'da `VideoCard`'ı yeniden kuruyor. İkinci bir abonelik
  eklemek aynı olayda iki rebuild yoluna geri döner.

## Backend'e karşı test etme

```bash
cd backend
JOB_STORAGE_PATH=./.local-jobs USE_MOCK_5G=true python -m uvicorn app.main:app --port 8000
```

Sonra `mobile/`'da:

```bash
flutter run --dart-define=BACKEND_URL=http://localhost:8000
flutter test test/backend_integration_test.dart   # gerçek servis kodu, gerçek backend
```

Backend `USE_MOCK_5G=true` iken bile NV/QoD/upload zincirinin **tamamı**
gerçek HTTP ile çalışır — `authorize_url`, backend'in kendi sahte onay
sayfasına (`/api/auth/mock-consent`) gider ve callback'e yönlendirir. Yani
"mock mod" gerçek Turkcell'i taklit eder, mobil kodunu değil; `AppConfig.useMock`
tamamen ayrı bir şeydir (yalnızca backend hiç ayakta değilken UI denemek için,
bkz. `app_config.dart`).

## Henüz gerçek ortamda doğrulanmadı

- Gerçek Turkcell + gerçek SIM ile NV/QoD (7 Ağustos'a kadar erişim yok).
- Gerçek Android cihazda ffmpeg HLS→MP4 kaydı (Windows'ta `webview_flutter`
  ve `video_player` kayıtlı değil — `windows/flutter/generated_plugin_registrant.cc`'ye
  bakarsan görürsün — bu yüzden Windows'ta yalnızca kayıt/paylaşım/HTTP
  denenebildi, WebView akışı denenemedi).
- Lifebox paylaşımı (native share sheet ile yarı-manuel, resmi API yok).

## Bir şey ekleyeceksen

- `docs/mobile-integration.md` tek doğruluk kaynağı — burada onun bir kopyasını
  YARATMA (önceki bir kopya tam da bu yüzden silindi, bkz. git log).
- Backend adresini/mock modunu koda gömme — `--dart-define` kullan
  (`app_config.dart`), yarışma günü yanlış sabitle build alma riskini bu
  önlüyor.
