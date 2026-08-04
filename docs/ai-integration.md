# AI Ekibi ↔ Sistem Entegrasyon Sözleşmesi

> **Bu doküman kimin için:** `ai/` klasöründeki Docker imajını (araç
> tespiti + sürücü davranışı analizi) yazacak/taşıyacak takım arkadaşı.
> Backend kodunu ya da mobil uygulamayı hiç açmadan, yalnızca bu dokümana
> bakarak işe başlayabilmelisin. Bir şey belirsizse önce burayı tara — büyük
> ihtimalle cevap burada.
>
> **Son güncelleme:** 4 Ağustos 2026 — backend ve mobil sözleşmesi
> (`docs/mobile-integration.md`) tamamlandı, sıradaki iş bu.

---

## 1. Büyük Resim

Yazacağın şey **tek bir Docker imajı**: video dosyası alır, `results.json`
üretir, çıkar. Bu imaj **iki farklı taraf tarafından, iki farklı bağlamda**
çalıştırılıyor ama ikisinde de **birebir aynı sabit sözleşmeyle**:

```
┌─────────────────────────────────────────────────────────────┐
│   AI İMAJI (senin yazacağın) — tek, sabit bir program        │
│   girdi: /app/data/input/video.mp4                            │
│   çıktı: /app/data/output/results.json                        │
│   → çıkar (self-terminating, web sunucusu DEĞİL)              │
└─────────────────────────────────────────────────────────────┘
              ▲                                      ▲
   [Backend'in canlı demo tetiklemesi]      [Hakemin Web UI'dan Execute'ı]
   Mobil videoyu backend'e yükler,          Hakem, kendi VM'indeki Web UI'dan
   backend videoyu diske yazıp senin        videoyu seçip Execute'a basar —
   imajını `docker run` ile tetikler.       backend hiç devrede değil, imajı
                                              platform doğrudan çalıştırır.
```

Bu yüzden imajının **kim tarafından çağrıldığını bilmesine hiç gerek yok** —
her iki durumda da aynı iki dosya yolunu okuyup yazman yeterli. Aşağıdaki
"Resmi Kurallar" bölümündeki anti-cheat maddesi de tam bunu söylüyor: ortamı
algılayıp farklı davranmak yasak, zaten ihtiyacın da yok.

**Puanlamadaki yeri:** Nihai puanın %50'si (düşük+yüksek kaliteli final
videosu, hakem tarafından batch çalıştırılıyor) + canlı demonun içindeki AI
sonucu kısmı (%25'in bir parçası) — tamamen senin yazacağın bu imajın
doğruluğuna bağlı. En yüksek kaldıraçlı iş burası.

---

## 2. Adım 0 — Repo Taşıma (senin yapacağın, ilk iş)

AI çekirdeği şu an geçici olarak `backend/` altında duruyor (backend'den
ayrıştırılmadan önceki düzen). Nihai repo yapısı üçe bölünüyor: `ai/`
(bu doküman), `backend/` (NV/QoD/video orkestrasyonu, zaten bitti),
`mobile/` (Flutter, ayrı arkadaş yazıyor). **Bu taşımayı sen yapacaksın** —
git geçmişini korumak için `git mv` kullan:

```bash
mkdir ai ai/streaming ai/schemas ai/tests

git mv backend/app/services/vehicle_ai/current_model_service.py ai/
git mv backend/app/services/vehicle_ai/model_registry.py         ai/
git mv backend/app/services/vehicle_ai/vision_ops.py              ai/
git mv backend/app/services/vehicle_ai/thresholds.py               ai/
git mv backend/app/services/vehicle_ai/attribute_voting.py        ai/
git mv backend/app/services/vehicle_ai/slalom_net.py               ai/
git mv backend/app/services/vehicle_ai/session.py                  ai/
git mv backend/app/services/vehicle_ai/interface.py                ai/
git mv backend/app/services/vehicle_ai/streaming/*.py               ai/streaming/
git mv backend/app/services/vehicle_ai/_ftr_reference               ai/_ftr_reference

git mv backend/app/schemas/mobile_contract.py    ai/schemas/
cp    backend/app/schemas/detection.py           ai/schemas/detection.py

git mv backend/tests/test_service_pipeline.py       ai/tests/
git mv backend/tests/test_streaming_equivalence.py  ai/tests/
git mv backend/tests/stubs.py                        ai/tests/
git mv backend/tests/reference_batch.py              ai/tests/

git mv backend/weights ai/weights
```

**Bağımlılıklar:** `ai/requirements.txt` de senin oluşturman gerekiyor —
ML bağımlılıkları (`opencv-python-headless`, `numpy`, `ultralytics`,
`mediapipe`, `torch`, `torchvision` + `--extra-index-url
https://download.pytorch.org/whl/cu121`) şu an geçici olarak
`backend/requirements-dev.txt`'te duruyor (backend'i hafif tutmak için
oraya taşınmıştı) — bu satırları oradan `ai/requirements.txt`'e taşı
(`backend/requirements-dev.txt`'ten sil, çünkü artık orada durmalarının
sebebi kalmıyor).

