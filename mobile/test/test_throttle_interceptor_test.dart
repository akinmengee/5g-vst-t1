import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teknofest_mobile/services/test_throttle_interceptor.dart';

/// 7 Ağustos: yarışma SIM'inin gerçek hızını (256 kbit/8 Mbit) test SIM'imiz
/// çok hızlı olduğu için göremiyoruz. Bu interceptor yalnızca --dart-define
/// ile açıkça istenirse yükleme isteklerini yapay olarak yavaşlatıyor.
/// Gerçek ağ yok — küçük bir gövde + göreceli olarak yüksek bir kbps seçilip
/// testin saniyeler içinde bitmesi sağlandı (tam 256 kbit ile 137 MB'lık bir
/// gövdeyi burada denemek testi dakikalarca sürdürürdü).
void main() {
  test('kbps=0 iken hicbir gecikme eklemez', () async {
    final adapter = _AninAdapter(govdeBoyutu: 1000 * 1000); // 1 MB
    final dio = Dio()..httpClientAdapter = adapter;
    dio.interceptors.add(const TestThrottleInterceptor(0));

    final sw = Stopwatch()..start();
    await dio.post('https://ornek.local/upload', data: 'x' * (1000 * 1000));
    sw.stop();

    expect(sw.elapsed, lessThan(const Duration(milliseconds: 300)));
  });

  test('hesaplanan gecikme govde boyutu / hedef kbpsye gore dogru', () async {
    // 100 KB gövde, 2000 kbit/s hedef -> (100*1000*8)/(2000*1000) = 0.4 sn.
    const govdeBoyutu = 100 * 1000;
    final adapter = _AninAdapter(govdeBoyutu: govdeBoyutu);
    final dio = Dio()..httpClientAdapter = adapter;
    dio.interceptors.add(const TestThrottleInterceptor(2000));

    final sw = Stopwatch()..start();
    await dio.post('https://ornek.local/upload', data: 'x' * govdeBoyutu);
    sw.stop();

    expect(sw.elapsed.inMilliseconds, greaterThanOrEqualTo(380));
    expect(sw.elapsed.inMilliseconds, lessThan(800));
  });

  test('istek zaten hedeften YAVAŞ tamamlandiysa ekstra gecikme eklemez', () async {
    // Adapter'in kendisi 500ms sürüyor; hedef süre yalnızca 50ms olsun ->
    // interceptor'un eklediği ekstra bekleme ~0 olmalı, toplam süre 500ms'e
    // yakın kalmalı, 500ms+50ms'e ZIPLAMAMALI.
    const govdeBoyutu = 10 * 1000; // hedef: (10*1000*8)/(1600*1000)=0.05sn
    final adapter = _AninAdapter(
      govdeBoyutu: govdeBoyutu,
      gecikme: const Duration(milliseconds: 500),
    );
    final dio = Dio()..httpClientAdapter = adapter;
    dio.interceptors.add(const TestThrottleInterceptor(1600));

    final sw = Stopwatch()..start();
    await dio.post('https://ornek.local/upload', data: 'x' * govdeBoyutu);
    sw.stop();

    expect(sw.elapsed.inMilliseconds, lessThan(700));
  });

  test('hata durumunda da (onError) gecikme uygulanir, istisna yutulmaz', () async {
    const govdeBoyutu = 50 * 1000; // hedef: (50*1000*8)/(1000*1000)=0.4sn
    final adapter = _HataliAdapter();
    final dio = Dio()..httpClientAdapter = adapter;
    dio.interceptors.add(const TestThrottleInterceptor(1000));

    final sw = Stopwatch()..start();
    await expectLater(
      dio.post('https://ornek.local/upload', data: 'x' * govdeBoyutu),
      throwsA(isA<DioException>()),
    );
    sw.stop();

    expect(sw.elapsed.inMilliseconds, greaterThanOrEqualTo(350));
  });
}

class _AninAdapter implements HttpClientAdapter {
  _AninAdapter({required this.govdeBoyutu, this.gecikme});
  final int govdeBoyutu;
  final Duration? gecikme;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (gecikme != null) await Future.delayed(gecikme!);
    return ResponseBody.fromString('ok', 200);
  }

  @override
  void close({bool force = false}) {}
}

class _HataliAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) =>
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
      );

  @override
  void close({bool force = false}) {}
}
