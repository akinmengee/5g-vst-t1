import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teknofest_mobile/models/ai_result.dart';
import 'package:teknofest_mobile/models/recording_item.dart';
import 'package:teknofest_mobile/services/results_service.dart';
import 'package:teknofest_mobile/state/session_controller.dart';

/// 6 Ağustos arızasının SessionController tarafı.
///
/// Gerçekte olan: telefon backend'e ulaşamaz hale geldi, AI ise arka planda
/// işi bitirdi (`status: DONE`). Bağlantı düzeldiğinde uygulamanın sonucu
/// yakalaması gerekirdi. Buradaki testler kopma → düzelme senaryosunu ve
/// "polling döngüsü asla sessizce ölmemeli" kuralını kilitliyor.

class _SahteAdapter implements HttpClientAdapter {
  final Future<ResponseBody> Function(RequestOptions options) _cevapla;
  _SahteAdapter(this._cevapla);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) =>
      _cevapla(options);

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Map<String, dynamic> govde, int kod) => ResponseBody.fromString(
      jsonEncode(govde),
      kod,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

/// Testin adım adım senaryo yazabildiği, çağrı sayan sahte backend.
class _SahteBackend {
  int cagriSayisi = 0;
  late Future<ResponseBody> Function(RequestOptions) davranis;

  Dio get dio => Dio(BaseOptions(baseUrl: 'http://test.local'))
    ..httpClientAdapter = _SahteAdapter((options) {
      cagriSayisi++;
      return davranis(options);
    });
}

RecordingItem _isleniyorKayit(String jobId) {
  final item = RecordingItem(
    path: '/tmp/kayit.mp4',
    name: 'kayit.mp4',
    createdAt: DateTime(2026, 8, 7, 1, 4),
  );
  item.jobId = jobId;
  item.uploadState = UploadState.uploaded;
  item.aiStatus = AiResultStatus.processing;
  item.processingStartedAt = DateTime(2026, 8, 7, 1, 4);
  return item;
}

Map<String, dynamic> get _doneGovde => {
      'status': 'DONE',
      'results': {
        'video_id': 'video.mp4',
        'arac_bilgisi': {
          'tip': 'suv',
          'plaka': '34TC8532',
          'renk': 'siyah',
          'confidence_score': 0.96,
        },
        'tespitler': [
          {
            'zaman_saniye': 0.6,
            'kategori': 'sofor_eylemi',
            'etiket': 'esneme',
            'confidence_score': 0.75,
          },
        ],
      },
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _SahteBackend backend;
  late SessionController controller;

  setUp(() {
    backend = _SahteBackend();
    controller = SessionController(resultsService: ResultsService(dio: backend.dio));
  });

  tearDown(() => controller.dispose());

  test('ağ koptuğunda iş YANLIŞLIKLA "başarısız" işaretlenmez', () async {
    backend.davranis = (options) => throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
        );
    final item = _isleniyorKayit('job-1');
    controller.recordings.add(item);

    await controller.refreshAiResults();

    // Kritik: AI hâlâ çalışıyor olabilir; ulaşamamak "AI başarısız" demek
    // değildir. Durum korunmalı ki bağlantı düzelince sonuç yakalansın.
    expect(item.aiStatus, AiResultStatus.processing);
    expect(item.aiResult, isNull);
  });

  test('ardışık hata sayacı artar; eşiği geçince bağlantı sorunu bildirilir',
      () async {
    backend.davranis = (options) => throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
        );
    controller.recordings.add(_isleniyorKayit('job-1'));

    expect(controller.aiBaglantiSorunu, isFalse, reason: 'başlangıçta sorun yok');

    await controller.refreshAiResults();
    expect(controller.ardisikAiPollHatasi, 1);
    expect(controller.aiBaglantiSorunu, isFalse, reason: 'tek dalgalanma panik değil');

    await controller.refreshAiResults();
    await controller.refreshAiResults();

    expect(controller.ardisikAiPollHatasi, 3);
    expect(controller.aiBaglantiSorunu, isTrue,
        reason: '3 ardışık başarısızlıkta ekran artık "işliyor" demeyi bırakmalı');
  });

  test('bağlantı düzelince sonuç yakalanır ve sayaç sıfırlanır', () async {
    // 6 Ağustos senaryosunun aynısı: önce kopukluk, sonra backend DONE diyor.
    backend.davranis = (options) => throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
        );
    final item = _isleniyorKayit('job-1');
    controller.recordings.add(item);

    await controller.refreshAiResults();
    await controller.refreshAiResults();
    await controller.refreshAiResults();
    expect(controller.aiBaglantiSorunu, isTrue);
    expect(item.aiStatus, AiResultStatus.processing);

    // Ağ geri geldi — AI bu arada işi çoktan bitirmişti.
    backend.davranis = (_) async => _json(_doneGovde, 200);
    await controller.refreshAiResults();

    expect(item.aiStatus, AiResultStatus.done);
    expect(item.aiResult!.vehicleInfo!.plaka, '34TC8532');
    expect(item.resultsSha256, isNotNull, reason: 'sonuç gelince SHA256 hesaplanır');
    expect(controller.ardisikAiPollHatasi, 0, reason: 'başarılı sorguda sıfırlanır');
    expect(controller.aiBaglantiSorunu, isFalse);
  });

  test('bozuk gövde polling döngüsünü ÖLDÜRMEZ, sonraki tur sonucu alır',
      () async {
    // Eski kod: fetchResult'tan DioException olmayan bir istisna sızıyordu,
    // refreshAiResults ortada patlıyordu ve sondaki _scheduleAiPoll() hiç
    // çalışmıyordu → ekran sonsuza dek "işleniyor"da donuyordu.
    backend.davranis = (_) async => _json({
          'status': 'DONE',
          'results': ['beklenmeyen', 'sekil'],
        }, 200);
    final item = _isleniyorKayit('job-1');
    controller.recordings.add(item);

    await controller.refreshAiResults(); // istisna DIŞARI sızmamalı
    expect(item.aiStatus, AiResultStatus.processing);
    expect(controller.ardisikAiPollHatasi, 1);

    backend.davranis = (_) async => _json(_doneGovde, 200);
    await controller.refreshAiResults();

    expect(item.aiStatus, AiResultStatus.done,
        reason: 'döngü hayatta kaldığı için sonraki tur sonucu yakaladı');
  });

  test('404 (job kayboldu/TTL doldu) kalıcı başarısızlıktır, sonsuz polling yok',
      () async {
    backend.davranis = (_) async => _json({'detail': 'job_id bulunamadı'}, 404);
    final item = _isleniyorKayit('eski-job');
    controller.recordings.add(item);

    await controller.refreshAiResults();

    expect(item.aiStatus, AiResultStatus.failed);
    expect(controller.ardisikAiPollHatasi, 0,
        reason: '404 bir bağlantı sorunu değil, kesin cevaptır');
  });

  test('birden fazla iş: biri biterken diğeri işlemeye devam eder', () async {
    final biten = _isleniyorKayit('job-biten');
    final devam = _isleniyorKayit('job-devam');
    controller.recordings.addAll([biten, devam]);

    backend.davranis = (options) async => options.path.contains('job-biten')
        ? _json(_doneGovde, 200)
        : _json({'status': 'PROCESSING'}, 200);

    await controller.refreshAiResults();

    expect(biten.aiStatus, AiResultStatus.done);
    expect(devam.aiStatus, AiResultStatus.processing);
    expect(controller.ardisikAiPollHatasi, 0);
  });
}
