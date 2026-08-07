import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../config/app_config.dart';
import '../models/ai_result.dart';
import '../models/nv_session.dart';
import '../models/qod_session.dart';
import '../models/recording_item.dart';
import '../services/api_client.dart';
import '../services/bandwidth_probe_service.dart';
import '../services/cellular_network_service.dart';
import '../services/hls_variant_service.dart';
import '../services/lifebox_service.dart';
import '../services/nv_service.dart';
import '../services/qod_service.dart';
import '../services/results_fingerprint.dart';
import '../services/results_service.dart';
import '../services/trace_log.dart';
import '../services/video_recording_service.dart';

/// Tüm final akışının tek gerçek kaynağı: NV -> QoD -> stream/kayıt -> upload
/// -> AI sonucu. Adımlar ve alan adları mobile-integration.md ile birebir;
/// UX Akış Kılavuzu'ndaki 01..07 adımlarıyla örtüşür.
///
/// Kayıt modeli: kullanıcı istediği kadar kayıt alır ([recordings]); her
/// kayıt bağımsız olarak Lifebox'a paylaşılabilir ya da backend'e yüklenip
/// kendi AI işine ([RecordingItem.jobId]) bağlanır. AI Sonucu sekmesi bu
/// listeden beslenir; seçilen işin sonucu detay olarak açılır.
class SessionController extends ChangeNotifier {
  final NvService _nvService = NvService();
  final QodService _qodService = QodService();
  final CellularNetworkService _cellular = CellularNetworkService();
  final VideoRecordingService _recordingService = VideoRecordingService();
  final ResultsService _resultsService;
  final LifeboxService _lifeboxService = LifeboxService();
  final BandwidthProbeService _bandwidthProbe = BandwidthProbeService();
  final HlsVariantService _hlsVariants = HlsVariantService();

  TraceLog get traceLog => ApiClient.instance.traceLog;

  NvSession nvSession = const NvSession();
  bool nvLoading = false;

  QodSession qodSession = const QodSession();
  bool qodLoading = false;
  BandwidthSample? bandwidthBefore;
  BandwidthSample? bandwidthAfter;
  bool bandwidthMeasuring = false;

  // ---- Kayıt durumu -------------------------------------------------------
  bool recording = false;
  Duration recordingElapsed = Duration.zero;
  String? recordingError;
  final List<RecordingItem> recordings = [];

  /// Son kayıtta ölçülen bant genişliğine göre seçilen HLS varyantı
  /// (şartname 4.2). UI bunu göstererek "en uygun kaliteyi seçtik"i
  /// kanıtlayabilir; null = henüz seçim yapılmadı ya da çözülemedi.
  HlsVariant? secilenVaryant;

  // ---- AI durumu ----------------------------------------------------------
  bool aiLoading = false;

  /// Arka arkaya kaç AI sonuç sorgusunun backend'e ULAŞAMADIĞI. Başarılı her
  /// sorguda sıfırlanır. Ekran bunu kullanıp "AI çalışıyor" ile "bağlantı
  /// koptu"yu ayırt eder — ikisi aynı görünürse kullanıcı kopmuş bir
  /// bağlantıyı dakikalarca "işleniyor" sanıp bekler (6 Ağustos hatası).
  int ardisikAiPollHatasi = 0;

  /// Tek bir dalgalanma paniğe yol açmasın diye eşik: 3 ardışık başarısız
  /// sorgu (~6 sn, poll aralığı 2 sn) sonrası bağlantı sorunu bildirilir.
  static const _baglantiSorunuEsigi = 3;

  bool get aiBaglantiSorunu => ardisikAiPollHatasi >= _baglantiSorunuEsigi;

  /// AI Sonucu sekmesinde detayı açık olan iş; null = liste görünümü.
  String? selectedJobId;

  /// Sonuç PROCESSING olduğu sürece periyodik otomatik sorgu — kullanıcı
  /// yenile butonuna basmak zorunda kalmaz (sözleşme 2.6: polling).
  Timer? _aiPollTimer;

  bool _disposed = false;

  /// [resultsService] yalnızca testler için enjekte edilir; uygulamada
  /// varsayılan (paylaşılan `ApiClient`'a bağlı) örnek kullanılır.
  SessionController({ResultsService? resultsService})
      : _resultsService = resultsService ?? ResultsService() {
    _loadExistingRecordings();
  }

