# VST T1 — Akıllı Yol Güvenliği: Final Yarışma Entegrasyon Planı

---

## ✅✅ 3 Ağustos 2026 (devam) — Backend İmplementasyonu Tamamlandı (BURADAN OKUMAYA BAŞLA — aşağıdaki bölümlerden bile daha yeni)

> Bu bölüm, aşağıdaki "EN GÜNCEL DURUM" bölümünden bile daha yeni — aynı gün
> içinde, kullanıcı Fable'a geçtikten sonraki devam oturumunda yazıldı.
> Aşağıdaki bölümler (mimari kararlar, doküman incelemeleri, resmi dokümanlardan
> çıkan bulgular) hâlâ tam geçerli ve referans değerinde; bu bölüm sadece en
> son eylem durumunu ekliyor, hiçbir şeyi çürütmüyor.

**Ne yapıldı:** Aşağıdaki "🔴 FİNAL-UYUMLU HEDEF MİMARİ" ve Bölüm H/I/J'deki
tasarım + kullanıcının paylaştığı 9 resmi doküman (Final Yarışma Senaryosu,
Turkcell OGW API spec'leri/Postman koleksiyonu, Yarışmacı Platformu Operasyon
Rehberi, FTR teslim formatı) birlikte kullanılarak plan modunda detaylı bir
implementasyon planı çıkarıldı (plan dosyası:
`C:\Users\akinm\.claude\plans\bunlar-da-gerekli-d-k-manlar-async-haven.md`)
ve **backend baştan sona kodlandı:**

- `POST/GET /api/auth/{login,callback,status}` — 3-legged OIDC NV akışı, gerçek
  `TurkcellOpenGatewayClient` (httpx) implementasyonu (artık stub değil).
- `POST /api/qod/start` — QoD, 409=başarı kuralı, diğer hatalar `success:false`
  (puan kaybı olmadan).
- `POST /api/videos/upload` + `GET /api/videos/{job_id}/result` — job kaydı
  (FlowRegistry/JobRegistry, SessionRegistry'nin TTL desenini tekrar eder ama
  bağımsız), `docker run` tetikleme (`DockerAiRunner`, tek-GPU semaforu,
  10dk timeout), mock modu (`MockAiRunner`, imaj olmadan uçtan uca test).
- `backend/app/main.py` yeniden yazıldı — artık `vehicle_ai/*`'a (dolayısıyla
  torch/opencv'ye) hiç bağımlı değil; eski `routes_inference.py` (WebSocket)
  diskte duruyor ama main.py'ye bağlı değil (kullanıcının "eski mimariden
  tamamen kop" kararı, bkz. G1).
- `backend/requirements.txt` artık ML'siz; ML bağımlılıkları
  `requirements-dev.txt`'ye taşındı (AI-core testleri hâlâ oradan kurulup
  çalıştırılabiliyor — 200+ testin hiçbiri kırılmadı).
- **230 test geçiyor** (37 yeni backend testi + 193 eski AI-core/streaming
  eşdeğerlik testi) + gerçek app+lifespan ile uçtan uca mock duman testi
  (login→callback→verified→QoD→upload→DONE) elle doğrulandı.
- **`docs/mobile-integration.md` yazıldı** — mobil ekip için tam API sözleşmesi
  (6 endpoint, hata tablosu, ortak kurallar, `mobile/` klasör konumu notu dahil).

**Değişmeyen:** AI çekirdeği (`vehicle_ai/*`, `_ftr_reference/`) bu oturumda
DOKUNULMADI — hâlâ eski `backend/app/services/vehicle_ai/` altında, `ai/`
klasörüne taşınmayı bekliyor (ayrı, sonraki bir faz). A1-A6 bulguları
(Dockerfile CMD, batch entrypoint, Katman 2, zaman kaynağı,
`etiket_basina_max_olay`) hiçbiri bu oturumda çözülmedi, hâlâ P0.

**✅ Ek temizlik (aynı oturum, kullanıcı isteğiyle):** Terk edilmiş mobil
edge-AI/WebSocket mimarisinden backend'de **hiçbir iz kalmayacak** şekilde
tam kopuş yapıldı — sadece main.py'den ayrılmakla kalmadı, fiziksel olarak
silindi: `routes_inference.py`, `app/fixtures/mock_mobile_payloads/` (WS
fixture üretici/gönderici), eski AI-baked `backend/Dockerfile` (nvidia/cuda +
weights kopyalayan, artık S2/G3 kararıyla çelişen imaj). `requirements.txt`'ten
`websockets` çıkarıldı. **Tek korunan istisna:** `vehicle_ai/*` (dedektörler,
oylama, event gate, 200+ test) — bu "eski mimari" değil, ayrı bir Docker
imajına (`ai/`) taşınacak olan, S1 kararıyla sıfırdan yazılmayıp korunan AI
çekirdeğinin kendisi; `mobile_contract.py`'nin (`MobileRoiPayload`) hâlâ
durması bu yüzden — `CurrentModelService.process_roi()`'nin arayüzü, silinirse
o 200+ test kırılır. 230 test + uçtan uca duman testi silme sonrası da geçti.

**Sıradaki adımlar (öncelik sırasıyla):**
1. Repo GitHub'a push edilecek; mobil ekip `mobile/` klasöründe (repo kökünde,
   aşağıdaki "Repo Yapısı" bölümünde zaten tanımlı konum, artık
   `docs/mobile-integration.md`'de de açıkça yazılı) Flutter projesini
   başlatacak.
2. `ai/` fazı: `batch_main.py`, Katman 2 (araç bul/kırp), Dockerfile CMD
   düzeltmesi — bkz. Bölüm D öncelik tablosu, hâlâ P0.
3. `redirect_uri` (`http://<VM_IP>:8080/api/auth/callback`) Turkcell'e kayıt
   ettirilmeli — hâlâ açık, kod bunu çözemez.
4. `PLAN.md` (repo kökü, takım paylaşım kopyası) **hâlâ senkronize değil** —
   bu md dosyasındaki güncel bilgilerle henüz güncellenmedi.

---

## 🆕 EN GÜNCEL DURUM — 3 Ağustos 2026 Toplantısı Sonrası (BURADAN OKUMAYA BAŞLA)

> **Bu bölüm dokümandaki en yüksek güven seviyesine sahip bilgidir.**
> Aşağıdakiler artık doküman satır-arası okumasından/çıkarımdan değil,
> **3 Ağustos 2026 Pazartesi 11:00'deki organizasyon toplantısında sözlü
> olarak doğrudan söylenenlerden** geliyor. Kullanıcı bu bilgiyi toplantı
> biter bitmez aktardı ve bu cihazı bırakıp başka bir oturumdan/Claude'dan
> devam edeceğini belirtti — **bu yüzden bu bölüm, önceki hiçbir konuşmayı
> görmemiş biri (yeni bir Claude oturumu ya da bir takım arkadaşı) için
> yeterli olacak şekilde kendi başına anlaşılır tutuldu.** Daha fazla detay/
> gerekçe isteyen, aşağıdaki "🔴 FİNAL-UYUMLU HEDEF MİMARİ" ve ilgili
> bölümlere (H, I, J, K) bakabilir — oradaki tasarım hâlâ geçerli, bu bölüm
> onu **teyit ediyor ve tamamlıyor**, çürütmüyor.

### Organizasyonun sözlü teyit ettiği final günü akışı (adım adım)
1. Takıma verilen (muhtemelen SIM kartlı demo) cihaz üzerinden mobil
   uygulama açılır, **Number Verification (NV)** yapılır.
   - NV başarısız → canlı demonun 25 puanlık kısmından **0 puan**, sonraki
     adımlara geçilmez.
2. NV başarılı → **+5 puan.** Sıradaki adım **QoD.**
   - QoD bağlanırsa → **+5 puan daha (toplam 10).**
   - QoD başarısız olursa → ek puan yok ama NV puanı korunur (**5'te
     kalınır**); stream kalitesi **240p'ye düşer** (kullanıcının notu
     "sanırım" ile geldi, %100 teyitli değil ama Doküman 2'deki ABR
     bulgusuyla tam tutarlı — QoD yoksa düşük bant genişliği, ABR player
     otomatik düşük çözünürlüğe geçer).
3. QoD açıksa (yüksek bant genişliği), mobil **streaming sunucusundan
   videoyu indirip MP4 olarak dışa aktarır** (bkz. Bölüm J).
4. Video **bir klasöre kaydedilir** ve **Lifebox ortamına yüklenir**
   (kullanıcı bu turda "livebox" yazdı — aynı şey, Bölüm J'de zaten "bizim
   yazacağımız bir şey değil, mekanizması bilinmiyor" diye not düşülmüştü,
   hâlâ öyle).
   - Bu adımın (kayıt+aktarım) başarısı **streaming puanını** belirliyor:
     **+5 puan.**
5. Mobil, aynı videoyu **kendi backend'imize** de iletir. Backend, **AI
   imajını çalıştırır** — video girer, `results.json` çıkar. **("AI imajı
   bir program, API değil" modeli — Bölüm E2 — artık organizasyon
   tarafından da fiilen teyit edildi, sadece doküman çıkarımı değil.)**
6. Backend, `results.json`'ı mobile döner; mobil bunu **bir arayüzde
   (UI) gösterir.**
7. Canlı demo tarafında ayrıca **bir sunum yapılıyor** ("ne yaptık, nasıl
   yaptık") — bu, Final Yarışma Senaryosu'ndaki 4'lü puan bölünümünün
   ("Sunum" %25) somut karşılığı; yeni bir kural değil, var olan yapının
   teyidi.

**Puan alt kırılımı (canlı demonun 25 puanı içinde, netleşen kısım):**
NV (+5) → QoD (+5, toplam 10) → Streaming/kayıt başarısı (+5, toplam 15) →
kalanı muhtemelen AI sonucunun mobilde doğru/güzel gösterilmesi. Kesin
kalan-puan formülü teyitli değil, ama üçünün toplamda 15 ettiği ve tavanın
25 olduğu net.

### 🆕 Yeni bulgu — Mobil UI estetiği de puanlanıyor
Kullanıcının notu: *"UI çok önemli değil, fakat estetik tarafından da puan
vereceğiz, size artı olur dediler mobil için."* Organizasyon bunu **açıkça,
sözlü olarak** belirtti — daha önce plana hiç girmemiş bir bilgi. Sonuç:
mobil ekranın işlevselliği yeterli olsa da, **görsel/estetik kaliteye de
bir miktar zaman ayırmak doğrudan puana yansıyor.** Bu, mobil implementasyon
kapsamına eklenmesi gereken yeni bir gereksinim (bkz. aşağıdaki "Kalan
Açık İşler" listesi).

### ✅ S2 (Paketleme) ARTIK ÇÖZÜLDÜ — backend ayrı olabilir
Kullanıcının kendi ifadesiyle (toplantıdan): *"Docker image'sinde backend'i
kaldırabiliriz, o konuda bir sıkıntı yok — eğer AI containeri ile
konuşabiliyorsa ve teslim etmemiz gereken formatı engellemiyorsa, yani API
video gönderip sonuç çıktısı alabiliyorsa sıkıntı yok demektir."*

**Karar (nihai):** Hakeme teslim edilen `teknofest-2026/*` imajının İÇİNDE
backend'in bulunması **gerekmiyor.** Tek şart: backend'in AI imajıyla
konuşabilmesi (video ver → `results.json` al) ve panelde **tek bir**
`teknofest-2026/*` imajının görünmesi kuralının (Bölüm 3. doküman, madde 5)
bozulmaması. Backend bu kuralın kapsamı dışında — istediği şekilde
paketlenebilir.

**Bunun somut sonucu — Docker/VM mekaniği netleşti (önceki oturumda
"bunu plana işleyeyim mi?" diye bekleyen soruyu da çözüyor):**
- **AI imajı** VM'de build edilir: kaynak kod `scp`/`WinSCP` ile VM'e
  aktarılır (bir imaj dosyası DEĞİL, `Dockerfile` + kaynak kod), sonra VM
  üzerinde `docker build -t teknofest-2026/vst-t1:latest .` çalıştırılır.
  Bu imaj, hakemin Web UI'ından "Execute" ile çalıştırılan, sabit
  `/app/data/input/video.mp4` → `/app/data/output/results.json` sözleşmesine
  uyan, **kendi kendine sonlanan** programdır (bkz. Bölüm A1/E2/K).
- **Backend, artık bu imajın İÇİNDE olmak zorunda değil** — en basit ve
  önerilen yol: backend, VM üzerinde **düz bir Python/uvicorn süreci**
  olarak çalışır (systemd servisi ya da ekranı kapatılmadan `screen`/`tmux`
  içinde, ya da kendi ayrı bir Docker container'ı olarak — organizasyon
  bunu görmüyor/karışmıyor). Backend, videoyu diske yazdıktan sonra AI
  imajını basitçe `docker run` ile tetikler:
  ```
  docker run --rm --gpus all \
    -v /srv/jobs/{job_id}/input:/app/data/input \
    -v /srv/jobs/{job_id}/output:/app/data/output \
    teknofest-2026/vst-t1:latest
  ```
  Backend bir host process olduğu için bu `docker run` komutunu doğrudan
  `subprocess` ile çağırabilir — **`/var/run/docker.sock` mount etmeye,
  Docker-in-Docker'a hiç gerek kalmıyor** (önceki oturumda bu S2'ye bağlı
  açık bir teknik komplikasyon olarak not düşülmüştü, artık gereksiz).
- Böylece VM'de iki şey çalışıyor: (1) arka planda sürekli açık backend
  process/servisi (mobil isteklerini karşılıyor), (2) hakemin Web UI'ından
  ya da backend'in kendisinin tetiklediği, kısa ömürlü AI container'ı
  (girip çıkıyor). Panelde yalnızca (2) `teknofest-2026/*` adıyla görünüyor
  — kural karşılanıyor.

**Not (muhtemel dil sürçmesi, dikkat):** Kullanıcı *"7 Temmuz'da teslim
etmemiz gereken formatı"* dedi — 7 Temmuz zaten geçmiş bir tarih (bugün 3
Ağustos), teslim tarihi olamaz. Bunun kastı büyük ihtimalle **7 Ağustos
21:00 dondurma tarihi** (zaten planda var, aşağıya bkz.).

### 🆕 Yeni logistik bilgi — Cuma günü (7 Ağustos 2026) test ortamı VE dondurma aynı güne denk geliyor
Kullanıcı: *"Cuma günü bize kodumuzu test edebilmemiz için ortam
sunacaklar."* Bugün Pazartesi 3 Ağustos 2026 olduğuna göre, bu Cuma **7
Ağustos 2026.** Bu, plandaki bilinen "7 Ağustos 21:00 imaj dondurma / SHA256
teslim" tarihiyle **aynı gün.** Yani: gerçek platformda ilk kez test etme
fırsatı ile son teslim tarihi aynı güne denk geliyor — **zaman baskısı çok
yüksek.** Sonuç: 7 Ağustos'tan ÖNCE, yerelde/mock ortamda mümkün olduğunca
çok şeyin doğrulanmış olması kritik; Cuma günü gelen gerçek ortam zamanı
sadece son rötuşlar + sürpriz-yakalama için kullanılabilecek, sıfırdan
geliştirme için değil.

### G1 kararı artık toplantıyla da sözlü teyitli (en yüksek güven seviyesi)
Kullanıcının notu: *"Bizim kurguladığımız sistemden tamamen uzak bir yapı,
mobilden event driven bir şey beklemiyorlar, telefonun kamerasından canlı
video akışı beklemiyorlar. Tüm AI elementleri bir container içinde
çalışacak."* → Mobil edge-AI / WebSocket-ROI mimarisi (eski ÖTR tasarımı)
**kesin ve nihai olarak resmi puanlamanın bir parçası değil** — artık
sadece doküman çıkarımına değil, doğrudan organizasyon açıklamasına
dayanıyor. S3 açık sorusu ("WebSocket P3'te mi kalsın") kendiliğinden
kapanıyor: yapılması **serbest ama tamamen opsiyonel/sunum-amaçlı**,
resmi puanlamanın hiçbir parçası değil.

### ROI (Katman 2) hakkında netleşen nüans — "şart değil ama istiyoruz"
Kullanıcı: *"ROI yapmamız şart değil, fakat bize 5dk/10dk gibi her aşama
için zaman kısıtlaması koydukları için, ve en iyi mimari ödülleri için buna
ihtiyacımız var tabii ki."* → Araç bulup kırpma (Katman 2), **kuralların
dayattığı bir zorunluluk değil**, ekibin **kendi mühendislik tercihiyle**
(zaman bütçesi + "En İyi Mimari" ödülü hedefi) yapılıyor. A4 bulgusu (mevcut
`process_roi` tam kareyi anlamlı işleyemiyor) hâlâ geçerli — yani "şart
değil" demek "kod gereksiz" demek değil; ama zaman baskısı altında en kötü
senaryoda "kırpmadan tam kare + daha kaba/riskli sonuç" bir düşüş seçeneği
olarak akılda tutulabilir. Öncelik hâlâ Katman 2'yi doğru yapmak (Bölüm D,
P0).

