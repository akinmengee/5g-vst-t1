# VST T1 — Akıllı Yol Güvenliği: Final Yarışma Entegrasyon Planı

## Özet (TL;DR)

- **Ne yapıyoruz:** ÖTR'de tasarladığımız edge+cloud+5G mimarisini, FTR'de teslim ettiğimiz çalışan AI pipeline'ını (`predict.py`) temel alarak, **7-9 Ağustos 2026'daki yüz yüze final yarışması için gerçekten çalışan, canlı bir sisteme** dönüştürüyoruz.
- **Mimari (özet):** Flutter mobil (mevcut `yolov8n.pt` ile edge araç tespiti → kırpılmış ROI + bbox metadata) → **WebSocket** → FastAPI backend (QoD/Number Verification şimdilik mock, `predict.py`'nin mantığı incremental/gerçek-zamanlı hale getirilmiş) → sonuçlar/uyarılar mobile geri döner.
- **Sıra:** Önce backend (mobilin göndereceği veriyi taklit eden mock veriyle), mobil edge geliştirmesi sonraki fazda — ama aralarındaki veri sözleşmesi en baştan netleştiriliyor ki ikisi birbirinden kopuk gelişmesin.
- **En büyük tekil iş/risk:** `predict.py`'deki "tüm videoyu işleyip sonunda tek JSON dön" mantığının, kare geldikçe olay yayınlayan gerçek **incremental/streaming** bir yapıya dönüştürülmesi (bilinçli olarak seçildi, riski kabul edildi).
- **5G API'leri (Number Verification, QoD) ve bulut ortamı yarışma günü/son anda verilecek, önceden test edilemiyor** — bu yüzden ikisi de arayüz (interface) arkasında, tek bir ortam değişkeniyle mock↔gerçek arası değiştirilebilecek şekilde tasarlanıyor.
- **Takvim:** Gün 0-1 iskelet+sözleşme, Gün 2-3 yürüyen iskelet (mock uçtan uca), Gün 4-7 asıl mühendislik (incremental refactor + model entegrasyonu + bilinen hataların düzeltilmesi), Gün 8-9 sağlamlaştırma/eşik ayarı/prova, yarışma günü gerçek 5G API'lerin ve (varsa) bulutun takılması.
- **Neden bu şekilde:** ÖTR'de mimari 92/100 ile övüldü, FTR'de rapor 90/100 ama kod sadece 19/100 aldı — yani ekibin güçlü yanı tasarım, zayıf yanı kodu sağlam yazmak. Bu plan bilinçli olarak kod kalitesini ve gerçek çalışırlığı önceliklendiriyor.

## Context

Takım (VST T1, Teknofest "5G & Yapay Zekâ ile Akıllı Yol Güvenliği Yarışması") ÖTR ve FTR aşamalarını tamamladı. **Final Yarışma Etabı 7-9 Ağustos 2026'da yüz yüze** yapılacak (bugün 30 Temmuz 2026 — ~8-10 gün kaldı).

Üç dokümanın (ÖTR, FTR, FTR-Docker-spec) karşılaştırmasından çıkan durum:

- **ÖTR'de** önerilen mimari: Flutter mobil (edge YOLOv8 Nano ile araç/plaka tespiti) → araç tespit edilince Turkcell 5G Open Gateway **QoD API**'si tetiklenip bant genişliği talep edilir → ROI, WebSocket ile FastAPI/Docker bulut sunucusuna gider → sunucuda YOLOv8 Small + yolov8n-face + PaddleOCR + ByteTrack paralel çalışır. Number Verification API ile sessiz kimlik doğrulama.
- **FTR'de fiilen teslim edilen** ise bunun hiçbirini içermeyen, tek parça (monolitik) bir offline video-işleme pipeline'ı (YOLOv8 + MediaPipe + LSTM + özel plaka karakter modeli) — çünkü FTR'nin otomatik değerlendirme ortamı (izole Docker, internet yok, tek video dosyası) buna zaten izin vermiyordu.
- Sonuç: **AI/CV pipeline'ı tek başına test edilip kanıtlanmış durumda** (mAP %85-93, slalom LSTM %99.26) ama **mobil+backend+5G entegrasyonu hiç kurulmamış, hiç test edilmemiş.**

Ek kısıtlar:
- Final round'un canlı demo formatına dair resmi kural henüz organizasyon tarafından yazılı paylaşılmadı; **3 Ağustos 2026 Pazartesi saat 11:00'de bir bilgilendirme toplantısı** planlandı. Takımın kendi tahmini/beklentisi: telefon kamerasıyla canlı akan trafik görüntüsü üzerinde, **Flutter mobil uygulama içinde gerçek zamanlı (on-device) yapay zekâ modelleriyle** ROI ve araç içi alan tespiti yapılması, Number Verification kullanılması ve modelin canlı ortamdaki başarısını gösteren basit bir dashboard sunulması bekleniyor. Bu bir tahmin, toplantı sonrası netleşecek — ama takım toplantıyı beklemeden geliştirmeye devam etme kararında.
- **Number Verification ve QoD API'leri yarışma günü verilecek**, önceden test edilemez (organizasyon, takımların sandbox'ı önceden "patlatmasını" önlemek istiyor). Her takıma bir **SIM kart** verilecek.
- **Backend için bulut sağlanacağı söylendi ama detay/toplantı yok** — şimdilik yerelde (laptop + Docker) geliştirilip, bulut bilgisi geldiğinde aynı image'ın deploy edilmesi planlanıyor.
- Mevcut modellerin doğrulukları şüpheli (organizasyon eğitim veri seti sağlamadı, takım kendi veri setini oluşturmak zorunda kaldı). Ağırlık dosyaları paylaşıldı (bkz. envanter); bunlar "template/placeholder" modeller olarak ele alınacak, yeni modellerin eğitimi AI/CV ekip arkadaşlarının sorumluluğunda.
- Takım tercihi: ÖTR'deki tam edge+cloud+5G vizyonunu sürdürmek. **Mobilde gerçek edge inference (mevcut `yolov8n.pt` ile "araç var mı" tespiti) kesinleşmiş bir tasarım kararı** — WebSocket/QoD üzerinden tüm görüntü yerine sadece ilgili ROI'yi göndererek hem gecikmeyi hem ağ yükünü azaltmak, hem de event-driven mimarinin işlevsel olarak anlamlı olmasını sağlamak amacıyla (bkz. Mimari Kararlar madde 6). Ancak **sprint 1'de mobil kod yazılmayacak**: bunun yerine mobilin üreteceği veriyi (kırpılmış ROI görüntüsü + bbox/metadata) taklit eden bir mock/fixture oluşturulup önce backend ayağa kaldırılacak; mobil geliştirmesi sonraki fazda başlayacak.

