import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
import '../models/ai_result.dart';
import '../models/nv_session.dart';
import '../models/qod_session.dart';
import '../services/api_client.dart';
import '../services/bandwidth_probe_service.dart';
import '../services/lifebox_service.dart';
import '../services/nv_service.dart';
import '../services/qod_service.dart';
import '../services/results_service.dart';
import '../services/trace_log.dart';
import '../services/video_recording_service.dart';

enum VideoStage { idle, recording, recorded, uploading, uploaded, failed }

/// Tüm final akışının tek gerçek kaynağı: NV -> QoD -> stream/kayıt -> upload
/// -> AI sonucu. mobile-integration.md'deki backend sözleşmesiyle birebir.
class SessionController extends ChangeNotifier {
  final NvService _nvService = NvService();
  final QodService _qodService = QodService();
  final VideoRecordingService _recordingService = VideoRecordingService();
  final ResultsService _resultsService = ResultsService();
  final LifeboxService _lifeboxService = LifeboxService();
  final BandwidthProbeService _bandwidthProbe = BandwidthProbeService();

  TraceLog get traceLog => ApiClient.instance.traceLog;

  NvSession nvSession = const NvSession();
  bool nvLoading = false;

  /// Login başarılı olup `authorize_url` gelince dolar; NvScreen bunu görüp
  /// WebView sheet'ini açar. Polling sonuçlanınca (verified/rejected/error/
  /// timeout) null'a döner — sheet bunu görüp kendini kapatır.
  String? pendingAuthorizeUrl;

  QodSession qodSession = const QodSession();
  bool qodLoading = false;
  BandwidthSample? bandwidthBefore;
  BandwidthSample? bandwidthAfter;
  bool bandwidthMeasuring = false;

  VideoStage videoStage = VideoStage.idle;
  Duration recordingElapsed = Duration.zero;
  int recordingBytes = 0;
  String? recordedFilePath;
  String? videoErrorMessage;

  String? _jobId;
  AiResultStatus aiStatus = AiResultStatus.idle;
  AiResult? aiResult;
  String? aiResultSha256;
  bool aiLoading = false;

  Future<void> submitPhoneNumber(String phoneNumber) async {
    nvLoading = true;
    nvSession = NvSession(status: NvStatus.pending, phoneNumber: phoneNumber);
    notifyListeners();

    final login = await _nvService.startLogin(phoneNumber);
    nvLoading = false;

    if (!login.success || login.flowId == null) {
      nvSession = NvSession(
        status: NvStatus.failed,
        phoneNumber: phoneNumber,
        errorMessage: login.errorMessage ?? 'Giriş başarısız',
      );
      notifyListeners();
      return;
    }

    nvSession = NvSession(status: NvStatus.pending, phoneNumber: phoneNumber, flowId: login.flowId);
    pendingAuthorizeUrl = login.authorizeUrl;
    notifyListeners();

    await _pollAuthStatus(login.flowId!, phoneNumber);
  }

  Future<void> _pollAuthStatus(String flowId, String phoneNumber) async {
    const maxAttempts = 60;
    for (var i = 0; i < maxAttempts; i++) {
      await Future.delayed(const Duration(seconds: 1));
      final result = await _nvService.checkStatus(flowId);

      switch (result.status) {
        case AuthPollStatus.verified:
          nvSession = NvSession(status: NvStatus.verified, phoneNumber: phoneNumber, flowId: flowId);
          pendingAuthorizeUrl = null;
          notifyListeners();
          return;
        case AuthPollStatus.rejected:
          nvSession = NvSession(
            status: NvStatus.failed,
            phoneNumber: phoneNumber,
            flowId: flowId,
            errorMessage: 'Numara bu cihazla eşleşmedi.',
          );
          pendingAuthorizeUrl = null;
          notifyListeners();
          return;
        case AuthPollStatus.error:
          final isWifiIssue = result.errorCode == kWifiErrorCode;
          nvSession = NvSession(
            status: NvStatus.failed,
            phoneNumber: phoneNumber,
            flowId: flowId,
            errorMessage: isWifiIssue
                ? 'Wi-Fi açık görünüyor — Wi-Fi\'yi kapatıp mobil veriyi açın ve tekrar deneyin.'
                : (result.message ?? 'Doğrulama hatası'),
          );
          pendingAuthorizeUrl = null;
          notifyListeners();
          return;
        case AuthPollStatus.notFound:
          nvSession = NvSession(
            status: NvStatus.failed,
            phoneNumber: phoneNumber,
            errorMessage: 'Oturum süresi doldu, tekrar deneyin.',
          );
          pendingAuthorizeUrl = null;
          notifyListeners();
          return;
        case AuthPollStatus.pending:
          continue;
      }
    }

    nvSession = NvSession(
      status: NvStatus.failed,
      phoneNumber: phoneNumber,
      flowId: flowId,
      errorMessage: 'Doğrulama zaman aşımına uğradı (60sn).',
    );
    pendingAuthorizeUrl = null;
    notifyListeners();
  }

