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
- `GET  /api/auth/status/{flow_id}` → NV durumu (mobil poller)
- `POST /api/qod/start` → QoD oturumu açar (201+REQUESTED = başarı), yanıtta
  Turkcell'in GERÇEKTEN verdiği `duration` da döner
- `POST /api/qod/stop` → oturumu erken kapatmayı dener (en iyi çaba, aşağıya bkz.)
- `POST /api/videos/upload` → multipart video, `202` + `job_id`
- `GET  /api/videos/{job_id}/result` → `PROCESSING|DONE|FAILED` + results.json

**Sahte/mock bir mod YOKTUR.** Gerçek credential ve SIM geldikten sonra
(7 Ağustos) `USE_MOCK_5G`, `MockOpenGatewayClient` ve `/api/auth/mock-consent`
tamamen kaldırıldı: Turkcell çağrıları her zaman gerçeğe gider, hata olursa
üretilmiş bir sonuçla maskelenmez. Testler `tests/network_stubs.py`'deki
`FakeOpenGatewayClient` ile çalışır — o yalnızca `tests/` altında yaşar.

## Testler

```bash
cd backend
python -m pytest -q   # 50 test, hiç ML bağımlılığı gerektirmez
```

## Ortam değişkenleri (`.env` veya shell)

| Değişken | Varsayılan | Açıklama |
|---|---|---|
| `TURKCELL_API_BASE_URL` | boş | `https://opengateway.turkcell.com.tr` |
| `TURKCELL_CLIENT_ID` / `TURKCELL_CLIENT_SECRET` | boş | OAuth2 kimlik bilgileri (yalnızca backend'de tutulur). Eksikse uygulama **açılışta** `RuntimeError` verir. |
| `TURKCELL_REDIRECT_URI` | boş | Turkcell'e önceden kayıtlı callback: `http://<VM_IP>:8080/api/auth/callback` |
| `QOD_DURATION_SECONDS` | `1200` | QoD oturum süresi. **Oturum bittiği anda cihazın veri bağlantısı kopuyor** (7 Ağustos ölçümü, 3 bağımsız oturumda saniyesi saniyesine) — bu yüzden süre tüm demoyu kapsamalı. Turkcell kırparsa gerçek değer loglanır. |
| `AI_DOCKER_IMAGE` | `teknofest-2026/vst-t1:latest` | Tetiklenecek AI imajı. Alternatif çalıştırıcı yoktur; imaj her zaman gerçekten koşar. |
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
# Turkcell kimlik bilgileri gizli: -e yerine --env-file (docker inspect'te ve
# shell geçmişinde görünmesin). Dosya repo DIŞINDA, chmod 600.
docker run -d --name vst-t1-backend --restart unless-stopped \
  -p 8080:8080 \
  --env-file /home/<kullanici>/backend.env \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v /home/<kullanici>/jobs:/home/<kullanici>/jobs \
  vst-t1-backend:latest
```

`backend.env` içeriği:

```
TURKCELL_API_BASE_URL=https://opengateway.turkcell.com.tr
TURKCELL_CLIENT_ID=<organizasyondan>
TURKCELL_CLIENT_SECRET=<organizasyondan>
TURKCELL_REDIRECT_URI=http://<VM_IP>:8080/api/auth/callback
JOB_STORAGE_PATH=/home/<kullanici>/jobs
AI_DOCKER_IMAGE=teknofest-2026/vst-t1:latest
LOG_LEVEL=INFO
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
- [x] `ai/` imajı build alıyor, GPU'da (Tesla T4) çalışıyor, şema-geçerli
      sonuç üretiyor
- [x] VM'de backend + AI imajı doğrulaması (uvicorn process, sonra
      container, çalışma süresi/imaj boyutu ölçümü)
- [x] Backend kendi Docker imajı olarak VM'de çalışıyor,
      `--restart unless-stopped` ile crash-recovery doğrulandı
- [x] Hakemin kendi Web UI'ından Execute çalıştırılıp
      `EXECUTION COMPLETED – status: SUCCESS` alındı (Faz C, 6 Ağustos)
- [x] Turkcell `client_id`/`secret` alındı, gerçek NV + QoD canlı çalıştı
      (7 Ağustos gecesi, gerçek SIM ile)
- [x] Sahte (mock) mod tamamen kaldırıldı — tek istemci `TurkcellOpenGatewayClient`
- [ ] AI imajı dondurulup SHA256 (image ID) alınacak (7 Ağustos 21:00'e yakın)
- [ ] Yarışma SIM'i (256 kbit / QoD'li 8 Mbit) ile uçtan uca kuru prova