Ek netleşen noktalar:
- **ÖTR ve FTR birer kapanmış aşama** — takım bunların mimarisini birebir tekrar etmek zorunda değil, final için mimari değişikliğe gidilebilir. Organizasyonun asıl beklediği: **hedeflenen doğruluk/performans oranlarını sağlayan, çalışan uçtan uca bir pipeline.**
- **Puanlama geçmişi önemli bir ders veriyor:** ÖTR'den 100 üzerinden 92 alındı (mimari "çok özgün, çok güzel" bulundu); FTR'den 200 üzerinden 109 alındı — bunun 90/100'ü rapor puanıyken, sadece **19/100'ü kod puanıydı**. Yani takımın güçlü yanı tasarım/mimari fikirleri, zayıf yanı bunları sağlam ve çalışan koda dökmek. **Bu plan bilinçli olarak kod kalitesini ve gerçekten uçtan uca çalışırlığı, ek tasarım zarafetinden önce önceliklendirir.**
- **WebSocket + olay-tetiklemeli ("agentic") yapı, ÖTR'de özellikle övülen ve puan getiren unsur** — takım bunu final için bilinçli olarak koruyup (verilecek QoD ile) güçlendirmek istiyor. Bu artık "opsiyonel/sadeleştirilebilir" bir parça değil, korunacak bir güç noktası.
- **Final için 10 dakikalık bir sunum yapılacak** (sistemi anlatan) — muhtemelen "en iyi mimari" gibi bir değerlendirme kategorisi de var. Plan ve kod, "neden bu şekilde" sorusuna net cevap verecek şekilde tutulmalı.
- **Mobil platform kararı: Flutter'da kalınıyor.** Gerekçe: iki platforma (Android+iOS) birden çıkabilme altyapısının değerli olması ve ekibin zaten Flutter'a hazırlanmış olması. Takımda Swift tecrübesi olan üye olduğu için, Flutter'da ciddi bir tıkanma yaşanırsa native iOS/Swift **yedek plan** olarak belgeleniyor, şu an aktif değil.
- **Model envanteri:** `yolov8n.pt`, `yolov8s.pt`, `yolov8n-pose.pt`, `yolov8s-cls.pt`, `kasa_modeli.pt`, `renk_modeli.pt`, `plaka_modeli.pt`, `karakter_modeli.pt`, `kemer_v3.pt`, `sigara_v1.pt`, `su_v2.pt`, `telefon_temiz_v1.pt`, `teknocan.pt`, `slalom_lstm.pt`, `face_landmarker.task` (MediaPipe).
- **Yerel geliştirme donanımı:** 6 GB VRAM, i7 10. nesil, 32 GB RAM'li laptop — bu envanterdeki modeller (hepsi nano/small ölçekli) için geliştirme/test amaçlı yeterli.

