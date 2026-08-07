import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teknofest_mobile/services/results_fingerprint.dart';

/// results.json parmak izi — organizasyonun istediği biçim:
/// JSON hiç boşluk bırakmadan yazılır, MD5'i alınır, ilk 7 karakter kısa
/// kimlik olarak gösterilir. Hem dosya hem hash Lifebox'a yükleniyor.
///
/// Buradaki en kritik kural: **dosyaya yazılan metin ile hash'lenen metin
/// birebir aynı olmalı.** Hakem Lifebox'tan indirdiği JSON'u hash'leyip bizim
/// değerimizle karşılaştıracak; tek bir boşluk farkı bile karşılaştırmayı
/// düşürür. Bu yüzden ikisi tek kaynaktan üretiliyor.

/// VM'den dönen gerçek gövde şekli (kısaltılmış).
Map<String, dynamic> _gercekSonuc() => {
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
        {
          'zaman_saniye': 11.8,
          'kategori': 'sofor_eylemi',
          'etiket': 'telefonla_konusma',
          'confidence_score': 0.95,
        },
      ],
    };

void main() {
  group('boşluksuz (minified) yazım', () {
    test('JSON metninde hiç boşluk/girinti/satır sonu yok', () {
      final pi = ResultsFingerprint.of(_gercekSonuc());

      // String literal'lerin İÇİ hariç hiçbir yerde boşluk olmamalı.
      // Bu veride tüm değerler boşluksuz, dolayısıyla metnin tamamı sınanabilir.
      expect(pi.json, isNot(contains(' ')));
      expect(pi.json, isNot(contains('\n')));
      expect(pi.json, isNot(contains('\t')));
      expect(pi.json, startsWith('{"video_id":"video.mp4"'));
    });

    test('anahtar sırası backendden geldiği gibi korunur', () {
      // Hakem, AI'nin ürettiği dosyayla karşılaştırabilir; alanları
      // yeniden sıralamak metni gereksizce değiştirirdi.
      final pi = ResultsFingerprint.of(_gercekSonuc());
      expect(
        pi.json.indexOf('"video_id"') < pi.json.indexOf('"arac_bilgisi"'),
        isTrue,
      );
      expect(
        pi.json.indexOf('"arac_bilgisi"') < pi.json.indexOf('"tespitler"'),
        isTrue,
      );
    });
  });

  group('MD5', () {
    test('32 kucuk-harf hex karakter uretir', () {
      final pi = ResultsFingerprint.of(_gercekSonuc());
      expect(pi.md5Hex, hasLength(32));
      expect(RegExp(r'^[0-9a-f]{32}$').hasMatch(pi.md5Hex), isTrue);
    });

    test('hash TAM OLARAK yuklenen metinden uretilir (birebir tutarlilik)', () {
      // Bu testin düşmesi = hakemin karşılaştırmasının tutmaması.
      final pi = ResultsFingerprint.of(_gercekSonuc());
      final elleHesap = md5.convert(utf8.encode(pi.json)).toString();
      expect(pi.md5Hex, elleHesap);
    });

    test('ayni icerik her zaman ayni hashi verir', () {
      expect(
        ResultsFingerprint.of(_gercekSonuc()).md5Hex,
        ResultsFingerprint.of(_gercekSonuc()).md5Hex,
      );
    });

    test('tek bir deger degisince hash tamamen degisir', () {
      final a = ResultsFingerprint.of(_gercekSonuc());
      final degisik = _gercekSonuc();
      (degisik['arac_bilgisi'] as Map)['plaka'] = '34TC8533';
      final b = ResultsFingerprint.of(degisik);
      expect(a.md5Hex, isNot(b.md5Hex));
    });

    test('bos tespit listesi de gecerli bir parmak izi uretir', () {
      final bos = {'video_id': 'video.mp4', 'tespitler': <dynamic>[]};
      expect(ResultsFingerprint.of(bos).md5Hex, hasLength(32));
    });
  });

  group('maskeleme (parola alanı mantığı)', () {
    test('ilk 7 karakter acik, kalani gizli, uzunluk korunur', () {
      const hash = '0123456789abcdef0123456789abcdef';
      final maskeli = ResultsFingerprint.maskele(hash);

      expect(maskeli.substring(0, 7), '0123456');
      expect(maskeli.length, hash.length, reason: 'hizalama bozulmamalı');
      expect(maskeli.substring(7), isNot(contains(RegExp(r'[0-9a-f]'))),
          reason: 'ilk 7 karakterden sonrası okunamamalı');
    });

    test('acik karakter sayisi ayarlanabilir', () {
      const hash = '0123456789abcdef0123456789abcdef';
      expect(ResultsFingerprint.maskele(hash, acikKarakter: 4).substring(0, 4), '0123');
    });

    test('hash acik karakter sayisindan kisaysa oldugu gibi doner', () {
      expect(ResultsFingerprint.maskele('abc'), 'abc');
    });
  });
}
