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

  group('selectForBandwidth', () {
    List<HlsVariant> variants() =>
        HlsVariantService.parseMaster(_gercekMaster, _taban);

    test('yuksek bantta 1080p secer (QoD basarili senaryosu)', () {
      // 50 Mbps: 1080p (9.155) güvenlik payıyla bile rahat sığar.
      final secilen = HlsVariantService.selectForBandwidth(variants(), 50);
      expect(secilen!.name, '1080p');
    });

    test('dusuk bantta 240pye duser (QoD basarisiz senaryosu)', () {
      // 5 Mbps: 1080p sığmaz. Şartname 4.2'nin uyardığı durum — burada
      // 1080p denenirse 5 dakikalık kayıt penceresi yetmez.
      final secilen = HlsVariantService.selectForBandwidth(variants(), 5);
      expect(secilen!.name, '240p');
    });

    test('guvenlik payi sinirda ust varyanti secmez', () {
      // 1080p tam 9.155 Mbps; ölçüm de 9.2 Mbps ise pay bırakmadan seçmek
      // riskli olurdu (guvenlikPayi = 0.85 -> bütçe 7.82 Mbps).
      final secilen = HlsVariantService.selectForBandwidth(variants(), 9.2);
      expect(secilen!.name, '240p');
    });

    test('hicbiri sigmazsa en dusugu secer (kayit hic alinamamaktansa)', () {
      final secilen = HlsVariantService.selectForBandwidth(variants(), 0.01);
      expect(secilen!.name, '240p');
    });

    test('olcum yoksa en yuksegi secer (mevcut ffmpeg davranisi)', () {
      final secilen = HlsVariantService.selectForBandwidth(variants(), null);
      expect(secilen!.name, '1080p');
    });

    test('varyant yoksa null doner', () {
      expect(HlsVariantService.selectForBandwidth([], 50), isNull);
    });
  });
}
