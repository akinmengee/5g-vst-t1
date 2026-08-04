@Timeout(Duration(minutes: 2))
library;

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teknofest_mobile/config/app_config.dart';
import 'package:teknofest_mobile/models/ai_result.dart';
import 'package:teknofest_mobile/models/qod_session.dart';
import 'package:teknofest_mobile/services/nv_service.dart';
import 'package:teknofest_mobile/services/qod_service.dart';
import 'package:teknofest_mobile/services/results_service.dart';

/// Uygulamanın GERÇEK servis kodunu GERÇEK backend'e karşı çalıştırır —
/// sözleşmenin iki tarafının da tuttuğunu kanıtlayan tek test budur.
///
/// Backend ayakta değilse testler atlanır (takım arkadaşlarında ve CI'da
/// kırmızı görünmesin diye):
///
/// ```
/// cd backend
/// JOB_STORAGE_PATH=./.local-jobs USE_MOCK_5G=true python -m uvicorn app.main:app --port 8000
/// cd ../mobile && flutter test test/backend_integration_test.dart
/// ```
void main() {
  late bool backendAyakta;

  setUpAll(() async {
    backendAyakta = await _saglikKontrolu();
  });

  test('NV: login -> WebView yonlendirmesi -> verified', () async {
    if (!backendAyakta) return;
    final nv = NvService();

    final login = await nv.startLogin(AppConfig.sandboxTestPhoneNumber);
    expect(login.success, isTrue, reason: login.errorMessage);
    expect(login.flowId, isNotNull);
    expect(login.authorizeUrl, isNotNull);

    // WebView açılmadan önce sonuç beklenmemeli.
    final ilkDurum = await nv.checkStatus(login.flowId!);
    expect(ilkDurum.status, AuthPollStatus.pending);

    // WebView'in yaptığının aynısı: authorize_url'i aç, yönlendirmeleri takip et.
    await _webViewGibiAc(login.authorizeUrl!);

    final sonDurum = await nv.checkStatus(login.flowId!);
    expect(sonDurum.status, AuthPollStatus.verified);
  });

  test('NV: bilinmeyen flow_id 404 -> notFound', () async {
    if (!backendAyakta) return;
    final durum = await NvService().checkStatus('boyle-bir-flow-yok');
    expect(durum.status, AuthPollStatus.notFound);
  });

  test('NV: bozuk telefon formati (422) cokme yerine hata mesaji verir', () async {
    if (!backendAyakta) return;
    // Sözleşme § 2.1: E.164 dışı numara 422 döner. FastAPI 422'de `detail`i
    // String değil LİSTE olarak döndürür — String'e cast etmek burada
    // patlardı, bu testin asıl konusu o.
    final login = await NvService().startLogin('05551234567');
    expect(login.success, isFalse);
    expect(login.errorMessage, isNotNull);
  });

  test('QoD: verified flow ile oturum acilir', () async {
    if (!backendAyakta) return;
    final flowId = await _dogrulanmisFlow();

    final oturum = await QodService().startSession(flowId: flowId);
    expect(oturum.status, QodStatus.requested);
    expect(oturum.sessionId, isNotNull);
  });

  test('Video: upload -> polling -> DONE + results ayristirilir', () async {
    if (!backendAyakta) return;
    final flowId = await _dogrulanmisFlow();
    final results = ResultsService();

    final gecici = File('${Directory.systemTemp.path}/vst_t1_test_video.mp4')
      ..writeAsBytesSync(List<int>.filled(64 * 1024, 7));
    addTearDown(() => gecici.existsSync() ? gecici.deleteSync() : null);

    final yukleme = await results.uploadVideo(flowId: flowId, filePath: gecici.path);
    expect(yukleme.success, isTrue, reason: yukleme.errorMessage);
    expect(yukleme.jobId, isNotNull);

    // SessionController'ın periyodik polling'inin yaptığı iş.
    FetchResultResponse? sonuc;
    for (var i = 0; i < 20; i++) {
      sonuc = await results.fetchResult(yukleme.jobId!);
      if (sonuc.status != AiResultStatus.processing) break;
      await Future<void>.delayed(AppConfig.aiPollInterval);
    }

    expect(sonuc!.status, AiResultStatus.done);
    expect(sonuc.result, isA<AiResult>());
    expect(sonuc.result!.detections, isNotEmpty);
    expect(sonuc.resultsSha256, hasLength(64));
  });

  test('Video: bilinmeyen job_id sonsuz polling yerine FAILED verir', () async {
    if (!backendAyakta) return;
    final sonuc = await ResultsService().fetchResult('boyle-bir-job-yok');
    expect(sonuc.status, AiResultStatus.failed);
  });

  tearDownAll(() {
    if (!backendAyakta) {
      // ignore: avoid_print
      print(
        'ATLANDI: ${AppConfig.backendBaseUrl} adresinde backend bulunamadi. '
        'Entegrasyon testleri icin once backend calistirilmali.',
      );
    }
  });
}

Future<bool> _saglikKontrolu() async {
  try {
    final resp = await Dio().get(
      '${AppConfig.backendBaseUrl}/health',
      options: Options(receiveTimeout: const Duration(seconds: 2)),
    );
    return resp.statusCode == 200;
  } catch (_) {
    return false;
  }
}

/// WebView'in yaptığı tek şey: adresi aç ve yönlendirmeleri takip et.
Future<void> _webViewGibiAc(String authorizeUrl) async {
  await Dio().get(
    authorizeUrl,
    options: Options(followRedirects: true, validateStatus: (_) => true),
  );
}

Future<String> _dogrulanmisFlow() async {
  final nv = NvService();
  final login = await nv.startLogin(AppConfig.sandboxTestPhoneNumber);
  await _webViewGibiAc(login.authorizeUrl!);
  return login.flowId!;
}
