# Backend — VST T1 Akıllı Yol Güvenliği

FastAPI tabanlı, mobil-yüzlü NV/QoD/video orkestrasyon API'si. AI çıkarımı bu
process'te ÇALIŞMAZ: backend videoyu diske yazıp ayrı bir Docker imajını
(`teknofest-2026/vst-t1`) tetikleyen ince bir katmandır — bu yüzden
torch/opencv bağımlılığı yoktur. Mobil tarafın uyacağı tam sözleşme:
`docs/mobile-integration.md`.

## Yerel kurulum

```bash
cd backend
python -m venv .venv
.venv\Scripts\activate        # Windows
pip install -r requirements.txt        # hafif — ML bağımlılığı YOK
```

> AI-core testlerini (`test_service_pipeline.py`, `test_streaming_equivalence.py`)
> de çalıştırmak istiyorsanız `pip install -r requirements-dev.txt` — bu, ai/
> paketine taşınana kadar geçici olarak torch/opencv vb. kurar (büyük indirme).

## Çalıştırma

```bash
# Windows'ta JOB_STORAGE_PATH mutlaka override edilmeli (/srv/jobs Linux yolu):
# .env dosyasına JOB_STORAGE_PATH=./.local-jobs yazın.
uvicorn app.main:app --reload
```

Endpoint'ler (tam istek/yanıt şemaları `docs/mobile-integration.md`'de):

- `GET  /health` → `{"status": "ok"}`
- `POST /api/auth/login` → NV akışını başlatır (`flow_id` + `authorize_url`)
- `GET  /api/auth/callback` → Turkcell'in yönlendirdiği OAuth callback
- `GET  /api/auth/mock-consent` → **yalnızca mock modda**: Turkcell'in onay
  sayfasının yerine geçer, callback'e yönlendirir. Gerçek modda `404` döner.
  Mobilin, gerçek Turkcell erişimi olmadan WebView akışını uçtan uca test
  edebilmesini sağlar (mobil tarafta hiçbir kod farkı yok).
- `GET  /api/auth/status/{flow_id}` → NV durumu (mobil poller)
- `POST /api/qod/start` → QoD oturumu açar (201+REQUESTED = başarı)
- `POST /api/videos/upload` → multipart video, `202` + `job_id`
- `GET  /api/videos/{job_id}/result` → `PROCESSING|DONE|FAILED` + results.json

## Testler

```bash
cd backend
python -m pytest tests/ -v
# Yalnızca yeni backend testleri (ML bağımlılığı gerektirmez):
python -m pytest tests/test_routes_auth.py tests/test_routes_qod.py \
  tests/test_routes_videos.py tests/test_flow_registry.py \
  tests/test_job_registry.py tests/test_ai_runner.py tests/test_turkcell_client.py
```

## Ortam değişkenleri (`.env` veya shell)

| Değişken | Varsayılan | Açıklama |
|---|---|---|
| `USE_MOCK_5G` | `true` | `false` → gerçek `TurkcellOpenGatewayClient` (yarışma günü). Sessiz fallback YOK. |
| `TURKCELL_API_BASE_URL` | boş | `https://opengateway.turkcell.com.tr` |
| `TURKCELL_CLIENT_ID` / `TURKCELL_CLIENT_SECRET` | boş | OAuth2 kimlik bilgileri (yalnızca backend'de tutulur). |
| `TURKCELL_REDIRECT_URI` | boş | Turkcell'e önceden kayıtlı callback: `http://<VM_IP>:8080/api/auth/callback` |
| `PUBLIC_BASE_URL` | `http://localhost:8000` | Backend'e **dışarıdan** erişilen adres; yalnızca mock modda sahte onay sayfası için. Gerçek telefonla test ederken LAN IP'si olmalı (`http://192.168.1.50:8000`) — `localhost` telefonun kendisini işaret eder. |
| `AI_RUNNER_MODE` | `mock` | `docker` → gerçek `docker run teknofest-2026/vst-t1`. |
| `AI_DOCKER_IMAGE` | `teknofest-2026/vst-t1:latest` | Tetiklenecek AI imajı. |
| `JOB_STORAGE_PATH` | `/srv/jobs` | Job giriş/çıkış klasörleri. **Windows'ta override şart** (örn. `./.local-jobs`). |
| `JOB_TIMEOUT_SECONDS` | `600` | AI çalıştırma üst sınırı (hakem limitiyle aynı: 10 dk). |
| `FLOW_TTL_SECONDS` | `1200` | İşlem görmeyen NV/QoD flow'larının hafızadan düşme süresi. |
| `JOB_RESULT_TTL_SECONDS` | `3600` | DONE/FAILED job kayıtlarının saklanma süresi (PROCESSING asla düşmez). |
| `MODEL_DIR` | `backend/weights` | (Eski AI-core kodu için; yeni backend kullanmaz.) |
| `LOG_LEVEL` | `INFO` | |

## Eski mimarinin durumu

Mobil edge-AI + WebSocket ROI-stream mimarisi (eski `routes_inference.py`,
`/ws/stream`, mock ROI fixture'ları) **tamamen kaldırıldı** — organizasyonun
resmi final akışının bir parçası değildi (bkz. `docs/mobile-integration.md`
ve final yarışma senaryosu). Backend'de bugün bu mimariden hiçbir iz yok.

Tek istisna: `app/services/vehicle_ai/*` (dedektörler, oylama, event gate —
200+ test) **kasıtlı olarak korunuyor.** Bu, "eski mimari" değil, resmi FTR
formatına göre çalışan ve ayrı bir Docker imajına (`ai/`) taşınacak olan AI
çekirdeğinin kendisi — S1 kararı gereği sıfırdan yazılmıyor, taşınıyor. Yeni
`main.py` bu kodu import etmiyor (backend artık ML bağımlılığı taşımıyor);
kod ve testleri yalnızca `ai/` fazı başlayana kadar referans olarak burada
duruyor. Model ağırlıkları (`backend/weights/`) da o imajın parçası olacak.

## Deploy

Backend'in kendi Dockerfile'ı **yok** — S2/G3 kararı gereği (organizasyon
teyidi: backend'in hakeme teslim edilen `teknofest-2026/*` imajının içinde
olması gerekmiyor). VM'de düz bir `uvicorn app.main:app` process'i olarak
çalıştırılır (systemd/`tmux`/kendi ayrı container'ı — serbest, organizasyon
karışmıyor). Sadece AI imajı (`ai/`) `teknofest-2026/` adıyla paketlenmek
zorunda.

## Durum

- [x] NV: login / callback / status (3-legged OIDC, Bölüm H)
- [x] QoD: start (tek senkron çağrı, 409=başarı kuralı, Bölüm I)
- [x] Video: upload (202+job) / result (polling), `docker run` tetikleme (Bölüm J)
- [x] Mock katmanları: `MockOpenGatewayClient`, `MockAiRunner` (imaj olmadan uçtan uca test)
- [x] 37 yeni backend testi + uçtan uca mock duman testi geçiyor
- [x] Eski edge-AI/WebSocket mimarisi backend'den tamamen kaldırıldı
- [ ] `ai/` imajı: `batch_main.py` + Dockerfile (ayrı faz — plan P0)
- [ ] VM'de gerçek ortam doğrulaması (`AI_RUNNER_MODE=docker`, gerçek Turkcell)
