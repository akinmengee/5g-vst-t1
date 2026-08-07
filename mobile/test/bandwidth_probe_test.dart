import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teknofest_mobile/services/bandwidth_probe_service.dart';

/// 7 Ağustos regresyonu: ölçer master playlist'teki **ilk** satırı, yani
/// EN YÜKSEK varyantı (1080p) indirmeye çalışıyordu. O segment 2.29 MB ve
/// yarışma SIM'inde QoD'siz hız 256 kbit/s — indirmesi 71 saniye sürüyor,
/// oysa `receiveTimeout` 8 saniye. Sonuç: ölçüm tam da kanıtlamak istediğimiz
/// "QoD öncesi" durumda hep başarısız oluyordu (şartname 4.1).
///
/// Düzeltme: en DÜŞÜK varyantın segmenti indiriliyor (240p, ~72 KB) —
/// 256 kbit'te bile ~2 saniye.

const _masterUrl = 'https://ornek.local/hls/faz2/playlist.m3u8';

/// Yarışmanın gerçek master playlist'i: 1080p ÖNCE listeleniyor.
const _gercekMaster = '''
#EXTM3U
#EXT-X-VERSION:3
#EXT-X-STREAM-INF:BANDWIDTH=9155202,NAME=1080p,RESOLUTION=1920x1080,CODECS="avc1.640028,mp4a.40.2"
hlssubplaylist-1080p.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=289282,NAME=240p,RESOLUTION=426x240,CODECS="avc1.424015,mp4a.40.2"
hlssubplaylist-240p.m3u8
''';

const _medyaPlaylist = '''
#EXTM3U
#EXT-X-PLAYLIST-TYPE:VOD
#EXTINF:2.00,
segment-0.ts
#EXTINF:2.00,
segment-1.ts
#EXT-X-ENDLIST
''';

/// İstenen adresleri kaydeden, gövdeleri testin verdiği sahte ağ katmanı.
class _SahteAdapter implements HttpClientAdapter {
  final List<String> istenenler = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final url = options.uri.toString();
    istenenler.add(url);

    if (url.endsWith('playlist.m3u8')) {
      return ResponseBody.fromString(_gercekMaster, 200);
    }
    if (url.endsWith('.m3u8')) {
      return ResponseBody.fromString(_medyaPlaylist, 200);
    }
    // Segment: ölçülebilir bir gövde.
    return ResponseBody.fromBytes(List<int>.filled(72 * 1024, 7), 200);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test('olcer EN DUSUK varyantin segmentini indirir (1080pyi DEGIL)', () async {
    final adapter = _SahteAdapter();
    final dio = Dio()..httpClientAdapter = adapter;
    final servis = BandwidthProbeService(dio: dio);

    final ornek = await servis.probe(_masterUrl);

    expect(ornek, isNotNull, reason: 'ölçüm başarılı olmalı');
    expect(
      adapter.istenenler.any((u) => u.contains('240p')),
      isTrue,
      reason: '240p alt playlistine inilmeli',
    );
    expect(
      adapter.istenenler.any((u) => u.contains('1080p')),
      isFalse,
      reason: '1080p segmenti indirilirse yavaş hatta timeout olur — asıl bug buydu',
    );
  });

  test('indirilen segmentin bayt sayisi ve suresi olcume yansir', () async {
    final dio = Dio()..httpClientAdapter = _SahteAdapter();
    final ornek = await BandwidthProbeService(dio: dio).probe(_masterUrl);

    expect(ornek!.bytes, 72 * 1024);
    expect(ornek.mbps, greaterThan(0));
  });

  test('master degil dogrudan medya playlisti verilirse de calisir', () async {
    final adapter = _SahteAdapter();
    final dio = Dio()..httpClientAdapter = adapter;

    final ornek = await BandwidthProbeService(dio: dio)
        .probe('https://ornek.local/hls/faz2/hlssubplaylist-240p.m3u8');

    expect(ornek, isNotNull);
    expect(adapter.istenenler.last, contains('segment-0.ts'));
  });

  test('ag hatasinda null doner, istisna sizdirmaz', () async {
    // Ölçüm kritik değil: başarısızsa UI o örneği göstermez, akış devam eder.
    final dio = Dio()
      ..httpClientAdapter = _HataliAdapter();

    expect(await BandwidthProbeService(dio: dio).probe(_masterUrl), isNull);
  });
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