### NV detayı — "bize verilen cihaz"
Kullanıcı, NV'nin *"bize verdikleri cihaz üzerinden"* yapılacağını söyledi —
muhtemelen organizasyonun SIM kartlı bir demo telefonu sağladığı (Context
bölümündeki "her takıma bir SIM kart verilecek" notuyla tutarlı) anlamına
geliyor: kendi mobil uygulamamız, organizasyonun sağladığı SIM'li cihazda
çalışacak. Kesin teyit değil ama en makul okuma bu; VM/cihaz teslim
alındığında netleşecek.

### Genel mühendislik standardı hatırlatması (kullanıcının vurgusu, tekrar)
*"Her şeyi genel mühendislik standartlarına uygun bir şekilde yazmalıyız,
ve neyi neden yaptığımızı açıklayabilmeliyiz ki sunumumuz da kuvvetli
olsun."* → G2'deki "neden bu şekilde yaptık" vurgusuyla aynı doğrultuda,
sunum (%25) ve "En İyi Mimari"/"En İyi Sunum" ödülleri için bilinçli kod
kalitesi + gerekçelendirilebilirlik önceliği bir kez daha teyit edildi.

### Açık sorular — ikinci tur netleştirme (3 Ağustos, aynı gün devam)

**✅ Bu turda çözülen/netleşen:**
- **"Final günü videosu" kaynağı:** Mekanizma netleşti — organizasyon/Turkcell
  bir streaming API üzerinden (Open Gateway Demo UX Kılavuzu'ndaki adım 04 ile
  aynı desen: HLS/ABR, QoD'ye göre 240p↔1080p) bir video sunuyor, biz onu MP4'e
  çevirip yüklüyoruz — Bölüm J bunu zaten bu şekilde tasarlamıştı.
  **Video prodüksiyonu yapmamıza gerek yok** — bu risk kapandı.
  **🆕 Önemli yeni bulgu:** Organizasyon açıkça *"karanlıktan çok
  aydınlıktan/yansımalardan korkun"* dedi — asıl risk düşük ışık değil,
  **parlak ışık + yansıma** (cam/far/ıslak zemin gibi). Model eğitimi/test
  önceliklerini etkiliyor, CV ekibine iletilmeli; eşik ayarı (Bölüm E) bu
  senaryolarla da test edilmeli.
- **Lifebox netleşti:** Turkcell'in **gerçek, genel-amaçlı tüketici bulut
  depolama servisi** (foto/video/müzik/rehber yedekleme, ilk üyelikte 5GB
  ücretsiz — bkz. mylifebox.com). Geliştirici API'sine dair hiçbir iz yok
  (hiçbir OGW dokümanında geçmiyor) — **muhtemelen manuel bir yükleme adımı**
  (uygulamamızın API entegrasyonu yapması gerekmeyebilir, sıradan kullanıcı
  gibi Lifebox uygulaması/sitesinden video yüklenip paylaşılıyor olabilir).
  Kesin teyit yok ama risk "bilinmeyen API" seviyesinden "bilinen tüketici
  uygulaması, muhtemelen manuel" seviyesine indi.
- **Puanlama scripti olay-başına mı etiket-başına mı:** Ground truth JSON
  yapısının kendisi cevap — her oluşum kendi zaman damgasıyla ayrı bir
  `tespitler[]` girdisi (`arka_koltuk_2` gibi etiketler tekrar tekrar).
  **Beklenen AI çıktısı tam olarak bu formatta:** bir olay görüldüğü an bir kez
  yazılır, tekrar eden etiketler serbest — zaten Bölüm K/A6 tasarımı bu. İç
  puanlama algoritmasının tam eşleştirme/tolerans mantığı hâlâ bilinmiyor ama
  bizim için aksiyon alınabilir kısım net. Bu ayrıca **backend/AI ayrımının
  (S2/G3) doğruluğunu bir kez daha teyit ediyor** — AI'nin girdi/çıktısı net
  şekilde "video → bu JSON" olduğu için backend'in araya girmesine gerek yok.
- **"07 Trace":** Kullanıcı: önemli değil, kodlama sırasında hallederiz —
  artık ayrı bir açık soru olarak takip edilmiyor.

**Hâlâ tam açık:**
- **SHA256 ibraz mekanizması** — organizasyon "her şey dokümanlarda net" dedi;
  elimizdeki dokümanlarda bunun tam mekanizması (nereye/nasıl teslim)
  bulunamadı. Kullanıcı kararı: **dokümanlarda gerçekten yoksa açık soru
  olarak kalsın**, ayrıca aranmayacak — yeni bir doküman/detay çıkarsa kapanır.

### 📱 Mobil Takım Arkadaşı İçin Sözleşme — bağımsız gitmemek için (3 Ağustos)

> Amaç: mobil ve backend/AI ayrı kişiler tarafından, aynı anda, birbirini
> beklemeden inşa edilebilsin — ama tek bir noktada (aşağıdaki 6 endpoint)
> anlaşarak. Tam istek/cevap şemaları zaten Bölüm H (NV), I (QoD), J (Video)
> içinde yazılı — bu, o üçünün **mobil gözünden özeti.** Teammate'e direkt H/I/J
> bölümlerini de gönderebilirsin, tam spesifikasyon orada.

**Mobilin uçtan uca yapması gerekenler (sırayla):**
1. NV ekranı: telefon no gir → `POST /api/auth/login {phoneNumber}` çağır →
   dönen `authorize_url`'i **olduğu gibi** bir WebView'de aç (kendi OAuth
   mantığını kurmaz, client_id/secret mobile hiç gelmez).
2. `GET /api/auth/status/{flow_id}` ile ~1sn'de bir polling yap; `verified`
   olunca WebView'i kapat.
3. NV başarılıysa `POST /api/qod/start {flow_id}` çağır — tek seferlik,
   senkron, sonucu bekleyip direkt sonraki adıma geç (başarısız olsa da devam).
4. Turkcell'in HLS adresine bağlan, ABR destekli bir player ile oynat/indir,
   **MP4'e çevir** (5 dakika limiti var).
5. `POST /api/videos/upload` (multipart: flow_id + video.mp4) → `job_id` al
   (hemen `202` döner, işlem arka planda).
6. `GET /api/videos/{job_id}/result` ile polling yap; `DONE` olunca
   `results.json`'ı ekranda göster.
7. `results.json` içeriğinin **kendi SHA256'sını hesaplayıp** ekranda göster
   (Docker imajının hash'inden ayrı bir şey, bkz. Bölüm L adım 17).
8. Lifebox'a yükleme muhtemelen manuel/uygulamanın işi değil (bkz. üstteki
   Lifebox notu) — teyit edilmeden mobile bir iş yükleme.
9. **UI/estetik önemli** — organizasyon bunu açıkça belirtti, biraz zaman
   ayrılmalı (bkz. üstteki "Mobil UI estetiği" bulgusu).

**Backend'in mobile sağlaması gereken 6 endpoint (henüz kodlanmadı, ama
sözleşme netleşti):**
`POST /api/auth/login`, `GET /api/auth/callback` (mobile'in doğrudan
çağırmadığı, Turkcell'in yönlendirdiği), `GET /api/auth/status/{flow_id}`,
`POST /api/qod/start`, `POST /api/videos/upload`, `GET /api/videos/{job_id}/result`.

**İkisinin de dikkat etmesi gereken ortak noktalar:**
- **`flow_id` tek iplik** — `/login`'den alınır, `/status`'a ve `/qod/start`'a
  taşınır. Kaybolursa NV'den yeniden başlanır.
- **Video işleme ASENKRON** — mobil `/upload`'dan hemen `202` alır, sonucu
  polling ile öğrenir; senkron bir cevap beklenmemeli.
- **Cihaz mutlaka hücresel veri üzerinde olmalı** — WiFi'deyken NV `403`
  döner (`USER_NOT_AUTHENTICATED_BY_MOBILE_NETWORK`); mobil bunu kullanıcıya
  açıkça göstermeli.
- **Backend henüz kodlanmadı** — paralel ilerlemek için mobil, bu sözleşmeye
  uyan basit bir mock sunucu/sabit JSON fixture'larıyla (Doküman 2'deki
  `PROCESSING`/`DONE`/`FAILED` durumlarını taklit ederek) kendi akışını inşa
  edebilir; gerçek backend hazır olunca sadece base URL değişir.
- **Teknik uyarı (HLS→MP4 çevirme için):** `ffmpeg_kit_flutter` paketi 2025'te
  resmi olarak retire edildi/artık bakımı yapılmıyor — mobil bu adımı
  kurgularken güncel/bakımlı bir alternatif araştırmalı, doğrudan varsayılan
  seçim olarak almamalı.

### Kalan Açık İşler (bu oturumun sonunda hâlâ yapılmamış, unutulmamalı)
1. **Repo kökündeki `PLAN.md`** (takım paylaşım kopyası) hâlâ eski durumda —
   bu md dosyasındaki güncel bilgilerle senkronize edilmesi bekliyor.
   Kullanıcı bunu istemişti ama "yazma, bekle" talimatıyla ertelenmişti; artık
   engel kalktıysa (kullanıcı "başla" dediğinde) yapılabilir.
2. **Mobil (Flutter) implementasyonu** hiç başlamadı — kimin yazacağı,
   ne zaman başlayacağı netleşmedi. Yeni eklenmesi gereken: NV WebView akışı
   (Bölüm H), QoD tetikleme (Bölüm I), HLS indirme+upload (Bölüm J), sonuç
   ekranı + **estetik/UI kalitesi** (bu bölümdeki yeni bulgu).
