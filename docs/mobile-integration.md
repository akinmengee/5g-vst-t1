# Mobil (Flutter) ↔ Backend Entegrasyon Sözleşmesi

> **Bu doküman kimin için:** Mobil uygulamayı yazan takım arkadaşı. Backend
> kodunu hiç açmadan, yalnızca bu dokümana bakarak uygulamayı uçtan uca
> yazabilmelisin. Bir şey belirsizse backend tarafına sor — ama önce burayı oku,
> cevap büyük ihtimalle burada.
>
> **Son güncelleme:** 3 Ağustos 2026 — backend implementasyonuyla birebir
> senkron (tüm endpoint'ler kodlandı ve testlerden geçti).

---

## 0. Kodun Repo İçindeki Yeri

Bu repo (`5g-vst-t1`), alanına göre üç klasörde ayrışıyor: `ai/` (hakemin
çalıştırdığı Docker imajı), `backend/` (bu dokümanın karşı tarafı), `mobile/`
(**senin işin**). Flutter projeni doğrudan repo kökündeki **`mobile/`**
klasörünün içine kur — standart Flutter proje yapısıyla
(`mobile/pubspec.yaml`, `mobile/lib/`, `mobile/android/`, `mobile/ios/`, ...).
Bu klasör henüz yok; ilk commit'in onu açacak.

`backend/` veya `ai/` koduna dokunmana gerek yok — bu dokümandaki sözleşme
dışında hiçbir backend detayına bağımlı olma. Backend zaten kodlandı ve
testlerden geçti; base URL netleşince (VM IP) burada güncellenecek.

---

## 1. Büyük Resim — Final Günü Akışı

Canlı demoda (25 puan) mobil uygulama şu zinciri yürütür:

**NV (numara doğrulama, +5) → QoD (bant genişliği, +5) → Turkcell stream'inden
videoyu indir + MP4'e çevir + Lifebox'a paylaş (+5) → MP4'ü backend'e yükle →
AI sonucunu (results.json) ekranda göster.**

Mobilin **hiçbir AI/model işi yok** — yalnızca orkestrasyon ve arayüz.
Organizasyon ayrıca **mobil UI estetiğine de puan vereceğini** açıkça söyledi;
işlevsellik bittiyse görsel kaliteye zaman ayırmak doğrudan puana yansıyor.

### Mobilin uçtan uca yapacakları (sırayla)

1. NV ekranı: telefon numarası al → `POST /api/auth/login` çağır → dönen
   `authorize_url`'i **olduğu gibi** bir uygulama-içi WebView'de aç.
   (Kendi OAuth mantığını kurma; client_id/secret mobile asla gelmez.)
2. `GET /api/auth/status/{flow_id}`'i ~1 sn'de bir polle; `verified` görünce
   WebView'i kapat. `rejected`/`error` görürsen kullanıcıya durumu göster
   (bkz. hata tablosu — özellikle WiFi hatası).
3. NV başarılıysa `POST /api/qod/start` çağır — tek seferlik, senkron.
   `success:false` gelse bile **akışa devam et** (QoD başarısızlığı puan
   kaybettirmez, sadece +5 kaçar).
4. Turkcell'in HLS adresine bağlan, ABR destekli bir player ile oynat,
   videonun tamamını indirip **MP4 olarak dışa aktar** (5 dakika limiti var).
5. MP4'ü Lifebox üzerinden hakemlerle paylaş (muhtemelen manuel adım —
   uygulamanın işi olmayabilir, yarışma günü teyit edilecek).
6. Aynı MP4'ü `POST /api/videos/upload` ile backend'e yükle → hemen `202` +
   `job_id` gelir.
7. `GET /api/videos/{job_id}/result`'ı polle (1-2 sn arayla); `DONE` olunca
   `results` içeriğini ekranda güzelce göster (araç kartı: tip/plaka/renk/güven +
   zaman damgalı tespit listesi).
8. `results` JSON içeriğinin **SHA256'sını hesaplayıp ekranda göster**
   (resmi akış diyagramı adım 17 — Docker imajının hash'inden ayrı bir şey).
9. UI/estetik cilası (yukarıdaki puan notu).

---

## 2. Endpoint Sözleşmeleri

**Base URL:** `http://<VM_IP>:8080` — VM IP'si netleşince buraya yazılacak.
Şimdilik geliştirmede kendi mock'unla ya da yerel backend'le
(`http://localhost:8000`) çalışabilirsin.

> **Alan adı uyarısı:** Sözleşmede casing karışıktır ve **kasıtlıdır** —
> Turkcell'den geçen alanlar camelCase (`phoneNumber`,
> `devicePhoneNumberVerified`, `sessionId`, `qosStatus`), bizim ürettiklerimiz
> snake_case (`flow_id`, `authorize_url`, `job_id`, `error_code`).
> "Düzeltmeye" çalışma, birebir bu adları kullan.

