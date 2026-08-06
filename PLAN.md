# VST T1 — Akıllı Yol Güvenliği: Final Yarışma Entegrasyon Planı

> **Son güncelleme:** 4 Ağustos 2026. Bu doküman, 30 Temmuz'da yazılan ve
> **terk edilmiş** bir mimariyi (mobil edge-AI + WebSocket) anlatan önceki
> sürümün yerine geçer. O mimariden kodda da dokümanda da hiçbir iz
> bırakılmadı — bkz. aşağıdaki "Neden Mimari Değişti" bölümü.

## Özet (TL;DR)

- **Ne yapıyoruz:** 3 Ağustos'ta organizasyondan gelen 9 resmi doküman
  (Final Yarışma Senaryosu, FTR teslim dokümanı, Turkcell Open Gateway
  OpenAPI spesifikasyonları, OGW entegrasyon akışı, UX kılavuzu, Postman
  koleksiyonu, Operasyon Rehberi, Faz 2 ground truth) doğrultusunda
  **backend'i sıfırdan, mobili takım arkadaşımızın yazdığı Flutter
  uygulamasıyla, AI'yı takım arkadaşımızın geliştirdiği pipeline'la**
  birleştirip 7-9 Ağustos'taki final için çalışan bir sisteme dönüştürüyoruz.
- **Mimari (özet):** Flutter mobil → FastAPI backend (Number Verification →
  Quality on Demand → video upload) → backend'in tetiklediği ayrı bir Docker
  imajı (`ai/`, hakemin de bağımsız olarak çalıştıracağı imajın ta kendisi) →
  sonuç JSON'ı mobile geri döner. **Mobilde hiçbir AI/model işi yok** —
  yalnızca orkestrasyon ve arayüz.
- **Şu anki durum (6 Ağustos akşamı):** Backend ↔ mobil zinciri gerçek HTTP
  ile uçtan uca doğrulandı (üç kez: yerelde, VM'de bare process olarak, VM'de
  container olarak — hepsi birebir aynı sonuç). Backend artık VM'de kendi
  Docker container'ı olarak çalışıyor, `--restart unless-stopped` ile
  çökme/reboot sonrası kendiliğinden ayağa kalkıyor (gerçek çökme simüle
  edilerek doğrulandı). AI imajında **4K diye bir varyant yok** — gerçek
  stream 1080p/240p'den ibaret, 1080p ölçümü (436 sn) rahat pay bırakıyor.
  Web UI'a giriş sağlandı (SSH ile aynı kimlik bilgisi işe yaradı) — Execute
  testi (Faz C madde 4) henüz koşulmadı ama artık engel yok. Bugün ayrıca
  organizasyonla 3 Ağustos Q&A toplantısının 27 sorusu tek tek işlendi (bkz.
  aşağıdaki bölüm) ve bu sırada mobilde iki gerçek açık bulunup düzeltildi:
  Lifebox'a giden videonun zip'lenmeden gitmesi (**diskalifiye riski**
  taşıyordu) ve HLS kaydının ağ koşulundan bağımsız her zaman en yüksek
  varyantı seçmesi (şartname 4.2 ihlali). Açık kalanlar: **Turkcell
  `client_id`/`secret` hâlâ gelmedi** (organizasyonun söz verdiği tarihten
  2 gün geçti, 7 Ağustos 21:00 teslime 1 gün kaldı) ve **hakemin Web UI'dan
  Execute testi henüz yapılmadı**.
- **Neden bu şekilde:** ÖTR'de mimari 92/100 ile övüldü, FTR'de rapor
  90/100 ama kod sadece 19/100 aldı — yani ekibin güçlü yanı tasarım, zayıf
  yanı kodu sağlam ve *gerçekten çalışır* halde teslim etmek. Bu plan
  bilinçli olarak "iddialı ama test edilmemiş mimari" yerine "sınırlı ama
  uçtan uca kanıtlanmış çalışırlık"ı önceliklendiriyor.

## Neden Mimari Değişti

Bu depo başlangıçta ÖTR'nin (Ön Tasarım Raporu) önerdiği mimariyi
sürdürüyordu: Flutter mobilde edge YOLOv8 ile araç tespiti → WebSocket
üzerinden kırpılmış ROI'nin backend'e akıtılması → backend'de tam analiz.
**3 Ağustos 2026'da organizasyondan gelen 9 resmi doküman bu senaryoyu
tamamen geçersiz kıldı**: final günü akışı, mobilin **Number Verification →
Quality on Demand → tüm videoyu Turkcell stream'inden indirip MP4 olarak
backend'e yüklemesi → backend'in ayrı bir Docker imajını (hakemin de
bağımsız çalıştıracağı imaj) tetikleyip sonucu alması** şeklinde, resmi ve
bağlayıcı olarak tarif ediyor. Mobilde hiçbir AI/model işi, WebSocket akışı
veya edge tespiti yok.