**Dikkat — `detection.py` istisnası:** bu dosya `cp` ile **kopyalanıyor**,
`git mv` ile taşınmıyor. Backend de `results.json`'ı mobile dönmeden önce
aynı şemayla doğruluyor (`backend/app/schemas/detection.py`,
`routes_videos.py` içinde kullanılıyor) — iki taraf da Python seviyesinde
birbirine bağımlı olmasın diye bilerek iki bağımsız kopya tutuluyor. İçeriği
birebir aynı, ileride ikisi de aynı resmi FTR şemasına göre güncellenecek.

**Tek gereken kod değişikliği — `model_registry.py`'nin config bağımlılığı:**
Şu an `model_registry.py:44`'te `self.model_dir = Path(model_dir) if model_dir else settings.model_dir`
satırı var; `settings`, `from app.core.config import settings` ile geliyor —
bu backend'e ait bir modül, taşıma sonrası import hatası verir. Yerine
`ai/` için kendi küçük config'ini yaz, örneğin:

```python
# ai/config.py (yeni, birkaç satır yeterli)
import os
from pathlib import Path

MODEL_DIR = Path(os.environ.get("MODEL_DIR", "/app/models"))
```

ve `model_registry.py`'deki import'u `from app.core.config import settings`
→ `from ai.config import MODEL_DIR`, kullanım yerini `settings.model_dir` →
`MODEL_DIR` olarak güncelle. Bu, dosyanın **tek** değişen satırı olmalı —
aşağıdaki "Dokunmayacaklarım" bölümüne bak.

