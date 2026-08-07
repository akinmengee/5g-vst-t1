import 'package:dio/dio.dart';

import 'hls_variant_service.dart';

class BandwidthSample {
  final int bytes;
  final Duration elapsed;

  const BandwidthSample({required this.bytes, required this.elapsed});

  double get mbps {
    final seconds = elapsed.inMicroseconds / 1e6;
    if (seconds <= 0) return 0;
    return (bytes * 8 / 1e6) / seconds;
  }
}

/// QoD'nin gerçek etkisini "kanıtlamak" (şartname 4.1) için, aynı HLS
/// akışının bir segmentini indirip süresini/hızını ölçer — QoD öncesi ve
/// sonrası bu ölçüm tekrarlanarak gerçek bir önce/sonra karşılaştırması elde
/// edilir. Simüle sayı üretmez: ölçüm başarısız olursa null döner ve UI o
/// örneği göstermez.
///
/// Ölçüm **yalnızca gösterim/kanıt** amaçlıdır; kayıt varyantı seçimi QoD
/// durumuna bakar (bkz. [HlsVariantService.selectForQod]).
///
/// **Segment boyutu [preferHighest]'e göre seçilir.** Önceden her zaman
/// master playlist'teki ilk satır (en yüksek varyant) kullanılıyordu: 1080p
/// segmenti 2.29 MB ve QoD'siz 256 kbit/s'lik hatta 71 saniye sürüyor, oysa
/// `receiveTimeout` 8 saniye — ölçüm tam da kanıtlamak istediğimiz "QoD
/// öncesi" durumda hep başarısız oluyordu. `preferHighest: false` ile 240p
/// segmenti (~72 KB) indirilir, 256 kbit'te bile ~2 saniye sürer.
///
/// **Ama `preferHighest: false` sabitlenirse "sonra" ölçümü de yanıltıcı
/// olur:** 72 KB'lık bir dosyada indirme süresi TCP/TLS el sıkışması gibi
/// sabit gecikmelerin hâkimiyetinde kalır — 8 Mbit'lik bir hatta bile ölçülen
/// hız gerçek bağlantı hızına değil, bu sabit gecikmeye yakınsar (ör. 0.5-0.6
/// Mbps, 8 Mbit'in çok altında). Bu yüzden QoD başarılı olduktan sonra
/// `preferHighest: true` ile en yüksek varyantın (1080p, 2.29 MB) segmenti
/// indirilir: 8 Mbit'te ~2.3 sn sürer (8 sn timeout'un altında) ve gerçek
/// bağlantı hızını gösterir — aynı zamanda kaydın gerçekte hangi varyantla
/// yapılacağının (`HlsVariantService.selectForQod`) doğru bir provası olur.
class BandwidthProbeService {
  /// [dio] yalnızca testler için; uygulamada kendi kısa zaman aşımlı
  /// istemcisini kurar (ölçüm kritik değil, uzun beklememeli).
  BandwidthProbeService({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 5),
              receiveTimeout: const Duration(seconds: 8),
            ));

  final Dio _dio;

  /// [preferHighest]: `false` (varsayılan) en düşük varyantı indirir — QoD
  /// henüz kurulmamışken (256 kbit) zaman aşımına düşmeden ölçüm almak için.
  /// `true` en yüksek varyantı indirir — QoD kurulduktan sonra gerçek 8
  /// Mbit'lik hızı görebilmek için (bkz. sınıf dokümantasyonu).
  Future<BandwidthSample?> probe(String hlsUrl, {bool preferHighest = false}) async {
    try {
      final segmentUrl =
          await _resolveDownloadableSegment(hlsUrl, preferHighest: preferHighest);
      if (segmentUrl == null) return null;

      final sw = Stopwatch()..start();
      final response = await _dio.get<List<int>>(
        segmentUrl,
        options: Options(responseType: ResponseType.bytes),
      );
      sw.stop();
      final bytes = response.data?.length ?? 0;
      if (bytes == 0) return null;
      return BandwidthSample(bytes: bytes, elapsed: sw.elapsed);
    } catch (_) {
      return null;
    }
  }

  /// Master playlist -> [preferHighest]'e göre en yüksek/en düşük varyantın
  /// playlist'i -> ilk segment. En fazla 3 sekme (master -> varyant -> segment).
  Future<String?> _resolveDownloadableSegment(
    String startUrl, {
    required bool preferHighest,
  }) async {
    var currentUrl = startUrl;
    for (var hop = 0; hop < 3; hop++) {
      if (!currentUrl.contains('.m3u8')) {
        return currentUrl; // zaten indirilebilir bir medya segmenti
      }
      final response = await _dio.get<String>(currentUrl);
      final body = response.data ?? '';

      // Master playlist ise: preferHighest'e göre varyanta in. Liste
      // yüksekten düşüğe sıralı (bkz. HlsVariantService.parseMaster).
      final varyantlar = HlsVariantService.parseMaster(body, Uri.parse(currentUrl));
      if (varyantlar.isNotEmpty) {
        currentUrl = preferHighest ? varyantlar.first.url : varyantlar.last.url;
        continue;
      }

      // Medya playlist'i: ilk segment.
      final nextLine = body
          .split('\n')
          .map((l) => l.trim())
          .firstWhere((l) => l.isNotEmpty && !l.startsWith('#'), orElse: () => '');
      if (nextLine.isEmpty) return null;
      currentUrl = Uri.parse(currentUrl).resolve(nextLine).toString();
    }
    return currentUrl.contains('.m3u8') ? null : currentUrl;
  }
}
