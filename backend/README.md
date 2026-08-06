# Backend — VST T1 Akıllı Yol Güvenliği

FastAPI tabanlı, mobil-yüzlü NV/QoD/video orkestrasyon API'si. AI çıkarımı bu
process'te ÇALIŞMAZ: backend videoyu diske yazıp ayrı bir Docker imajını
(`teknofest-2026/vst-t1`) tetikleyen ince bir katmandır — bu yüzden
torch/opencv bağımlılığı yoktur. Mobil tarafın uyacağı sözleşme aşağıdaki
Endpoint'ler listesi ve testlerdir (`tests/test_routes_*.py`).

## Yerel kurulum

```bash
cd backend
python -m venv .venv
.venv\Scripts\activate        # Windows
pip install -r requirements.txt        # hafif — ML bağımlılığı YOK
```

## Çalıştırma

```bash
# Windows'ta JOB_STORAGE_PATH mutlaka override edilmeli (/srv/jobs Linux yolu):
# .env dosyasına JOB_STORAGE_PATH=./.local-jobs yazın.
uvicorn app.main:app --reload
```

Endpoint'ler:

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
| `AI_DOCKER_IMAGE` | `teknofest-2026/vst-t1:latest` | Tetiklenecek AI imajı. Sahte çalıştırıcı yoktur; imaj her zaman gerçekten koşar. |
| `JOB_STORAGE_PATH` | `/srv/jobs` | Job giriş/çıkış klasörleri. **Windows'ta override şart** (örn. `./.local-jobs`). |
| `JOB_TIMEOUT_SECONDS` | `600` | AI çalıştırma üst sınırı (hakem limitiyle aynı: 10 dk). |
| `FLOW_TTL_SECONDS` | `1200` | İşlem görmeyen NV/QoD flow'larının hafızadan düşme süresi. |
| `JOB_RESULT_TTL_SECONDS` | `3600` | DONE/FAILED job kayıtlarının saklanma süresi (PROCESSING asla düşmez). |
| `LOG_LEVEL` | `INFO` | |

## Eski mimarinin durumu

