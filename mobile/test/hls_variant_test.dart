import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teknofest_mobile/services/hls_variant_service.dart';

/// Yarışmanın Faz 2 master playlist'inin GERÇEK içeriği
/// (6 Ağustos 2026'da `playlist.m3u8` adresinden çekildi).
const _gercekMaster = '''
#EXTM3U
#EXT-X-VERSION:3
#EXT-X-STREAM-INF:BANDWIDTH=9155202,NAME=1080p,RESOLUTION=1920x1080,CODECS="avc1.640028,mp4a.40.2"
hlssubplaylist-ovbn2Ur8_oacnUA.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=289282,NAME=240p,RESOLUTION=426x240,CODECS="avc1.424015,mp4a.40.2"
hlssubplaylist-ovdncBeb_oacnUA.m3u8
''';

final _taban = Uri.parse(
  'https://teknofest-arge-turkcell.ercdn.net/hls/4/pZ/faz2/faz2.smil/playlist.m3u8',
);

void main() {
  group('parseMaster', () {
    test('gercek yarisma playlistini iki varyanta ayirir', () {
      final variants = HlsVariantService.parseMaster(_gercekMaster, _taban);

      expect(variants, hasLength(2));
      // Yüksekten düşüğe sıralı olmalı — seçim buna dayanıyor.
      expect(variants.first.bandwidthBps, 9155202);
      expect(variants.first.name, '1080p');
      expect(variants.first.resolution, '1920x1080');
      expect(variants.last.bandwidthBps, 289282);
      expect(variants.last.name, '240p');
    });

    test('goreli URIleri master adresine gore mutlaklastirir', () {
      final variants = HlsVariantService.parseMaster(_gercekMaster, _taban);

      expect(
        variants.first.url,
        'https://teknofest-arge-turkcell.ercdn.net/hls/4/pZ/faz2/faz2.smil/'
        'hlssubplaylist-ovbn2Ur8_oacnUA.m3u8',
      );
    });

    test('CODECS icindeki virgul ayrac sayilmaz', () {
      // Düz split(',') kullanılsaydı NAME/RESOLUTION kaybolurdu.
      final variants = HlsVariantService.parseMaster(_gercekMaster, _taban);

      expect(variants.first.resolution, isNotNull);
      expect(variants.last.resolution, isNotNull);
    });

    test('master olmayan (dogrudan medya) playlist bos liste doner', () {
      const medya = '''
#EXTM3U
#EXT-X-TARGETDURATION:10
#EXTINF:10.0,
segment0.ts
''';
      expect(HlsVariantService.parseMaster(medya, _taban), isEmpty);
    });
  });

  // Seçim kuralı 7 Ağustos'ta bant genişliği ÖLÇÜMÜNDEN QoD DURUMUNA çevrildi.
  //
  // Gerekçe: yarışma SIM'inde ara bir hız yok — QoD'siz 256 kbit/s, QoD'li
  // 8 Mbit/s. Ölçüme dayalı seçim hem gereksizdi hem de tam ters yönde
  // çalışıyordu: QoD'siz durumda ölçüm zaman aşımına düşüyor, "ölçüm yok"
  // hâli de en YÜKSEK varyantı seçtiriyordu (256 kbit'te 1080p ≈ 68 dakika,
  // ekran donmuş görünüyordu).
  //
  // Akış VOD olduğu için (#EXT-X-PLAYLIST-TYPE:VOD + #EXT-X-ENDLIST) QoD
  // varken en yükseği seçmek güvenli: 8 Mbit'lik hatta 9.16 Mbps'lik yayın
  // iner, sadece video süresinden biraz uzun sürer (114 sn video ≈ 130 sn).
  group('selectForQod', () {
    List<HlsVariant> variants() =>
        HlsVariantService.parseMaster(_gercekMaster, _taban);

    test('QoD acikken 1080p secer (8 Mbit, VOD - gercek zamanli yetisme sart degil)', () {
      final secilen = HlsVariantService.selectForQod(
        varyantlar: variants(),
        qodAktif: true,
      );
      expect(secilen!.name, '1080p');
    });

    test('QoD kapaliyken 240pye duser (256 kbit fallback)', () {
      // Tercih DEĞİL, çaresizlik: 256 kbit'te 1080p ~68 dakika sürerdi ve
      // 5 dakikalık kayıt penceresine hiç sığmazdı.
      final secilen = HlsVariantService.selectForQod(
        varyantlar: variants(),
        qodAktif: false,
      );
      expect(secilen!.name, '240p');
    });

    test('tek varyantli playlistte QoD durumundan bagimsiz o varyant secilir', () {
      final tek = HlsVariantService.parseMaster('''
#EXTM3U
#EXT-X-STREAM-INF:BANDWIDTH=800000,NAME=480p
only.m3u8
''', _taban);
      expect(
        HlsVariantService.selectForQod(varyantlar: tek, qodAktif: true)!.name,
        '480p',
      );
      expect(
        HlsVariantService.selectForQod(varyantlar: tek, qodAktif: false)!.name,
        '480p',
      );
    });

    test('varyant yoksa null doner (cagiran master URLe duser)', () {
      expect(
        HlsVariantService.selectForQod(varyantlar: [], qodAktif: true),
        isNull,
      );
      expect(
        HlsVariantService.selectForQod(varyantlar: [], qodAktif: false),
        isNull,
      );
    });
  });

  // 7 Ağustos: "1:54'lük video 5 saniyede indi, bu normal mi" sorusu üstüne
  // eklendi. ffmpeg VOD'u gerçek zamanlı okumadığı için hızlı inmesi normal,
  // ama ağ/QoD kesintisiyle akışın ERKEN kesilip SUCCESS dönmesi de mümkün —
  // bu fonksiyon, kayıt sonrası ffprobe ile ölçülen gerçek süreyle
  // karşılaştırılacak "beklenen toplam süre" referansını üretiyor.
  group('sumSegmentDurations', () {
    test('birden fazla EXTINF toplanir', () {
      const medya = '''
#EXTM3U
#EXT-X-PLAYLIST-TYPE:VOD
#EXTINF:2.002,
segment-0.ts
#EXTINF:2.002,
segment-1.ts
#EXTINF:1.536,
segment-2.ts
#EXT-X-ENDLIST
''';
      expect(HlsVariantService.sumSegmentDurations(medya), closeTo(5.54, 0.001));
    });

    test('EXTINF yoksa null doner (dogrulama sessizce atlanir)', () {
      const medya = '''
#EXTM3U
#EXT-X-PLAYLIST-TYPE:VOD
#EXT-X-ENDLIST
''';
      expect(HlsVariantService.sumSegmentDurations(medya), isNull);
    });

    test('tam sayili EXTINF degerlerini de ayristirir', () {
      const medya = '''
#EXTM3U
#EXTINF:10,
segment-0.ts
#EXTINF:10,
segment-1.ts
''';
      expect(HlsVariantService.sumSegmentDurations(medya), closeTo(20.0, 0.001));
    });

    test('bos govdede null doner', () {
      expect(HlsVariantService.sumSegmentDurations(''), isNull);
    });
  });

  group('fetchExpectedDuration', () {
    test('varyantin playlistini indirip toplam sureyi doner', () async {
      final adapter = _SahteMedyaAdapter('''
#EXTM3U
#EXT-X-PLAYLIST-TYPE:VOD
#EXTINF:2.0,
segment-0.ts
#EXTINF:1.5,
segment-1.ts
#EXT-X-ENDLIST
''');
      final dio = Dio()..httpClientAdapter = adapter;
      final servis = HlsVariantService(dio: dio);
      final varyant = HlsVariant(
        bandwidthBps: 9155202,
        url: 'https://ornek.local/hlssubplaylist-1080p.m3u8',
        name: '1080p',
      );

      final sure = await servis.fetchExpectedDuration(varyant);

      expect(sure, closeTo(3.5, 0.001));
    });

    test('ag hatasinda null doner, istisna sizdirmaz', () async {
      final dio = Dio()..httpClientAdapter = _HataliMedyaAdapter();
      final servis = HlsVariantService(dio: dio);
      final varyant = HlsVariant(bandwidthBps: 1, url: 'https://ornek.local/x.m3u8');

      expect(await servis.fetchExpectedDuration(varyant), isNull);
    });
  });
}

class _SahteMedyaAdapter implements HttpClientAdapter {
  _SahteMedyaAdapter(this.govde);
  final String govde;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async =>
      ResponseBody.fromString(govde, 200);

  @override
  void close({bool force = false}) {}
}

class _HataliMedyaAdapter implements HttpClientAdapter {
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