Sonuç: backend, mobil kodu, ve (o zaman ayrı dosyalar olan)
`docs/mobile-integration.md` / `docs/ai-integration.md` sözleşme
dokümanları o gün sıfırdan, bu resmi sözleşmeye göre yeniden yazıldı. Eski
mimariden (`routes_inference.py`, `/ws/stream`, `mobile_contract.py`, mock
ROI fixture'ları, `VehicleAnalysisService` arayüzü) kodda ve dokümanlarda
hiçbir iz kalmadı. Bu iki sözleşme dokümanı da kendisi 6 Ağustos'ta
kaldırıldı — kod ve testler zaten sözleşmeyi kanıtladığı için ayrı, kolayca
eskiyen bir doküman kopyası tutmanın faydası kalmadı (bkz. Bilinen Riskler).

**Tek istisna (geçiciydi):** `predict.py`/`utils.py`'nin temelini oluşturan
FTR AI pipeline'ı (`backend/app/services/vehicle_ai/_ftr_reference/`) — bu
"eski mimari" değil, resmi FTR çıktı şemasına göre çalışan ve doğruluğu FTR
aşamasında kanıtlanmış AI çekirdeğinin kendisiydi. AI ekibi bunu temel alıp
`ai/src/predict.py`'de bağımsız olarak genişletti (aşağıda detaylı). Bu
referans klasör de `ai/` VM'de bağımsız olarak doğrulandıktan sonra 6
Ağustos'ta kaldırıldı — artık repoda yok.

## Context — ÖTR/FTR Puan Geçmişi (hâlâ geçerli, hâlâ önemli)

Takım (VST T1) ÖTR ve FTR aşamalarını tamamladı. **Final Yarışma Etabı
7-9 Ağustos 2026'da yüz yüze** yapılıyor.

**Puanlama geçmişi önemli bir ders veriyor:** ÖTR'den 100 üzerinden 92
alındı (mimari "çok özgün, çok güzel" bulundu); FTR'den 200 üzerinden 109
alındı — bunun 90/100'ü rapor puanıyken, sadece **19/100'ü kod puanıydı**.
Yani takımın güçlü yanı tasarım/mimari fikirleri, zayıf yanı bunları sağlam
ve çalışan koda dökmek. **Bu ders hâlâ geçerli** ve bu depodaki her karar
(mock-consent endpoint'i test edilebilirlik için eklemek, gerçek video ile
uçtan uca test etmek, hataları kod okuyarak değil çalıştırarak bulmak) bu
dersin doğrudan uygulanması.

Model envanteri (`ai/weights/`): `yolov8n.pt`, `yolov8s.pt`,
`yolov8n-pose.pt`, `yolov8s-pose.pt`, `yolov8s-cls.pt`, `kasa_modeli.pt`,
`renk_modeli.pt`, `plaka_modeli.pt`, `karakter_modeli.pt`, `kemer.pt`,
`sigara.pt`, `su.pt`, `telefon.pt`, `teknocan.pt`, `yolcu.pt`,
`slalom_lstm.pt`, `face_landmarker.task` — bunlardan yalnızca 16'sı
`predict.py` tarafından fiilen yükleniyor (`yolov8m.pt`, `yolov8n.pt`,
`yolov8s-cls.pt`, kök dizindeki `yolo11n.pt` ölü ağırlık, Dockerfile'a
kopyalanmıyor).

## Mimari

```
┌─────────────────┐      NV → QoD → upload      ┌──────────────────┐
│  Mobil (Flutter) │ ───────────────────────────▶│ Backend (FastAPI)│
│  mobile/         │◀─────────────────────────── │  backend/         │
└─────────────────┘   sonuç (polling ile)         └────────┬─────────┘
                                                             │ docker run
                                                             ▼
                                                   ┌──────────────────┐
                                                   │  AI Docker imajı │
         Hakemin Web UI'ı da AYNI imajı ──────────▶│  ai/              │
         bağımsız olarak çalıştırır                │  (teknofest-2026/*)│
                                                   └──────────────────┘
```

İki dış bağımlılık bilinçli olarak **arayüz arkasına** alındı, çünkü
ikisi de geç aşamada gelecek/değişecek:

| Bağımlılık | Arayüz | Şu anki (mock) | Gerçek |
|---|---|---|---|
| Turkcell Open Gateway (NV, QoD) | `OpenGatewayClient` | `MockOpenGatewayClient` (+ backend'in kendi sahte onay sayfası: `/api/auth/mock-consent`) | `TurkcellOpenGatewayClient` — kodlandı, hiç canlı test edilmedi |
| AI çıkarımı | Ayrı Docker imajı, `docker run` ile tetiklenir | — (sahte çalıştırıcı artık YOK, AI çıktısı her zaman gerçek imajdan gelir) | `ai/` — build alıyor, GPU'da çalışıyor |

`USE_MOCK_5G` tek bir ortam değişkeni; anti-cheat ilkesi gereği canlı
demoda gerçek Turkcell çağrısı başarısız olursa **sessizce mock'a
düşülmez** — bu bilinçli bir deploy-zamanı seçimidir, ortam tespiti değil.

## Repo Yapısı

```
5g-vst-t1/
├── PLAN.md, README.md
├── ai/                     # Hakemin çalıştıracağı Docker imajı (teknofest-2026/vst-t1)
│   ├── main.py                    # FTR Bölüm 6 giriş noktası, sabit /app/data yolları
│   ├── Dockerfile                 # nvidia/cuda:12.1.0-base-ubuntu22.04 temelli
│   ├── requirements.txt           # torch cu121'e SABİT (bkz. Bilinen Riskler)
│   ├── src/predict.py, utils.py   # AI çekirdeği (FTR referansından genişletildi)
│   └── weights/                   # Model ağırlıkları (git'e girmez, ~230MB)
├── backend/                # FastAPI orkestrasyon katmanı — kendi torch/opencv bağımlılığı YOK
│   ├── Dockerfile                 # 6 Ağustos: backend de kendi imajı (vst-t1-backend,
│   │                               # BİLEREK teknofest-2026/ önekSİZ — Web UI panelinde
│   │                               # AI imajıyla karışmasın). DooD: docker.sock + aynı
│   │                               # host path'i mount edilir (bkz. backend/README.md Deploy)
│   ├── app/api/routes_auth.py, routes_qod.py, routes_videos.py
│   ├── app/services/network/      # Turkcell istemcisi + mock + mock-consent
│   └── app/services/orchestration/ # Flow/Job registry, docker run tetikleyici
│       # (eski app/services/vehicle_ai/ referans kodu kaldırıldı — ai/ VM'de
│       # kanıtlandığı için referans ihtiyacı bitti, bkz. Bilinen Riskler)
├── mobile/                 # Flutter uygulaması — takım arkadaşımızın kodu
│   ├── lib/                       # NV/QoD/video/AI-sonuç ekranları
│   └── CLAUDE.md                  # Kod üzerinde çalışırken nelere dikkat edilmeli
```

Not: `docs/mobile-integration.md` ve `docs/ai-integration.md` 6 Ağustos'ta
kaldırıldı — sözleşmeler artık kod + testlerle kanıtlanıyor, ayrı ve kolayca
eskiyen bir doküman kopyası kafa karıştırmaktan başka işe yaramıyordu.

## Tamamlanan İşler

**Backend** — NV (3-legged OIDC: login/callback/status), QoD (tek senkron
çağrı, 409=başarı kuralı), video upload/result (202+job_id, polling,
`docker run` tetikleme) uçtan uca kodlandı ve test edildi. Mock modda bile
mobilin WebView akışını gerçek Turkcell olmadan uçtan uca deneyebilmesi
için `/api/auth/mock-consent` endpoint'i eklendi. 39 test geçiyor.

**6 Ağustos — backend kendi Docker imajına taşındı** (`backend/Dockerfile`,
`vst-t1-backend:latest`, bilerek `teknofest-2026/` öneksiz). Gerçek dünya
mimarisi için bilinçli tercih (prestij değerlendirmesi — bkz. organizasyonun
"mimari becerinizi gösterin" notu); artık iki container var: AI (job başına
tetiklenen, geçici) ve backend (kalıcı, `--restart unless-stopped`). VM'de
Docker-outside-of-Docker olarak doğrulandı: `docker.sock` + `JOB_STORAGE_PATH`
host'taki path ile birebir aynı şekilde mount edildi, backend container'ı
kendi içinden host'ta gerçek bir `teknofest-2026/vst-t1` container'ı
başlatabildi. Gerçek Faz 2 videosuyla uçtan uca tekrar test edildi —
containerize öncesiyle **birebir aynı sonuç** (araç bilgisi + 47 tespit,
aynı zaman damgaları/confidence) üretti, path/volume kurulumunun doğru
olduğunun en güçlü kanıtı. Ayrıca artık VM reboot/çökme sonrası backend
kendiliğinden ayağa kalkıyor (önceki çıplak `nohup` sürecinde bu yoktu) —
gerçek bir çökme simüle edilerek doğrulandı (`docker exec` içinden SIGTERM,
bkz. `backend/README.md` Deploy — SIGKILL'in neden işe yaramadığının ve
`docker kill`/`stop`'un neden restart tetiklemediğinin açıklaması orada).
Restart sonrası aynı gerçek video **üçüncü kez** birebir aynı sonucu
üretti — hem containerize etme hem de crash-recovery tamamen doğrulandı.

**Mobil** — Takım arkadaşımızın yazdığı Flutter uygulaması repoya alındı
(junk dosyalar/bozuk `.gitignore` olmadan, temiz bir git geçmişiyle) ve
code review'dan geçirildi. Bulunan kritik hatalar düzeltildi: WebView geri
tuşunun login döngüsüne sokması, AI sonucunun otomatik pollenmemesi
(sözleşme ihlali), "İptal"in süren bir poll döngüsü tarafından ezilmesi,
büyük video upload'ının retry'da sessizce başarısız olması, çift dokunmada
duplicate upload/kayıt oluşması, 422 hata gövdesinin (liste, string değil)
yanlış cast edilmesi, ve %100 başarısız bozuk test dosyası. Tüm sahte
(mock) veri modu kaldırıldı — `dart analyze` temiz (not: bu makinede
`flutter analyze` yol içindeki `Masaüstü` karakteri yüzünden çöküyor,
`dart analyze` kullanılmalı).

**Not (5 Ağustos'ta bir sonraki sürümle değişti):** takım arkadaşımızın
mobili çoklu-kayıt destekli yeni bir sürümle değiştirmesiyle
`mobile/CLAUDE.md` silindi ve yukarıdaki düzeltmelerden bazıları (WebView
geri-tuşu, çift render) muhtemelen farklı bir daldan geldiği için geri
geldi — kimsenin suçu değil, `note.md`'nin 5 Ağustos bölümünde ayrıntılı.

**6 Ağustos — organizasyon Q&A'sinden çıkan iki gerçek açık düzeltildi**
(tam detay `note.md`'de, özet aşağıdaki Q&A bölümünde): Lifebox'a
zip'lenmeden giden video (diskalifiye riski) ve ffmpeg'in ağ koşulundan
bağımsız hep en yüksek HLS varyantını seçmesi (şartname 4.2 ihlali).
İkisi de kod + testle doğrulandı, ikisi de gerçek Android cihazda henüz
denenmedi. Ayrıca `HLS_URL` de `BACKEND_URL` gibi `--dart-define` oldu
(final günü kod değiştirmeden adres verilebilsin diye). Mobil testler
şu an **20** (13'ü bugün eklendi: 10 HLS varyant, 3 Lifebox zip).

**AI** — `ai/main.py` yazıldı (FTR referans `main.py`'sinin uyarlaması),
Dockerfile'daki `/app/weights` → `/app/models` hatası düzeltildi (FTR
spesifikasyonu). `requirements.txt`'deki sabitlenmemiş torch sürümü, sürücü
uyumsuzluğu yüzünden GPU'yu sessizce devre dışı bırakıyordu — cu121'e
sabitlenerek düzeltildi (aşağıda detaylı, bu ciddi bir buluştu). İmaj build
alıyor, GPU'da çalışıyor (RTX 2060 ile doğrulandı), gerçek Faz 2 test
videosundan 7 farklı etiketli tespit üretip backend'in `SonucJson`
şemasından (plaka regex'i dahil) geçiyor.

**Uçtan uca doğrulama** — Gerçek backend ayağa kaldırılıp hem mobilin kendi
Dio servis kodu hem de curl ile: NV login → WebView yönlendirmesi →
`verified` → QoD → video upload → backend'in tetiklediği **gerçek**
`docker run` → GPU'da çıkarım → results.json → şema doğrulaması →
istemciye dönüş zinciri baştan sona çalıştığı kanıtlandı.

**6 Ağustos — VM'de, gerçek internet üzerinden tekrarlandı ve genişletildi:**
Windows'tan `flutter test test/backend_integration_test.dart
--dart-define=BACKEND_URL=http://<VM_IP>:8080` ile NV+QoD testleri gerçek
ağ üzerinden VM backend'ine karşı geçti (video alt testi hariç — bkz.
aşağıda, fixture'ı eskimiş). Ayrıca VM'in kendi terminalinden, curl ile
tam mobil sözleşmesi taklit edilerek (`login → mock-consent → status →
qod/start → videos/upload → videos/{id}/result` polling) gerçek Faz 2
videosu (`aitest/input/video.mp4`, 115MB) yüklendi: **413 saniyede DONE**,
araç bilgisi (`suv`/`34TC8532`/`siyah`) ground truth ile birebir eşleşti.
Bu, backend'in HTTP zincirinin (daha önce yalnızca doğrudan `docker run`
ile test edilmişti) ilk kez uçtan uca, mobilin kullanacağı gerçek API
üzerinden doğrulanmasıydı.

**Faz 2 ground truth (`faz2_gt.json`) ile karşılaştırma (elle, kaba):**
araç bilgisi ve `arka_koltuk_2`/`teknocan`/`esneme`/`slalom` sağlam
eşleşiyor. **`emniyet_kemeri_ihlali` GT'de 4, bizde 12 — 3 kat fazla tespit**
(AI ekibinin zaten üzerinde çalıştığı `kemer.pt` sorunuyla örtüşüyor).
Ayrıca `arka_koltuk_1` GT'de 1, bizde 4 (fazla yanlış pozitif) ve
`on_koltuk` GT'de 1, bizde 0 (tam kayıp) — bunlar AI ekibinin henüz
gündemine almamış olabileceği, ön koltuk/arka_koltuk_1 doluluk tespitine
özgü ayrı bir sorun gibi duruyor. Kesin precision/recall için otomatik bir
skorlama scripti henüz yazılmadı (bkz. Doğrulama Planı).

## 🗺️ Yol Haritası — Fazlar

- **Faz A — Mobil ↔ Backend: TAMAMLANDI.** `USE_MOCK_5G=true` + mock-consent
  ile NV/QoD dahil tüm akış gerçek HTTP ile test edildi.
- **Faz B — AI Entegrasyonu: TAMAMLANDI.** İmaj build alıyor, GPU'da
  çalışıyor, gerçek videodan şema-geçerli sonuç üretiyor. AI ekibi
  (sigara/telefon için poz-tabanlı tespit sistemi) algoritmayı aktif
  geliştirmeye devam ediyor.
- **Faz C — VM Doğrulaması: 3/4 TAMAMLANDI.** Organizasyonun verdiği VM'de:
  (1) backend düz `uvicorn` process'i olarak ayağa kaldırıldı ✅, (2) AI
  imajı build edilip Tesla T4'te gerçek süre ölçüldü ✅ (limitin belirgin
  altında, aşağıda detaylı), (3) imaj boyutu temizlik sonrası VM'de yeniden
  ölçüldü ✅. **(4) hakemin Web UI'sinin aynı imajı `TOGG_MOBESE_FULL.mp4`
  ile çalıştırıp `EXECUTION COMPLETED – status: SUCCESS` verdiği doğrulaması
  henüz yapılmadı** — 7 Ağustos 21:00 son teslim tarihine kadar planlanıyor.
- **Faz D — 7 Ağustos: Gerçek Ortam + Dondurma: BEKLEMEDE.** Gerçek
  `TURKCELL_CLIENT_ID/SECRET` + kayıtlı `TURKCELL_REDIRECT_URI` ile
  `USE_MOCK_5G=false`; gerçek telefon + gerçek SIM + hücresel veri ile tam
  kuru prova. Aynı gün imaj dondurma + SHA256 ibrazı (mekanizma hâlâ
  organizasyondan netleşmedi).

## Bilinen Riskler

- **İmaj boyutu: resmi bir sınır YOK.** Final Yarışma Senaryosu PDF'i (6
  Ağustos'ta baştan sona okundu) imaj boyutuyla ilgili hiçbir kısıt
  içermiyor — önceki "FTR limiti 8GB" iddiası yalnızca (artık kaldırılmış)
  `docs/ai-integration.md`'deki FTR-fazına özel bir tablodan geliyordu ve
  Final'e uygulanmıyor. Ham ölçüm bilgi amaçlı: yerelde (RTX 2060)
  temizlik sonrası 10.8GB → 9.19GB, VM'de yeniden build; `docker images`
  VM'de "10.5GB disk usage / 3.6GB content size" gösteriyor (ikisi farklı
  ölçüm, resmi limit olmadığı için önemli değil).
- **Düzeltildi — "4K riski" yanlış alarmmış, gerçek stream'de 4K yok.**
  `final_dogrulama.sh`'nin test isimlendirmesi (1080p→4K→240p) takımın
  kendi varsayımıydı; 6 Ağustos'ta yarışmanın gerçek Faz2 master
  playlist'i çekilip incelendiğinde stream'in yalnızca **2 varyant**
  içerdiği görüldü: 1080p (9.16 Mbps) ve 240p (0.29 Mbps) — 4K hiç yok.
  Yani "yüksek kaliteli video" gerçekte 1080p'dir ve ölçümü **436 sn,
  limitin (600 sn) belirgin altında, rahat pay var.** 240p 358 sn.
  Önceki "583/600 sn, 17 sn pay" endişesi var olmayan bir çözünürlüğü
  ölçüyormuş. `predict.py`'deki `atlama = 1` (kare atlama yok) ayarı
  şimdilik değiştirilmesine gerek yok gibi duruyor — final videosunun
  gerçek uzunluğu organizasyon tarafından belirtilmedi (bizim test
  videomuz ~114 sn), daha uzun çıkarsa bu risk yeniden değerlendirilmeli.
- **Çözüldü — Web UI'a giriş sağlandı.** İlk başta "ayrı bir kimlik bilgisi
  gerekiyor, henüz verilmedi" sanılıyordu; meğer organizasyonun asıl
  mailindeki tek USERNAME/PASSWORD çifti (SSH ile aynı) Web UI için de
  geçerliymiş — Operasyon Rehberi'nin "SSH ayrı, Web UI ayrı" ifadesi iki
  farklı ERİŞİM YÖNTEMİni anlatıyormuş, iki ayrı kimlik bilgisi setini
  değil. `http://<VM_IP>` (http, https değil) üzerinden giriş 6 Ağustos'ta
  doğrulandı. **Kalan iş (Faz C, madde 4):** `TOGG_MOBESE_FULL.mp4` ile bir
  Execute çalıştırıp "EXECUTION COMPLETED – status: SUCCESS" görmek —
  organizasyon Q&A'sinde bunun canlı demo'dan (otomatik mobil→backend→AI
  zinciri) AYRI, offline bir değerlendirme adımı olduğu netleşti (bkz.
  aşağıdaki Q&A bölümü, madde 13/24), henüz koşulmadı.
- **Gerçek Turkcell hiç canlı test edilmedi** — yalnızca request-shape
  testleri (`test_turkcell_client.py`) ve mock-consent köprüsü var. **Netleşti
  (organizasyon Q&A, 3 Ağustos toplantısı):** `TURKCELL_CLIENT_ID`/`SECRET`
  yarışma esnasında DEĞİL, öncesinde, VM bilgilerinin paylaşıldığı yöntemle
  (takıma özel, genel bir kanal değil) — organizasyon toplantıda "yarın
  iletiriz" (yani 4 Ağustos) demişti. **6 Ağustos itibarıyla hâlâ
  gelmedi** — söz verilen tarihten 2 gün geçti, 7 Ağustos 21:00 teslim
  tarihine yalnızca 1 gün kaldı. Bugün (6 Ağustos) proaktif takip
  gerekiyor. Not: `TURKCELL_REDIRECT_URI`'nin de Turkcell tarafında
  önceden kayıtlı olması gerekiyor (muhtemelen client_id/secret ile birlikte
  paketlenir). **NV'yi ilk kez Cuma günü (7 Ağustos) test edebileceğimiz Q&A'de
  teyit edildi** (aynı gün cihaz/SIM de organizasyondan geliyor — bkz. Q&A
  bölümü madde 4/1). **Nüans geri çekildi:** Daha önce "21:00 dondurması
  yalnızca Docker imajını kapsıyor, backend değişiklikleri dışında kalabilir"
  denmişti — Q&A'de "21:00 son teslim HER ŞEY için Cuma" notu düşüldüğünden
  bu artık güvenilir bir varsayım değil. **En güvenli plan: Cuma 21:00'den
  sonra hiçbir şeyi (backend dahil) değiştirmemek.**
- **SHA256 mekanizması netleşti, ama henüz uygulanmadı.** Final Yarışma
  Senaryosu: yarışmacı kendi imajının SHA256'sını alıp **kendisi
  saklayacak/ibraz edecek**; hakem, inference'tan önce teslim aldığı
  imajın SHA256'sının bizim ibraz ettiğimizle eşleştiğini kontrol edecek.
  **Netleşti (organizasyon Q&A, 6 Ağustos):** `docker save` + tar hash'i
  GEREKMİYOR — yarışmacı platformu (Web UI, `teknofest-contestant-web`
  container'ı) doğrudan VM'deki local imajı çalıştırdığı için (ayrı bir
  dosya yükleme adımı yok), yalnızca **Docker image ID** yeterli:
  ```
  docker inspect teknofest-2026/vst-t1:latest --format='{{.Id}}'
  ```
  Bunu **7 Ağustos 21:00'e yakın, imaj donduktan hemen sonra** almamız
  gerekiyor — AI ekibi hâlâ iterasyon yaptığı için (bkz. kemer.pt testleri)
  şimdi almak anlamsız, o ana kadar değişecek. İbrazın tam olarak hangi
  kanaldan (form/mail/Web UI) yapılacağı hâlâ organizasyondan netleşmedi.
- **AI çıktısında sessiz bir uyarı var, AI ekibine iletilmeli:** VM
  log'larında (`final.log`, `kemer_test.log`) her koşuda defalarca
  `WARNING ⚠️ GMC failed, falling back to identity: OpenCV ... Assertion
  failed ... in function 'calc'` çıkıyor — pipeline çökmüyor (fallback'e
  düşüp exit=0 ile bitiyor) ama global motion compensation'ın hiç
  çalışmadığı, sürekli devre dışı kaldığı anlamına geliyor. Tracking
  doğruluğunu sessizce etkiliyor olabilir; hata değil ama gözden kaçmış
  olabilir.
- ~~`mobile/test/backend_integration_test.dart`'ın video upload testi sahte
  veri kullanıyordu~~ **çözüldü (6 Ağustos):** artık `DONE`/tespit
  beklemiyor, yalnızca upload→job→polling sözleşmesinin tuttuğunu sınıyor;
  `@Timeout` 2dk→5dk. VM backend'ine karşı 6/6 geçiyor.
- ~~AI tarafında iki farklı sigara/telefon tespit mantığı var~~ **çözüldü**
  (6 Ağustos): `ai/` VM'de kanıtlandığı için `backend/app/services/vehicle_ai/`
  referans kodu ve ona özel testler repodan kaldırıldı — artık tek, aktif
  geliştirilen versiyon var (`ai/src/predict.py`).
- ~~Lifebox'a giden video zip'lenmeden gidiyordu~~ **çözüldü (6 Ağustos,
  DİSKALİFİYE RİSKİYDİ):** organizasyon Q&A'sinde hem "Lifebox ham videoyu
  galeri sayıp çözünürlüğünü düşürebilir" hem de "Lifebox'tan inen video
  bizim sistemimizden geçince canlı demodan farklı sonuç verirse bu
  diskalifiye sebebi" denildi. `lifebox_service.dart` artık videoyu
  `CompressionType.none` ile ZIP'liyor (MP4 zaten sıkıştırılmış, deflate
  hem kazanç sağlamaz hem de `archive` paketinde tüm dosyayı belleğe
  alan bir yola sokar — 100+MB kayıtta risk). Test: `lifebox_zip_test.dart`.
- ~~ffmpeg kaydı ağ koşulundan bağımsız hep en yüksek varyantı seçiyordu~~
  **çözüldü (6 Ağustos, ŞARTNAME 4.2 İHLALİYDİ):** yarışmanın gerçek Faz2
  master playlist'i çekilip incelendi (2 varyant: 1080p 9.16Mbps, 240p
  0.29Mbps), yerel ffmpeg 8.1.1 ile uygulamanın kullandığı komutun birebir
  aynısı test edildi — ffmpeg master playlist verildiğinde ağ koşulundan
  bağımsız hep 1080p seçiyordu. Düşük bantta (QoD başarısız senaryosu)
  1080p denenirse 5 dakikalık kayıt penceresi yetişmeyip canlı demo
  başarısız olurdu. `hls_variant_service.dart` (yeni) artık ölçülen bant
  genişliğine göre doğru alt-playlist URL'ini ffmpeg'e veriyor — gerçek
  sunucuya karşı doğrulandı (5 Mbps→240p URL'i üretildi, ffmpeg o URL'de
  gerçekten 426x240 verdi). Detaylar `note.md`'de.

## Organizasyon Q&A Netleştirmeleri (3 Ağustos toplantısı, 6 Ağustos işlendi)

27 soru-cevap tek tek incelendi. Mimariyi/riskleri değiştirenler yukarıdaki
ilgili bölümlere zaten işlendi; burada geri kalan ama kaydı tutulması
gereken bulgular var.

**AI ekibine iletilmesi gereken, henüz aksiyon alınmamış bulgular**
(`note.md`'deki 5 Ağustos AI bug listesiyle kesiştiği yerler orada
işaretlendi):

- **"Yaşam döngüsü" kuralı:** bir aracın TEK geçişi boyunca her etiketten
  yalnızca 1 tespit olmalı — video geneli değil, GEÇİŞ/KLİP başına. Aynı
  geçişte tekrar gönderim **false positive sayılır** (nötr değil, puan
  kaybı). Bir videoda birden fazla ayrı araç geçişi olabilir, her biri
  kendi hakkına sahip.
- **`arka_koltuk_1`/`arka_koltuk_2`, koltuk pozisyonu değil KİŞİ SAYISI**
  ("arka koltukta 1/2 kişi var"). 6 Ağustos sabahki ground-truth
  karşılaştırmasındaki "arka_koltuk_1 ayrı kategori, fazla yanlış pozitif"
  yorumu muhtemelen yanlıştı — gerçek sorun sayım kararlılığı (2→1
  flicker) olabilir.
- **Emniyet kemeri ihlali için kemerin TAKILI OLMADIĞININ görülmesi
  gerekiyor** (varlık tespitinden yokluk çıkarımı kabul, yöntem serbest);
  kemer hiç görünmüyorsa ihlal sayılabilir. Veri setinde çelişkili örnek
  yok.
- **Aydınlıktan/parlamadan korkun, karanlıktan değil** — beklenenin
  aksine yüksek ışık/glare daha riskli, "nesneleri birden fazla görüyor
  olabiliriz" (duplicate tespit) uyarısı yapıldı.
- **Puanlama netleşti:** sapma 0-10 saniye arası lineer düşüş (10 sn'de 0
  puan, etiket başına 5 puan varsa 5 sn sapma = 2.5 puan). "Look-ahead"
  penceresi: hakemin gözle işaretleyebileceğinden ERKEN tespitte %10'a
  kadar bonus (5→5.5 puan) — "ilk görülen anda raporlayın" tavsiyesinin
  sayısal gerekçesi bu.
- Pratik öneri (uygulanmadı, isteğe bağlı): Faz2 videosunu indirip kendi
  gözünüzle hakem gibi işaretleyip GT ile karşılaştırmak, anlayış farkını
  gösterir — 6 Ağustos sabah otomatik GT karşılaştırmasıyla kısmen zaten
  yapıldı.

**Mimariyi doğrulayan, aksiyon gerektirmeyen cevaplar** (özet):
backend'i AI ile aynı VM'de container olarak koşturmak organizasyon
tarafından açıkça onaylandı ("gateway" rolü tarif edildi — NV+QoD+AI
tetikleme+mobil iletişimi); canlı demo'da AI mutlaka otomatik
mobil→backend→AI zinciriyle tetiklenmeli, Web UI kullanılmamalı (offline
hakem değerlendirmesinden ayrı bir aşama); Lifebox'a giden video ile
canlı demo AI'sı 2 paralel/bağımsız yol; QoD 201+REQUESTED yeterli
(AVAILABLE beklenmez); NV+QoD stream başlamadan önce atılır; final günü
video stream olarak gelir (mp4 dosya değil); test ortamı ayrı
kurulmayacak — üzerinde geliştirdiğimiz VM yarışma günü de kullanılacak
VM'in ta kendisi; mobilde AI inference yapılmayacak; canlı demo + hakem
offline değerlendirmesi AYNI Docker imajını kullanmalı (ayrı build yok).

**Diğer bilgiler (aksiyon gerektirmiyor, kayıt amaçlı):** dokümandaki
`+905390000020` test numarası anlamsız bir placeholder, final günü önemi
yok; sunumu birden fazla kişi yapabilir, kaptan zorunluluğu yok, tek
sınır 10 dakika; sunum formatı serbest, vurgu AR-GE sürecinin gösterilmesi
(prestij ödülleri "nasıl bir mühendislik çalışması yaptığınız"a bakıyor);
mobil APK organizasyonun verdiği cihaza yüklenecek; cihaz+SIM organizasyon
tarafından sağlanıyor (kullanıcının tahmini: Cuma).

**Hâlâ açık/belirsiz kalanlar:**
- SHA256 (Docker image ID) ibrazının nereye/nasıl yapılacağı hâlâ
  belirsiz (yalnızca "hangi değer" sorusu cevaplandı, "nereye" değil).
- Turkcell `client_id`/`secret` hâlâ gelmedi (bkz. Bilinen Riskler).
- Final videosunun gerçek uzunluğu belirtilmedi.
- Test SIM'i kimin sağlayacağı bu turda ayrıca teyit edilmedi (muhtemelen
  cihaz+SIM ile aynı paket, ama net değil).

Tam 27 maddenin ham notu (kim ne dedi, birebir) oturumun scratchpad
dosyasında; bu bölüm onun işlenmiş özeti.

## Doğrulama Planı

- **Backend:** `cd backend && python -m pytest -q` (39 test — backend'in
  hiç ML bağımlılığı yok, `requirements-dev.txt` sadece pytest içerir).
- **Mobil:** `cd mobile && flutter test` (20 test). Backend ayaktayken
  `flutter test test/backend_integration_test.dart` — uygulamanın gerçek
  servis kodunu gerçek backend'e karşı çalıştırır.
- **AI imajı:** `docker build -t teknofest-2026/vst-t1:latest ai/` sonra
  `docker run --rm --gpus all -v <input>:/app/data/input
  -v <output>:/app/data/output teknofest-2026/vst-t1:latest` — gerçek bir
  video ile `results.json`'ın üretildiği ve backend'in `SonucJson`
  şemasından geçtiği doğrulanır.
- **Faz 2 ground truth** ile skorlama karşılaştırması — AI ekibinin işi,
  henüz yapılmadı.
