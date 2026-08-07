import 'package:dio/dio.dart';

/// SADECE TEST İÇİN — backend'e giden istekleri (özellikle video yüklemesini)
/// yapay olarak yavaşlatır, yarışma SIM'inin gerçek hızını (256 kbit/8 Mbit)
/// simüle etmek için. `AppConfig.testUploadThrottleKbps > 0` iken
/// `api_client.dart`'ta koşullu olarak eklenir — varsayılan build'de bu
/// interceptor hiç yaratılmaz.
///
/// **Bayt-bayt gerçek bir hız sınırlaması DEĞİLDİR** — istek gövdesinin
/// toplam boyutunu (`FormData.length`, zaten Content-Length için Dio'da
/// hesaplanıyor) hedef `kbps`'e bölüp bunun ne kadar süreceğini hesaplar,
/// gerçek istek o süreden daha kısada bitmişse aradaki farkı TEK bir
/// `Future.delayed` ile ekler. İlerleme çubuğunu adım adım yavaşlatmaz —
/// amaç bu değil zaten: "yavaş bir yüklemede zaman aşımı/AI-poll
/// dayanıklılığı/QoD süresi dolması gibi senaryolar gerçekten çalışıyor mu"
/// sorusuna cevap vermek, ki toplam duvar-saati süresi doğru simüle edildiği
/// sürece bu sorular test edilebilir.
///
/// **Pratik not:** düşük `kbps` + büyük bir video ile hesaplanan gecikme
/// gerçekçi ama UZUN olabilir (ör. 256 kbit'te 137 MB ~71 dakika) — hızlı
/// bir doğruluk testi için küçük bir test videosu ya da daha yüksek bir
/// `kbps` kullanın, tam 256 kbit simülasyonunu bilerek uzun sürecek bir
/// tek seferlik provaya saklayın.
class TestThrottleInterceptor extends Interceptor {
  final int kbps;

  const TestThrottleInterceptor(this.kbps);

  static const _baslangicAnahtari = '_test_throttle_baslangic';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.extra[_baslangicAnahtari] = DateTime.now();
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) async {
    await _bekle(response.requestOptions);
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    await _bekle(err.requestOptions);
    handler.next(err);
  }

  Future<void> _bekle(RequestOptions options) async {
    if (kbps <= 0) return;
    final baslangic = options.extra[_baslangicAnahtari] as DateTime?;
    if (baslangic == null) return;

    final gonderilenBayt = _govdeBoyutu(options.data);
    if (gonderilenBayt <= 0) return;

    final hedefSaniye = (gonderilenBayt * 8) / (kbps * 1000);
    final gecenSaniye = DateTime.now().difference(baslangic).inMicroseconds / 1e6;
    final kalanSaniye = hedefSaniye - gecenSaniye;
    if (kalanSaniye > 0) {
      await Future.delayed(Duration(milliseconds: (kalanSaniye * 1000).round()));
    }
  }

  int _govdeBoyutu(dynamic data) {
    if (data is FormData) return data.length;
    if (data is List<int>) return data.length;
    if (data is String) return data.length;
    return 0;
  }
}
