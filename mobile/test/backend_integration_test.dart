// Video testi gerçek AI imajını tetikliyor (sahte çalıştırıcı yok), bu yüzden
// dakikalar sürebilir — 2 dakika yetmiyordu.
@Timeout(Duration(minutes: 5))
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
///
void main() {
  late bool backendAyakta;

  setUpAll(() async {
    backendAyakta = await _saglikKontrolu();
  });

  test('NV: login -> WebView yonlendirmesi -> verified', () async {
    if (!backendAyakta) return;
    final nv = NvService();

    final login = await nv.login(AppConfig.sandboxTestPhoneNumber);
    expect(login.success, isTrue, reason: login.errorMessage);
    expect(login.flowId, isNotNull);
    expect(login.authorizeUrl, isNotNull);

    // WebView açılmadan önce sonuç beklenmemeli.
    final ilkDurum = await nv.fetchStatus(login.flowId!);
    expect(ilkDurum.status, 'pending');

    // WebView'in yaptığının aynısı: authorize_url'i aç, yönlendirmeleri takip et.
    await _webViewGibiAc(login.authorizeUrl!);

    final sonDurum = await nv.fetchStatus(login.flowId!);
    expect(sonDurum.status, 'verified');
  });

  test('NV: bilinmeyen flow_id 404 -> error (yeniden giris istenir)', () async {
    if (!backendAyakta) return;
    final durum = await NvService().fetchStatus('boyle-bir-flow-yok');
    expect(durum.status, 'error');
    expect(durum.message, isNotNull);
  });

  test('NV: bozuk telefon formati (422) cokme yerine hata mesaji verir', () async {
    if (!backendAyakta) return;
    // Sözleşme § 2.1: E.164 dışı numara 422 döner (FastAPI `detail`i liste
    // olarak döndürür — String cast'i burada patlardı).
    final login = await NvService().login('05551234567');
    expect(login.success, isFalse);
    expect(login.errorMessage, isNotNull);
  });

  test('QoD: verified flow ile oturum acilir', () async {
    if (!backendAyakta) return;
    final flowId = await _dogrulanmisFlow();

    final oturum = await QodService().start(flowId);
    expect(oturum.outcome, QodOutcome.success);
    expect(oturum.sessionId, isNotNull);
  });

  test('Video: upload -> job -> polling sozlesmesi tutar', () async {
    if (!backendAyakta) return;
    final flowId = await _dogrulanmisFlow();
    final results = ResultsService();

    // Sahte gövde: burada sınanan şey AI'ın NE BULDUĞU değil,
    // upload -> job_id -> polling sözleşmesinin iki tarafta da tuttuğu.
    // Sahte AI çalıştırıcısı kaldırıldığından bu dosya gerçek imaja gidiyor
    // ve (beklendiği gibi) sıfır tespitle DONE dönüyor — tespit BEKLENMEZ.
    // Gerçek video ile uçtan uca doğrulama VM'de ayrıca yapılıyor (PLAN.md).
    final gecici = File('${Directory.systemTemp.path}/vst_t1_test_video.mp4')
      ..writeAsBytesSync(List<int>.filled(64 * 1024, 7));
    addTearDown(() => gecici.existsSync() ? gecici.deleteSync() : null);

    final yukleme = await results.uploadVideo(flowId: flowId, filePath: gecici.path);
    expect(yukleme.success, isTrue, reason: yukleme.errorMessage);
    expect(yukleme.jobId, isNotNull);

    // SessionController'ın periyodik polling'inin yaptığı iş.
    ({AiResultStatus status, AiResult? result, bool pollFailed})? sonuc;
    for (var i = 0; i < 90; i++) {
      sonuc = await results.fetchResult(yukleme.jobId!);
      if (sonuc.status != AiResultStatus.processing) break;
      await Future<void>.delayed(AppConfig.aiPollInterval);
    }

    // Sözleşme: iş kesin bir sonuca ulaşmalı, sonsuz PROCESSING'de kalmamalı.
    expect(sonuc!.status, isNot(AiResultStatus.processing));
    if (sonuc.status == AiResultStatus.done) {
      expect(sonuc.result, isA<AiResult>());
      expect(sonuc.result!.raw, isNotEmpty);
    }
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
  final login = await nv.login(AppConfig.sandboxTestPhoneNumber);
  await _webViewGibiAc(login.authorizeUrl!);
  return login.flowId!;
}