3. **Test stratejisi** yeni P0 kodu için (`batch_main.py`, Katman 2, NV/QoD
   endpoint'leri) hâlâ yok.
4. **Bu md dosyası, kullanıcı bu cihazdan ayrılmadan önce, konuşmanın
   tamamını (mimari kararlar, kod bulguları, tüm doküman incelemeleri, bu
   toplantı sonuçları) kaybetmeden aktarabilecek şekilde güncellendi** —
   yeni bir Claude oturumu ya da bir takım arkadaşı, bu dosyayı okuyarak
   kaldığı yerden devam edebilmeli. Standing kural hâlâ geçerli: **kullanıcı
   "başla" demeden kod yazılmıyor** (bkz. "Çalışma anlaşmaları").

---

## 🗺️ GENEL PIPELINE ÖZETİ — buradan başla (1 Ağustos, en güncel/en okunabilir anlatım)

> Detaylı gerekçeler ve bulgular aşağıdaki A-L bölümlerinde duruyor. Burası,
> sadece "büyük resim nedir" sorusuna hızlı cevap için.

### Tek cümleyle
**Tek bir "AI programı" yazıyoruz (video ver, sonuç al), ve bu programı iki
farklı taraf, iki farklı bağlamda çalıştırıyor.** Bütün mimari bu tek fikrin
üzerine oturuyor.

```
┌─────────────────────────────────────────────────────────────┐
│   ÇEKİRDEK: "AI İmajı" — tek, sabit bir program               │
│   girdi: bir video dosyası  →  çıktı: results.json  →  çıkar  │
└─────────────────────────────────────────────────────────────┘
              ▲                                      ▲
              │                                      │
   [YOL A — Canlı Demo, puanın %25'i]     [YOL B — Hakem Batch, puanın %50'si]
              │                                      │
   Mobil uygulama, NV+QoD+video       Hakem, kendi VM'indeki Web UI'dan
   akışını yürütüp videoyu bizim      videoyu seçip "Execute"e basar —
   BACKEND'imize verir. Backend       bizim backend'imiz burada HİÇ
   bu imajı arka planda tetikler.     DEVREDE DEĞİL, imajı doğrudan
                                       hakemin kendi platformu çalıştırır.
```

Kalan %25 (sunum) kod değil, anlatım. Yani aslında **iki pipeline**, ama
motorları (AI çekirdeği) ortak — bu yüzden çekirdeği sağlam kurmak ikisini
birden güçlendiriyor.

### Adım 1 — AI çekirdeği: "video ver, JSON al" programı (bkz. Bölüm K)
1. Video dosyasını kare kare oku (OpenCV).
2. Her karede: **"bu karede araç var mı, nerede?"** diye bak. *(Daha önce
   mobilin işiydi; mobilde AI olmadığı netleştiği için artık bunu AI imajının
   içinde yapıyoruz. Tek araç olduğu bilindiği için basit bir "en güvenli
   kutu" yeterli, karmaşık takip gerekmiyor — bkz. Bölüm L.)*
3. Araç bulunduysa kırp, üzerinde tüm modelleri çalıştır: kasa/renk/plaka,
   sürücü davranışı (telefon/sigara/su/kemer/esneme/bakınma), yolcu tespiti,
   nesne tespiti (teknocan/bilgisayar), slalom.
4. Zaman içinde biriken bilgiyle (ardışık kare sayacı, oylama) gürültüyü ele,
   kesinleşince olayı listeye ekle.
5. Video bitince `results.json` yaz, **programdan çık** (bu bir web sunucusu
   değil — A1/A2 bulgusu: mevcut Dockerfile bunu yanlış yapıyordu).

**Durum:** 3-4-5 zaten yazıldı/test edildi (Gün 4-7). Eksik olan tek şey 2.
madde (araç bulma) — yanlışlıkla mobile verilmişti, geri alınıyor.

### Adım 2 — Canlı demo: mobil ne yapıyor (bkz. Bölüm H, I, J)
1. Uygulama açılır.
2. **NV:** telefon no backend'e verilir, backend Turkcell ile kimlik doğrulama
   dansını yapar (mobil sadece kısa süreliğine bir tarayıcı penceresi açar),
   sonuç: doğrulandı/doğrulanmadı.
3. **QoD:** backend, NV'de aldığı yetkiyle tek bir "bant genişliğini artır"
   isteği atar.
4. **Video:** mobil, Turkcell'in yayın sunucusundan videoyu indirip tam bir
   MP4 hâline getirir (ekran kaydı değil, akışı dosyaya indirip paketlemek).
5. MP4, backend'e yüklenir.
6. Backend, AI programını arka planda tetikler, mobile hemen "işleme aldım"
   der (beklemeden).
7. Mobil "bitti mi?" diye sorar (polling); bitince `results.json`'ı ve onun
   SHA256 parmak izini ekranda gösterir.
8. *(Video ayrıca Lifebox üzerinden organizasyonla paylaşılır — mekanizması
   henüz bilinmiyor, bizim yazacağımız bir şey değil.)*

### Adım 3 — Hakem değerlendirmesi: bizim hiç görmediğimiz kısım (bkz. Doküman 3)
1. 7 Ağustos 21:00'e kadar imaj dondurulur, SHA256'sı organizasyona verilir.
2. Hakem, kendi VM'indeki Web UI'dan imajı seçip iki hazır test videosuyla
   (düşük/yüksek kalite) çalıştırır — **Adım 1'deki AYNI program**, biz
   müdahale etmiyoruz.
3. Canlı demo başarılıysa, Lifebox'tan indirilen video da bir kez daha
   çalıştırılır.
4. Üç sonuç da ground truth'la karşılaştırılıp puanlanır.

---

## ⏸️ MOLA SONRASI — BURADAN DEVAM ET (son güncelleme: 1 Ağustos 2026)

### Nerede kaldık
Teknofest'in 4 resmi doküman seti incelendi ve plana işlendi. Mevcut kod bu
dokümanlara karşı okundu ve **mimarinin resmi final akışıyla uyuşmadığı, kod
okunarak doğrulandı**. Detaylar: "🔴 FİNAL-UYUMLU HEDEF MİMARİ" bölümü.

### Tek cümlelik özet
> Şu anki Docker imajı hakem değerlendirmesinde **0 puan alır** (%50'lik kısım),
> çünkü `Dockerfile:26` bir web sunucusu başlatıp asla sonlanmıyor; ayrıca
> backend'de araç bulan/kırpan aşama hiç yok (edge-AI kararıyla silinmişti).
> Ama AI çekirdeği (dedektörler, oylama, eşikler, registry) sağlam ve
> kurtarılıyor — düzeltme 6 günde fazlasıyla yapılabilir.

### ✅ Verilen kararlar
- **G1:** Araç bul/takip/kırp aşaması (Katman 2) backend'e taşınacak. Mobil edge
  modeli zorunlu yolun parçası değil. Mimariyi değiştirmek serbest.
- **Çerçeve:** "ÖTR yalan olmuş" değil — ÖTR bir tasarım önerisiydi, kurallar
  sonradan yayınlandı, 92 puan geri alınmıyor. Finalin özü: *FTR'yi bu sefer
  düzgün yap + 5G/mobil demo katmanı ekle.*

### ❓ AÇIK SORULAR (S1 çözüldü ✅ — kalan 2 tanesi)

**S1 — Kod stratejisi: ✅ KARAR VERİLDİ (1 Ağustos, mola sonrası).**
**"Çekirdeği koru, taşımayı değiştir."** Dedektörler/oylama/eşikler/registry
aynen kalır (200+ testiyle); yalnızca şu 7 kalem cerrahi olarak güncellenir:
Dockerfile CMD, batch entrypoint (`batch_main.py`), Katman 2 (araç bul/takip/kırp
— A3), zaman kaynağı (A5), `etiket_basina_max_olay` (A6), NV/QoD arayüzü (A8),
WebSocket'in P3'e (opsiyonel/ek katman) inmesi. Sıfırdan yazma seçeneği
değerlendirildi ve **bilinçli olarak elendi** — doğrulanmış/test edilmiş çekirdeği
riske atmadan, 6 günlük süre kısıtına en uygun yol bu. (Not: plan dokümanının
kendisinin yeniden konsolide edilmesi — ayrı bir soruydu — kullanıcı bu turda
seçmedi, şimdilik mevcut katmanlı haliyle devam ediyor.)

**S2 — Paketleme: ✅ ÇÖZÜLDÜ (3 Ağustos toplantısında).** Bkz. yukarıdaki
"🆕 EN GÜNCEL DURUM" bölümü. Organizasyon: backend, hakeme teslim edilen
`teknofest-2026/*` imajının içinde olmak zorunda değil; tek şart AI imajıyla
konuşabilmesi (video ver → JSON al). **Seçilen yaklaşım: (b) Sadece AI imaj
+ backend VM'de düz Python process** — Docker-in-Docker/`docker.sock`
mount etme ihtiyacı da bu sayede ortadan kalktı. (a) seçeneği (tek imaj +
iki komut) hâlâ teknik olarak geçerli bir alternatif ama artık gerekli değil.

**S3 — Canlı önizleme katmanı** (WebSocket + mobil edge): P3'te mi kalsın, yoksa
tamamen çıkarılsın mı? G1 kararı sonrası zorunlu yolun parçası değil; sadece
sunum/mimari anlatımı için değerli.

### 🚀 Karar beklemeden başlanabilecek işler (hepsi P0)
1. `batch_main.py` — `/app/data/input/video.mp4` → `/app/data/output/results.json`, sonlanan program
2. `Dockerfile` `CMD` düzeltmesi (uvicorn → batch)
3. Katman 2: araç tespit/takip/kırpma — kaynak hazır: `_ftr_reference/predict.py:383-460`
4. Zaman kaynağını video-zamanına (`frame_index / fps`) çevirilebilir yapmak
5. `event_gate.py:28` → `etiket_basina_max_olay` düzeltmesi + `thresholds.py`'ye taşınması
6. Faz 2 videosunu indirip (`ffmpeg`, HLS linki dokümanda) GT ile skorlama scripti yazmak

### 📌 Çalışma anlaşmaları (unutma)
- Bu proje için **Sonnet ile kod yazılmayacak.** Fable, 3 Ağustos toplantısından
  sonra her şey netleşince devreye girecek.
- **Kullanıcı "başla" demeden kod yazılmıyor.**
- Commit/push işlerini **kullanıcı kendisi** yapıyor; ben sadece commit mesajı hazırlıyorum.
- İki seçenek arasında kalınırsa sessizce seçme — **sor.**
- Repo kökündeki `PLAN.md` (takım paylaşım kopyası) **hâlâ eski durumda**, bu
  bulgularla güncellenmesi bekliyor.
- VM erişim bilgileri geldi ama **henüz denenmedi**; `TOGG_MOBESE_FULL.mp4` platformda hazır.
- Rakip bir takımın GitHub reposu incelenecek (öncelik değil).
- **Sert tarih: 7 Ağustos 21:00** — imaj dondurma + SHA256 alma.

---

## Durum Güncellemesi

- **Gün 0-1 (İskelet):** ✅ Tamamlandı ve doğrulandı. Repo `https://github.com/akinmengee/5g-vst-t1` (main) ile bağlandı. FastAPI iskeleti, `schemas/detection.py` + `schemas/mobile_contract.py`, `VehicleAnalysisService`/`OpenGatewayClient` arayüzleri + mock implementasyonları, paylaşılan FTR kodu (`predict.py`/`utils.py`/`main.py`) `_ftr_reference/` altında referans olarak duruyor, `PLAN.md` ve detaylı `README.md` yazıldı.
- **Gün 2-3 (Yürüyen İskelet):** ✅ Fiilen doğrulandı — mock veri üreticisi + WebSocket test istemcisiyle uçtan uca boru hattı (mock veri → `/ws/stream` → geçerli JSON cevabı) çalıştığı gösterildi; hatalı payload'larda bağlantının çökmeden hata döndürdüğü de doğrulandı.
- **Gün 4-7 (Asıl mühendislik):** ✅ Tamamlandı — tam incremental refactor, gerçek model entegrasyonu, Kod İncelemesi Bulguları düzeltmeleri, 202 test (o zamana kadar) geçiyordu.
- **1 Ağustos 2026 — Teknofest resmi final dokümanları geldi ve incelendi:** Kullanıcının isteğiyle (bkz. aşağıdaki "Süreç notu") bu oturum (Sonnet) yalnızca dokümanları detaylıca plana işleme ve açık soruları çıkarma rolünde kaldı; detaylı yeniden planlama ve implementasyon **ayrı bir model (Fable) ile** yapılacak. 4 doküman seti sırayla paylaşılıp incelendi: (1) Final Yarışma Senaryosu, (2) Open Gateway Demo UX Akış Kılavuzu, (3) Yarışmacı Platformu Operasyon Rehberi, (4) Turkcell OGW API spec'leri + Postman koleksiyonu + Faz 2 ground truth. Kullanıcı "elimdeki bütün dokümantasyonlar bunlar" dedi — doküman inceleme turu tamamlandı. Detaylar aşağıdaki ilgili bölümlerde; konsolide açık soru listesi "Tüm Paylaşılan Dokümanlar İncelendi" başlığı altında. **En kritik bulgu:** `event_gate.py`'deki `etiket_basina_max_olay=1` varsayılanı, Faz 2 ground truth'unun beklediği tekrarlı etiket davranışıyla doğrulanmış şekilde çelişiyor — implementasyon aşamasında ilk ele alınacaklardan.
- **1 Ağustos 2026 — kullanıcı yönü netleştirdi:** Fable'a geçiş, 3 Ağustos Pazartesi toplantısından SONRA (her şey netleşince) verilecek bir karar — şimdi değil. Bu arada takım boş durmuyor: mevcut iskelet zaten "boş durmamak için" atılmış bir temel adımdı, zaman daraldıkça daha yoğun çalışılacak. **Hemen sıradaki somut adım: repo kökündeki takım-paylaşım kopyası `PLAN.md`'yi, bu oturumda çıkan tüm yeni bulgularla (Final Senaryosu, Open Gateway akışı, VM/Docker operasyon kuralları, Turkcell API entegrasyon detayları, `event_gate.py` kritik bulgusu, konsolide açık sorular) senkronize etmek** — kullanıcı bunu güncelledikten sonra sıradaki adımı söyleyecek. Ayrıca: rakip bir takımın paylaştığı bir GitHub reposu incelenecek (öncelik değil, ama gündemde) — kendi çözümleri öncelikli kalıyor. Uzun vadeli hedef: mimari kusursuzsa + açık sorular doğru cevaplanırsa + modeller iyi eğitilirse + mobil-uç ROI sistemi ile QoD arasındaki network katmanı minimum tutulursa, **"En İyi Mimari" ödülü** de hedefleniyor.

## 🔴 FİNAL-UYUMLU HEDEF MİMARİ (1 Ağustos, Opus analizi) — aşağıdaki eski Mimari Kararlar'ın bir kısmını GEÇERSİZ KILAR

> Bu bölüm, 4 resmi doküman + mevcut kodun birlikte okunmasıyla yazıldı.
> Aşağıdaki bulguların hepsi **kod okunarak fiilen doğrulandı**, tahmin değil.

### A. Doğrulanmış Kritik Bulgular

**A1 — 🔴 En kritik: Mevcut Docker imajı hakem değerlendirmesinde fiilen 0 puan alır.**
`backend/Dockerfile:26` → `CMD ["python3", "-m", "uvicorn", "app.main:app", ...]`
Bu bir **web sunucusu başlatır ve asla çıkmaz**. Oysa Doküman 3'e göre hakem, Web
UI'dan "Execute"a basar ve imajın `/app/data/input/video.mp4` okuyup
`/app/data/output/results.json` yazıp **sonlanmasını** (`EXECUTION COMPLETED –
status: SUCCESS`) bekler. Uvicorn asla sonlanmaz → execution takılır → sonuç
üretilmez. **Puanın %50'si (düşük kaliteli video %25 + yüksek kaliteli video %25)
şu anki halde doğrudan kaybedilir.**

**A2 — Batch giriş noktası hiç yok.** `backend/app/` altında `/app/data/input/...`
okuyan hiçbir modül yok. Tek örnek `_ftr_reference/main.py` — ama o, "değiştirmeyin"
notuyla duran salt-okunur referans ve `src.predict`'i import ediyor (bizim
yapımızda böyle bir modül yok).

**A3 — 🔴 Araç tespiti/takibi backend'den tamamen çıkarılmış.**
`grep` ile doğrulandı: `detector_model.track(frame, classes=[2, 7, 63], ...)`
satırı **yalnızca** `_ftr_reference/predict.py:383`'te var — `backend/app/` altında
araç bulan/takip eden **tek bir satır bile yok**. `vision_ops.py`'de de yok
(`kabin_kirp` var ama o, zaten kırpılmış ROI'nin içinde *kişi* arıyor).
**Sebep:** Artık terk edilmiş eski ÖTR kararı ("mobil edge yolov8n aracı bulup
kırpar"), bu aşamayı backend'den *silmişti*. Yani o eski edge-AI kararı sadece
mobile bir şey eklemekle kalmamış — **backend'den zorunlu bir aşamayı da
çıkarmıştı.**

**A4 — `process_roi` tam kare kabul edemez.** `current_model_service.py:324-326`:
`# ROI aracın kendisi olduğu için araç kutusu = tüm görüntü` → `arac_orta = w / 2`.
Tam kare (MOBESE görüntüsü) verilirse şoför/yolcu ayrımı, kasa/renk/plaka
sınıflandırması — hepsi tüm kare üzerinde çalışır ve **anlamsız sonuç üretir**.
Yani A2'yi çözüp "batch entrypoint" eklemek tek başına yetmez; A3 çözülmeden
batch yolu çalışsa bile çöp üretir.

**A5 — Zaman kaynağı yanlış olur.** `session.rolatif_zaman(payload.timestamp)`
duvar saati (unix epoch) kullanıyor. Batch'te zaman **video zamanı**
(`frame_index / fps`) olmalı — ground truth'taki `zaman_saniye` değerleri
(0.89, 4.29, …) video-göreli. Zaman kaynağı değiştirilebilir olmalı.

**A6 — `etiket_basina_max_olay=1` ground truth ile çelişiyor.** (Önceden tespit
edildi, bkz. Faz 2 Ground Truth bölümü.) `event_gate.py:28`. GT'de `arka_koltuk_2`
12 kez geçiyor, biz 1 tane yayınlıyoruz → recall katliamı.

**A8 — 🔴 `OpenGatewayClient.verify_number()` arayüzü, gerçek NV protokolüyle
şekil olarak uyuşmuyor (1 Ağustos, kod okunarak doğrulandı).**
`services/network/interface.py`: `async def verify_number(self) -> bool` —
parametresiz, tek çağrıda sonuç dönen, backend'in tek başına yapabileceği bir
şey olarak tasarlanmış. Docstring'i de bunu "oturum başında şebeke seviyesinde
sessiz kimlik doğrulama" diye tarif ediyor. **Gerçekte NV böyle çalışmıyor:**
- Turkcell, isteğin **gerçekten o telefonun hücresel bağlantısı üzerinden**
  geldiğini görerek doğruluyor — backend'in arka planda tek başına "doğrula"
  demesi teknik olarak mümkün değil, çünkü kimliği doğrulayan şey backend'in
  isteği değil, **mobilin kendi ağ oturumunun** Turkcell'e ulaşmasıdır.
- Gerçek akış (OGW_Teknofest.pdf, 11 adım) en az 3 ayrı HTTP taşıması gerektiriyor:
  mobil → backend (telefon no ile başlat) → **mobil hücresel veri üzerinden
  Turkcell'in `/oauth2/authorize`'ına gider** → Turkcell backend'in
  `redirect_uri`'sine `code` ile döner → backend `/oauth2/token`'dan
  `access_token` alır (5 dk geçerli) → backend `/number-verification/v1/verify`'ı
  çağırır.
- **QoD, NV'de alınan `access_token`'ı yeniden kullanıyor** (adım 14) — ama
  `request_quality_on_demand(session_id)` imzasında token kavramı hiç yok, ikisi
  birbirinden kopuk tasarlanmış.
- Çağrı noktası da (`routes_inference.py:30`, WebSocket bağlanınca çağrılıyor)
  zaten terk edilen WebSocket mimarisine bağlı — ikinci kez obsolete.

**Önerilen şekil (henüz kodlanmadı, tartışılıyor):** tek fonksiyon yerine 3
endpoint — `POST /api/auth/login` (telefon no al, Turkcell authorize URL +
`flow_id` dön), `GET /api/auth/callback` (Turkcell'in yönlendirdiği yer; kodu
token'a çevirir, NV'yi çağırır, sonucu `flow_id`'ye karşı saklar), `GET
/api/auth/status/{flow_id}` (mobil bunu poll'lar). `flow_id` → {phoneNumber,
access_token, expires_at, verified} eşlemesi, `SessionRegistry`'deki TTL-eviction
deseniyle aynı şekilde tutulabilir. DI/mock-swap deseni (Protocol tabanlı arayüz)
doğru, korunuyor — sadece metod imzaları gerçek protokole göre yeniden
tasarlanmalı.

**A7 — 10 dakikalık inference limiti gerçek bir kısıt.** Kare başına ~10 model
çağrısı yapılıyor (detector + sigara/telefon/su + kemer + face_landmarker + poz +
teknocan + laptop + kişi). 2 dakikalık 30fps video = 3600 kare × ~10 çağrı.
"Final günü videosu"nun uzunluğu **bilinmiyor** — kare atlama (stride) stratejisi
ve ölçülmüş bir zaman bütçesi şart.

### B. Hedef Mimari — "Kaynak-bağımsız çekirdek, takılabilir ROI kaynağı"

Kurtarılan asıl değer şu: **streaming dedektörleri (`run_detectors.py`,
`event_gate.py`) kare kaynağından tamamen bağımsız.** `(zaman, değer)` gözlemi
alıyorlar; verinin WebSocket'ten mi video dosyasından mı geldiğini bilmiyorlar.
Gün 4-7'de yapılan incremental refactor **boşa gitmedi** — sadece yanlış bir
taşıma katmanına bağlanmıştı.

```
Katman 3 — KARE KAYNAĞI
   [Batch]  cv2.VideoCapture(/app/data/input/video.mp4)   ← ZORUNLU YOL
   [Canlı]  WebSocket akışı                                ← opsiyonel ek

Katman 2 — ROI ÜRETİCİ  (tam kare → aracı bul/takip et → kırp + bbox)
   [Batch]  Backend içinde: detector.track(classes=[2,7,63])  ← YENİDEN EKLENMELİ (A3)
   [Canlı]  Mobil cihazda: yolov8n on-device                  ← aynı işin uçta yapılan hali

Katman 1 — AI ÇEKİRDEĞİ   ★ DEĞİŞMİYOR, ZATEN VAR VE TEST EDİLMİŞ ★
   CurrentModelService.process_roi(roi, bbox, zaman)
   + streaming dedektörleri + oylama + event gate

Katman 0 — ÇIKTI
   results.json (SonucJson)  →  /app/data/output/results.json
```

**Mimari açıdan asıl güzel nokta (sunumda anlatılacak):** Katman 2'nin iki
implementasyonu var — biri sunucuda, biri **5G üzerinden uca itilmiş** hali.
Mobil edge modeli artık "yapıştırma bir ekstra" değil, **aynı katmanın dağıtık
implementasyonu**. QoD de buraya oturuyor: yüksek bant genişliği → yüksek
çözünürlüklü akış → Katman 2'ye daha iyi girdi → daha iyi tespit. Bu, ÖTR'de 92
alan hikâyeyi *öldürmeden*, resmi akışa %100 uyumlu hale getiriyor.

### C. Paketleme: Tek imaj, iki giriş noktası

> **GÜNCELLEME (3 Ağustos toplantısı):** Bu bölümdeki tasarım hâlâ geçerli bir
> alternatif ama artık **tercih edilen yol değil** — organizasyon backend'in
> AI imajının içinde olmasının gerekmediğini teyit etti. Seçilen nihai yaklaşım
> "sadece AI imajı + backend VM'de ayrı process" (bkz. dokümanın en üstündeki
> "🆕 EN GÜNCEL DURUM" bölümü, S2/G3 çözümü). Aşağıdaki "tek imaj, iki entrypoint"
> tasarımı, o karardan önce düşünülmüş ve artık gereksiz olan bir alternatif
> olarak referans amaçlı kalıyor.

Doküman 3 madde 5 "panelde tek imaj kalmalı" diyor. Önerilen çözüm (eski, artık gereksiz alternatif):

- **Tek imaj:** `teknofest-2026/vst-t1:latest`
- **Varsayılan `CMD` = batch çıkarım** (`python3 -m app.batch_main`) → hakem
  Web UI'dan çalıştırınca doğru şey olur, sonlanır, SUCCESS verir.
- **Backend, aynı imajdan entrypoint override ile** kaldırılır
  (`docker run --entrypoint python3 ... -m uvicorn app.main:app`) → panelde
  ikinci bir imaj görünmez, kural ihlal edilmez.
- Backend, canlı demoda videoyu paylaşımlı klasöre yazıp **aynı imajı batch
  modunda tetikler** (Doküman 2'deki "paylaşımlı klasör + tetikle + 202 dön"
  deseni birebir).

Böylece **canlı demoda gösterilen results.json ile hakemin ürettiği results.json
aynı kodun çıktısı olur** — tutarlılık hem puan hem güvenilirlik açısından kritik.

### D. Öncelik Sırası (puan ağırlığına göre)

| Öncelik | İş | Puan etkisi |
|---|---|---|
| **P0** | `batch_main.py` + Dockerfile `CMD` düzeltmesi (A1, A2) | **%50** — şu an 0 |
| **P0** | Katman 2'yi geri ekle: araç tespit/takip + kırpma (A3, A4) | **%50** — olmadan P0 çöp üretir |
| **P0** | Video-zamanı kaynağı (A5) | **%50** — zamanlar yanlışsa eşleşme olmaz |
| **P0** | `etiket_basina_max_olay` düzeltmesi (A6) | **%50** — recall |
| **P1** | Faz 2 videosu + GT ile ölçüm ve eşik ayarı | **%50** doğruluk |
| **P1** | 10 dk zaman bütçesi ölçümü + stride (A7) | **%50** — aşılırsa 0 |
| **P1** | VM'de gerçek Web UI ile uçtan uca deneme | tümü |
| **P2** | Backend: NV/QoD proxy + video upload + job tetikleme | %25 canlı demo |
| **P2** | Mobil: NV → QoD → HLS kayıt → upload → sonuç ekranı | %25 canlı demo |
| **P3** | Canlı önizleme (WebSocket + mobil edge) — *resmi sonuç kaynağı DEĞİL* | %25 sunum |

**Kritik gözlem:** Batch doğruluğu (%50), tüm canlı demonun (%25) iki katı
değerinde — ve canlı demonun AI kısmı da zaten aynı batch imajı. Yani **enerjinin
çoğu Katman 1+2'nin doğruluğuna gitmeli.**

### E. Ölçülebilir Doğrulama (elimizde GT var — bu bir şans)

Faz 2 videosu (HLS linki) + `faz2_gt.json` elimizde. Bu, "modelimiz iyi mi"
sorusunu **tahminden çıkarıp ölçüme** dönüştürüyor:
1. Faz 2 videosunu iki çözünürlükte indir (`ffmpeg`).
2. Batch imajını çalıştır → `results.json`.
3. GT ile karşılaştıran bir skorlama scripti yaz (etiket + zaman toleransı).
4. Eşikleri (`thresholds.py` — zaten hepsi config'te, madde 8 sayesinde) bu
   ölçüme göre ayarla.
Bu döngü kurulduğu an, eşik ayarı körlemesine değil veriye dayalı olur.

### E2. Kavramsal Netleştirme — "AI imajı bir API DEĞİL, bir programdır"

Bu ayrım, A1'deki hatanın kök sebebi olduğu için plana açıkça yazılıyor:

**AI imajı (hakemin çalıştırdığı şey):** port dinlemez, HTTP almaz, istek beklemez.
```
Web UI "Execute" → container başlar
   /app/data/input/video.mp4    OKUR
   ... işler ...
   /app/data/output/results.json YAZAR
   exit 0 → container ÖLÜR
Web UI: "EXECUTION COMPLETED – status: SUCCESS"
```
Hakem ona video "göndermez"; Web UI videoyu volume ile o yola koyar ve container'ı
çalıştırır. Container **sonlanmak zorundadır**. Mevcut `CMD` uvicorn başlattığı
için asla sonlanmıyor — A1'in tam sebebi bu.

**Backend (bizim yazdığımız API):** hakem için değil, **telefon için**.
```
Telefon → POST /api/upload (video.mp4)
Backend → /data/{job}/input/video.mp4 olarak yazar
Backend → AI imajını batch modunda tetikler (docker run)
Backend → telefona hemen 202 + job_id döner
Telefon → GET /api/jobs/{id} → PROCESSING → DONE + results.json
```
Yani backend, batch programı API'ye *çeviren* ince bir katman (Doküman 2'deki
desenin aynısı).

**Sonuç:** Hakem, %50'lik batch değerlendirmesinde (Doküman 1 Adım 5) bizim
backend'imize **hiç dokunmaz** — kendi Web UI'ından imajı çalıştırır. Backend
yalnızca %25'lik canlı demoda (Adım 4) devrededir. Bu yüzden paketleme kararı
düşük riskli ve geri dönülebilir.

### G0. Model Envanteri Denetimi (1 Ağustos) — "hız modeli eksik mi?" sorusuna cevap

**Soru:** Ekip arkadaşları "modellerde hız ile ilgili bir model yok" dedi.

**Cevap: Spesifikasyonda "hız" diye bir tespit YOK — hız modeli de gerekmiyor.**
Doğrulama (üç bağımsız kaynak):
- `schemas/detection.py:13-18` — geçerli etiketlerin tam listesi; hiçbiri hız değil.
- `faz2_gt.json` (resmi ground truth) — hız içermiyor.
- FTR'de fiilen teslim edilen kod — `hiz|hız|speed` araması **sıfır sonuç**.

**Karışıklığın kaynağı bu plan dosyasının kendisiydi:** "Gün 4-7" maddesinde
*"Slalom/hız gibi daha karmaşık tespitler"* yazıyordu — önceki bir oturumda yazılmış
hatalı bir ifade. Düzeltildi.

**Gereken tüm çıktıların model karşılığı MEVCUT — eksik model yok:**

| Çıktı | Üreten | Ağırlık | Durum |
|---|---|---|---|
| sigara_icme | sigara_v1.pt | ✅ | kendi eğitimimiz |
| telefonla_konusma | telefon_temiz_v1.pt | ✅ | kendi eğitimimiz |
| su_icme | su_v2.pt | ✅ | kendi eğitimimiz |
| emniyet_kemeri_ihlali | kemer_v3.pt | ✅ | kendi eğitimimiz |
| teknocan | teknocan.pt | ✅ | kendi eğitimimiz |
| slalom | slalom_lstm.pt + yörünge | ✅ | kendi eğitimimiz |
| esneme | face_landmarker.task (MAR) | ✅ | **hazır (MediaPipe)** |
| arkaya_bakma / etrafa_bakinma | yolov8n-pose.pt | ✅ | **hazır (stock)** |
| bilgisayar | yolov8s.pt COCO sınıf 63 | ✅ | **hazır (stock)** |
| arka_koltuk_1/2, on_koltuk | yolov8s.pt COCO sınıf 0 + geometri | ✅ | **hazır (stock)** |
| tip / renk | kasa_modeli.pt / renk_modeli.pt | ✅ | kendi eğitimimiz |
| plaka | plaka_modeli.pt + karakter_modeli.pt | ✅ | kendi eğitimimiz |
| **Katman 2: araç bul/takip** | yolov8s.pt COCO [2,7,63] | ✅ ağırlık var | ❌ **KOD YOK** (bkz. A3) |

→ **Eksik olan model değil, kod.** Zaten P0 listesinde.

**Ground truth olay dağılımı (34 olay sayıldı) — öncelik için kritik:**

| Kaynak | Olay | Pay |
|---|---|---|
| yolcular (arka_koltuk_2 ×12, arka_koltuk_1 ×1, on_koltuk ×1) | 14 | **%41** |
| emniyet_kemeri_ihlali | 4 | %12 |
| teknocan | 4 | %12 |
| sigara_icme | 3 | %9 |
| su_icme / telefonla_konusma | 2+2 | %12 |
| esneme / arkaya_bakma / etrafa_bakinma / slalom / bilgisayar | 1 each | %15 |

- **%53'ü (18/34) hazır modellerden geliyor** (stock YOLO kişi/COCO, MediaPipe, stock pose) — model eğitimi gerektirmez.
- %47'si (16/34) kendi eğittiğimiz ağırlıklara bağlı.

**→ En yüksek getirili tek iş: yolcu koltuk-atama geometrisini doğru yapmak.**
Olayların %41'i orada ve **hiç model eğitimi gerektirmiyor**, saf geometri
(`current_model_service.py:296-346`). Model eğitimi eforu ise kemer + teknocan +
sigara'ya (toplam %33) yoğunlaşmalı.

**⚠️ Çekince:** Puanlama scriptinin olay-başına mı etiket-başına mı saydığı
bilinmiyor. Olay-başına sayarsa yukarıdaki dağılım geçerli; etiket-başına sayarsa
yolcuların ağırlığı düşer (14 olay → 3 etiket). (bkz. "🆕 EN GÜNCEL DURUM"
bölümündeki açık soru listesi.)

**Ölü ağırlık dosyaları:** `yolov8n.pt` (mobil edge içindi, G1 kararıyla gereksiz)
ve `yolov8s-cls.pt` (ne bizde ne FTR'de kullanılıyor) — imajdan çıkarılabilir.

### G. Kullanıcı Kararları (1 Ağustos)

**G1 — Katman 2 backend'e taşınıyor. ✅ Karar verildi.**
Kullanıcının ifadesiyle: *"ROI için küçük bir model yerine, backend'de yine ilk
aşama olarak kullanılacak ayrıştırma aracını backend'e taşırız… bize keskin
kurallarla beraber sınırları belirtmişler, bizden istenen şey çok net. O yüzden
elimizdeki mimariyi değiştirebiliriz, en baştan da yazabiliriz."*
→ Araç bul/takip et/kırp aşaması artık backend'in **zorunlu** bir parçası
(B bölümündeki Katman 2). Mobil edge modeli zorunlu yolun parçası değil.
→ Mimariyi değiştirmek serbest; sıfırdan yazmak da masada.

**G2 — Moral/çerçeve notu (kayda geçsin):** Kullanıcı bu bulgular karşısında
"ÖTR yalan olmuş gibi görünüyor" dedi. Bu çerçeve **yanlış ve düzeltildi**:
ÖTR bir *tasarım önerisiydi*, kurallar ÖTR'den sonra yayınlandı, 92 puan hak
edilerek alındı ve geri alınmıyor. Finalin özü aslında *"FTR'yi bu sefer düzgün
yap + üstüne 5G/mobil demo katmanını ekle"* — FTR'de kod 19/100 almıştı, elimizdeki
çekirdek ondan çok daha iyi mühendislik ürünü. Ayrıca bu hatayı 8 Ağustos'ta değil
**1 Ağustos'ta** yakalamış olmak ciddi bir kazanç.

**Kurtarılan varlıklar (somut):**
- Streaming dedektörleri + event gate — kare kaynağından bağımsız, 193 eşdeğerlik
  testiyle doğrulanmış, aynen çalışacak.
- `thresholds.py` — 30+ eşiğin config'te olması, ground truth ile ölçüm yapacağımız
  için şu an kritik değerde (FTR'de bunlar koda gömülüydü).
- `model_registry.py` — model-başına try/except yükleme (FTR'nin import-anında
  çöken yapısına göre büyük iyileşme).
- Şemalar, `attribute_voting`, `vision_ops` — aynen duruyor.
- **`SessionRegistry` sürpriz kazanç:** canlı çok-oturum için tasarlanmıştı ama
  batch'te **çok-araç takibine** (`session_id = track_id`) neredeyse birebir
  oturuyor; TTL eviction bile işe yarıyor.

### L. Kullanıcının Paylaştığı Akış Diyagramı — Doğrulama (1 Ağustos)

Kullanıcı, tüm final akışını (Hazırlık/Teslimat → NV/QoD → Streaming → YZ
Değerlendirme → Hakem Değerlendirme, 28 adımlı) gösteren bir sequence diyagram
paylaştı. Bu, H/I/J/K bölümlerindeki tasarımı **üçüncü bağımsız kaynaktan**
doğruluyor:

- **Mobilin AI/model çalıştırma gibi bir işi yok** — NV, QoD, video kaydı/aktarımı,
  sonuç gösterimi: hepsi orkestrasyon, hiçbiri çıkarım değil. G1 kararını
  (mobil edge modeli zorunlu değil) bir kez daha doğruluyor.
- **Kullanıcının açık talimatı:** *"Bu akış doğrultusunda bütün kodu yazacağız.
  Başka senaryolar önemli değil, MOBESE olması falan önemli değil, bizden
  beklenen tamamen bu."* → Tek-araç varsayımı (Bölüm K) ve genel tasarım yönü
  **kesinleşti**, başka senaryo/genelleme aranmayacak.

**⚠️ Önemli teknik netleştirme (diyagramın basitleştirdiği nokta):**
Diyagramda mobil, NV Servisi'yle doğrudan konuşuyor gibi çizilmiş (backend
görünmüyor). Bu muhtemelen sadece diyagramın sadeleştirmesi — `OGW_Teknofest.pdf`
(Doküman 4), `client_id`/`client_secret`'ın **yalnızca backend'de** saklanması
gerektiğini açıkça belirtiyor, yani `/oauth2/token` değişimi mobilde asla
yapılamaz. **H bölümündeki backend-relay tasarımı (flow_id, callback, polling)
hâlâ geçerli ve zorunlu** — diyagramla çelişmiyor, sadece atladığı detayı
dolduruyor.

**Yeni yakalanan detay (adım 17):** Mobil uygulama, `results.json`'ı göstermenin
yanında **onun SHA256 parmak izini de hesaplayıp ekranda göstermeli** (Docker
imajının SHA256'sından ayrı, farklı bir hash — muhtemelen şeffaflık/doğrulama
amaçlı). Ucuz bir iş, J bölümüne eklenmeli (mobil tarafta `results.json`
içeriğinin SHA256'sını hesaplayıp UI'da göster).

**Adım 18 — Lifebox paylaşımı** diyagramda ayrı bir adım olarak teyit edildi,
zaten J bölümünde "bizim işimiz değil" diye işaretlenmişti.

**Adım 22-27 (Hakem Değerlendirme Aşaması) — batch değerlendirmeyi netleştiriyor:**
Hakem, düşük+yüksek kaliteli videoları HER ZAMAN değerlendiriyor; yarışmacının
canlı demoda ilettiği (Lifebox) video ise **yalnızca NV başarılıysa VE veri
iletildiyse** koşullu olarak üçüncü kez değerlendiriliyor (`opt` bloğu) — Doküman
1'in "3 video" ifadesindeki koşulu netleştiriyor.

### K. Batch AI (Katman 2 dahil) İmplementasyon Planı — ✅ tasarım netleşti (1 Ağustos)

**✅ Doğrulandı (kullanıcı + `faz2_gt.json`'ın kendisi): klip başına TEK araç.**
Faz 2 GT, tek bir `arac_bilgisi` bloğu ve ~111sn boyunca kesintisiz süren tek bir
sürücünün sırayla farklı senaryoları "sahnelediği" 34 olaydan oluşuyor (esneme →
telefon → kemer → su → sigara → arkaya bakma → slalom, birbirinden net ayrık
zaman dilimlerinde). Bu, kasıtlı kurgulanmış bir test videosu — MOBESE tarzı
çoklu-araç trafik görüntüsü **değil**. Önceki turdaki "FTR'nin `best_vid` çoklu-araç
seçim mantığı gerekli mi" sorusu bu doğrulamayla **kapandı: gerekli değil.**

**Basitleştirilmiş `batch_main.py` akışı** (FTR'nin `.track(persist=True)` +
çoklu-`vehicle_id` sözlükleri yerine — tek adayı ayırt etmeye gerek yok):

```
1. cap = cv2.VideoCapture(input_path); fps = cap.get(CAP_PROP_FPS)
2. registry = ModelRegistry(); service = CurrentModelService(registry)
3. frame_idx = 0
4. while cap.read() başarılıysa:
     if frame_idx % STRIDE == 0:
        zaman = frame_idx / fps                      # A5 çözümü: video-göreli zaman
        kutu = tek_arac_bul(detector, frame)          # tek en güvenli kutu, .predict() yeterli — .track() GEREKMİYOR
        if kutu bulunduysa:
            crop = pad_ve_kirp(frame, kutu)
            service.process_roi(session_id="main", crop, bbox=kutu, zaman)  # HER ZAMAN aynı session_id
     frame_idx += 1
5. service.finalize_session("main")
6. results.json = {video_id, arac_bilgisi: session.oylama'dan, tespitler: session'ın yayınladıkları}
7. /app/data/output/results.json yaz, exit 0
```

**Neden `.track()` gerekmiyor:** Takip, birden fazla adayı birbirinden ayırt
etmek içindir. Tek araç varsa, her karede "bu karede görünen araç" zaten tek
adaydır — kimlik sürekliliğine ihtiyaç yok, sadece "bu karede araç var mı,
nerede" yeterli. `SessionRegistry`'nin TTL-eviction'ı da batch'te gereksiz
(video boyunca tek session, process bir kere çalışıp çıkıyor) — process_roi'yi
hep aynı `session_id` ile çağırmak yeterli, özel bir bypass gerekmiyor.

**Değişmeyen/gerekli parçalar (özet, A3/A5/A6'nın somutlaşmış hali):**
- Katman 2: araç bul + kırp (`_ftr_reference/predict.py:383` civarındaki mantık,
  tracking kısmı hariç sadeleştirilerek).
- `process_roi`'nin ham `numpy` frame kabul eden bir varyantı — batch'te
  JPEG encode/decode turuna gerek yok (mevcut arayüz `image_bytes: bytes`
  bekliyor, bu MobileRoiPayload/WebSocket'e özgü bir tasarım kalıntısı).
- `etiket_basina_max_olay` cap'inin kaldırılıp cooldown'a bırakılması — bu GT
  (`arka_koltuk_2` ×12) ile bir kez daha doğrulandı.
- `STRIDE` değeri: 10 dakikalık bütçeye göre **ölçülerek** belirlenecek (A7),
  şimdiden tahmin edilmiyor.

### J. Streaming / Video Upload İmplementasyon Planı — ✅ tasarım netleşti (1 Ağustos)

**Kritik kavramsal netleştirme: backend'in bu adımda neredeyse hiç rolü yok.**
İki ayrı alt-parça var:

**Parça 1 — Mobil ↔ Turkcell (backend'in hiç görmediği kısım):** Mobil,
Turkcell'in HLS adresine (`.../faz2/faz2.smil/playlist.m3u8`) doğrudan bağlanır,
adaptif bir player başlatır (kalite QoD durumuna göre kendiliğinden 240p↔1080p
arası değişir — Doküman 2), ve videoyu **tam bir MP4 dosyası olarak dışa aktarır.**
Önerilen teknik yaklaşım: ekran kaydı DEĞİL, HLS'i doğrudan dosyaya indirip
yeniden paketlemek (`ffmpeg -i <hls_url> -c copy output.mp4` mantığı,
Flutter'da bir ffmpeg wrapper paketiyle). Video ~2dk, 5dk'lık pencereye bolca
sığıyor. *(Bu adım mobil tarafın işi — burada backend'in kararı yok, sadece
teknik yön gösterildi.)*

**Parça 2 — Mobil → Backend (bizim asıl işimiz):**
```
Mobil ── POST /api/videos/upload (multipart: flow_id, video.mp4) ──► Backend
                                                                        │ job_id üret
                                                                        │ /data/jobs/{job_id}/input/video.mp4 yaz
                                                                        │ AI imajını arka planda tetikle:
                                                                        │  docker run -v .../input:/app/data/input
                                                                        │             -v .../output:/app/data/output
                                                                        │             teknofest-2026/vst-t1
Mobil ◄── 202 {job_id} ─────────────────────────────────────────────┤ (bloklamadan hemen döner)
Mobil ── GET /api/videos/{job_id}/result (polling) ──► Backend
                                                          │ /output/results.json var mı? process bitti mi?
Mobil ◄── {status: PROCESSING|DONE|FAILED, results?} ──┤
```
Doküman 2'nin "Upload Video to Backend" → `202 Accepted` → "AI Result sekmesi
PROCESSING/DONE/FAILED" akışıyla birebir örtüşüyor — referans olarak
doğrulanmış. Bölüm C/E2'deki "AI imajı program, backend onu API'ye çeviren ince
katman" tasarımı burada devreye giriyor: `docker run` komutu varsayılan CMD'yi
(batch inference) kullanır, entrypoint override GEREKMİYOR.

**Job takibi:** `job_id → {process_handle, started_at}` hafif dict
(`SessionRegistry`'deki TTL deseniyle aynı), **10 dakikalık zaman aşımı
eklenmeli** (Doküman 1 madde 5'teki hakem inference limitiyle tutarlı — süreç
10dk'yı geçerse FAILED işaretlenir).

**Lifebox paylaşımı (3 Ağustos'ta netleşti):** Doküman 1: *"MP4 dosyası
hakemler ile Lifebox üzerinden paylaşılacak"* — bu, yukarıdaki backend
akışından **ayrı, ikinci bir paylaşım kanalı.** Lifebox, Turkcell'in gerçek,
genel-amaçlı tüketici bulut depolama servisi (foto/video/müzik/rehber/belge
yedekleme, ilk üyelikte 5GB ücretsiz — bkz. mylifebox.com). Hiçbir OGW
dokümanında geliştirici API'sinden bahsedilmiyor — **muhtemelen bu adım
manuel** (video kaydedildikten sonra Lifebox uygulaması/sitesi üzerinden elle
yüklenip paylaşılıyor, uygulamamızın bunu programatik yapması gerekmeyebilir).
Kesin teyit yok ama risk seviyesi "bilinmeyen API" → "bilinen tüketici
uygulaması, muhtemelen manuel adım" olarak düştü. **Kod yazma aşamasına
geçildiğinde unutulmamalı** — otomatik entegrasyon gerekip gerekmediği son
anda teyit edilmeli.

### I. QoD (Quality on Demand) İmplementasyon Planı — ✅ tasarım netleşti (1 Ağustos)

NV'ye göre çok daha basit: mobilin tarayıcıya gitmesi gerekmiyor, NV'de alınan
`access_token`'ı yeniden kullanan **tek, doğrudan, senkron** bir backend→Turkcell
çağrısı. WebView/callback/polling YOK.

```
Mobil ── POST /api/qod/start {flow_id} ──► Backend
                                              │ flow'dan access_token bul (<300sn)
                                              ├─ POST /quality-on-demand/v1/sessions
                                              │  (Bearer, duration:360,
                                              │   applicationServer.ipv4Address:
                                              │   "0.0.0.0/0", qosProfile:"teknofest2026")
                                              │◄─ 201 {sessionId, qosStatus:REQUESTED}
Mobil ◄── {success:true, sessionId, qosStatus:"REQUESTED"} ──┤
```

**`POST /api/qod/start {flow_id}`:**
- `duration` (360sn = Doc 1'deki 5dk streaming penceresi + 1dk pay),
  `applicationServer.ipv4Address` ("0.0.0.0/0"), `qosProfile` ("teknofest2026")
  — **üçü de backend'e sabit gömülü**, mobil bir parametre göndermiyor (Doc 1'in
  akışı sabit sıralı adımlar, Doc 2'deki demonun aksine kullanıcı süre seçmiyor).
- `409 Conflict` (zaten aktif oturum) → hata değil, `{success:true,
  already_active:true}` — puan kaybı yok.
- Diğer hatalar (400/401/422/429) → `{success:false}`, mobil sorunsuz streaming
  adımına geçer — **QoD başarısızlığı puan kaybettirmiyor**, sadece +5 kaçıyor.
- Flow state, NV'nin `FlowState`'i genişletilerek tutulur (yeni state deposu yok):
  `qod_status`, `qod_session_id` eklenir.

**✅ Karar — QoD "başarı" kriteri:** `201 Created` + `qosStatus: REQUESTED` almak
**yeterli sayılır**, `AVAILABLE` durumunu beklemek (polling/webhook) **eklenmiyor**.
Gerekçe: basitlik + hız (5dk'lık streaming penceresinden zaman çalmamak); video
zaten kendi ABR mantığıyla gerçek bant genişliğine adapte olacak (Doküman 2).
Bu, konsolide açık soru listesindeki 2. maddeyi çözer.

### H. NV (Number Verification) İmplementasyon Planı — ✅ tasarım netleşti (1 Ağustos)

A8'deki bulgunun (arayüz şekli protokolle uyuşmuyor) çözümü olarak somut akış:

```
Mobil                    Bizim Backend                  Turkcell
  │─ POST /api/auth/login {phoneNumber} ──►│
  │◄─ {flow_id, authorize_url} ────────────┤ (flow_id üretir, "pending" saklar)
  │─ authorize_url'i WebView'de açar (hücresel veri) ─────────►│ (prompt=none,
  │                                                              görünmez geçer)
  │◄──────── redirect_uri?code=...&state=flow_id ───────────────┤
  │  (arka planda, WebView farkında olmadan) ──► GET /api/auth/callback
  │                            ├─ POST /oauth2/token (Basic Auth b64(client_id:secret)) ─►│
  │                            │◄─ access_token (300sn geçerli) ─────────────────────────┤
  │                            ├─ POST /number-verification/v1/verify (Bearer) ─────────►│
  │                            │◄─ devicePhoneNumberVerified ────────────────────────────┤
  │                            │  flow → "verified"/"rejected", basit HTML döner
  │  (WebView'i kapatır)       │
  │─ GET /api/auth/status/{flow_id} (~1sn polling) ──►│
  │◄─ {status, devicePhoneNumberVerified} ────────────┤
```

**Endpoint sözleşmeleri:**
- `POST /api/auth/login {phoneNumber}` → `{flow_id, authorize_url}`. authorize_url:
  `{Turkcell}/oauth2/authorize?response_type=code&client_id=...&redirect_uri=...`
  `&state={flow_id}&scope=openid+dpv:RequestedServiceProvision%23quality-on-demand:`
  `sessions:create+dpv:FraudPreventionAndDetection%23number-verification:verify&prompt=none`
- `GET /api/auth/callback?code=...&state=...` → `state`den flow bulunur → token
  exchange → NV verify → flow güncellenir (**`access_token`, QoD'nin yeniden
  kullanması için flow'a yazılır**) → basit HTML ("kapatabilirsiniz") döner.
- `GET /api/auth/status/{flow_id}` → `{status: pending|verified|rejected|error,
  devicePhoneNumberVerified?}`.
- State deposu: `SessionRegistry`'deki TTL-eviction deseninin aynısı, `flow_id →
  FlowState` dict.

**Mobil tasarım kararı: uygulama içi WebView (deep-link YOK).** Gerekçe: iki
platformda (Android+iOS) deep-link/URL-scheme kurulumu 6 günde risk; WebView
programatik kapatılabiliyor, polling mobilin callback URL'ini parse etmesini bile
gerektirmiyor.

**Hata durumları:** WiFi'de olma hatası (`403
NUMBER_VERIFICATION.USER_NOT_AUTHENTICATED_BY_MOBILE_NETWORK`) → status'a açık
mesaj olarak yansıtılmalı ("mobil veriyi aç"); süresi geçmiş `code` → mobil yeni
`flow_id` ile `/login`'i tekrar çağırabilir (idempotent); 60sn'de sonuç
gelmezse mobil timeout gösterip yeniden dener.

**🔴 Aksiyon maddesi — zamana duyarlı:** `redirect_uri`, Turkcell'e **önceden
kayıtlı** olmalı (standart OAuth kuralı). VM IP zaten elde — **3 Ağustos
toplantısına tam `redirect_uri` değeri (`http://<VM_IP>:<port>/api/auth/callback`)
hazır götürülmeli**, Turkcell client_id ile eşleştirip kaydetsin.

**G3 — Paketleme kararı: ✅ ÇÖZÜLDÜ (3 Ağustos toplantısında, bkz. dokümanın en
üstündeki "🆕 EN GÜNCEL DURUM" bölümü).** Organizasyon sözlü olarak backend'in
AI imajının içinde olmak zorunda olmadığını teyit etti — tek şart AI imajıyla
konuşabilmesi (video ver → JSON al). **Seçilen: (B) Sadece AI imaj + backend
VM'de düz Python process.** Bu, Docker-in-Docker/`docker.sock` mount etme
ihtiyacını da ortadan kaldırıyor.

## Yeni Gelişme (Teknofest resmi maili — 30 Temmuz akşamı)

Teknofest'ten final öncesi hazırlık maili geldi. Mailin kendisi sadece kapak metni;
gerçek senaryo/teknik gereksinim/hazırlık dokümanları ayrıca ek olarak gönderilmiş
ama bu konuşmada henüz paylaşılmadı — **taranıp bu plana işlenmesi bekleniyor.**

Mailden çıkan somut, doğrulanmış bilgiler:
- **Takıma özel bir VM (sanal makine) tahsis edildi** (`teknofest-competition-10`,
  VM_IP/USERNAME/PASSWORD ile). Bu, planın "Backend için bulut sağlanacağı söylendi
  ama detay/toplantı yok" belirsizliğini muhtemelen çözüyor — VM specs (GPU var mı,
  RAM, OS) henüz bilinmiyor, dokümanlarda veya VM'e bağlanılınca netleşecek.
- 3 Ağustos 2026 Pazartesi 11:00 Soru-Cevap toplantısı teyit edildi (zaten planda vardı).
- Final öncesi VM ortamının test edilmesi ve gerekli kurulumların tamamlanması
  organizasyon tarafından açıkça bekleniyor.

**Süreç notu:** Kullanıcı, dokümanlar geldikten sonraki detaylı planlama ve
uygulama işini bu oturumda değil, ayrı bir model (Fable) ile yapacak. Bu oturumda
(Sonnet) sadece gereksinimlerin netleştirilmesi ve kullanıcıya sorulması gereken
açık noktaların çıkarılması hedefleniyor — plana büyük yapısal değişiklik bu
dokümanlar okunup Fable ile planlama yapılana kadar ertelendi.

## Final Yarışma Senaryosu — Resmi Doküman (1. paylaşılan doküman, 1 Ağustos 2026)

Kullanıcının paylaştığı "Final Yarışma Senaryosu" PDF'i, final gününün adım adım
akışını ve puanlama kurallarını **resmi olarak** tanımlıyor. Bu, yukarıdaki
"Context" bölümündeki takımın kendi TAHMİNİNİN (3 Ağustos toplantısı öncesi
yapılmıştı) yerini alıyor. Kullanıcı dokümanları sırayla paylaşacak (hepsini
birden değil) — bu ilk doküman. Aşağıda tüm önemli detaylar ve **önceki mimari
kararlarla gerilim yaratan noktalar** ayrıştırılmış şekilde tutuluyor.

### Genel Akış
- Final'e katılan 20 takım, Turgut Özal Yabancı Diller Yüksekokulu Kongre ve
  Öğrenci Sosyal Merkezi'nde toplanır; kurallar anlatılır, yaka kartı dağıtılır,
  kura ile sıra belirlenir.
- Yarışma 4'er takımlık **5 oturum** halinde yapılır.
- Her oturumda takım kaptanı/sözcüsü **en fazla 10 dk** sunum yapar (format
  serbest). Bu sunum hem final puanına hem de ayrı bir **"En İyi Sunum Ödülü"**
  değerlendirmesine giriyor.

### Final Günü Senaryosu — adım adım
1. **Geliştirme kesim tarihi: 7 Ağustos 21:00.** Bu saatten sonra değiştirilen
   Docker image değerlendirmeye alınmıyor. **Yarışmacı, ürettiği image'ın SHA256
   hash'ini almalı** (hakem VM'inde inference öncesi bu hash, teslim edilenle
   karşılaştırılıyor — bkz. madde 5).
2. Mobil uygulama açılır, **Number Verification (NV)** tamamlanır. NV
   başarısızsa sonraki adımlara geçilemez, canlı demo kulvarından **0 puan**.
3. NV başarılı → **+5 puan**. Ardından **QoD çağrısı** yapılır: başarılıysa
   **+5 puan daha (toplam 10)**; başarısızsa puan kaybı olmadan bir sonraki
   adıma geçilir (5 puanda kalınır).
4. Mobil uygulama **streaming sunucusuna bağlanıp, maksimum 5 dakika içinde**
   videonun tamamını kaydedip **MP4 olarak dışa aktarmalı**. MP4, hakemlerle
   **Lifebox** üzerinden paylaşılır. Kayıt/aktarım başarısız olursa diskalifiye
   edilmez — o ana kadarki puan (5 ya da 10) korunur.
   - Yarışmacı, kaydettiği videoyu **kendi backend'ine** aktarıp **yapay zeka
     imajına** vererek inference tetikler; üretilen **results.json**'ı
     uygulamada göstererek canlı demo tamamlanır.
   - Yarışmacı, mobil-backend-YZ arayüzlerini tasarlamak/geliştirmek/ayağa
     kaldırmaktan sorumlu; **ağ koşullarından kaynaklı gecikmeleri test edip
     önlem almalı.**
5. Final günü videosunun düşük/yüksek çözünürlüklü versiyonları + (varsa)
   stream'den kaydedilip Lifebox'tan indirilen video — **toplam 3 video** —
   hakemlerce **yarışmacı VM'ine** yüklenir, bu videolar üzerinden inference ile
   results.json'lar üretilir. **Her inference için maksimum 10 dakika.**
   İnference öncesi, teslim alınan YZ image'ın SHA256'sı yarışmacının verdiğiyle
   eşleşiyor mu kontrol edilir.
6. results.json dosyaları **hakem VM'ine** aktarılır, orada otomatik
   değerlendirme scriptiyle puanlanır.

### Çözüm Mimarisi (Şekil 2 + Şekil 3)
- Renk kodu: **kırmızı = yarışmacı geliştirir, mavi = Turkcell sağlar.**
- **Şekil 2 (Stream Kaydı):** Mobil Uygulama (UE/Telefon + 5G SIM) → Turkcell'in
  **Streaming Server**'ına bağlanır → "stream kaydı" backend'e gider. Backend,
  Google Cloud / **Ubuntu VM** üzerinde.
- **Şekil 3 (Canlı Video Analizi):** Mobil Uygulama → (1-video) → **Backend** →
  (2-video) → **Yapay Zeka İmajı** → (3-results.json) → Backend → (4-results.json)
  → Mobil Uygulama. Backend ve Yapay Zeka İmajı, ikisi de aynı Ubuntu VM (Google
  Cloud) üzerinde ama **diyagramda ayrı bileşenler** olarak çizilmiş.
- "Mimarinin teknik detayları ve arabirim kurgusu yarışmacıların inisiyatifine
  bırakılmıştır" — resmi doküman kasıtlı olarak açık uçlu bırakıyor. Ama
  **testlerin ve farklı ağ koşullarına karşı sağlamlığın sınanması tamamen
  yarışmacı sorumluluğu** diye özellikle vurgulanmış.

### Final Puanlama Kuralları

| Düşük Kaliteli Video | Yüksek Kaliteli Video | Canlı Demo | Sunum | Toplam |
|---|---|---|---|---|
| %25 | %25 | %25 | %25 | %100 |

- Nihai puanın %50'si: genel sunum (%25) + canlı demo (%25).
- Diğer %50'si: YZ çözümünün, final videosunun düşük/yüksek çözünürlüklü
  versiyonlarında (organizasyon tarafından, yarışmacı VM'inde) çalıştırılmasıyla.
- Canlı demo içi kademeli puanlama (Şekil 4):
  NV başarısız → 0 puan | NV başarılı → 5 puan | +QoD başarılı → 10 puan (toplam)
  | +QoD başarısız → puan kaybı yok, 5 puanda kalınır → Streaming başarılı →
  **kaydedilen videonun YZ çıktısı puana yansır** | Streaming başarısız + sadece
  NV yapılmış → toplam 5 puan | Streaming başarısız + NV&QoD yapılmış → toplam
  10 puan.

### Streaming ve Faz 2 Detayları
- Streaming sunucusunda **iki farklı çözünürlükte video** var (QoD kullanımından
  doğan bant genişliği farkını simüle etmek için) — ikisi de Faz 2'de kullanılan
  videodan üretilmiş.
- **Mobil uygulama, anlık bant genişliğine uygun çözünürlüğü seçerek stream
  etmeli.** QoD başarısız olup düşük bant genişliğindeyken yüksek çözünürlüklü
  videoyu indirmeye çalışırsa, 5 dakikalık süre yetmez → canlı demo aşaması
  başarısız olur. **Yani mobil tarafta, QoD sonucuna göre doğru stream kalitesini
  seçen adaptif bir mantık kurulması gerekiyor** — yarışmanın kendisi bunu ölçen
  bir tuzak kurmuş durumda.
- Faz 2 videosu:
  `https://teknofest-arge-turkcell.ercdn.net/hls/4/pZ/faz2/faz2.smil/playlist.m3u8`
  (**HLS/m3u8** formatında — Turkcell'in streaming altyapısının teknolojisi
  hakkında ipucu; `ffmpeg`/`ffprobe` ile incelenebileceği belirtiliyor).
- Bu video için bir **"ground truth"** da paylaşılmış; **iki çözünürlükteki video
  + ground truth kullanılarak YZ çözümünün fine-tune edilmesi bekleniyor.**
  Ground truth'ta olaylar/nesneler/yolcular **görülebilir oldukları anda**
  işaretlenmiş (frame-accurate) — mevcut streaming eşdeğerlik testleri için de
  değerli, gerçek bir referans olabilir.

### Kritik Bulgular / Önceki Planla Gerilim Yaratan Noktalar

1. **Mobilde edge-AI (on-device yolov8n ile "araç var mı" tespiti + WebSocket
   üzerinden kırpılmış ROI gönderimi) bu resmi dokümanda HİÇ geçmiyor.** Tarif
   edilen mobil sorumlulukları sadece: NV yap → QoD yap → Turkcell'in streaming
   sunucusuna bağlan → videoyu indir/stream et/kaydet → MP4 olarak dışa aktar →
   kendi backend'ine yükle. Mobilin kendi kamerasından "canlı trafik görüntüsü"
   çektiğine dair de bir ifade yok — tam tersine, mobilin bağlandığı video,
   **Turkcell'in streaming sunucusunda önceden hazırlanmış, iki çözünürlükte
   sunulan bir video** (Faz 2 videosuyla aynı kaynaktan üretilmiş). Bu, planın
   "Mimari Kararlar madde 6"sındaki (mobil edge model + ROI-crop + slalom bbox
   metadata + "QoD'yi anlamlı kılmak için edge tespiti şart" gerekçesi)
   **temelini sarsıyor** — QoD burada "araç tespit edilince" değil, **NV'den
   hemen sonra gelen sabit, koşulsuz bir sıra adımı** olarak tarif ediliyor.
   Edge-AI/WebSocket-ROI mimarisinin devam edip etmeyeceği netleşmeli (bkz.
   Açık Sorular).
2. **"Backend" ve "Yapay Zeka İmajı" diyagramda ayrı bileşenler.** Şekil 3'te
   video backend'den YZ imajına, results.json YZ imajından backend'e akıyor. Bu,
   mevcut kod tabanının (AI mantığı doğrudan backend süreci içinde,
   `CurrentModelService` olarak çalışıyor) mimarisiyle birebir örtüşmüyor
   olabilir — ayrı bir Docker image olarak paketlenmiş, "video ver → results.json
   al" arayüzüne sahip bağımsız bir YZ bileşeni gerekebilir. **İyi haber:** bu
   tam olarak FTR'de zaten teslim edilmiş olan `predict.py`/`main.py`'nin batch
   arayüzüyle (`video_path` al → JSON dön) örtüşüyor — yani incremental
   refactor'a rağmen, FTR'nin orijinal batch-görünümlü dış arayüzünün (video
   dosyası içeri, results.json dışarı) **ayrıca ayakta tutulması/korunması
   gerekebilir**, çünkü hem 4. adımdaki (video → backend → YZ imajı →
   results.json) canlı demo akışı hem de 5. adımdaki (3 video, hakem VM'inde
   batch inference) resmi değerlendirme akışı esasen "dosya ver, JSON al"
   şeklinde çalışıyor — WebSocket/canlı-akış değil.
3. **SHA256 + 7 Ağustos 21:00 kesim saati** — yeni, somut ve sert bir kısıt.
   Plan'a ve takvime (Gün 8-9) eklenmeli: image dondurma, hash alma, hash'i
   nereye/nasıl ibraz edeceğimiz netleşmeli (muhtemelen 3 Ağustos toplantısında
   veya sonraki dokümanlarda anlatılacak).
4. **"Final günü videosu"nun kaynağı belirsiz** — düşük/yüksek çözünürlüklü
   versiyonları hakemlerce yarışmacı VM'ine yükleniyor (madde 5), ama bu
   videonun nereden geldiği (organizasyon mu sağlıyor, yoksa takımın o gün
   çektiği/kaydettiği video mu işleniyor) bu dokümanda açık değil. Faz 2
   videosuyla aynı video mu, farklı bir final-günü-özel video mu belirsiz.
5. **Mobil adaptif bitrate/çözünürlük seçimi**, yeni ve somut bir mühendislik
   gereksinimi: QoD sonucuna göre doğru streaming URL'sini/çözünürlüğünü seçmek
   gerekiyor — mobil tarafın "sadece video kaydet" değil, ağ koşuluna duyarlı bir
   mantık da taşıması gerektiği anlamına geliyor.
6. **Number Verification burada "sessiz kimlik doğrulama arka planda" değil,
   mobil uygulamanın açıkça tamamlaması gereken görünür bir adım** gibi okunuyor
   ("Yarışmacı, mobil uygulamayı açacak ve Number Verification adımını
   tamamlayacak") — önceki plandaki "silent auth" varsayımının bununla tam
   örtüşüp örtüşmediği netleşmeli.

### Açık Sorular (Fable ile detaylı planlama öncesi netleşmesi gereken)
- Mobilde edge-AI/on-device tespit hâlâ gerekli mi, yoksa final senaryosu bunu
  büyük ölçüde gereksiz mi kılıyor? (bkz. Kritik Bulgular madde 1)
- QoD, "araç tespit edilince" tetiklenen bir event mi, yoksa NV'den hemen sonra
  gelen sabit bir adım mı — resmi senaryo ikincisini gösteriyor; mimari kararın
  buna göre revize edilip edilmeyeceği.
- Backend ile "Yapay Zeka İmajı" gerçekten iki ayrı Docker image/servis olarak mı
  paketlenecek, yoksa tek image içinde iki mantıksal bileşen olarak mı kalacak?
- "Final günü videosu" (düşük/yüksek çözünürlük) nereden geliyor — organizasyon
  mu sağlıyor, takım mı üretiyor?
- SHA256 / 7 Ağustos 21:00 kesim süreci pratikte nasıl işleyecek (ibraz
  mekanizması)?
- Sıradaki paylaşılacak dokümanlar (teknik gereksinimler, hazırlık adımları) bu
  soruların bir kısmını zaten cevaplıyor olabilir — kullanıcı sırayla paylaşacak.

## Open Gateway Demo — UX Akış Kılavuzu (2. paylaşılan doküman, 1 Ağustos 2026)

Turkcell'in yayınladığı bir "demo uygulaması" akışı — **bağlayıcı bir mimari değil,
açıkça bir referans/örnek** ("yarışmacılar bu sırayı referans alarak demoyu
çalıştırabilir ancak kendi akışlarını ve sistem mimarilerini kurgulamaları önemle
rica olunur"). Yine de somut API kullanım şekli ve olası bir "beklenen" backend↔AI
konteyner deseni açısından çok değerli ipuçları taşıyor.

Kullanılan API'ler: **Number Verification `/verify`**, **Quality-on-Demand `/sessions`**.
Akış: 01 Doğrula → 02 Oturum → 03 QoD Aç → 04 Video → 05 Yükle → 06 AI Sonucu → 07 Trace

### 01 — Numara Doğrulama
- Kullanıcı MSISDN girer, "Sign in"e basar. Doğrulama **SMS/OTP olmadan, mobil ağ
  üzerinden** (OIDC Authorization Code / 3-legged) yapılır — yani **görünür bir UI
  adımı var** (numara girişi + buton), ama arka planda kod girişi gerektirmeyen bir
  "sessiz" doğrulama. Önceki "tamamen sessiz/invisible auth" varsayımını netleştiriyor:
  UI'da görünür ama kullanıcıdan OTP istemiyor.
- Test MSISDN: `+905390000020` (muhtemelen sadece bu demo/sandbox'a özel).
- API: `POST /verify` → sonuç: `devicePhoneNumberVerified: true`.
- Auth-gate yalnızca `COMPLETED + verified` durumunda ana ekrana geçiyor.

### 02 — Doğrulanmış oturum
- Home ekranındaki "Session" kartı: **Verified rozeti, telefon numarası, Flow ID,
  Correlation ID.** Bu iki kimlik (Flow ID, Correlation ID) sonraki tüm adımları
  (QoD, yükleme, trace) aynı akışa bağlamak için kullanılıyor.

### 03 — QoD'yi aç
- QoD butonu, cihazın **tüm indirme trafiği için (`0.0.0.0/0`)** bir hızlandırma
  oturumu açıyor (belirli bir hedef IP/porta değil, cihaz geneline).
- API: `POST /sessions`, **profil: `teknofest2026`.**
- Kart, oturum kimliğini + `qosStatus: REQUESTED` + süreyi gösteriyor.

### 04 — Video başlat, kaliteyi izle
- Kaynak: **HLS (veya YouTube)** seçilip "Teknofest Start"a basılıyor.
- **Tek bir adaptif bitrate (ABR) HLS akışı** kullanılıyor — bant genişliğine göre
  kalite seçimini **standart ABR player mantığı** yapıyor: QoD açıkken throughput
  artıyor → video 1080p'ye çıkıyor; QoD kapalıyken 240p'ye düşüyor.
- **Bu, doküman 1'deki "Kritik Bulgular madde 5" (mobilin QoD sonucuna göre elle
  çözünürlük seçmesi gerekiyor) bulgusunu yumuşatıyor:** özel bir bant genişliği
  algılama/seçim mantığı yazmaya gerek olmayabilir — standart bir ABR-destekli HLS
  player (örn. `hls.js`, ExoPlayer, AVPlayer'ın native HLS desteği) bunu otomatik
  hallediyor gibi görünüyor. Yine de 5 dakikalık streaming süresi kısıtına (doküman 1)
  göre player'ın davranışının test edilmesi gerekir.

### 05 — Videoyu backend'e yükle (AI hattı)
- Video başladıktan sonra **"Upload Video to Backend"** butonu görünür (yalnızca HLS
  modunda + video başladıysa).
- İstemci, bant genişliğine göre seçilen HLS render'ını indirir, **multipart upload**
  ile backend'e yükler.
- **Backend, videoyu `video.mp4` olarak paylaşımlı bir klasöre yazıp AI konteynerini
  tetikliyor, hemen `202 Accepted` dönüyor** (senkron beklemiyor).
- **Bu, doküman 1'deki "Kritik Bulgular madde 2" (Backend ile "Yapay Zeka İmajı"
  gerçekten ayrı bileşenler mi) sorusuna somut bir referans cevap veriyor:** evet,
  ayrı bileşenler; aralarındaki arayüz **paylaşımlı dosya sistemi (shared
  volume/folder) + tetikleme** şeklinde, REST/HTTP çağrısı değil. Backend, AI
  konteynerinin işini bitirip bitirmediğini muhtemelen dosya sistemini
  gözlemleyerek (ör. `results.json` oluştu mu) anlıyor.

### 06 — AI sonucunu gör
- "AI Result" sekmesine girildiğinde `results.json` **otomatik çekiliyor (polling/fetch
  tabanlı, push değil)**.
- Durumlar: `PROCESSING` ("AI videoyu işliyor"), `DONE` (araç bilgisi: tip/plaka/renk/
  güven + tespit listesi + ham JSON), `FAILED` (hata mesajı).
- Sağ üstte "yenile" butonu (`ai-result-refresh`) ile tekrar sorgulanabiliyor.

### 07 — Trace
- Adım listesinde yer alıyor ama paylaşılan sayfalarda ayrı bir detay bölümü yok —
  muhtemelen her adımdaki "Connection logs" genişletilebilir kartları (doküman
  madde 01'de görülen) ile dağıtık şekilde temsil ediliyor. **Netleşmedi, açık soru
  olarak not düşüldü.**

### Doküman 1 ile ilişki / güçlenen bulgular
- Bu doküman, **doküman 1'in resmi final senaryosuyla aynı iskeleti** izliyor
  (Doğrula → QoD → Video/Stream → Yükle → AI Sonucu) ve **mobilde edge-AI/ROI
  kırpmadan hiç bahsetmiyor** — düz "videoyu indir/kaydet, olduğu gibi yükle,
  backend+AI işlesin" akışı gösteriyor. Bu, doküman 1 incelemesinde açık soru olarak
  bırakılan "mobil edge-AI hâlâ gerekli mi" sorusunu **daha da güçlü şekilde
  sorguluyor** — henüz karar verilmedi (kullanıcı tercihiyle sona bırakıldı) ama
  kanıt birikimi aynı yönü gösteriyor.
- **Backend ↔ AI konteyner arasındaki "paylaşımlı klasör + tetikleme + `202` async +
  `results.json` polling" deseni**, doküman 1'in belirsiz bıraktığı mimari ayrıntıya
  (madde 2) somut bir referans model sunuyor — nihai kararı Fable ile vereceğiz ama
  bu, güçlü bir varsayılan aday.

### Açık Sorular (bu dokümandan)
- ~~Flow ID / Correlation ID gerçek API gereksinimi mi?~~ **Kısmen cevaplandı
  (Doküman 4 — OpenAPI spec'leri + Postman koleksiyonu):** **Correlation ID** kısmı
  netleşti — bu, CAMARA spesifikasyonundaki gerçek, opsiyonel **`x-correlator`**
  header'ı (her iki API'de de tanımlı, `POST /verify` ve `POST /sessions`
  isteklerine eklenebilir, backend üretip taşıyabilir). **Flow ID** için netlik
  daha düşük ama güçlü bir aday var: Postman koleksiyonundaki `/oauth2/authorize`
  isteğinde bir `state=realState` parametresi geçiyor — OIDC'nin standart `state`
  parametresi (CSRF koruması + callback'i orijinal istekle eşleştirme amaçlı).
  Demo uygulamasının "Flow ID" dediği şey büyük olasılıkla bu `state` değeri ya da
  buna benzer bir OIDC akış tanımlayıcısı olabilir — kesin teyit yok ama makul bir
  varsayım.
- ~~`teknofest2026` QoD profili demo'ya mı özel?~~ **Cevaplandı/düzeltildi (Doküman
  4 — resmi OGW entegrasyon rehberi ve Postman koleksiyonu):** HAYIR, demo'ya özel
  değilmiş — `qosProfile: "teknofest2026"` ve test MSISDN `+905390000020`,
  Turkcell'in resmi entegrasyon dokümanında ve Postman koleksiyonunda da **birebir
  aynı değerlerle** geçiyor. Bunlar gerçek/standart sandbox değerleri (yarışma günü
  gerçek MSISDN'ler SIM kartlarla değişebilir ama `qosProfile` muhtemelen aynı
  kalacak) — önceki "muhtemelen demo'ya özel" tahmini yanlıştı, düzeltildi.
- "07 Trace" adımının içeriği bu PDF sayfalarında görünmüyor — sıradaki
  dokümanlarda ayrıca ele alınıyor mu, yoksa bu doküman burada mı bitiyor?

## Yarışmacı Platformu Operasyon Rehberi (3. paylaşılan doküman, 1 Ağustos 2026)

Hakem/değerlendirme platformunun (yarışmacıya tahsis edilen Google Cloud Ubuntu VM
+ üzerindeki Web UI) **fiili çalışma mekaniğini** anlatan, çok somut ve operasyonel
bir doküman. Önceki iki dokümandaki mimari belirsizliklerin bir kısmını doğrudan
çözüyor.

### 1. Sisteme Erişim
- **SSH:** `ssh u<Başvuru ID>@<VM_IP>` (örnek: `u4445555`). Kesin kullanıcı adı/IP
  ayrıca paylaşılacak.
- **Dosya aktarımı:** `scp dosya u...@VM_IP:~` veya `scp -r klasör u...@VM_IP:~`;
  alternatif olarak WinSCP/FileZilla (SFTP).
- **Web UI: `http://<VM_IP>`** (dikkat: tarayıcı otomatik `https://`ye
  yükseltirse elle `http://`ye geri döndürülmeli, yoksa bağlanmıyor).
- **KRİTİK KURAL (dokümanda vurgulanmış):** *"Web UI yerine komut satırı üzerinden
  yapılan gösterimler değerlendirmeye alınmayacaktır. Hakem heyeti Web UI yerine
  komut satırı üzerinden projeyi çalıştırmayacaktır."* Yani nihai değerlendirme
  **tamamen bu Web UI akışı üzerinden** yapılıyor — `docker run` ile elle
  çalıştırabilmemiz yeterli değil, imajın bu spesifik Web UI'dan sorunsuz
  çalıştığından emin olmalıyız.
- Takıma özel Kullanıcı Adı/Şifre ile bu Web UI'da ayrıca login yapılıyor
  ("TEKNOFEST-2026 Contestant workspace").

### 2. İmaj Yönetimi
- **Docker imaj isimleri MUTLAKA `teknofest-2026/` ile başlamalı** — aksi halde
  panelde (sağdaki "Docker – Images") hiç görünmüyor. (Örnek:
  `teknofest-2026/test_container:latest`.)
- İmajlar VM üzerinde (SSH ile erişilen "çalışma makinesi") oluşturulmalı/build
  edilmeli; "Docker – Images" panelinden boyut/tarih/hash görülebiliyor.

### 3. Proje Konfigürasyonu ve Çalıştırma
- Web UI'da "+Add project" ile bir proje oluşturuluyor (örnek: `TAKIM-123`); bu
  projenin sayfasında **Input Video**, **Image to Run**, **Executions** bölümleri var.
- **Girdi videosu iki şekilde seçilebiliyor:**
  1. **Hazır sistem videosu:** `TOGG_MOBESE_FULL.mp4` (268.8 MB) — **"yarışmacıların
     final etabına hazırlık sürecinde kullanabilecekleri"** diye açıkça belirtilmiş.
     **Bu, VM erişimi geldiği an gerçek platform üzerinde uçtan uca test
     yapabileceğimiz gerçek bir video demek — büyük fırsat, erken kullanılmalı.**
  2. **Yerel yükleme:** "Upload video" butonu, ya da dosyaları sunucuda
     `/data/common-inputs/` dizinine koyup dropdown'dan tekrar tekrar
     yüklemeden seçme.
- "Image to run" dropdown'undan imaj seçilip **Execute**'a basılıyor →
  onay kutusu **"...on the GPU!"** diyor — **çalıştırma platformunda GPU
  kullanıldığı teyit edildi** (yerel laptop'taki 6GB VRAM/CPU kısıtı,
  değerlendirme ortamı için geçerli değil).

### 4. Süreç İzleme ve Sonuç Doğrulama
- **"Live Output" penceresi**nde ilerleme (%) canlı izleniyor; başarı işareti:
  **`EXECUTION COMPLETED – status: SUCCESS`**.
- **KRİTİK — sabit dosya yolu sözleşmesi (dokümanda "ikinci faz standartlarına
  uygun" deniyor, yani FTR ile aynı):**
  - **Girdi: `/app/data/input/video.mp4`**
  - **Çıktı: `/app/data/output/results.json`**
- Her çalıştırma ("execution") kendi klasöründe log + `results.json` ile
  saklanıyor, "Executions" sekmesinden geçmiş çalıştırmalara bakılabiliyor.
- **Örnek `results.json` ekran görüntüsü, mevcut şemamızla (`schemas/detection.py`)
  birebir örtüşüyor:** `video_id`, `arac_bilgisi.{tip, plaka, renk,
  confidence_score}`, `tespitler[].{zaman_saniye, kategori, etiket,
  confidence_score}` — ör. `kategori: "sofor_eylemi"`, `etiket: "sigara_icme"`.
  **Bu güçlü bir doğrulama: FTR'den miras aldığımız JSON şeması hâlâ doğru hedef.**

### 5. Temizlik ve Kapanış
- Final teslimden önce **"Docker – Images" panelinde yalnızca TEK bir (nihai)
  imaj bırakılmalı**, tüm deneme/test imajları kalıcı silinmeli — aksi halde
  hakem heyeti hangi imajın nihai olduğunu ayırt edemez. **Gün 8-9 / yarışma
  günü kontrol listesine eklenmeli.**

### Kritik Bulgular / Önceki Dokümanlarla Bağlantı

1. **Bu doküman, "Yapay Zeka İmajı"nın tam teknik sözleşmesini netleştiriyor:**
   sabit yol (`/app/data/input/video.mp4` → `/app/data/output/results.json`),
   GPU'lu çalıştırma, `EXECUTION COMPLETED` başarı sinyali. Bu sözleşme **FTR'nin
   zaten sahip olduğu batch arayüzle (`predict.py`/`main.py`: video yolu al → JSON
   dön) doğrudan örtüşüyor** — yani FTR'nin orijinal, tek-seferlik/batch
   çalışan giriş noktasının (mevcut incremental/streaming backend'den **ayrı,
   bağımsız bir CLI-tarzı entrypoint** olarak) korunması/yeniden kurulması
   gerekecek gibi duruyor. Şu anki kod tabanında bu tam olarak bu şekilde (sabit
   path okuyup yazan, bağımsız çalışan bir script/entrypoint olarak) mevcut
   değil — bu bir **spesifikasyon/implementasyon işi**, sona bırakıldı, ama
   önemli bir açık iş kalemi olarak not düşülüyor.
2. **İki ayrı çalıştırma yolu olabileceği ihtimali güçlendi:**
   - **(a) Canlı demo yolu** (Doküman 1 madde 4, Doküman 2'nin tüm akışı):
     mobil → **takımın kendi backend'i** → (takımın kendi kurgulayacağı bir
     tetikleme mekanizması, Doküman 2'de örneklenen "paylaşımlı klasör" gibi)
     → YZ imajı → results.json → backend → mobil.
   - **(b) Hakem batch-değerlendirme yolu** (Doküman 1 madde 5, bu doküman):
     hakem, bu **Web UI**'dan videoyu seçip Execute'a basıyor — **YZ imajını
     doğrudan bu platform çalıştırıyor**, takımın backend'i araya girmiyor.
   - **Sonuç: aynı tek Docker image (tek SHA256), hem takımın kendi backend'i
     tarafından hem de bu bağımsız Web UI tarafından, İKİSİNDE DE aynı sabit
     path sözleşmesiyle çalışabilmeli.** Bu, imajın entrypoint tasarımı için
     bağlayıcı bir kısıt.
3. **"Backend" bu dokümanda hiç geçmiyor** — doküman yalnızca "video ver →
   results.json al" yapan tek tip bir Docker imajından bahsediyor. Bu, bu Web
   UI panelinin **özellikle "Yapay Zeka İmajı" için** olduğu, mobil-yüzlü
   "Backend" bileşeninin bu panelin kapsamı dışında (muhtemelen aynı VM'de ama
   ayrı şekilde) çalıştığı yorumunu güçlendiriyor — ama teyit edilmedi.

### Açık Sorular
- ~~VM erişim bilgileri elimize geçti mi?~~ **Cevaplandı (1 Ağustos):** VM
  erişim bilgileri (kullanıcı adı, VM_IP, Web UI şifresi) **geldi, ama henüz
  denenmedi.** `TOGG_MOBESE_FULL.mp4` ile gerçek platformda erken bir uçtan uca
  deneme (mevcut Docker image'ımızla) artık hemen yapılabilir durumda — 7
  Ağustos 21:00 kesim saatinden önce sürprizleri erken yakalamak için değerli;
  ne zaman yapılacağı henüz planlanmadı (Fable ile planlama aşamasına
  bırakılabilir ya da öncesinde bağımsız bir doğrulama adımı olarak yapılabilir).
- "Backend" ile "Yapay Zeka İmajı" gerçekten bu panelde ayrı mı yönetiliyor,
  yoksa ikisi de aynı imajın parçası olup farklı "mod"larla mı (ör. ortam
  değişkeni/entrypoint argümanıyla) çalıştırılacak? Sıradaki dokümanlar
  (teknik gereksinimler) bunu netleştirebilir.

## Turkcell Open Gateway — Resmi API Spesifikasyonları ve Entegrasyon Rehberi (4. paylaşılan doküman seti, 1 Ağustos 2026)

Bu sette dört parça var: `number-verification.yaml` (OpenAPI), `quality-on-demand.yaml`
(OpenAPI), `OGW_Teknofest.pdf` (Turkcell'in adım adım entegrasyon akışı — team'in
kendi backend'inin gerçek Open Gateway'i nasıl çağıracağının **doğrudan uygulama
şeması**), ve resmi bir Postman koleksiyonu. Bunlar `network/turkcell_client.py`
(şu an iskelet halinde, yarışma günü doldurulacak) için **hazır bir implementasyon
reçetesi** niteliğinde.

### Number Verification (`/verify`) — teknik özet
- **3-legged OIDC Authorization Code Flow**, `prompt=none` ile kullanıcı
  etkileşimsiz (arka planda, hücresel ağ üzerinden) doğrulama.
- `POST /number-verification/v1/verify` — body: `phoneNumber` (E.164, `+` ile,
  regex `^\+[1-9][0-9]{4,14}$`) **veya** `hashedPhoneNumber` (SHA-256 hex) —
  ikisinden sadece biri.
- Yanıt: `{ devicePhoneNumberVerified: true/false }`.
- Opsiyonel `x-correlator` header'ı (bkz. yukarıdaki Correlation ID çözümü).
- **403 hata kodu `NUMBER_VERIFICATION.USER_NOT_AUTHENTICATED_BY_MOBILE_NETWORK`
  özellikle önemli**: kullanıcı hücresel veri yerine WiFi üzerindeyse doğrulama
  başarısız olur — demo sırasında telefonun **mobil veri/hücresel ağda** olduğundan
  emin olunmalı, WiFi kapalı tutulmalı.
- Base URL: `https://opengateway.turkcell.com.tr`.

### Quality-on-Demand (`/sessions`) — teknik özet
- `POST /quality-on-demand/v1/sessions` — body: `applicationServer.ipv4Address`,
  `qosProfile`, `duration` zorunlu; **3-legged token kullanılırken `device` alanı
  KESİNLİKLE gönderilmemeli** (gönderilirse `422 UNNECESSARY_IDENTIFIER` hatası —
  NV adımından sonra elde edilen token zaten cihazı örtük olarak tanımlıyor).
- **KRİTİK — QoD ASENKRON çalışıyor:** `201 Created` yanıtı `qosStatus: REQUESTED`
  döner — bu, **QoD'nin aktif olduğu anlamına gelmiyor**, sadece talebin kabul
  edildiği anlamına geliyor. Asıl durum değişikliği (`AVAILABLE` ya da
  `UNAVAILABLE`) ya bir webhook'la (`sink` parametresi + CloudEvents
  `QOS_STATUS_CHANGED` bildirimi) ya da polling ile öğreniliyor. **Doküman
  1'deki "QoD başarılı/başarısız" puanlama kuralının, bu asenkron gerçekliğe göre
  nasıl yorumlanacağı netleşmeli** — `201` almak "başarı" sayılıyor mu, yoksa
  `AVAILABLE` durumunu beklemek mi gerekiyor?
- **409 Conflict**: aynı cihaz için zaten aktif bir oturum varsa yeni oturum
  açılamaz — eski oturum silinmeli/bitmesi beklenmeli. Demo sırasında tekrar
  deneme mantığı bunu hesaba katmalı.
- `applicationServer.ipv4Address` sabit `"0.0.0.0/0"`, `qosProfile` sabit
  `"teknofest2026"` — **resmi olarak doğrulandı** (bkz. yukarıdaki düzeltme).

### OGW_Teknofest.pdf — Backend'in gerçek entegrasyon akışı (uygulama şeması)
Bu, `turkcell_client.py`'nin gerçek implementasyonu için **hazır bir tarif**:

1. Mobil → **kendi backend'imiz**: `POST /your_number_verification_endpoint {phoneNumber}`.
2. Backend → Mobil: `302` ile Open Gateway'in `/oauth2/authorize` adresine
   yönlendirme bilgisi (response_type=code, client_id, **hem NV hem QoD scope'u
   birlikte**, redirect_uri).
3. Mobil (hücresel ağ üzerinden) → Open Gateway `/oauth2/authorize` (GET).
4. Open Gateway → Backend'in `redirect_uri`'sine `302` + `code=operator_auth_code`.
5. Mobil bu yönlendirmeyi takip edip `code`'u backend'e ulaştırır.
6. Backend → Open Gateway: `POST /oauth2/token` — **`client_id:client_secret`
   Base64 kodlanıp `Authorization: Basic ...` header'ına konur** (HTTP Basic
   Auth, query param değil), body: `grant_type=authorization_code`, `code`,
   `redirect_uri`.
7. Open Gateway → Backend: `200 OK` ile `access_token` + `id_token` +
   **`expires_in=300` (yalnızca 5 dakika!)**.
8. Backend → Open Gateway: `POST /number-verification/v1/verify` (Bearer token).
9. Backend, sonucu mobile iletir; login kabul/red.
10. (QoD) Mobil → Backend: `POST /your_qod_endpoint {duration}`.
11. Backend: **access_token hâlâ geçerliyse aynen kullanılır** (5 dk sınırı
    nedeniyle sık sık yenileme gerekebilir), değilse 2-7 arası adımlar tekrarlanır.
    Ardından `POST /quality-on-demand/v1/sessions`.

**Önemli implementasyon notları:**
- **`scope`, `/authorize` isteğinde HEM NV HEM QoD için birlikte istenmeli**:
  `openid dpv:RequestedServiceProvision#quality-on-demand:sessions:create
  dpv:FraudPreventionAndDetection#number-verification:verify` — böylece NV
  sırasında alınan tek `access_token`, (5 dk içinde) QoD için de yeniden
  kullanılabilir.
- **`client_id`/`client_secret` yalnızca backend'de saklanmalı, asla mobil
  uygulamaya gömülmemeli** (güvenlik gereği, dokümanda açıkça belirtilmiş).
- Gerçek endpoint yolları (Postman'dan, PDF diyagramındaki sadeleştirilmiş
  isimlerden daha kesin): `/oauth2/authorize`, `/oauth2/token`,
  `/number-verification/v1/verify`, `/quality-on-demand/v1/sessions`.
- `redirect_uri` örneği düz `http://` (https değil) — VM Web UI'daki
  "https'yi elle http'ye çevir" garipliğiyle tutarlı bir örüntü, bu ortamda.

### Postman Koleksiyonu
Takıma özel `client_id`/`client_secret`/`api-gateway-url` geldiğinde, **hiç kod
yazmadan gerçek Open Gateway akışını uçtan uca test edebileceğimiz hazır bir test
seti.** Test MSISDN (`+905390000020`) burada da aynı — takım-genelinde ortak bir
sandbox numarası olduğu iyice teyitlendi.

## Faz 2 Ground Truth (`faz2_gt.json`) İncelendi — Kritik Bulgu

Kullanıcı, daha önce doküman 1'de bahsi geçen Faz 2 test videosunun (HLS,
`.../faz2/faz2.smil/playlist.m3u8`, ~2 dakika) **ground truth JSON'ını** paylaştı.
Yapı, mevcut şemamızla birebir örtüşüyor (üçüncü kez doğrulandı — doküman 3'teki
örnek ekran görüntüsü ve mevcut `schemas/detection.py` ile de tutarlı).

**🔴 KRİTİK BULGU — mevcut kodla doğrulanmış, somut bir uyumsuzluk:**

Ground truth'ta **aynı etiket, video boyunca defalarca, farklı zamanlarda**
tekrar ediyor — bu tesadüf değil, doküman 1'in "olaylar görülebilir oldukları
anda işaretlenmiştir" notuyla tutarlı bir tasarım. Örnekler (111 saniyelik
videoda): `arka_koltuk_2` **12 kez** (6.04sn'den 111.5sn'ye kadar yayılı),
`emniyet_kemeri_ihlali` 4 kez, `teknocan` 4 kez, `sigara_icme` 3 kez, `su_icme`
ve `telefonla_konusma` 2'şer kez.

Bunu mevcut kodla karşılaştırmak için `event_gate.py` ve `thresholds.py`'yi
okudum:

- **`backend/app/services/vehicle_ai/streaming/event_gate.py:28`** —
  `EventGate.__init__`'de `etiket_basina_max_olay: int = 1` **varsayılan değer** —
  yani şu anki mantık, **bir oturum boyunca her etiketi en fazla BİR KEZ**
  yayınlıyor (`_admit`, satır 79-80: `self._yayin_sayisi.get(...) >= self._max_olay`
  → ikinci ve sonraki tüm oluşumlar sessizce düşürülüyor).
- Bu değer **`thresholds.py`'deki `DetectionThresholds`'da hiç yok** —
  yapılandırılabilir değil, kodda sabit — Mimari Kararlar madde 8'in ("tespit
  başına eşikler yapılandırılabilir olmalı, sabit kodlanmamalı") kapsamı dışında
  kalmış bir alan.
- `test_service_pipeline.py`'deki `test_ayni_etiket_yalnizca_bir_kez_yayinlanir`
  testi bunu doğrudan doğruluyor ve docstring'inde **"FTR çıktı kuralı"** olarak
  gerekçelendiriyor — yani bu kasıtlı bir tasarım kararıydı, kazara değil, ama
  **Faz 2 ground truth'u ile açıkça çelişiyor.**
- Ek gözlem: `cooldown_saniye=3.0` eşiği var (aynı etiketin 3sn içindeki
  tekrarlarını bastırmak için) — ama `max_olay=1` ile bu eşik **anlamsız
  hale geliyor**: ilk yayından sonra cooldown süresi geçse bile ikinci
  oluşum zaten `max_olay` kontrolünde eleniyor. Bu, `cooldown`'ın "aynı
  tespidin gürültüsünü bastır ama farklı zamanlardaki tekrar tekrar
  görünmeleri kabul et" amacıyla tasarlandığını, `max_olay=1`'in ise bunun
  üzerine sonradan (muhtemelen yanlışlıkla ya da farklı bir senaryo için)
  eklenmiş bir kısıt olduğunu düşündürüyor.

**Sonuç:** Şu anki haliyle backend, Faz 2 videosunu işlese, ground truth'un
büyük çoğunluğunu (`arka_koltuk_2`'nin 11/12'si, `emniyet_kemeri_ihlali`'nin
3/4'ü, vb.) **sessizce kaybeder** — otomatik puanlama scripti ground truth ile
birebir eşleşme/örtüşme arıyorsa bu ciddi puan kaybı demektir. **Bu, implementasyon
işi olduğu için düzeltmeyi şimdi yapmıyorum** (spesifikasyon/kod değişikliği
kullanıcının isteğiyle sona/Fable'a bırakıldı) — ama bu, şu ana kadar bulunan
bulgular arasında **en somut, en yüksek öncelikli, en az tartışmaya açık** olanı:
bir mimari tercih sorunu değil, ground truth karşısında doğrulanmış bir mantık
hatası. Fable ile planlama başladığında ilk ele alınacaklar arasında olmalı.

## 📋 3 Ağustos Toplantısında Sorulacaklar — TEK LİSTE (1 Ağustos, gözden geçirildi)

> **GÜNCELLEME (3 Ağustos, toplantı + ikinci tur netleştirme sonrası):** Bu
> toplantı fiilen oldu, kullanıcı çıktılarını aktardı ve kalan açık sorular
> ikinci bir turda tek tek netleştirildi (bkz. dokümanın en üstündeki
> "🆕 EN GÜNCEL DURUM" bölümü). Madde 1 ✅, madde 2 artık mekanizma olarak ✅
> (kaynağın tam kimliği hâlâ belirsiz ama bu artık aksiyon gerektirmiyor).
> Sadece madde 3 (SHA256 ibraz mekanizması) hâlâ tam açık.

Tasarım turu (H, I, J, K bölümleri) tamamlandıktan sonra kalan tüm açık sorular
tek tek gözden geçirildi. Elimizdeki dokümanlarla **daha fazla ilerletilemeyen,
yalnızca organizasyondan gelecek bilgiyle çözülebilecek** maddeler şunlardı:

1. ~~**Paketleme (S2):** Backend'i ayrı bir Docker image olarak mı çalıştırmamız
   bekleniyor, yoksa tek imaj + iki komut mu kabul edilir?~~ **✅ ÇÖZÜLDÜ (3
   Ağustos) — bkz. "🆕 EN GÜNCEL DURUM" bölümü.** Backend ayrı olabilir.
2. ~~**"Final günü videosu" nereden geliyor?**~~ **✅ Mekanizma netleşti:**
   organizasyon/Turkcell tarafından streaming API üzerinden sunulacak (Open
   Gateway Demo UX Kılavuzu adım 04 ile aynı desen), biz MP4'e çevirip
   yüklüyoruz — video prodüksiyonu yapmamıza gerek yok. Ayrıca yeni bulgu:
   asıl risk parlak ışık/yansıma, karanlık değil (bkz. üstteki bölüm).
3. **[HÂLÂ AÇIK] SHA256 ibraz mekanizması nedir?** Parmak izi nereye/nasıl
   teslim edilecek — dokümanlarda bulunamadı, kullanıcı kararıyla daha fazla
   aranmayacak, yeni bilgi gelirse kapanır.

**Kapanmış, tekrar sorulmayacak:**
- "07 Trace" (Doküman 2) — kullanıcı: önemli değil, kodlama sırasında hallederiz.
- Lifebox mekanizması — Turkcell'in gerçek tüketici bulut depolama servisi
  olduğu netleşti (mylifebox.com), muhtemelen manuel yükleme adımı, API
  entegrasyonu gerekmeyebilir (bkz. üstteki bölüm ve Bölüm J).
- Canlı önizleme katmanının (WebSocket/mobil edge) P3'te kalması — G1 kararı ve
  öncelik sıralaması (Bölüm D) zaten netleştirdi, sadece kaynak/zaman meselesi.

## Context

Takım (VST T1, Teknofest "5G & Yapay Zekâ ile Akıllı Yol Güvenliği Yarışması")
ÖTR ve FTR aşamalarını tamamladı. **Final Yarışma Etabı 7-9 Ağustos 2026'da
yüz yüze** yapılacak (bugün 3 Ağustos 2026).

**Puanlama geçmişi (neden bu plan kod kalitesini önceliklendiriyor):** ÖTR'den
100 üzerinden 92 alındı (mimari "çok özgün, çok güzel" bulundu); FTR'den 200
üzerinden 109 alındı — bunun 90/100'ü rapor puanıyken, sadece **19/100'ü kod
puanıydı**. Yani takımın güçlü yanı tasarım/mimari fikirleri, zayıf yanı
bunları sağlam ve çalışan koda dökmek. **Final planı bilinçli olarak kod
kalitesini ve gerçekten uçtan uca çalışırlığı önceliklendiriyor.**

**Final için 10 dakikalık bir sunum yapılacak** — "En İyi Mimari" ve "En İyi
Sunum" gibi ayrı ödül kategorileri de var. Mimarinin sadece çalışması değil,
**anlatılabilir/gerekçelendirilebilir** olması da değerli — kod, "neden bu
şekilde" sorusuna net cevap verecek şekilde tutulmalı.

**Mobil platform: Flutter.** Gerekçe: iki platforma (Android+iOS) birden
çıkabilme + ekibin hazırlığı. **Mobil implementasyonu artık bir takım
arkadaşına devredildi** (bkz. "🆕 EN GÜNCEL DURUM" bölümü) — bu plandaki
H/I/J bölümleri, o implementasyonun uyması gereken sözleşmeyi tanımlıyor.

**Model envanteri:** `yolov8n.pt`, `yolov8s.pt`, `yolov8n-pose.pt`,
`yolov8s-cls.pt`, `kasa_modeli.pt`, `renk_modeli.pt`, `plaka_modeli.pt`,
`karakter_modeli.pt`, `kemer_v3.pt`, `sigara_v1.pt`, `su_v2.pt`,
`telefon_temiz_v1.pt`, `teknocan.pt`, `slalom_lstm.pt`,
`face_landmarker.task` (MediaPipe). Doğrulukları hâlâ şüpheli/doğrulanmamış
(organizasyon eğitim veri seti sağlamadı, takım kendi veri setini oluşturmak
zorunda kaldı) ama envanter belli — hangi modelin hangi çıktıyı ürettiği
Bölüm G0'da tam tablo hâlinde var. `yolov8n.pt` ve `yolov8s-cls.pt` artık
ölü ağırlık (bkz. G0 — mobil edge modeli kalktığı, sınıflandırıcı da hiç
kullanılmadığı için).

**Yerel geliştirme donanımı:** 6 GB VRAM, i7 10. nesil, 32 GB RAM'li laptop —
listedeki modeller (hepsi nano/small ölçekli) için yeterli; değerlendirme
sunucusundaki GPU'nun (Doküman 3'te teyitli) hızını yakalamayı beklemeyin
ama geliştirme için sorun değil.

**Amaç:** Gerçek 5G API'leri (NV/QoD) ve VM detayları geldiğinde koda
dokunmadan/minimum dokunuşla yerine oturacak, **uçtan uca çalışan** bir
sistem kurmak — güncel ve kesinleşmiş tasarım "🔴 FİNAL-UYUMLU HEDEF MİMARİ"
bölümünde.

## Mimari Kararlar

> Bu bölüm, eski ÖTR mimarisinin (mobil edge-AI + WebSocket-ROI + event-driven
> QoD tetikleme) tamamen terk edildiği 3 Ağustos toplantısı sonrası temizlendi
> — sadece hâlâ geçerli kararlar kaldı. Silinen eski kararlar/gerekçeler için
> git geçmişine bakılabilir, dokümanda tutulmuyor (kafa karışıklığı yaratıyordu).

1. **FastAPI (backend) + Flutter (mobile)** — onaylandı, değişmiyor. Gerekçe:
   iki platforma birden çıkabilme değeri + ekip hazırlığı. Native Swift/iOS,
   Flutter'da ciddi bir tıkanma çıkarsa devreye girecek belgelenmiş bir yedek plan.
2. **Değişken/dış bağımlılıklar arayüz (interface) arkasına alınır, Dependency
   Injection ile enjekte edilir:**
   - `VehicleAnalysisService` (Protocol/ABC) — modelleri saran implementasyon;
     modeller güncellendiğinde sadece bu implementasyon değişir.
   - `OpenGatewayClient` (Protocol/ABC) — `MockOpenGatewayClient` (yarışma günü
     öncesi) ve `TurkcellOpenGatewayClient` (yarışma günü) aynı arayüzü uygular.
     Hangisinin kullanılacağı `USE_MOCK_5G` ortam değişkeniyle seçilir.
     **Anti-cheat hatırlatması:** canlı demoda gerçek 5G çağrısı başarısız
     olursa sessizce mock'a düşen bir "güvenlik ağı" KESİNLİKLE olmamalı —
     jüri önünde sahte sonuç üretmek gibi algılanabilir.
   - Deploy hedefi tamamen ortam değişkenleriyle yönetilir.
3. **Docker'dan başlanır** — AI imajının Dockerfile'ı erken yazılır; VM bilgisi
   geldiğinde aynı imaj doğrudan deploy edilebilir.
4. **Backend'deki alt modeller (plaka, renk, kasa tipi, sürücü eylemi, vb.)
   hangileri paralel hangileri sıralı çalıştırılmalı** — ampirik olarak
   ölçülecek (10 dakikalık zaman bütçesi kısıtı, bkz. A7).
5. **Tespit başına doğrulama/oylama eşikleri (temporal voting thresholds)
   yapılandırılabilir olmalı, sabit kodlanmamalı** — `thresholds.py`'de zaten
   config'te, Faz 2 ground truth ile ölçülerek ayarlanacak (bkz. Bölüm E).
   Organizasyon eğitim verisi sağlamadığından model kalitesi doğası gereği
   sınırlı — bu eşikleme/oylama mantığı, modelin yetersiz kaldığı yeri backend
   tarafının telafi ettiği kısım.
6. **Streaming dedektörlerinin (cooldown, temporal voting, event gate) kare
   kaynağından bağımsız tasarlanmış olması** — bu mantık hem canlı bir
   akıştan hem de bir video dosyasını sırayla okumaktan aynı şekilde
   beslenebiliyor (bkz. Bölüm B). Gün 4-7'de yapılan incremental refactor,
   mimarinin "AI imajı = batch programı" olarak netleşmesinden sonra da
   **değerini koruyor** — tek değişen, kare kaynağının WebSocket değil
   `cv2.VideoCapture` olması (bkz. Bölüm K).

## Repo Yapısı (nihai — 3 Ağustos'ta ai/backend/mobile olarak ayrıştırıldı)

```
ai/                      # Hakemin test ettiği, tek başına build edilen imaj
  Dockerfile             # nvidia/cuda base, ağır bağımlılıklar (ultralytics, opencv, mediapipe, torch)
  requirements.txt
  batch_main.py          # entrypoint: /app/data/input/video.mp4 → /app/data/output/results.json (bkz. Bölüm K)
  current_model_service.py, model_registry.py, vision_ops.py, thresholds.py
  streaming/              # event_gate.py, run_detectors.py — kare kaynağından bağımsız (bkz. Bölüm B)
  schemas/detection.py    # results.json şeması (Pydantic)
  _ftr_reference/         # salt-okunur referans, değiştirilmiyor
  weights/                # tüm .pt dosyaları + face_landmarker.task (backend/weights/'ten taşındı)

backend/                 # API yöneticisi — hafif, GPU/torch bağımlılığı yok
  app/
    main.py
    core/config.py       # USE_MOCK_5G, TURKCELL_*, job storage path
    api/
      routes_auth.py     # NV: /api/auth/login, /callback, /status/{flow_id} (Bölüm H)
      routes_qod.py       # /api/qod/start (Bölüm I)
      routes_videos.py    # /api/videos/upload, /{job_id}/result (Bölüm J) — AI imajı burada docker run ile tetiklenir
      routes_health.py
    services/
      network/
        interface.py, mock_client.py, turkcell_client.py
  requirements.txt        # fastapi, uvicorn, httpx — torch/ultralytics YOK
  (Dockerfile opsiyonel — ya da VM'de düz process, bkz. S2/G3 çözümü)

mobile/                   # Flutter — bir takım arkadaşına devredildi, bu repoda ayrı ilerliyor
  (NV WebView akışı, QoD tetikleme, HLS indirme+upload, sonuç ekranı — Bölüm H/I/J)

docs/
  integration-notes.md    # entegrasyon sırasında çıkan kütüphane/sürüm sorunları
```

Mevcut kod (`backend/app/services/vehicle_ai/*` + `backend/weights/`) bu yeni
yapıya taşınırken `ai/` klasörüne geçecek — mantık değişmiyor, sadece konum.
**`backend/`, artık AI koduyla Python seviyesinde hiç konuşmuyor**: sadece
`docker run` ile tetikliyor ve `/app/data/output/results.json` dosyasının
oluşmasını bekliyor (dosya sistemi üzerinden haberleşme, bkz. "🆕 EN GÜNCEL
DURUM" bölümündeki S2/G3 çözümü).

## Risk Kaydı

- **5G API'leri canlı ortamda hiç test edilmedi** → gerçek entegrasyon akışı
  dokümanlarla netleşti (bkz. Bölüm H/I) ama ilk gerçek deneme muhtemelen
  Cuma (7 Ağustos) test ortamında ya da yarışma günü olacak; sürpriz payı
  bırakın.
- **Model kalitesi doğası gereği sınırlı** (organizasyon eğitim verisi
  sağlamadı) → tespit başına yapılandırılabilir oylama eşikleriyle
  (Mimari Kararlar madde 5) ve Faz 2 ground truth ile ölçülerek (Bölüm E)
  telafi ediliyor.
- **`etiket_basina_max_olay=1` düzeltmesi henüz kodlanmadı** (A6) → ground
  truth ile doğrulanmış, yüksek öncelikli, tartışmaya açık değil.
- **Paralel/sıralı model dağılımı henüz belirsiz** → ölçülerek çözülecek
  (Mimari Kararlar madde 4).
- **10 dakikalık inference bütçesi ölçülmedi** (A7) → stride stratejisi
  gerçek donanımda test edilmeli.
- **Test ortamı ile dondurma tarihinin aynı güne (7 Ağustos) denk gelmesi**
  → zaman baskısı yüksek, o güne kadar yerelde mümkün olduğunca çok şey
  doğrulanmış olmalı (bkz. "🆕 EN GÜNCEL DURUM").

## Doğrulama Planı

- `OpenGatewayClient` için hem mock hem gerçek implementasyonun aynı
  arayüzü sağladığını gösteren birim testler.
- AI imajının çıktısının resmi JSON şemasıyla (`schemas/detection.py`)
  birebir eşleştiğini doğrulayan bir şema testi.
- VM'de gerçek Web UI üzerinden `TOGG_MOBESE_FULL.mp4` ile uçtan uca
  "Execute" testi (bkz. Yarışmacı Platformu Operasyon Rehberi bölümü) —
  mümkün olduğunca erken yapılmalı.
- Faz 2 videosu + `faz2_gt.json` ile AI çıktısının ölçülmesi (bkz. Bölüm E)
  — eşik ayarının veri temelli yapılması için.
- Gerçek telefonda NV → QoD → stream indirme → upload → sonuç ekranı
  akışının uçtan uca denenmesi (emülatör yeterli değil — hücresel ağ/SIM
  gerekiyor).
- Yarışmadan önce en az bir tam "kuru prova" (dry run): NV açılışından
  `results.json` gösterimine kadar tüm akış.
- Paralel/sıralı model dağılımı deneyinin sonuçları `docs/integration-notes.md`'e
  kaydedilir.
