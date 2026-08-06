import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teknofest_mobile/models/ai_result.dart';
import 'package:teknofest_mobile/services/results_service.dart';

/// 6 Ağustos gecesi yaşanan gerçek arıza için regresyon testleri.
///
/// Olay: backend işi 7 dakikada bitirip `{"status":"DONE"}` dönmeye başladı,
/// ama telefon o sırada backend'e ULAŞAMIYORDU. Sorgular ağ seviyesinde
/// düşüyordu (VM loglarında bu isteklerin izi bile yok). Mobil taraf 404
/// dışındaki HER hatayı "hâlâ işleniyor" saydığı için ekran, kopmuş bir
/// bağlantıyı 10+ dakika boyunca "AI videoyu işliyor" olarak gösterdi.
///
/// Buradaki testler iki şeyi kilitliyor:
///   1. Başarısız sorgu, "işleniyor"dan AYIRT EDİLEBİLİR olmalı (pollFailed).
///   2. Hiçbir istisna servisten DIŞARI sızmamalı — sızarsa
///      SessionController'daki polling döngüsü sessizce ölür.

/// Testin verdiği cevabı/hatayı aynen döndüren sahte ağ katmanı.
/// (Yeni paket gerektirmez: dio'nun kendi HttpClientAdapter arayüzü.)
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

Dio _dioWith(Future<ResponseBody> Function(RequestOptions) cevapla) {
  return Dio(BaseOptions(baseUrl: 'http://test.local'))
    ..httpClientAdapter = _SahteAdapter(cevapla);
}

ResponseBody _json(Map<String, dynamic> govde, int kod) => ResponseBody.fromString(
      jsonEncode(govde),
      kod,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

void main() {
  group('fetchResult — başarısız sorgu "işleniyor"dan ayrılabiliyor', () {
    test('ağ hatası (cevap YOK): pollFailed=true, durum processing korunur', () async {
      final servis = ResultsService(
        dio: _dioWith((options) => throw DioException(
              requestOptions: options,
              type: DioExceptionType.connectionError,
              error: 'Network is unreachable',
            )),
      );

      final sonuc = await servis.fetchResult('job-1');

      // Kritik: eskiden pollFailed diye bir bilgi YOKTU, çağıran bunu
      // gerçek bir "işleniyor" sanıyordu.
      expect(sonuc.pollFailed, isTrue);
      expect(sonuc.status, AiResultStatus.processing);
      expect(sonuc.result, isNull);
    });

    test('bağlantı zaman aşımı da pollFailed sayılır', () async {
      final servis = ResultsService(
        dio: _dioWith((options) => throw DioException(
              requestOptions: options,
              type: DioExceptionType.connectionTimeout,
            )),
      );

      final sonuc = await servis.fetchResult('job-1');

      expect(sonuc.pollFailed, isTrue);
      expect(sonuc.status, AiResultStatus.processing);
    });

    test('500 (backend results.json parse edemedi) pollFailed sayılır', () async {
      final servis = ResultsService(
        dio: _dioWith((_) async => _json({'detail': 'results.json okunamadı'}, 500)),
      );

      final sonuc = await servis.fetchResult('job-1');

      expect(sonuc.pollFailed, isTrue);
      expect(sonuc.status, AiResultStatus.processing);
    });

    test('404 pollFailed DEĞİL — kalıcı hata, polling durmalı', () async {
      final servis = ResultsService(
        dio: _dioWith((_) async => _json({'detail': 'job_id bulunamadı'}, 404)),
      );

      final sonuc = await servis.fetchResult('yok-boyle-job');

      expect(sonuc.status, AiResultStatus.failed);
      expect(sonuc.pollFailed, isFalse);
    });
  });

  group('fetchResult — başarılı yollar bozulmadı', () {
    test('PROCESSING: pollFailed=false (gerçekten işleniyor)', () async {
      final servis = ResultsService(
        dio: _dioWith((_) async => _json({'status': 'PROCESSING'}, 200)),
      );

      final sonuc = await servis.fetchResult('job-1');

      expect(sonuc.status, AiResultStatus.processing);
      expect(sonuc.pollFailed, isFalse, reason: 'gerçek PROCESSING hata değildir');
      expect(sonuc.result, isNull);
    });

    test('DONE: sonuç ayrıştırılır (VM\'den gelen gerçek gövde şekli)', () async {
      final servis = ResultsService(
        dio: _dioWith((_) async => _json({
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
            }, 200)),
      );

      final sonuc = await servis.fetchResult('job-1');

      expect(sonuc.status, AiResultStatus.done);
      expect(sonuc.pollFailed, isFalse);
      expect(sonuc.result!.vehicleInfo!.plaka, '34TC8532');
      expect(sonuc.result!.detections, hasLength(1));
      expect(sonuc.result!.detections.first.etiket, 'esneme');
    });

    test('FAILED: backend AI hatasını bildirdi', () async {
      final servis = ResultsService(
        dio: _dioWith((_) async => _json({'status': 'FAILED'}, 200)),
      );

      final sonuc = await servis.fetchResult('job-1');

      expect(sonuc.status, AiResultStatus.failed);
      expect(sonuc.pollFailed, isFalse);
    });
  });

  group('fetchResult — hiçbir istisna DIŞARI sızmamalı', () {
    // Sızarsa SessionController.refreshAiResults ortada patlar ve sondaki
    // _scheduleAiPoll() hiç çalışmaz: polling sonsuza dek ölür, ekran donar.

    test('beklenmeyen gövde şekli (results bir liste) çökertmez', () async {
      final servis = ResultsService(
        dio: _dioWith((_) async => _json({
              'status': 'DONE',
              'results': ['beklenmeyen', 'sekil'],
            }, 200)),
      );

      final sonuc = await servis.fetchResult('job-1');

      expect(sonuc.pollFailed, isTrue);
      expect(sonuc.status, AiResultStatus.processing);
    });

    test('JSON olmayan gövde (ör. proxy HTML hata sayfası) çökertmez', () async {
      final servis = ResultsService(
        dio: _dioWith((_) async => ResponseBody.fromString(
              '<html><body>502 Bad Gateway</body></html>',
              200,
              headers: {
                Headers.contentTypeHeader: ['text/html'],
              },
            )),
      );

      final sonuc = await servis.fetchResult('job-1');

      expect(sonuc.pollFailed, isTrue);
      expect(sonuc.status, AiResultStatus.processing);
    });

    test('gövde tamamen boş olsa bile çökertmez', () async {
      final servis = ResultsService(
        dio: _dioWith((_) async => ResponseBody.fromString('', 200, headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType],
            })),
      );

      final sonuc = await servis.fetchResult('job-1');

      expect(sonuc.pollFailed, isTrue);
      expect(sonuc.status, AiResultStatus.processing);
    });
  });
}