### 2.1 `POST /api/auth/login`

NV akışını başlatır.

```jsonc
// İstek
{ "phoneNumber": "+905390000020" }   // E.164: +90... formatı ZORUNLU

// Yanıt 200
{
  "flow_id": "38043c55-4975-4f41-b8e4-d078e8ae62b7",
  "authorize_url": "https://opengateway.turkcell.com.tr/oauth2/authorize?..."
}
```

- `flow_id`'yi sakla — **sonraki her çağrının anahtarı** (status, qod, upload).
- `authorize_url`'i uygulama-içi WebView'de aç. **Deep-link kurma** — WebView
  Turkcell'in yönlendirmelerini kendi içinde takip eder, sen hiçbir URL parse
  etmezsin; sonucu status polling'le öğrenirsin.
- Telefon formatı bozuksa `422` döner.

### 2.2 `GET /api/auth/callback` — **mobil bunu ASLA doğrudan çağırmaz**

Turkcell, WebView'in içinden backend'in bu adresine yönlendirme yapar; WebView
bunu kendiliğinden takip eder. Senin için görünmezdir — bilgin olsun diye
burada: bu çağrı gerçekleştiğinde backend token alışverişini ve doğrulamayı
yapar, flow durumunu günceller.

### 2.3 `GET /api/auth/status/{flow_id}`

~1 sn arayla polle.

```jsonc
// Yanıt 200
{
  "status": "pending" | "verified" | "rejected" | "error",
  "devicePhoneNumberVerified": true | false | null,
  "error_code": null | "NUMBER_VERIFICATION.USER_NOT_AUTHENTICATED_BY_MOBILE_NETWORK" | "...",
  "message": null | "insan-okur hata detayı"
}
```

- `pending` → pollemeye devam et. 60 sn'de sonuç gelmezse timeout göster,
  kullanıcı yeni `login` ile baştan başlayabilir (idempotent).
- `verified` → WebView'i kapat, +5 puan adımı tamam, QoD'ye geç.
- `rejected` → numara bu cihazla eşleşmedi.
- `error` → `error_code`'a bak. **Özel durum:** kod
  `NUMBER_VERIFICATION.USER_NOT_AUTHENTICATED_BY_MOBILE_NETWORK` ise cihaz
  WiFi'deydi — kullanıcıya **"WiFi'yi kapatıp mobil veriyi açın"** de ve
  yeniden dene. Bu, sahada en olası hatadır; UI'da özel mesajı olsun.
