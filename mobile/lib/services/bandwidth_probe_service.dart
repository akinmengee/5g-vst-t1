import 'package:dio/dio.dart';

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
/// edilir. Sahte/simüle sayı üretmez: ölçüm başarısız olursa null döner ve
/// UI o örneği göstermez.
class BandwidthProbeService {
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 5),
    receiveTimeout: const Duration(seconds: 8),
  ));

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

  /// Master playlist -> varyant playlist -> ilk segment, en fazla 3 sekme.
  Future<String?> _resolveDownloadableSegment(String startUrl) async {
    var currentUrl = startUrl;
    for (var hop = 0; hop < 3; hop++) {
      if (!currentUrl.contains('.m3u8')) {
        return currentUrl; // zaten indirilebilir bir medya segmenti
      }
      final response = await _dio.get<String>(currentUrl);
      final body = response.data ?? '';
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