Mobil edge-AI + WebSocket ROI-stream mimarisi (eski `routes_inference.py`,
`/ws/stream`, mock ROI fixture'ları) **tamamen kaldırıldı** — organizasyonun
resmi final akışının bir parçası değildi (bkz. final yarışma senaryosu
resmi dokümanları, `PLAN.md`). Backend'de bugün bu mimariden hiçbir iz yok.

Daha önce `app/services/vehicle_ai/*` (dedektörler, oylama, event gate) S1
kararı gereği "`ai/` fazı kanıtlanana kadar referans" olarak bilinçli
korunuyordu. `ai/` imajı artık VM'de (Tesla T4) gerçek video ile uçtan uca
doğrulandı (bkz. `PLAN.md` Faz C) — taşıma tamamlandı, referans ihtiyacı
bitti. Bu klasör ve ona özel testler (`test_service_pipeline.py`,
`test_streaming_equivalence.py`) repodan kaldırıldı; backend'in ML
bağımlılığı hiç olmadı, şimdi de yok.

## Deploy

Backend, S2/G3 kararı gereği hakeme teslim edilen `teknofest-2026/*` imajının
içinde olmak ZORUNDA değil (organizasyon teyidi) — nasıl çalıştırılacağı
serbest bırakılmış (systemd/`tmux`/kendi ayrı container'ı). 6 Ağustos'tan
itibaren **kendi Docker imajı** olarak çalışıyor (`backend/Dockerfile`),
`teknofest-2026/` ÖNEKİ OLMADAN (`vst-t1-backend:latest`) — bilinçli: Web UI
"Docker – Images" paneli yalnızca `teknofest-2026/` önekli imajları
gösteriyor, backend'in orada görünüp "hangisi final AI imajı" karışıklığı
yaratmasını istemiyoruz.

Backend, kendi içinden `docker run` ile AI imajını tetiklediği için bu bir
Docker-outside-of-Docker kurulumu: host'un `/var/run/docker.sock`'u ve
`JOB_STORAGE_PATH`'in **host'taki path ile birebir aynı path'te** container'a
mount edilmesi şart (aksi halde AI container'ı boş/yanlış girdiyle sessizce
çalışır — bkz. `Dockerfile`'daki not ve `app/services/orchestration/ai_runner.py`).

```bash
docker build -t vst-t1-backend:latest backend/
docker run -d --name vst-t1-backend --restart unless-stopped \
  -p 8080:8080 \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v /home/<kullanici>/jobs:/home/<kullanici>/jobs \
  -e PUBLIC_BASE_URL=http://<VM_IP>:8080 \
  -e USE_MOCK_5G=true \
  -e JOB_STORAGE_PATH=/home/<kullanici>/jobs \
  -e AI_DOCKER_IMAGE=teknofest-2026/vst-t1:latest \
  vst-t1-backend:latest
```

`--restart unless-stopped` VM reboot/crash sonrası backend'in kendiliğinden
ayağa kalkmasını sağlıyor — daha önceki çıplak `nohup` sürecinin eksikti.
6 Ağustos'ta VM'de doğrulandı (`RestartCount` 0→1, container gerçekten
çöküp kendiliğinden geri geldi).

**Bunu test ederken (ya da gerçek bir arıza ayıklarken) dikkat:**
- `docker kill`/`docker stop` **restart'ı TETİKLEMEZ** — Docker bunları
  "kasıtlı durdurma" sayıyor, `unless-stopped` de tam olarak "kasıtlı
  durdurulmadıkça" demek. Container'ı bilerek durdurduysan geri getirmek
  için elle `docker start vst-t1-backend` gerekir.
- Container İÇİNDEN (`docker exec ... kill -9 1`) PID 1'e SIGKILL
  göndermek de işe yaramaz — Linux çekirdeği, bir PID namespace'inin init
  process'ini (PID 1) **aynı namespace içinden** gelen, kendi kurduğu bir
  handler'ı olmayan sinyallere karşı korur (`pid_namespaces(7)`); SIGKILL
  hiçbir zaman handler alamayacağı için sessizce yok sayılır.
- Gerçek bir çökmeyi doğru simüle etmenin yolu: `docker exec vst-t1-backend
  python3 -c "import os, signal; os.kill(1, signal.SIGTERM)"` — uvicorn
  SIGTERM için zaten bir handler kurduğundan (graceful shutdown) namespace
  koruması buna izin verir, ve bu `docker stop`/`kill` API'sinden geçmediği
  için Docker'ı "kasıtlı" değil "beklenmedik çıkış" olarak görür, restart
  policy normal şekilde devreye girer.

## Durum

- [x] NV: login / callback / status (3-legged OIDC, Bölüm H)
- [x] QoD: start (tek senkron çağrı, 409=başarı kuralı, Bölüm I)
- [x] Video: upload (202+job) / result (polling), `docker run` tetikleme (Bölüm J)
- [x] Sahte AI çalıştırıcı KALDIRILDI — video her zaman gerçek `ai/` imajına gider
- [x] Mobil ↔ backend uçtan uca gerçek HTTP ile doğrulandı
- [x] Eski edge-AI/WebSocket mimarisi backend'den tamamen kaldırıldı
- [ ] `ai/` imajı: `batch_main.py` + Dockerfile (ayrı faz — plan P0)
- [x] VM'de backend + AI imajı doğrulaması (Tesla T4, uvicorn process,
      çalışma süresi/imaj boyutu ölçümü)
- [ ] Hakemin kendi Web UI'ının aynı imajı bağımsız çalıştırıp SUCCESS
      vermesi (7 Ağustos 21:00 son teslim tarihine kadar)
- [ ] Gerçek Turkcell ile canlı test (`USE_MOCK_5G=false`)
