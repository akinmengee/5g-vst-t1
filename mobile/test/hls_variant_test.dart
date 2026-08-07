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
}