**Taşımanın doğru yapıldığının kanıtı:** `ai/tests/` altındaki testler
(200'den fazla) **hiçbir mantık değişikliği olmadan** geçmeli:

```bash
cd ai && pip install -r requirements-dev.txt && python -m pytest tests/ -v
```

---

## 3. Dokunmayacakların (S1 kararı: "çekirdeği koru, sıfırdan yazma")

Aşağıdakiler **200'den fazla testle korunan, çalışan, doğrulanmış kod** —
mantığını değiştirme, sadece yukarıdaki taşımayı yap:

- `current_model_service.py` — sürücü eylemi/yolcu/nesne/araç-özelliği
  tespit mantığının tamamı (`process_roi`, `finalize_session`).
- `model_registry.py` — model yükleme (eksik model varsa çökmez, loglar).
- `vision_ops.py`, `attribute_voting.py`, `slalom_net.py` — yardımcı görüntü
  işleme ve oylama mantığı.
- `streaming/event_gate.py`, `streaming/run_detectors.py` — **kare
  kaynağından bağımsız** tasarlandılar (WebSocket'ten mi video dosyasından
  mı geldiği önemli değil); bu yüzden batch'te de aynen çalışırlar.
- `session.py` — `SessionRegistry`/`SessionState` (TTL-eviction batch'te
  gereksiz ama zararsız — tek session, process bir kere çalışıp çıkıyor).
- `_ftr_reference/` — **salt okunur referans, HİÇ düzenlenmez** (kendi
  README.md'sinde de yazılı: "değişiklikler current_model_service.py'de
  yapılmalı"). Aşağıdaki Katman 2 kodu için oradan **okuyup adapte
  edeceksin**, dosyanın kendisini değiştirmeyeceksin.

Yazman gereken/düzelteceğin şeyler yalnızca aşağıdaki 4 madde — hepsi ya
**yeni dosya** ya da **yukarıdaki dosyaların dışında** bir yerde.

---

## 4. Yazman Gereken #1 — `batch_main.py` (yeni dosya, `ai/batch_main.py`)

Bu, imajın giriş noktası. Tasarım (zaten netleşti, doğrulanmış GT'ye göre
tek klipte **tek araç** olduğu bilindiği için basit):

```python
import sys
import json
import cv2

from ai.model_registry import ModelRegistry
from ai.current_model_service import CurrentModelService
from ai.schemas.detection import SonucJson

INPUT_PATH = "/app/data/input/video.mp4"
OUTPUT_PATH = "/app/data/output/results.json"
STRIDE = ...  # ölçülerek belirlenecek, bkz. Bölüm 7


def main() -> None:
    cap = cv2.VideoCapture(INPUT_PATH)
    if not cap.isOpened():
        print(f"Hata: video acilamadi -> {INPUT_PATH}")
        sys.exit(1)
    fps = cap.get(cv2.CAP_PROP_FPS) or 30.0

    registry = ModelRegistry()
    service = CurrentModelService(registry)

    frame_idx = 0
    while True:
        ret, frame = cap.read()
        if not ret:
            break
        if frame_idx % STRIDE == 0:
            zaman = frame_idx / fps
            kutu = tek_arac_bul(registry.yolo("detector"), frame)  # Bölüm 5
            if kutu is not None:
                crop = pad_ve_kirp(frame, kutu)                    # Bölüm 5
                service.process_roi_batch(session_id="main", crop, zaman)  # Bölüm 6
        frame_idx += 1
    cap.release()

    sonuc = service.finalize_session("main")
    veri = sonuc_to_sonucjson(sonuc, video_id="video.mp4")  # SonucJson'a çevir
    with open(OUTPUT_PATH, "w", encoding="utf-8") as f:
        json.dump(veri.model_dump(), f, ensure_ascii=False, indent=2)
    print("EXECUTION COMPLETED - status: SUCCESS")
    sys.exit(0)


if __name__ == "__main__":
    main()
```

Önemli noktalar:
- **Web sunucusu DEĞİL** — `cap.release()`'den sonra dosyayı yazıp `sys.exit(0)`
  ile çıkar. Bu, en kritik kural (bkz. Bölüm 8, Dockerfile).
- Video açılamazsa/bozuksa **çökme** — `sys.exit(1)` ile temiz hata ver
  (FTR dokümanı madde 7: "girdi dizininde video bulamama/hasarlı video"
  senaryosunda try-except önerisi).
- `STRIDE` (kaç karede bir işleneceği) tahmin edilmiyor — 10 dakikalık
  bütçeye göre gerçek donanımda ÖLÇÜLEREK belirlenmeli (Bölüm 7).

---

## 5. Yazman Gereken #2 — Katman 2: Araç Bul + Kırp

Referans kod `_ftr_reference/predict.py:383-388`'de (**okuyup adapte et,
düzenleme**):

```python
detector_results = detector_model.track(frame, classes=[2, 7, 63], conf=0.45, persist=True, verbose=False)
```

Bu, `.track()` ile **çoklu araç takibi** yapıyor (`persist=True`,
`vehicle_id` bazlı sözlükler, video boyunca hangi aracın hangisi olduğunu
ayırt ediyor) — çünkü FTR'nin orijinal senaryosunda birden fazla araç geçişi
olabiliyordu. **Final Faz 2 ground truth'u, klip başına TEK ve sürekli araç
olduğunu doğruladı** (111 saniyelik tek video, tek sürücü, sırayla farklı
senaryolar) — bu yüzden takip/kimlik sürekliliği GEREKMİYOR, basitleştirilmiş
hali yeterli:

```python
def tek_arac_bul(detector_model, frame):
    """Karede en güvenli araç kutusunu döner (yoksa None). Takip YOK —
    tek araç olduğu bilindiği için her karede en iyi kutuyu almak yeterli."""
    sonuclar = detector_model.predict(frame, classes=[2, 7], conf=0.45, verbose=False)
    en_iyi = None
    for r in sonuclar:
        for box in r.boxes:
            conf = float(box.conf[0])
            if en_iyi is None or conf > en_iyi[0]:
                en_iyi = (conf, tuple(map(int, box.xyxy[0])))
    return en_iyi[1] if en_iyi else None


def pad_ve_kirp(frame, kutu, pad_oran=0.05):
    """predict.py:438-444'teki %5 padding mantığının tek-kutu hali."""
    x1, y1, x2, y2 = kutu
    w, h = x2 - x1, y2 - y1
    pad_x, pad_y = int(w * pad_oran), int(h * pad_oran)
    x1p = max(0, x1 - pad_x)
    y1p = max(0, y1 - pad_y)
    x2p = min(frame.shape[1], x2 + pad_x)
    y2p = min(frame.shape[0], y2 + pad_y)
    return frame[y1p:y2p, x1p:x2p]
```

**Sınıf `63` (laptop) bilerek çıkarıldı** — `predict.py`'de laptop/bilgisayar
tespiti araç kutusuyla aynı `.track()` çağrısına bindirilmiş ama bu, senin
Katman 2'nde gerekli değil: `bilgisayar` etiketi zaten `current_model_service.py`
içindeki `_nesneler` metodunda aynı `yolov8s.pt` modeliyle **ayrıca**
üretiliyor (dokunmuyorsun, çalışıyor). Katman 2'nin tek işi: aracı bulup
kırpmak.

`detector` model anahtarı zaten `model_registry.py:24`'te tanımlı
(`"detector": "yolov8s.pt"`) — yeni model eklemene gerek yok.

---

## 6. `process_roi` ile Bağlantı — İnce Bir Adaptör

`current_model_service.py:48`'deki mevcut imza:
```python
def process_roi(self, payload: MobileRoiPayload, image_bytes: bytes) -> VehicleAnalysisResult
```
Bu, mobil/JPEG-bytes'a özgü bir sözleşme (eski mimarinin kalıntısı) — ama
**bunu değiştirmene gerek yok ve değiştirmemelisin** (200+ test bu imzaya
göre yazıldı). İki önemli nokta zaten senin lehine çözülmüş durumda,
kod değişikliği gerektirmiyor:

- **"ROI = tüm görüntü" varsayımı bir bug değil, bir sözleşme.**
  `current_model_service.py:324-326`:
  ```python
  # ROI aracın kendisi olduğu için araç kutusu = tüm görüntü
  arac_orta = w / 2
  sofor_adaylari = [k for k in kisiler if k["merkez_x"] > arac_orta] or kisiler
  ```
  Bu kod DOĞRU — sadece sen (Katman 2) tam kareyi değil, **önceden
  kırpılmış** `pad_ve_kirp()` çıktısını vermelisin. Kırpmayı unutursan bu
  satır yanlış çalışır; kırparsan doğru çalışır. Kod değişikliği yok.

- **Zaman kaynağı da bir sözleşme, bug değil.** `session.py:85-89`'daki
  `rolatif_zaman(timestamp)` transport-agnostic: ilk çağrıdaki değeri sıfır
  noktası alıp farkını döner. Sen `payload.timestamp` alanına
  `frame_idx / fps` (video-göreli saniye) verirsen otomatik doğru çalışır —
  wall-clock (`time.time()`) VERME. `session.py`'ye dokunma.

Yapman gereken tek şey, `process_roi`'yi bu iki sözleşmeye uyarak çağıran
ince bir sarmalayıcı (adaptör) yazmak — örneğin `current_model_service.py`'ye
(veya `batch_main.py`'ye) eklenecek bir yardımcı:

```python
import cv2
from ai.schemas.mobile_contract import BBox, MobileRoiPayload

def process_roi_batch(self, session_id: str, crop, zaman_saniye: float) -> VehicleAnalysisResult:
    """Batch'te ham numpy kareyi process_roi'nin beklediği JPEG+payload'a çevirir."""
    ok, buf = cv2.imencode(".jpg", crop)
    h, w = crop.shape[:2]
    payload = MobileRoiPayload(
        session_id=session_id,
        sequence_number=0,           # batch'te anlamsız, sabit verilebilir
        timestamp=zaman_saniye,       # ÖNEMLİ: video-göreli saniye, wall-clock DEĞİL
        bbox=BBox(x1=0, y1=0, x2=w, y2=h, frame_width=w, frame_height=h),
        mobile_confidence=1.0,        # batch'te mobil edge-model yok, sabit
        image_base64="",              # kullanılmıyor, image_bytes ayrıca geçiliyor
        image_format="jpeg",
    )
    return self.process_roi(payload, buf.tobytes())
```

(Bu metodu `CurrentModelService`'e eklemek mantıklı çünkü `self.process_roi`'ye
erişmesi gerekiyor — ama `process_roi`'nin KENDİSİNİ değiştirmiyorsun, yanına
yeni bir metot ekliyorsun.)

---

## 7. Düzeltmen Gereken Tek Gerçek Bug — Tekrarlanan Etiketler

Faz 2 ground truth'unda (`faz2_gt.json`) aynı etiket video boyunca defalarca
tekrar ediyor — `arka_koltuk_2` tam **12 kez**, farklı zamanlarda. Şu anki
kod bunu böyle üretmiyor:

- `thresholds.py`'de (34 alan tam, kontrol ettim) **`etiket_basina_max_olay`
  diye bir alan YOK.**
- `streaming/event_gate.py:28`'de `EventGate.__init__`'in constructor
  varsayılanı: `etiket_basina_max_olay: int = 1`.
- `session.py:62-65`, `EventGate`'i bu parametreyi **geçmeden** kuruyor →
  varsayılan `1` her zaman geçerli oluyor → her etiket oturum boyunca
  **en fazla bir kez** yayınlanıyor → GT'nin beklediği 12 tekrardan 11'i
  sessizce kayboluyor.
- Ayrıca `cooldown_saniye=3.0` diye bir eşik var (aynı etiketin 3sn içindeki
  tekrarını bastırıyor) — bu doğru davranış ve KALMALI; sorun sadece
  `max_olay=1`'in bunun üstüne binmiş olması.

**Düzeltme (iki küçük değişiklik):**

1. `thresholds.py`'ye yeni bir alan ekle (projedeki "hiçbir eşik sabit
   kodlanmaz" ilkesine uygun olarak — mevcut 34 alanın hepsi böyle):
   ```python
   etiket_basina_max_olay: int = 999  # GT'de tekrarlı etiketler var; cooldown zaten
                                        # yakın-zamanlı tekrarları eliyor, bu sınırlamıyor.
   ```
2. `session.py:62-65`'teki `EventGate(...)` çağrısına bu alanı ekle:
   ```python
   EventGate(
       cooldown_saniye=thresholds.cooldown_saniye,
       cakisma_marji_saniye=thresholds.cakisma_marji_saniye,
       etiket_basina_max_olay=thresholds.etiket_basina_max_olay,  # YENİ satır
   )
   ```

Bunu yaptıktan sonra Faz 2 videosuyla (Bölüm 9) tekrar ölç — `arka_koltuk_2`
artık 12 kez (ya da yakın) yayınlanmalı, 1 değil.

---

## 8. Dockerfile Düzeltmesi

Eski (backend'e aitken kullanılan, artık silinmiş) Dockerfile şu hataları
içeriyordu — sana yenisini yazarken referans olsun diye listeliyorum:

1. **CMD web sunucusu başlatıyordu** (`uvicorn app.main:app`) — asla
   sonlanmıyor. Hakem "Execute"a bastığında `EXECUTION COMPLETED` mesajı
   hiç gelmiyor, değerlendirme takılıyor. **Senin CMD'in `batch_main.py`'yi
   çalıştırmalı ve çıkmalı.**
2. **Model yolu `/app/weights` kullanıyordu** — resmi FTR dokümanı
   ("docker format.pdf" bölüm 6, "Model Ağırlıkları" satırı) **`/app/models/`**
   diyor. Bu iki yol farklı — kendi Dockerfile'ında **`/app/models/`**
   kullan, `ai/config.py`'deki `MODEL_DIR` varsayılanı da buna göre
   `/app/models` olsun (Bölüm 2'de zaten öyle yazdım).

Önerilen iskelet (resmi FTR örnek Dockerfile'ıyla + mevcut GPU/base-image
gereksinimleriyle uyumlu):

```dockerfile
FROM nvidia/cuda:12.1.0-base-ubuntu22.04

RUN apt-get update && apt-get install -y \
    python3 python3-pip ffmpeg libsm6 libxext6 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
RUN mkdir -p /app/data/input /app/data/output /app/models

COPY requirements.txt .
RUN pip3 install --no-cache-dir -r requirements.txt

# Sadece FİİLEN KULLANILAN ağırlıklar (bkz. Bölüm 10 — yolov8n.pt ve
# yolov8s-cls.pt kopyalanmıyor, ölü ağırlık, imaj boyutu limiti için).
COPY weights/ /app/models/
COPY . /app/ai/

ENV MODEL_DIR=/app/models
ENV PYTHONPATH=/app

CMD ["python3", "-m", "ai.batch_main"]
```

Kontrol listesi (FTR dokümanı bölüm 9'daki resmi checklist'le aynı):
- [ ] İmaj adı **`teknofest-2026/vst-t1:latest`** (bu tam isim zorunlu —
  `teknofest-2026/` öneki olmadan Web UI panelinde hiç görünmez).
- [ ] `docker run ... teknofest-2026/vst-t1:latest` çalıştırıldığında
  otomatik başlıyor mu (elle komut girmeden)?
- [ ] Program `/app/data/input/video.mp4`'ü okuyor mu?
- [ ] Sonuç `/app/data/output/results.json`'a yazılıyor mu?
- [ ] Program **sonlanıyor mu** (exit 0)?
- [ ] İmaj boyutu 8GB'ı aşmıyor mu (`docker images` ile kontrol et)?

---

## 9. Backend Seni Böyle Çalıştıracak (bilgi amaçlı, sana bir şey yapman gerekmiyor)

Canlı demo sırasında backend, senin imajını tam olarak şöyle tetikliyor
(`backend/app/services/orchestration/ai_runner.py`, zaten kodlandı ve test
edildi — bu kısma dokunmana gerek yok, sadece sözleşmeyi bil):

```bash
docker run --rm --gpus all \
  -v {job_klasoru}/input:/app/data/input \
  -v {job_klasoru}/output:/app/data/output \
  teknofest-2026/vst-t1:latest
```

- Backend, senin çalıştırmanı **10 dakika** bekler (`JOB_TIMEOUT_SECONDS=600`,
  resmi FTR limitiyle aynı) — aşarsan backend süreci öldürür, iş `FAILED`
  sayılır. **Bu yüzden Bölüm 4'teki `STRIDE` değerini gerçek donanımda
  (ya da elindeki en yakın donanımda) ölçüp bu bütçeye göre seç.**
- Backend'in seninle Python seviyesinde hiçbir teması yok — tamamen dosya
  sistemi üzerinden (volume mount) konuşuyor. Backend kodunu okumana hiç
  gerek yok.
- Hakem değerlendirmesinde (%50'lik kısım) backend devrede değil — hakem
  seni doğrudan kendi Web UI'ından çalıştırıyor, ama **aynı sabit path
  sözleşmesiyle** (Bölüm 1'deki şema). Yani imajın davranışı iki durumda da
  birebir aynı olmalı.

---

## 10. Resmi Kurallar (FTR Teslim Dokümantasyonu'ndan, uyulması zorunlu)

| Kriter | Değer |
|---|---|
| İşlemci | 4.0 vCPU |
| RAM | 16 GB |
| GPU | NVIDIA Tesla T4 |
| Paylaşımlı bellek (SHM) | 2 GB |
| Base image | `nvidia/cuda:12.1.0-base-ubuntu22.04` |
| Maks. imaj boyutu | 8 GB |
| Maks. çalışma süresi | 10 dakika (**imaj build süresi dahil değil**) |
| Girdi | `/app/data/input/video.mp4` |
| Çıktı | `/app/data/output/results.json` |
| Model ağırlıkları | `/app/models/` |

- **Çıktı formatı birebir uyumlu olmalı** — JSON anahtarları (`video_id`,
  `arac_bilgisi`, `tespitler`, `zaman_saniye`, `kategori`, `etiket`,
  `confidence_score`) ve etiket değerleri **ASCII, küçük harf** (`kirmizi`
  değil `kırmızı`, `sofor_eylemi` değil `şoför_eylemi`). Bu zaten
  `ai/schemas/detection.py`'deki Pydantic modelleriyle garanti — modeli
  kullandığın sürece bunu elle kontrol etmen gerekmez.
- **🔴 Anti-cheat (kritik, verbatim):** *"Submission içerisinde; ortam
  değişkeni, hostname, IP adresi veya dosya varlığı kontrolü gibi
  yöntemlerle 'değerlendirme ortamında mıyım?' tespiti yapan ve buna göre
  farklı davranış sergileyen yapılar (if/else, try/except tabanlı
  manipülasyon) tespit edilmesi halinde ilgili takımın değerlendirmesi
  geçersiz sayılacaktır."* — kodların hakem tarafından incelenecek, bilerek
  ya da bilmeyerek böyle bir şey yazma.
- **Web UI kuralı** (Yarışmacı Platformu Operasyon Rehberi): hakem heyeti
  imajını **komut satırından ÇALIŞTIRMAYACAK**, sadece kendi VM'lerindeki
  Web UI'dan "Execute" ile. Bu yüzden imajının Web UI akışıyla (build →
  Images panelinde görünme → Execute → "Live Output"ta `EXECUTION COMPLETED
  – status: SUCCESS` görünmesi) çalıştığını, VM erişimi geldiğinde erkenden
  elle test etmen çok değerli (platformda hazır bir test videosu var:
  `TOGG_MOBESE_FULL.mp4`).
- **Teslim öncesi:** Web UI'daki "Docker – Images" panelinde **yalnızca tek
  bir nihai imaj** bırakılmalı, deneme imajları silinmeli.

---

## 11. Ground Truth ile Doğrulama (elinde gerçek veri var — kullan)

- Faz 2 videosu (HLS): `https://teknofest-arge-turkcell.ercdn.net/hls/4/pZ/faz2/faz2.smil/playlist.m3u8`
  — `ffmpeg`/`ffprobe` ile indirip inceleyebilirsin.
- Aynı videonun ground truth'u (`faz2_gt.json`) elimizde — 34 olay, frame-
  accurate (olaylar görülebilir oldukları anda işaretlenmiş).
- **Model eğitimi gerektirmeyen, en yüksek getirili iş:** olayların **%41'i
  yolcu koltuk-atama** (`arka_koltuk_1/2`, `on_koltuk`) — bu saf geometri
  (`current_model_service.py`'deki `_yolcular`), stok `yolov8n-pose.pt`/kişi
  tespitiyle çalışıyor, kendi model eğitimi gerektirmiyor. Bunu doğru
  yapmak tek başına en çok puan getiren şey.
- **Model eğitimi gereken kısım (%47):** kemer, teknocan, sigara, telefon,
  su, kasa/renk/plaka — kendi eğitilmiş ağırlıklarınız zaten `ai/weights/`'te
  (taşıma sonrası) hazır, doğruluk kalitesi organizasyon eğitim verisi
  sağlamadığı için doğası gereği sınırlı — bu yüzden `thresholds.py`'deki
  eşiklerin GT ile ölçülerek ayarlanması önemli.
- Önerilen döngü: (1) batch imajını Faz 2 videosuyla çalıştır, (2) çıkan
  `results.json`'ı `faz2_gt.json` ile karşılaştıran basit bir skorlama
  scripti yaz (etiket + zaman toleransı), (3) `thresholds.py`'deki
  eşikleri buna göre ayarla — körlemesine değil veriye dayalı.
- **⚠️ Yeni bulgu (organizasyondan sözlü):** asıl risk düşük ışık değil,
  **parlak ışık + yansıma** (cam/far/ıslak zemin). Eşik ayarını/model
  testini bu senaryolarla da yap.

---

## 12. Test/Doğrulama Planı

1. Taşıma sonrası (Bölüm 2): mevcut 200+ test **değişmeden** geçmeli.
2. Yeni testler yaz: `tek_arac_bul`/`pad_ve_kirp` için (sahte/stub bir YOLO
   sonucu ile — `ai/tests/stubs.py`'deki mevcut stub kalıplarına bak, aynı
   üslup: `StubDetectionModel`, `StubBox` zaten var, doğrudan kullanılabilir).
3. `batch_main.py` için: küçük bir test videosuyla uçtan uca çalıştır,
   `results.json`'ın `ai/schemas/detection.py::SonucJson`'dan geçtiğini
   doğrula.
4. A6 düzeltmesi sonrası: Faz 2 videosuyla çalıştır, `arka_koltuk_2`'nin
   artık tek seferden fazla yayınlandığını doğrula.
5. Gerçek VM/Web UI erişimi geldiğinde: `TOGG_MOBESE_FULL.mp4` ile uçtan
   uca "Execute" denemesi — mümkün olduğunca erken (7 Ağustos test/dondurma
   gününden önce sürprizleri yakalamak için).

---

## 13. Sorular / Açık Noktalar

- **`STRIDE` değeri henüz seçilmedi** — gerçek donanımda (10 model çağrısı/
  kare × video uzunluğu) ölçülüp 10 dakikalık bütçeye göre belirlenmeli.
  Final günü videosunun uzunluğu bilinmiyor, güvenli tarafta kal.
- **Ağırlık dosyaları muhtemelen git'te değil** (büyük binary'ler için
  `.gitignore` kuralı var) — repo'yu çeken biri `ai/weights/` boş bulabilir.
  Ağırlıkları nasıl elden ele geçireceğinizi (paylaşımlı depolama, elle
  kopyalama, vs.) ekip içinde ayrıca konuşun; bu doküman bunu çözmüyor.
- Bir şey belirsizse veya bu dokümandaki bir bilgi kodla çelişiyorsa, önce
  kodu (yukarıdaki dosya/satır referansları) doğru kaynak say ve backend
  tarafıyla konuş — bu doküman tek doğruluk kaynağı olmaya çalışıyor ama
  kod her zaman son sözü söyler.