**Amaç:** 8-10 günde, gerçek 5G API'leri ve nihai modeller gelmeden önce **uçtan uca çalışan bir iskelet** kurmak; öyle ki bu iki parça geldiğinde koda dokunmadan/minimum dokunuşla "tık diye" yerlerine oturabilsin.

## Mimari Kararlar

1. **FastAPI (backend) + Flutter (mobile)** — onaylandı, değişmiyor. Native Swift/iOS, Flutter'da ciddi bir tıkanma çıkarsa devreye girecek belgelenmiş bir yedek plan.
2. **Sprint 1'de backend önce, mobil mock ile taklit edilir — mobil gerçek edge inference çalıştıracak (bkz. madde 6), ama kodu sonraki fazda yazılacak.**
3. **Değişken/dış bağımlılıklar arayüz (interface) arkasına alınır, Dependency Injection ile enjekte edilir:**
   - `VehicleAnalysisService` (Protocol/ABC) — modeller güncellendiğinde sadece implementasyon değişir.
   - `OpenGatewayClient` (Protocol/ABC) — `MockOpenGatewayClient` / `TurkcellOpenGatewayClient`, `USE_MOCK_5G` env var ile seçilir.
   - Deploy hedefi (yerel Docker / bulut) tamamen ortam değişkenleriyle yönetilir.
4. **Docker'dan başlanır.**
5. **WebSocket, ÖTR'de özellikle övülen mimarinin bir parçası — bilinçli olarak korunuyor.** Redis hâlâ opsiyonel.
6. **Uç (mobil) model tasarımı:** Mobil, her karede `yolov8n.pt` ile "araç var mı" tespiti yapar. Araç yoksa hiçbir şey gönderilmez. Araç varsa: kırpılmış tek görüntü + tam kareye göre bbox koordinatları (slalom trajectory için) WebSocket'ten gönderilir, aynı anda QoD tetiklenir. Backend bu ROI'ye bugünkü `predict.py`'nin tam kareye yaptığı her şeyi neredeyse değişmeden uygular.
7. **Backend'deki alt modellerin paralel/sıralı dağılımı** ampirik olarak ölçülecek (Gün 4-7).
8. **Tespit başına doğrulama/oylama eşikleri** yapılandırılabilir olmalı (`ARDISIK_GEREK`, `KEMER_GEREK`, `PLATO_GEREK`, vb.) — config'e taşınacak, "sweet spot" test edilerek bulunacak.
9. **Batch → canlı akış: tam incremental refactor** (mikro-batch değil) — bilinçli seçildi, risk kabul edildi, en büyük tekil mühendislik kalemi.