  /// WebView sheet'indeki "İptal" butonu.
  void cancelPendingLogin() {
    pendingAuthorizeUrl = null;
    if (nvSession.status == NvStatus.pending) {
      nvSession = NvSession(
        status: NvStatus.failed,
        phoneNumber: nvSession.phoneNumber,
        flowId: nvSession.flowId,
        errorMessage: 'İptal edildi',
      );
    }
    notifyListeners();
  }

  Future<void> startQod() async {
    if (nvSession.flowId == null) return;
    qodLoading = true;
    bandwidthMeasuring = true;
    notifyListeners();

    // QoD'nin gerçek etkisini kanıtlamak için (şartname 4.1) aynı stream'den
    // önce/sonra gerçek bir indirme hızı örneği alınır — sahte sayı yok.
    bandwidthBefore = await _bandwidthProbe.probe(streamUrl);
    notifyListeners();

    qodSession = await _qodService.startSession(flowId: nvSession.flowId!);
    qodLoading = false;
    notifyListeners();

    await Future.delayed(const Duration(milliseconds: 800));
    bandwidthAfter = await _bandwidthProbe.probe(streamUrl);
    bandwidthMeasuring = false;
    notifyListeners();
  }

  Future<void> startRecording(String hlsUrl) async {
    videoStage = VideoStage.recording;
    recordingElapsed = Duration.zero;
    recordingBytes = 0;
    videoErrorMessage = null;
    notifyListeners();

    final result = await _recordingService.startRecording(
      hlsUrl: hlsUrl,
      onProgress: (elapsed, bytes) {
        recordingElapsed = elapsed;
        recordingBytes = bytes;
        notifyListeners();
      },
    );

    if (result.status == RecordingStatus.completed || result.status == RecordingStatus.cancelled) {
      videoStage = VideoStage.recorded;
      recordedFilePath = result.filePath;
    } else {
      videoStage = VideoStage.failed;
      videoErrorMessage = result.errorMessage;
    }
    notifyListeners();
  }

  Future<void> stopRecordingEarly() => _recordingService.stopRecording();

  Future<void> uploadAndTriggerAi() async {
    if (recordedFilePath == null || nvSession.flowId == null) return;
    videoStage = VideoStage.uploading;
    notifyListeners();

    final upload = await _resultsService.uploadVideo(
      flowId: nvSession.flowId!,
      filePath: recordedFilePath!,
    );

    if (upload.success) {
      _jobId = upload.jobId;
      videoStage = VideoStage.uploaded;
      aiStatus = AiResultStatus.processing;
    } else {
      videoStage = VideoStage.failed;
      videoErrorMessage = upload.errorMessage;
    }
    notifyListeners();
  }

  Future<void> shareToLifebox() async {
    if (recordedFilePath == null) return;
    await _lifeboxService.shareVideo(recordedFilePath!);
  }

  Future<void> refreshAiResult() async {
    if (_jobId == null) return;
    aiLoading = true;
    notifyListeners();
    final response = await _resultsService.fetchResult(_jobId!);
    aiStatus = response.status;
    if (response.result != null) {
      aiResult = response.result;
      aiResultSha256 = response.resultsSha256;
    }
    aiLoading = false;
    notifyListeners();
  }

  /// ÜST ÇUBUK "çıkış" butonu. NvScreen, `nvSession.isVerified` true kaldığı
  /// sürece otomatik olarak Home'a geri döner — bu yüzden çıkışta oturumun
  /// tamamen sıfırlanması şart (yoksa çıkış tuşu görünürde çalışmaz).
  void logout() {
    nvSession = const NvSession();
    nvLoading = false;
    pendingAuthorizeUrl = null;
    qodSession = const QodSession();
    qodLoading = false;
    bandwidthBefore = null;
    bandwidthAfter = null;
    bandwidthMeasuring = false;
    videoStage = VideoStage.idle;
    recordingElapsed = Duration.zero;
    recordingBytes = 0;
    recordedFilePath = null;
    videoErrorMessage = null;
    _jobId = null;
    aiStatus = AiResultStatus.idle;
    aiResult = null;
    aiResultSha256 = null;
    aiLoading = false;
    notifyListeners();
  }

  String get streamUrl => AppConfig.testHlsUrl;

  /// StepTimeline için 1..7 arası ilerleme göstergesi (01 Doğrula .. 07 İz).
  int get currentStepIndex {
    if (aiStatus == AiResultStatus.done) return 7;
    if (aiStatus != AiResultStatus.idle) return 6;
    if (videoStage == VideoStage.uploading || videoStage == VideoStage.uploaded) return 5;
    if (videoStage != VideoStage.idle) return 4;
    if (qodSession.status != QodStatus.idle) return 3;
    if (nvSession.isVerified) return 2;
    return 1;
  }
}