  @override
  void dispose() {
    _disposed = true;
    _aiPollTimer?.cancel();
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  static String _basename(String path) => path.split(RegExp(r'[/\\]')).last;

  // ---------------------------------------------------------------------------
  // 01 — Number Verification (login + WebView + status polling)
  // ---------------------------------------------------------------------------

  Future<void> submitPhoneNumber(String phoneNumber) async {
    nvLoading = true;
    nvSession = NvSession(status: NvStatus.idle, phoneNumber: phoneNumber);
    _notify();

    // Önceki denemeden kalmış olabilecek BAYAT hücresel bağlamayı temizle.
    // Bayat bağlama uygulamanın tüm ağını öldürüyor: login isteği bile
    // çıkamıyor ve kullanıcı "connection failed" görüyor, oysa backend
    // sağlam (7 Ağustos gecesi tarayıcıdan /health açılıyorken uygulama
    // bağlanamıyordu). Bağlama yoksa bu çağrı no-op.
    await _cellular.unbind();

    final login = await _nvService.login(phoneNumber);
    if (!login.success) {
      nvLoading = false;
      nvSession = NvSession(
        status: NvStatus.failed,
        phoneNumber: phoneNumber,
        errorMessage: login.errorMessage ?? 'Giriş başlatılamadı',
      );
      _notify();
      return;
    }

    // NvScreen authorize_url'i görüp WebView'i açar (Turkcell'in onay sayfası,
    // hücresel ağ üzerinden); sonucu aşağıdaki status polling'i bekler.
    nvSession = NvSession(
      status: NvStatus.authorizing,
      phoneNumber: phoneNumber,
      flowId: login.flowId,
      authorizeUrl: login.authorizeUrl,
    );
    nvLoading = false;
    _notify();

    // NV, hücresel veri bağlantısı üzerinden doğrulanır (şartname + sözleşme 3).
    // Android'de process'i geçici olarak SIM ağına bağlarız — WebView trafiği
    // de bu bağlamadan geçer. Diğer platformlarda no-op.
    await _cellular.bindToCellular();
    try {
      await _pollNvStatus(login.flowId!, phoneNumber);
    } finally {
      // KOŞULSUZ unbind. Eskiden `if (bound)` şartı vardı: Dart 3 sn'de pes
      // edip false alırsa unbind ATLANIYORDU, ama native taraf saniyeler
      // sonra bağlamayı yapıyordu → bağlama kalıcı asılı kalıyor, bayatlayınca
      // uygulamanın tüm ağı ölüyordu (7 Ağustos arızası).
      await _cellular.unbind();
    }
  }

  Future<void> _pollNvStatus(String flowId, String phoneNumber) async {
    final deadline = DateTime.now().add(AppConfig.nvPollTimeout);

    while (DateTime.now().isBefore(deadline)) {
      await Future.delayed(AppConfig.nvPollInterval);
      if (_disposed || nvSession.flowId != flowId) return; // logout/yeni deneme

      final result = await _nvService.fetchStatus(flowId);
      switch (result.status) {
        case 'verified':
          await _startFreshSession();
          nvSession = nvSession.copyWith(status: NvStatus.verified);
          _notify();
          return;
        case 'rejected':
          nvSession = nvSession.copyWith(
            status: NvStatus.rejected,
            errorMessage: 'Numara bu cihazla eşleşmedi',
          );
          _notify();
          return;
        case 'error':
          nvSession = nvSession.copyWith(
            status: NvStatus.failed,
            errorCode: result.errorCode,
            errorMessage: result.message ?? 'Doğrulama hatası',
          );
          _notify();
          return;
        default:
          break; // pending — pollemeye devam
      }
    }

    // Sözleşme 2.3: 60 sn'de sonuç yoksa timeout; kullanıcı yeniden başlatır.
    if (nvSession.flowId == flowId) {
      nvSession = nvSession.copyWith(
        status: NvStatus.failed,
        errorMessage: 'Doğrulama zaman aşımına uğradı — yeniden deneyin',
      );
      _notify();
    }
  }

  /// Her başarılı NV sonrası çağrılır (yeni giriş ya da aynı numarayla
  /// tekrar deneme fark etmez): cihazdaki önceki kayıtlar diskten SİLİNİR,
  /// liste ve seçili iş sıfırlanır. Demo/test sırasında Home ve AI Sonucu
  /// hep temiz açılsın diye — logout() bunu zaten yapıyordu ama yalnızca
  /// bellekte; disk üzerindeki .mp4 dosyaları kalıyordu ve uygulama yeniden
  /// açıldığında ([_loadExistingRecordings]) geri geliyordu.
  Future<void> _startFreshSession() async {
    await _recordingService.deleteAllRecordings();
    if (_disposed) return;
    recordings.clear();
    selectedJobId = null;
  }

  // ---------------------------------------------------------------------------
  // 03 — Quality on Demand
  // ---------------------------------------------------------------------------

  Future<void> startQod() async {
    final flowId = nvSession.flowId;
    if (flowId == null) return;
    qodLoading = true;
    bandwidthMeasuring = true;
    _notify();

    // QoD'nin gerçek etkisini kanıtlamak için (şartname 4.1) aynı stream'den
    // önce/sonra gerçek bir indirme hızı örneği alınır — sahte sayı yok.
    bandwidthBefore = await _bandwidthProbe.probe(streamUrl);
    _notify();

    qodSession = await _qodService.start(flowId);
    qodLoading = false;
    _notify();

    await Future.delayed(const Duration(milliseconds: 800));
    bandwidthAfter = await _bandwidthProbe.probe(streamUrl);
    bandwidthMeasuring = false;
    _notify();
  }

  // ---------------------------------------------------------------------------
  // 04 — Stream kaydı (sınırsız: her kayıt listeye eklenir)
  // ---------------------------------------------------------------------------

  Future<void> _loadExistingRecordings() async {
    final files = await _recordingService.listExistingRecordings();
    if (_disposed || files.isEmpty) return;
    for (final f in files) {
      if (recordings.any((r) => r.path == f.path)) continue;
      DateTime zaman;
      int? boyut;
      try {
        final stat = await f.stat();
        zaman = stat.modified;
        boyut = stat.size;
      } catch (_) {
        zaman = DateTime.now();
      }
      recordings.add(RecordingItem(
        path: f.path,
        name: _basename(f.path),
        createdAt: zaman,
        sizeBytes: boyut,
      ));
    }
    recordings.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    _notify();
  }

  Future<void> startRecording(String hlsUrl) async {
    if (recording) return;
    recording = true;
    recordingElapsed = Duration.zero;
    recordingError = null;
    secilenVaryant = null;
    _notify();

    final result = await _recordingService.startRecording(
      hlsUrl: await _kayitKaynagi(hlsUrl),
      onProgress: (elapsed) {
        recordingElapsed = elapsed;
        _notify();
      },
    );

    recording = false;
    final tamam = result.status == RecordingStatus.completed ||
        result.status == RecordingStatus.cancelled;
    if (tamam && result.filePath != null) {
      final item = RecordingItem(
        path: result.filePath!,
        name: _basename(result.filePath!),
        createdAt: DateTime.now(),
        duration: recordingElapsed,
      );
      await _fillSize(item);
      recordings.insert(0, item);
    } else if (result.status == RecordingStatus.failed) {
      recordingError = result.errorMessage ?? 'Kayıt başarısız';
    }
    _notify();
  }

  /// Şartname 4.2: kayıt, bağlantı kalitesine EN UYGUN varyanttan alınmalıdır —
  /// ffmpeg'e master playlist verilirse her koşulda en yüksek çözünürlüğü
  /// seçer ve QoD'siz 256 kbit'lik hatta 1080p indirmek ~68 dakika sürer.
  ///
  /// Seçim **QoD durumuna** bakar, bant genişliği ölçümüne değil: yarışma
  /// SIM'inde ara bir hız yok (QoD'siz 256 kbit, QoD'li 8 Mbit), dolayısıyla
  /// ölçmenin bir şeyi değiştirdiği bir senaryo yok. Ayrıca ölçüm QoD'siz
  /// durumda zaten zaman aşımına düşüyordu ve "ölçüm yok" hâli en yükseği
  /// seçtiriyordu — yani ölçüme dayanmak tam da yanlış anda yanlış kararı
  /// veriyordu.
  ///
  /// Çözümleme yapılamazsa master URL'e düşeriz — kayıt hiç başlamamaktansa
  /// ffmpeg kendi seçsin.
  Future<String> _kayitKaynagi(String masterUrl) async {
    final variant = await _hlsVariants.resolveVariant(
      masterUrl,
      qodAktif: qodSession.succeeded,
    );
    if (variant == null) return masterUrl;

    secilenVaryant = variant;
    _notify();
    return variant.url;
  }

  Future<void> _fillSize(RecordingItem item) async {
    if (kIsWeb) return;
    try {
      item.sizeBytes = await File(item.path).length();
    } catch (_) {/* boyut kritik değil */}
  }

  Future<void> stopRecordingEarly() => _recordingService.stopRecording();

  // ---------------------------------------------------------------------------
  // 05 — Kayıt başına upload / Lifebox
  // ---------------------------------------------------------------------------

  Future<void> uploadRecording(RecordingItem item) async {
    final flowId = nvSession.flowId;
    if (flowId == null ||
        item.uploadState == UploadState.uploading ||
        item.uploaded) {
      return;
    }
    item.uploadState = UploadState.uploading;
    item.uploadError = null;
    _notify();

    final upload = await _resultsService.uploadVideo(
      flowId: flowId,
      filePath: item.path,
    );

    if (upload.success && upload.jobId != null) {
      item.uploadState = UploadState.uploaded;
      item.jobId = upload.jobId;
      item.aiStatus = AiResultStatus.processing;
      item.processingStartedAt = DateTime.now();
      _scheduleAiPoll();
    } else {
      item.uploadState = UploadState.failed;
      item.uploadError = upload.errorMessage;
    }
    _notify();
  }

  Future<void> shareToLifebox(RecordingItem item) async {
    if (kIsWeb) return; // web önizlemede paylaşım menüsü yok
    await _lifeboxService.shareVideo(item.path);
  }

  // ---------------------------------------------------------------------------
  // 06 — AI sonuçları (iş başına)
  // ---------------------------------------------------------------------------

  /// Backend'e yüklenmiş (AI işi açılmış) kayıtlar — AI sekmesinin listesi.
  List<RecordingItem> get uploadedJobs =>
      recordings.where((r) => r.jobId != null).toList();

  RecordingItem? get selectedRecording {
    for (final r in recordings) {
      if (r.jobId == selectedJobId) return r;
    }
    return null;
  }

  void selectJob(String jobId) {
    selectedJobId = jobId;
    _notify();
  }

  void clearSelectedJob() {
    selectedJobId = null;
    _notify();
  }

  /// PROCESSING durumundaki tüm işleri sorgular; biten işlerin sonucunu ve
  /// SHA256'sını kaydeder (sözleşme adım 8/17).
  Future<void> refreshAiResults() async {
    final beklemede = recordings
        .where((r) => r.jobId != null && r.aiStatus == AiResultStatus.processing)
        .toList();
    if (beklemede.isEmpty) return;

    aiLoading = true;
    _notify();
    var turdaHataVar = false;
    try {
      for (final r in beklemede) {
        final response = await _resultsService.fetchResult(r.jobId!);
        if (response.pollFailed) {
          // Backend'e ulaşılamadı: mevcut durumu KORU (yanlışlıkla FAILED
          // yazmıyoruz), sadece sorunu kaydet — polling aşağıda yeniden
          // planlanıyor, ağ düzelince sonuç kendiliğinden gelir.
          turdaHataVar = true;
          continue;
        }
        r.aiStatus = response.status;
        if (response.result != null) {
          r.aiResult = response.result;
          // Parmak izi BİR KEZ, sonuç geldiği anda hesaplanır (ekran her
          // çizilişinde değil). Lifebox'a yüklenecek metnin ta kendisinden
          // üretiliyor — dosya ile hash'in ayrışması mümkün değil.
          final parmakIzi = ResultsFingerprint.of(response.result!.raw);
          r.resultsJsonMinified = parmakIzi.json;
          r.resultsMd5 = parmakIzi.md5Hex;
          r.resultsSha256 =
              sha256.convert(utf8.encode(parmakIzi.json)).toString();
        }
      }
    } catch (e) {
      // Savunma katmanı: fetchResult artık kendi istisnalarını yutuyor, ama
      // buradaki bir istisna (ör. sha256/jsonEncode) aşağıdaki finally
      // olmadan `_scheduleAiPoll()`'u atlatır ve polling'i SONSUZA DEK
      // öldürürdü — ekran "işleniyor"da donardı.
      turdaHataVar = true;
      debugPrint('AI sonucu sorgusunda beklenmeyen hata: $e');
    } finally {
      ardisikAiPollHatasi = turdaHataVar ? ardisikAiPollHatasi + 1 : 0;

      // Kendi kendini onarma: ısrarlı bağlantı hatasının bilinen bir sebebi,
      // NV'den kalan bayat hücresel bağlamanın uygulamanın tüm ağını
      // öldürmesi. Eşiğe gelindiğinde BİR KEZ temizlemeyi dene — bağlama
      // yoksa zararsız no-op, varsa arıza kendiliğinden düzelir.
      if (ardisikAiPollHatasi == _baglantiSorunuEsigi) {
        unawaited(_cellular.unbind());
      }

      aiLoading = false;
      _notify();

      if (recordings.any((r) => r.aiStatus == AiResultStatus.processing)) {
        _scheduleAiPoll();
      }
    }
  }

  void _scheduleAiPoll() {
    _aiPollTimer?.cancel();
    // Sözleşme § 2.6: 1-2 sn arayla polle.
    _aiPollTimer = Timer(AppConfig.aiPollInterval, () {
      if (_disposed) return;
      refreshAiResults();
    });
  }

  static String _sonucDosyaAdi(RecordingItem item) =>
      'results_${item.name.replaceAll('.mp4', '')}.json';

  /// results.json'u dışa aktarır: Android'de dosya olarak paylaşım menüsüne
  /// (Drive/WhatsApp/Dosyalar -> indirme), web önizlemede panoya. Dönen metin
  /// kullanıcıya snackbar ile gösterilir.
  ///
  /// İçerik **boşluksuz** yazılır — organizasyonun istediği biçim bu ve
  /// parmak izi de tam olarak bu metinden üretiliyor.
  Future<String> exportResultsJson(RecordingItem item) async {
    final jsonStr = item.resultsJsonMinified;
    if (jsonStr == null) return 'Henüz sonuç yok';
    if (kIsWeb) {
      await Clipboard.setData(ClipboardData(text: jsonStr));
      return 'results.json panoya kopyalandı (web önizleme)';
    }
    await _lifeboxService.shareJson(
      fileName: _sonucDosyaAdi(item),
      content: jsonStr,
    );
    return 'results.json paylaşım menüsünde — Dosyalar\'a veya Drive\'a kaydedebilirsin';
  }

  /// results.json + MD5 parmak izini **tek paylaşımda** Lifebox'a gönderir.
  ///
  /// Canlı demoda video'dan sonraki ikinci (ve son) Lifebox adımı: AI sonucu
  /// geldiğinde hakem bu ikisini birlikte indirip hash'i doğrulayabilsin.
  Future<String> shareResultsBundle(RecordingItem item) async {
    final jsonStr = item.resultsJsonMinified;
    final hash = item.resultsMd5;
    if (jsonStr == null || hash == null) return 'Henüz sonuç yok';
    if (kIsWeb) {
      await Clipboard.setData(ClipboardData(text: '$jsonStr\n$hash'));
      return 'Sonuç ve parmak izi panoya kopyalandı (web önizleme)';
    }
    await _lifeboxService.shareResultsWithHash(
      jsonFileName: _sonucDosyaAdi(item),
      jsonIcerik: jsonStr,
      hash: hash,
    );
    return 'results.json + MD5 paylaşım menüsünde — Lifebox\'ı seçin';
  }

  /// ÜST ÇUBUK "çıkış" butonu. NvScreen, `nvSession.isVerified` true kaldığı
  /// sürece otomatik olarak Home'a geri döner — bu yüzden çıkışta oturumun
  /// tamamen sıfırlanması şart (yoksa çıkış tuşu görünürde çalışmaz).
  void logout() {
    _aiPollTimer?.cancel();
    // Kayıt sürerken çıkılırsa ffmpeg arkaplanda çalışmaya devam etmesin.
    if (recording) {
      _recordingService.stopRecording();
    }
    // QoD oturumunu kapatmayı dene (en iyi çaba, sonucu beklemiyoruz).
    // Oturum bitene kadar aynı cihaz için ikinci oturum açılamıyor (409) ve
    // süre 20 dakika: kullanıcı çıkıp yeniden girerse temiz başlayabilmeli.
    // Ayrıca hücresel bağlamayı da bırak — asılı kalırsa uygulamanın tüm
    // ağını öldürüyor (bkz. cellular_network_service.dart).
    final cikanFlowId = nvSession.flowId;
    if (cikanFlowId != null) {
      unawaited(_qodService.stop(cikanFlowId));
    }
    unawaited(_cellular.unbind());

    nvSession = const NvSession();
    nvLoading = false;
    qodSession = const QodSession();
    qodLoading = false;
    bandwidthBefore = null;
    bandwidthAfter = null;
    bandwidthMeasuring = false;
    recording = false;
    recordingElapsed = Duration.zero;
    recordingError = null;
    recordings.clear();
    selectedJobId = null;
    aiLoading = false;
    _notify();
    // Dosyalar cihazda duruyor — yeni oturumda liste yeniden taransın.
    _loadExistingRecordings();
  }

  /// Kayıt alınacak HLS akışının adresi.
  ///
  /// Final günü organizasyon FARKLI bir adres verecek (protokol aynı, yalnızca
  /// base'den sonrası değişiyor) ve bunu canlı demoda, uygulamayı yeniden
  /// derlemeden girebilmemiz gerekiyor — bu yüzden sabit değil, çalışma
  /// zamanında değiştirilebilir bir alan. Başlangıç değeri `--dart-define`
  /// ile de verilebiliyor (bkz. [AppConfig.testHlsUrl]).
  String _streamUrl = AppConfig.testHlsUrl;

  String get streamUrl => _streamUrl;

  /// Varsayılan (Faz 2 test) akışında mıyız — UI "varsayılana dön" butonunu
  /// buna göre etkinleştirir.
  bool get streamUrlVarsayilan => _streamUrl == AppConfig.testHlsUrl;

  void setStreamUrl(String url) {
    final temiz = url.trim();
    if (temiz.isEmpty || temiz == _streamUrl) return;
    _streamUrl = temiz;
    // Yeni akışın varyantları farklı olabilir; önceki seçim artık geçersiz.
    secilenVaryant = null;
    _notify();
  }

  void streamUrlVarsayilanaDon() => setStreamUrl(AppConfig.testHlsUrl);

  /// Girilen adres HLS gibi mi görünüyor? `null` = sorun yok.
  ///
  /// Yumuşak doğrulama: kaydı ENGELLEMEZ, yalnızca uyarır. Final günü
  /// beklemediğimiz bir biçim gelirse uygulamanın kilitlenmesini istemiyoruz.
  static String? streamUrlUyarisi(String url) {
    final temiz = url.trim();
    if (temiz.isEmpty) return 'Adres boş olamaz';
    final uri = Uri.tryParse(temiz);
    if (uri == null || !uri.hasScheme || !(uri.isScheme('http') || uri.isScheme('https'))) {
      return 'Adres http:// veya https:// ile başlamalı';
    }
    if (!temiz.contains('.m3u8')) {
      return 'HLS playlist adresleri genelde .m3u8 ile biter — emin misin?';
    }
    return null;
  }

  /// StepTimeline için 1..7 arası ilerleme göstergesi (01 Doğrula .. 07 İz).
  int get currentStepIndex {
    final anyDone = recordings.any((r) => r.aiStatus == AiResultStatus.done);
    final anyAi = recordings.any((r) => r.aiStatus != AiResultStatus.idle);
    final anyUpload = recordings.any((r) =>
        r.uploadState == UploadState.uploading ||
        r.uploadState == UploadState.uploaded);
    if (anyDone) return 7;
    if (anyAi) return 6;
    if (anyUpload) return 5;
    if (recording || recordings.isNotEmpty) return 4;
    if (qodSession.outcome != QodOutcome.idle) return 3;
    if (nvSession.isVerified) return 2;
    return 1;
  }
}
