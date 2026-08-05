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
- **Şu anki durum:** Backend ↔ mobil zinciri gerçek HTTP ile uçtan uca
  doğrulandı. AI imajı build alıyor, GPU'da çalışıyor, gerçek yarışma
  videosundan gerçek tespitler üretip backend'in resmi şemasından geçiyor.
  Üç parça ayrı ayrı VE birlikte (mobil servis kodu → backend → gerçek AI
  imajı → sonuç) test edildi. **İki açık teknik risk var** (imaj boyutu,
  çalışma süresi — aşağıda detaylı) ve **gerçek Turkcell erişimi hâlâ yok**
  (7 Ağustos'a kadar).
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

Sonuç: backend, mobil kodu, ve `docs/mobile-integration.md` /
`docs/ai-integration.md` dokümanları o gün sıfırdan, bu resmi sözleşmeye
göre yeniden yazıldı. Eski mimariden (`routes_inference.py`, `/ws/stream`,
`mobile_contract.py`, mock ROI fixture'ları, `VehicleAnalysisService`
arayüzü) kodda ve dokümanlarda hiçbir iz kalmadı.

**Tek istisna:** `predict.py`/`utils.py`'nin temelini oluşturan FTR AI
pipeline'ı (`backend/app/services/vehicle_ai/_ftr_reference/`) — bu "eski
mimari" değil, resmi FTR çıktı şemasına göre çalışan ve doğruluğu FTR
aşamasında kanıtlanmış AI çekirdeğinin kendisiydi. AI ekibi bunu temel alıp
`ai/src/predict.py`'de bağımsız olarak genişletti (aşağıda detaylı).

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
│   ├── app/api/routes_auth.py, routes_qod.py, routes_videos.py
│   ├── app/services/network/      # Turkcell istemcisi + mock + mock-consent
│   ├── app/services/orchestration/ # Flow/Job registry, docker run tetikleyici
│   └── app/services/vehicle_ai/   # ESKİ AI çekirdeği — artık main.py import ETMİYOR,
│                                   # yalnızca referans/FTR kanıtı olarak duruyor (200+ test)
├── mobile/                 # Flutter uygulaması — takım arkadaşımızın kodu
│   ├── lib/                       # NV/QoD/video/AI-sonuç ekranları
│   └── CLAUDE.md                  # Kod üzerinde çalışırken nelere dikkat edilmeli
└── docs/
    ├── mobile-integration.md      # Backend ↔ mobil sözleşmesi (TEK doğruluk kaynağı)
    └── ai-integration.md          # Backend ↔ AI sözleşmesi + AI ekibi için onboarding
```

## Tamamlanan İşler

**Backend** — NV (3-legged OIDC: login/callback/status), QoD (tek senkron
çağrı, 409=başarı kuralı), video upload/result (202+job_id, polling,
`docker run` tetikleme) uçtan uca kodlandı ve test edildi. Mock modda bile
mobilin WebView akışını gerçek Turkcell olmadan uçtan uca deneyebilmesi
için `/api/auth/mock-consent` endpoint'i eklendi. 39 test geçiyor.

**Mobil** — Takım arkadaşımızın yazdığı Flutter uygulaması repoya alındı
(junk dosyalar/bozuk `.gitignore` olmadan, temiz bir git geçmişiyle) ve
code review'dan geçirildi. Bulunan kritik hatalar düzeltildi: WebView geri
tuşunun login döngüsüne sokması, AI sonucunun otomatik pollenmemesi
(sözleşme ihlali), "İptal"in süren bir poll döngüsü tarafından ezilmesi,
büyük video upload'ının retry'da sessizce başarısız olması, çift dokunmada
duplicate upload/kayıt oluşması, 422 hata gövdesinin (liste, string değil)
yanlış cast edilmesi, ve %100 başarısız bozuk test dosyası. Tüm sahte
(mock) veri modu kaldırıldı — 12 test geçiyor, `dart analyze` temiz.

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

## 🗺️ Yol Haritası — Fazlar

- **Faz A — Mobil ↔ Backend: TAMAMLANDI.** `USE_MOCK_5G=true` + mock-consent
  ile NV/QoD dahil tüm akış gerçek HTTP ile test edildi.
- **Faz B — AI Entegrasyonu: FONKSİYONEL OLARAK TAMAMLANDI, 2 açık risk
  var** (aşağıda). İmaj build alıyor, GPU'da çalışıyor, gerçek videodan
  şema-geçerli sonuç üretiyor. AI ekibi (sigara/telefon için poz-tabanlı
  tespit sistemi) algoritmayı aktif geliştirmeye devam ediyor.
- **Faz C — VM Doğrulaması: SIRADA.** Bu makine (RTX 2060, 6GB VRAM) yeterli
  değil — organizasyonun verdiği VM'de: (1) backend düz `uvicorn` process'i
  olarak ayağa kaldırılır, (2) AI imajı build edilip Tesla T4'te gerçek süre
  ölçülür, (3) imaj boyutu temizlik sonrası yeniden ölçülür, (4) hakemin Web
  UI'sinin aynı imajı `TOGG_MOBESE_FULL.mp4` ile çalıştırıp `EXECUTION
  COMPLETED – status: SUCCESS` verdiği doğrulanır.
- **Faz D — 7 Ağustos: Gerçek Ortam + Dondurma: BEKLEMEDE.** Gerçek
  `TURKCELL_CLIENT_ID/SECRET` + kayıtlı `TURKCELL_REDIRECT_URI` ile
  `USE_MOCK_5G=false`; gerçek telefon + gerçek SIM + hücresel veri ile tam
  kuru prova. Aynı gün imaj dondurma + SHA256 ibrazı (mekanizma hâlâ
  organizasyondan netleşmedi).

## Bilinen Riskler

- **İmaj boyutu: 9.19GB (ölçüldü), FTR limiti 8GB — hâlâ ~1.2GB fazla.**
  Dockerfile temizliği (triton kaldırma, OpenCV kopya kaldırma,
  `torch/include` silme, yalnızca fiilen kullanılan 16 ağırlığı kopyalama)
  uygulanıp yerelde (RTX 2060 makinesi) yeniden build edildi: 10.8GB →
  9.19GB. Yetmedi. Katman dökümü (`docker history`): `pip3 install` katmanı
  tek başına 5.06GB (torch+CUDA kütüphaneleri+opencv+mediapipe+ultralytics),
  `apt-get`/CUDA base katmanları ~3.9GB, ağırlıklar 183MB. Sonraki adaylar:
  `nvidia-nccl-cu12` (~188MB indirilen — çoklu-GPU haberleşmesi, tek Tesla
  T4'te muhtemelen gereksiz, ama torch import'unu kırıp kırmadığı test
  edilmeli), `matplotlib`/`polars` gibi mediapipe'ın çektiği ama
  `predict.py`'nin kullanmadığı paketler. Faz C'de VM'de ele alınacak.
- **Çalışma süresi: 578 saniye, limit 600 saniye — yalnızca 22 saniye pay
  var** (114 saniyelik gerçek Faz 2 videosu, RTX 2060'ta). `predict.py`'de
  `atlama = 1`, yani **her kare** 16 modelden geçiyor. Kare atlama en büyük
  hızlanma kaldıracı ama bir doğruluk/hız takası — AI ekibinin kararı.
  Tesla T4 RTX 2060'tan biraz hızlı ama tek başına yetip yetmeyeceği VM'de
  ölçülmeden bilinemez.
- **Gerçek Turkcell hiç canlı test edilmedi** — yalnızca request-shape
  testleri (`test_turkcell_client.py`) ve mock-consent köprüsü var. 7
  Ağustos'a kadar mümkün değil.
- **SHA256 ibraz mekanizması hâlâ bilinmiyor** — imaj dondurma sonrası
  hangi formatta/nereye teslim edileceği organizasyondan netleşmedi.
- **AI tarafında iki farklı sigara/telefon tespit mantığı var**:
  `backend/app/services/vehicle_ai/`'daki basit (test edilmiş ama artık
  kullanılmayan) versiyon ve `ai/src/predict.py`'deki AI ekibinin aktif
  geliştirdiği poz-tabanlı, daha detaylı versiyon. Kasıtlı bir karar: AI
  ekibinin kendi sistemi üzerinde devam ediyoruz, ikisini birleştirmiyoruz.

## Doğrulama Planı

- **Backend:** `cd backend && python -m pytest tests/test_routes_auth.py
  tests/test_routes_qod.py tests/test_routes_videos.py
  tests/test_flow_registry.py tests/test_job_registry.py
  tests/test_ai_runner.py tests/test_turkcell_client.py -q` (39 test, ML
  bağımlılığı gerektirmez). `vehicle_ai/`'ın kendi testleri (200+, FTR
  kanıtı) `requirements-dev.txt` ister, ayrı çalıştırılır.
- **Mobil:** `cd mobile && flutter test` (12 test). Backend ayaktayken
  `flutter test test/backend_integration_test.dart` — uygulamanın gerçek
  servis kodunu gerçek backend'e karşı çalıştırır.
- **AI imajı:** `docker build -t teknofest-2026/vst-t1:latest ai/` sonra
  `docker run --rm --gpus all -v <input>:/app/data/input
  -v <output>:/app/data/output teknofest-2026/vst-t1:latest` — gerçek bir
  video ile `results.json`'ın üretildiği ve backend'in `SonucJson`
  şemasından geçtiği doğrulanır.
- **Faz 2 ground truth** ile skorlama karşılaştırması — AI ekibinin işi,
  henüz yapılmadı.