- Bilinmeyen `flow_id` → `404` (flow ~20 dk işlem görmezse sunucudan düşer —
  bu durumda login'den baştan başla).

### 2.4 `POST /api/qod/start`

```jsonc
// İstek
{ "flow_id": "..." }

// Yanıt 200 (her durumda 200 — Turkcell hatası HTTP hatasına çevrilmez)
{
  "success": true | false,
  "already_active": false | true,     // true: zaten aktif oturum vardı, başarı say
  "sessionId": "..." | null,
  "qosStatus": "REQUESTED" | null
}
```

- Süre/IP/profil gibi hiçbir parametre gönderme — hepsi backend'de sabit.
- `success:true` → +5 puan adımı tamam.
- `success:false` → **puan kaybı yok, akışa devam** (video adımına geç; stream
  240p'de kalır, ABR player bunu kendisi halleder).
- NV'den sonra **300 saniye içinde** çağrılmalı (Turkcell token ömrü 5 dk).
  Geç kalınırsa `success:false` döner — akış yine devam eder.
- Bilinmeyen `flow_id` → `404`.

### 2.5 `POST /api/videos/upload` — multipart/form-data

| Alan | Tip | Açıklama |
|---|---|---|
| `flow_id` | form alanı (text) | login'den gelen id |
| `video` | dosya | MP4 dosyası |

```jsonc
// Yanıt 202 (HEMEN döner — işleme arka planda)
{ "job_id": "cc8d8627-..." }
```

- **Senkron cevap bekleme** — video işleme dakikalar sürebilir, upload sadece
  kabul eder. Sonuç için `job_id` ile polling yap.
- NV `verified` olmasa bile upload **kabul edilir** (bilinçli karar: NV sahada
  arızalansa bile AI hattı gösterilebilsin). Yalnızca `flow_id` hiç yoksa `404`.

### 2.6 `GET /api/videos/{job_id}/result`

1-2 sn arayla polle.

```jsonc
// Yanıt 200
{
  "status": "PROCESSING" | "DONE" | "FAILED",
  "results": null | {                    // yalnızca DONE'da dolu
    "video_id": "video.mp4",
    "arac_bilgisi": {
      "tip": "sedan", "plaka": "34ABC123", "renk": "beyaz",
      "confidence_score": 0.94
    },
    "tespitler": [
      { "zaman_saniye": 14.5, "kategori": "sofor_eylemi",
        "etiket": "telefonla_konusma", "confidence_score": 0.89 }
      // ... aynı etiket farklı zamanlarda TEKRAR EDEBİLİR, normaldir
    ]
  }
}
```

- `kategori` değerleri: `sofor_eylemi` | `nesneler` | `yolcular`.
- `FAILED` → kullanıcıya sade bir hata göster; yeniden upload denenebilir.
- İşleme üst sınırı 10 dakikadır; aşılırsa backend job'ı `FAILED` yapar.
- Bilinmeyen `job_id` → `404`.

---

## 3. Ortak Kurallar (ikimiz için de bağlayıcı)

- **`flow_id` tek ipliktir:** login'de doğar; status, qod ve upload'a aynen
  taşınır. Kaybolursa NV'den yeniden başlanır.
- **Cihaz mutlaka hücresel veride olmalı** — WiFi'de NV kesin başarısız olur
  (yukarıdaki 403 kodu). Demo öncesi kontrol listesine "WiFi kapalı mı?" yaz.
- **Video işleme tamamen asenkron** — 202 + polling deseni; hiçbir yerde uzun
  süren senkron istek yok.
- **Hiçbir adım akışı kilitlemez:** NV başarısızsa puan gider ama teknik olarak
  upload yine çalışır; QoD başarısızsa stream düşük kalitede devam eder.
- Tüm hata gövdeleri FastAPI standardıdır: `{ "detail": "açıklama" }`.

### Hata durumları özeti

| Durum | Nerede | Ne yapmalı |
|---|---|---|
| `422` | login (bozuk telefon formatı) | `+90...` E.164'e çevir, tekrar dene |
| `status:error` + WiFi kodu | auth/status | "Mobil veriyi açın" uyarısı, tekrar NV |
| `404` | status/qod/upload/result | flow/job süresi dolmuş ya da yanlış id — akışı baştan başlat |
| `success:false` | qod/start | Devam et, puan kaybı yok |
| `already_active:true` | qod/start | Başarı say, devam et |
| `FAILED` | videos/result | Hata göster, yeniden upload denenebilir |

---

## 4. Backend Hazır Olmadan Paralel Çalışma

Backend kodlandı ve mock modda uçtan uca test edildi, ama VM'e deploy edilene
kadar kendi mock'unla ilerlemek istersen: yukarıdaki 6 endpoint'i taklit eden
basit bir sabit-JSON sunucusu yeterli. `PROCESSING → DONE` geçişini 2-3 sn'lik
bir gecikmeyle simüle et. `DONE` yanıtındaki `results` için örnek veri:
repodaki `backend/app/fixtures/mock_ai_results/results.json` dosyasını
kullanabilirsin. Gerçek backend hazır olduğunda **yalnızca base URL değişir.**

---

## 5. Teknik Uyarılar (mobil tarafın seçimleri)

- **HLS → MP4 çevirme:** `ffmpeg_kit_flutter` paketi 2025'te resmi olarak
  retire edildi — **varsayılan seçim olarak alma**, güncel/bakımlı bir
  alternatif araştır (aktif bir ffmpeg-kit forku, platform kanalı üzerinden
  native çözüm, vb.). Yaklaşım: ekran kaydı DEĞİL, HLS akışını dosyaya indirip
  yeniden paketlemek (`ffmpeg -i <hls_url> -c copy output.mp4` mantığı).
- **ABR player:** Turkcell tek bir adaptif HLS akışı sunuyor; kalite seçimini
  (QoD açık → 1080p, kapalı → 240p) standart ABR player'lar otomatik yapar.
  Elle kalite seçme mantığı kurmadan önce player'ın 5 dk limitine sığdığını
  gerçek ortamda test et.
- **WebView:** programatik kapatılabilir olmalı (status `verified` olunca sen
  kapatacaksın). Sayfa içeriğini parse etme ihtiyacın yok.
- **Test numarası (sandbox):** `+905390000020` — yarışma günü SIM'le değişir.

---

## 6. Sorular / Değişiklik Talepleri

Sözleşmede bir alan eklemek/değiştirmek gerekirse önce backend tarafıyla
konuş — bu dosya tek doğruluk kaynağıdır (single source of truth) ve her
sözleşme değişikliğinde güncellenir.
