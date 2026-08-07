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
/// **EN DÜŞÜK varyantın segmenti indirilir.** Önceden master playlist'teki ilk
/// satır (yani en yüksek varyant) kullanılıyordu: 1080p segmenti 2.29 MB ve
/// QoD'siz 256 kbit/s'lik hatta 71 saniye sürüyor, oysa `receiveTimeout`
/// 8 saniye — ölçüm tam da kanıtlamak istediğimiz "QoD öncesi" durumda hep
/// başarısız oluyordu. 240p segmenti ~72 KB, 256 kbit'te bile ~2 saniye:
/// hem ölçüm artık her koşulda çalışıyor hem de demo süresinden kazanıyoruz.
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

  Future<BandwidthSample?> probe(String hlsUrl) async {
    try {
      final segmentUrl = await _resolveDownloadableSegment(hlsUrl);
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

  /// Master playlist -> **en düşük** varyantın playlist'i -> ilk segment.
  /// En fazla 3 sekme (master -> varyant -> segment).
  Future<String?> _resolveDownloadableSegment(String startUrl) async {
    var currentUrl = startUrl;
    for (var hop = 0; hop < 3; hop++) {
      if (!currentUrl.contains('.m3u8')) {
        return currentUrl; // zaten indirilebilir bir medya segmenti
      }
      final response = await _dio.get<String>(currentUrl);
      final body = response.data ?? '';

      // Master playlist ise: en düşük bant genişlikli varyanta in. Böylece
      // ölçüm, yavaş hatta bile zaman aşımına düşmeyecek kadar küçük bir
      // segment üzerinden yapılır.
      final varyantlar = HlsVariantService.parseMaster(body, Uri.parse(currentUrl));
      if (varyantlar.isNotEmpty) {
        currentUrl = varyantlar.last.url; // liste yüksekten düşüğe sıralı
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
