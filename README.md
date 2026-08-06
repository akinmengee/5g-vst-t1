# 5G VST T1 — Akıllı Yol Güvenliği

**5G & Yapay Zekâ ile Akıllı Yol Güvenliği Yarışması** (Teknofest) kapsamında
VST T1 takımının final için geliştirdiği sistem. Mobil uygulama üzerinden
Number Verification → Quality on Demand → video yükleme akışını yürütür;
video, ayrı bir Docker imajındaki AI pipeline'ında işlenip araç bilgisi
(plaka, renk, kasa tipi) ve sürücü/yolcu ihlalleri (telefon kullanımı,
emniyet kemeri, slalom, esneme, vb.) tespit edilir.

> **Takvim:** Final Yarışma Etabı **7-9 Ağustos 2026**, yüz yüze.

## İçindekiler

1. [Proje Hakkında](#proje-hakkında)
2. [Mimari](#mimari)
3. [Proje Yapısı](#proje-yapısı)
4. [Başlarken](#başlarken)
5. [Durum ve Yol Haritası](#durum-ve-yol-haritası)
6. [Takım](#takım)
7. [Daha Fazla Bilgi](#daha-fazla-bilgi)

## Proje Hakkında

Sistem üç bağımsız parçadan oluşuyor:

- **`mobile/`** — Flutter uygulaması. Number Verification, Quality on
  Demand, video kaydı/yükleme ve AI sonucunun gösterimi. Hiçbir AI/model
  işi yapmaz, yalnızca orkestrasyon ve arayüz.
- **`backend/`** — FastAPI. Mobil ile Turkcell Open Gateway arasında
  aracılık eder, video yüklenince AI imajını tetikler, sonucu mobile
  döner. Kendi torch/opencv bağımlılığı yoktur — ince bir katmandır.
- **`ai/`** — Hakemin de bağımsız olarak çalıştıracağı Docker imajı
  (`teknofest-2026/vst-t1`). Videoyu okur, `results.json` yazar, sonlanır.

Bu üçlü ayrışma **3 Ağustos 2026'da organizasyondan gelen 9 resmi
dokümanın** (Final Yarışma Senaryosu, FTR teslim dokümanı, Turkcell Open
Gateway spesifikasyonları, Operasyon Rehberi vb.) tarif ettiği resmi final
akışına birebir dayanıyor. Projenin daha önceki bir sürümü farklı bir
mimari (mobilde edge AI + WebSocket) izliyordu; bu mimari organizasyonun
resmi akışıyla çeliştiği için tamamen terk edildi — bugün kodda veya
dokümanlarda bundan hiçbir iz yok.

Kararların *neden* böyle alındığına, tamamlanan işlere ve yol haritasına
dair detay için bkz. **[`PLAN.md`](./PLAN.md)**.

## Mimari

```mermaid
flowchart LR
    subgraph M["📱 Mobil (Flutter)"]
        NV["Number Verification"] --> QOD["Quality on Demand"]
        QOD --> REC["Turkcell stream'ini\nMP4'e kaydet"]
    end

    REC -- "video upload" --> B

    subgraph B["🖥️ Backend (FastAPI)"]
        UP["POST /api/videos/upload"] --> TRIG["docker run\nteknofest-2026/vst-t1"]
    end

    TRIG --> AI

    subgraph AI["🤖 AI Docker İmajı (ai/)"]
        IN["/app/data/input/video.mp4"] --> PIPE["predict.py"]
        PIPE --> OUT["/app/data/output/results.json"]
    end

    OUT -- "polling" --> B
    B -- "sonuç JSON" --> M

    JUDGE["👤 Hakemin Web UI'ı"] -. "aynı imajı\nbağımsız çalıştırır" .-> AI
```

Backend'deki tek dış bağımlılık (Turkcell Open Gateway) arayüz arkasında:
mock ↔ gerçek arası `USE_MOCK_5G` ortam değişkeniyle seçilir, kod
değişikliği gerekmez. AI çıktısı için sahte bir mod **yoktur** — video her
zaman gerçek `ai/` imajına gider.

## Proje Yapısı

```text
5g-vst-t1/
├── PLAN.md, README.md
├── ai/                     # Hakemin çalıştıracağı Docker imajı
│   ├── main.py, Dockerfile, requirements.txt
│   ├── src/predict.py, utils.py
│   └── weights/            # Model ağırlıkları (git'e girmez)
├── backend/                # FastAPI orkestrasyon katmanı
│   └── app/api/, services/network/, services/orchestration/
├── mobile/                 # Flutter uygulaması
│   └── lib/
└── docs/
    ├── mobile-integration.md   # Backend ↔ mobil sözleşmesi
    └── ai-integration.md       # Backend ↔ AI sözleşmesi
```

## Başlarken

Her parçanın kendi kurulum/çalıştırma talimatı kendi klasöründe:

- **Backend:** [`backend/README.md`](./backend/README.md) — `uvicorn
  app.main:app --reload`, ortam değişkenleri, test komutları.
- **Mobil:** [`mobile/README.md`](./mobile/README.md) ve
  [`mobile/CLAUDE.md`](./mobile/CLAUDE.md) — `flutter run
  --dart-define=BACKEND_URL=...`, bilinen platform kısıtları (Windows
  masaüstünde NV WebView test edilemez).
- **AI:** `docker build -t teknofest-2026/vst-t1:latest ai/` ile imaj
  build edilir; çalışma sözleşmesi, açık riskler ve doğrulama durumu
  [`PLAN.md`](./PLAN.md)'de.

Üçünü birlikte, gerçek bir backend + gerçek AI imajına karşı test etmek
için:

```bash
cd backend
JOB_STORAGE_PATH=./.local-jobs USE_MOCK_5G=true python -m uvicorn app.main:app --port 8000
```

```bash
cd mobile
flutter run --dart-define=BACKEND_URL=http://localhost:8000
```

## Durum ve Yol Haritası

- [x] **Backend ↔ Mobil** — NV/QoD/video akışının tamamı gerçek HTTP ile
  uçtan uca doğrulandı.
- [x] **AI imajı** — build alıyor, GPU'da çalışıyor, gerçek yarışma
  videosundan şema-geçerli sonuç üretiyor.
- [x] **Uçtan uca** — mobil servis kodu → backend → gerçek AI imajı →
  sonuç zinciri baştan sona kanıtlandı.
- [ ] **VM doğrulaması** — imaj boyutu (rebuild + ölçüm yapıldı: 10.8GB →
  9.19GB, limit 8GB — hâlâ ~1.2GB fazla, detay `PLAN.md`) ve çalışma süresi
  (578sn, limit 600sn) gerçek donanımda (Tesla T4) yeniden ölçülecek.
- [ ] **7 Ağustos** — gerçek Turkcell erişimi açılınca `USE_MOCK_5G=false`
  ile tam kuru prova + imaj dondurma.

Detaylı yol haritası, açık riskler ve gerekçeler için bkz.
**[`PLAN.md`](./PLAN.md)**.

## Takım

| Rol | Sorumluluk |
|---|---|
| Akademik Danışman | Proje takibi ve danışmanlık |
| Kaptan — Sunucu ve Veri Tabanı Mimarı | Backend mimarisi (bu repo) |
| 5G API Entegrasyonu | Turkcell Open Gateway (Number Verification, QoD) entegrasyonu |
| Yapay Zekâ / Görüntü İşleme | AI pipeline'ı, model geliştirme, doğruluk iyileştirme |
| Sistem Entegrasyonu ve Test | Uçtan uca test, saha provaları |
| Mobil Uygulama Geliştirici | Flutter uygulaması |

## Daha Fazla Bilgi

- **[`PLAN.md`](./PLAN.md)** — mimari kararlar, gerekçeler, tamamlanan
  işler, yol haritası, açık riskler, doğrulama planı.
- **[`backend/README.md`](./backend/README.md)**,
  **[`mobile/README.md`](./mobile/README.md)**,
  **[`mobile/CLAUDE.md`](./mobile/CLAUDE.md)** — parçaya özel kurulum ve
  bilinen kısıtlar.
