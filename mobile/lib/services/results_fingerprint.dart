import 'dart:convert';

import 'package:crypto/crypto.dart';

/// results.json'un Lifebox'a yüklenecek metni ve onun MD5 parmak izi.
///
/// **Neden tek bir sınıf:** Hakem, Lifebox'tan indirdiği JSON'u hash'leyip
/// bizim ibraz ettiğimiz değerle karşılaştırıyor. Dosyaya yazılan metin ile
/// hash'lenen metin bir karakter bile farklı olursa (girinti, satır sonu,
/// anahtar sırası) karşılaştırma tutmaz. Bu yüzden ikisi ASLA ayrı ayrı
/// üretilmez: [ResultsFingerprint.of] tek bir metin üretir, hash'i ondan
/// hesaplar ve ikisini birlikte taşır.
class ResultsFingerprint {
  /// Boşluksuz (minified) JSON — hem dosyaya yazılan hem hash'lenen metin.
  final String json;

  /// [json]'un MD5'i: 32 küçük-harf hex karakter.
  final String md5Hex;

  const ResultsFingerprint({required this.json, required this.md5Hex});

  /// Organizasyonun istediği biçim: JSON, insan okusun diye hiçbir boşluk /
  /// girinti eklenmeden düz yazılır, sonra o metnin MD5'i alınır.
  ///
  /// `jsonEncode` zaten ayraçların etrafına boşluk koymaz; anahtar sırası da
  /// backend'den geldiği sırayla korunur (Dart'ın decode ettiği map ekleme
  /// sırasını saklar), yani sonuç backend'in ürettiği gövdeyle aynı düzendedir.
  factory ResultsFingerprint.of(Map<String, dynamic> raw) {
    final minified = jsonEncode(raw);
    return ResultsFingerprint(
      json: minified,
      md5Hex: md5.convert(utf8.encode(minified)).toString(),
    );
  }

  /// Parmak izinin ekranda gösterilecek maskeli hâli: ilk [acikKarakter]
  /// karakter okunur, gerisi gizli.
  ///
  /// Git'in kısa commit hash'i mantığı — 7 hex karakter ~268 milyon olasılık,
  /// yarışmadaki birkaç video için ayırt edici olmaya fazlasıyla yeter; tam
  /// değer zaten Lifebox'a yüklenen dosyada.
  static String maskele(String hash, {int acikKarakter = 7}) {
    if (hash.length <= acikKarakter) return hash;
    return hash.substring(0, acikKarakter) +
        '•' * (hash.length - acikKarakter);
  }
}
