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
import '../services/lifebox_service.dart';
import '../services/nv_service.dart';
import '../services/qod_service.dart';
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
  final ResultsService _resultsService = ResultsService();
  final LifeboxService _lifeboxService = LifeboxService();
  final BandwidthProbeService _bandwidthProbe = BandwidthProbeService();

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

  // ---- AI durumu ----------------------------------------------------------
  bool aiLoading = false;

  /// AI Sonucu sekmesinde detayı açık olan iş; null = liste görünümü.
  String? selectedJobId;

  /// Sonuç PROCESSING olduğu sürece periyodik otomatik sorgu — kullanıcı
  /// yenile butonuna basmak zorunda kalmaz (sözleşme 2.6: polling).
  Timer? _aiPollTimer;

  bool _disposed = false;

  SessionController() {
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

    // authorize_url varsa NvScreen bunu görüp WebView'i açar; polling her iki
    // durumda da (mock/gerçek) aynı şekilde sonucu bekler.
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
    final bound = await _cellular.bindToCellular();
    try {
      await _pollNvStatus(login.flowId!, phoneNumber);
    } finally {
      if (bound) await _cellular.unbind();
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
    _notify();

    final result = await _recordingService.startRecording(
      hlsUrl: hlsUrl,
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
    for (final r in beklemede) {
      final response = await _resultsService.fetchResult(r.jobId!);
      r.aiStatus = response.status;
      if (response.result != null) {
        r.aiResult = response.result;
        r.resultsSha256 = sha256
            .convert(utf8.encode(jsonEncode(response.result!.raw)))
            .toString();
      }
    }
    aiLoading = false;
    _notify();

    if (recordings.any((r) => r.aiStatus == AiResultStatus.processing)) {
      _scheduleAiPoll();
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

  /// results.json'u dışa aktarır: Android'de dosya olarak paylaşım menüsüne
  /// (Drive/WhatsApp/Dosyalar -> indirme), web önizlemede panoya. Dönen metin
  /// kullanıcıya snackbar ile gösterilir.
  Future<String> exportResultsJson(RecordingItem item) async {
    final raw = item.aiResult?.raw;
    if (raw == null) return 'Henüz sonuç yok';
    final jsonStr = const JsonEncoder.withIndent('  ').convert(raw);
    if (kIsWeb) {
      await Clipboard.setData(ClipboardData(text: jsonStr));
      return 'results.json panoya kopyalandı (web önizleme)';
    }
    final dosyaAdi = 'results_${item.name.replaceAll('.mp4', '')}.json';
    await _lifeboxService.shareJson(fileName: dosyaAdi, content: jsonStr);
    return 'results.json paylaşım menüsünde — Dosyalar\'a veya Drive\'a kaydedebilirsin';
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

  String get streamUrl => AppConfig.testHlsUrl;

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
