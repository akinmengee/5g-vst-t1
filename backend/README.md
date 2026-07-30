# Backend — VST T1 Akıllı Yol Güvenliği

FastAPI tabanlı backend. Detaylı mimari/karar gerekçeleri için repo kökündeki
`PLAN.md` dosyasına bakın.

## Yerel kurulum

```bash
cd backend
python -m venv .venv
.venv\Scripts\activate        # Windows
pip install -r requirements.txt
```

> Not: `requirements.txt` GPU'lu PyTorch indirir (büyük). CPU'da geliştirme
> yapacaksanız `torch`/`torchvision` satırlarını CPU wheel'leriyle değiştirebilirsiniz.

## Çalıştırma

```bash
uvicorn app.main:app --reload --app-dir .
```

- `GET /health` → `{"status": "ok"}`
- `WS /ws/stream` → mobilin (edge yolov8n tespiti sonrası) kırpılmış araç ROI'lerini
  gönderdiği uç. Şema: `app/schemas/mobile_contract.py::MobileRoiPayload`.

## Mock veriyle uçtan uca test (mobil kodu olmadan)

```bash
# 1) Backend'i bir terminalde çalıştır
uvicorn app.main:app --reload

# 2) Mock fixture'ları uret (ilk seferde)
python -m app.fixtures.mock_mobile_payloads.generate_fixtures

# 3) Fixture'ları backend'e gönder, cevapları gör
python -m app.fixtures.mock_mobile_payloads.send_mock_stream
```

## Ortam değişkenleri (`.env` veya shell)

| Değişken | Varsayılan | Açıklama |
|---|---|---|
| `USE_MOCK_5G` | `true` | `false` yapılınca gerçek `TurkcellOpenGatewayClient` kullanılır (yarışma günü). |
| `MODEL_DIR` | `backend/weights` | Model ağırlıklarının bulunduğu klasör. |
| `TURKCELL_API_BASE_URL` / `TURKCELL_API_KEY` | boş | Gerçek 5G Open Gateway credential'ları (yarışma günü doldurulacak). |

## Model ağırlıkları

`backend/weights/` klasörüne şu dosyalar konulmalı (paylaşılan model envanteri —
büyük binary dosyalar oldukları için git'e eklenmiyor, `.gitignore`'a bakın):
`yolov8n.pt`, `yolov8s.pt`, `yolov8n-pose.pt`, `yolov8s-cls.pt`, `kasa_modeli.pt`,
`renk_modeli.pt`, `plaka_modeli.pt`, `karakter_modeli.pt`, `kemer_v3.pt`,
`sigara_v1.pt`, `su_v2.pt`, `telefon_temiz_v1.pt`, `teknocan.pt`, `slalom_lstm.pt`,
`face_landmarker.task`.

## Durum (Gün 0-1)

- [x] FastAPI iskeleti, `/health`, `/ws/stream`
- [x] Mobil-backend veri sözleşmesi (Pydantic şemaları)
- [x] `VehicleAnalysisService` / `OpenGatewayClient` arayüzleri + mock implementasyonlar
- [x] Mock mobil veri üreticisi
- [ ] Gerçek model entegrasyonu + incremental refactor (Gün 4-7, bkz. `PLAN.md`)