## Repo Yapısı

```
backend/
  app/
    main.py, core/config.py, api/(routes_health, routes_inference),
    schemas/(detection.py, mobile_contract.py),
    fixtures/mock_mobile_payloads/,
    services/vehicle_ai/(interface.py, current_model_service.py, _ftr_reference/),
    services/network/(interface.py, mock_client.py, turkcell_client.py, factory.py)
  weights/, Dockerfile, requirements.txt
mobile/        # Flutter — sonraki faz
docs/
  integration-notes.md
```

## Kod İncelemesi Bulguları (paylaşılan predict.py / main.py / utils.py)

1. **`run_inference` tamamen batch/offline** — video bitince tek JSON döner. Kare-başına mantık artımlı, doğrudan taşınabilir; ama zamansal post-processing (`ardisik_seg`, `esneme_seg`, `bakinma_seg`, cooldown) sadece video sonunda çalışıyor — incremental hale getirilecek (madde 9).
2. **`main.py`'nin çökme-güvenliği model yükleme hatalarına karşı çalışmıyor** — modeller import anında yükleniyor, try/except sadece `run_inference()` çağrısını sarıyor.
3. **Aynı YOLO dedektörü kare başına 2-3 kez çalışıyor** — optimizasyon fırsatı.
4. **`WEIGHTS_DIR` cwd'ye göre göreli** — `MODEL_DIR` env var'a bağlanacak.
5. **Araç başına hafıza sözlükleri hiç temizlenmiyor** — canlı serviste TTL/eviction gerekiyor.
6. **Senkron/bloklayan ağır hesaplama** — thread pool/ayrı worker'da çalıştırılmalı.
7. **Anti-cheat hatırlatması:** `USE_MOCK_5G` bilinçli bir deploy config'i, ortam tespiti değil — ama canlı demoda gerçek 5G çağrısı başarısız olursa sessizce mock'a düşülmemeli.

## Öncelik Sıralı Yapım Planı

- **Gün 0-1:** İskelet + veri sözleşmesi + mock mobil veri üreticisi + 3 Ağustos toplantısına katılım.
- **Gün 2-3:** Yürüyen iskelet — mock veri → WebSocket → stub JSON, uçtan uca boru hattı kanıtlanır.
- **Gün 4-7:** Asıl mühendislik — tam incremental refactor + gerçek model entegrasyonu + bilinen hataların düzeltilmesi + paralel/sıralı deney.
- **Gün 8-9:** Sağlamlaştırma, eşik ayarı, gerçek telefonda test, kuru provalar, sunum hazırlığı.
- **Yarışma günü:** `USE_MOCK_5G=false`, gerçek Turkcell entegrasyonu, (varsa) bulut deploy.

## Risk Kaydı

- 5G API'leri hiç önceden test edilemiyor → arayüz arkasında mock, risk azaltıldı ama yarışma günü sürpriz olabilir.
- Bulut ortamı belirsiz → Docker + env-var config ile taşınabilirlik sağlandı, yerel yedek hazır tutulmalı.
- Model kalitesi sınırlı → yapılandırılabilir oylama eşikleriyle telafi; demo senaryosu en güvenilir 1-2 tespit etrafında kurulmalı.
- Final round kuralları resmi değil → 3 Ağustos sonrası plan revize edilebilir.
- **Tam incremental refactor en büyük risk** → Gün 4-7'ye yeterli zaman ayrılmalı, günlük takip edilmeli.

## Doğrulama Planı

- Mock/gerçek implementasyonların aynı arayüzü sağladığını gösteren birim testler.
- Backend çıktısının ftr-docker-spec JSON şemasıyla birebir eşleştiğini doğrulayan şema testi.
- Yerel Docker container ile uçtan uca `docker run` testi.
- Gerçek telefonda canlı deneme.
- Yarışmadan önce en az bir tam kuru prova.
- Incremental refactor'ın orijinal batch versiyonuyla aynı sonuçları ürettiğini doğrulayan karşılaştırma testi.
