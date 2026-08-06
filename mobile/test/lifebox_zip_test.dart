import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teknofest_mobile/services/lifebox_service.dart';

/// Lifebox'a giden video ZIP'inin dosyayı BOZMADAN taşıdığını doğrular.
/// Hakem, Lifebox'tan indirdiği videoyu bizim AI imajımızdan geçirip canlı
/// demodaki sonuçla karşılaştırıyor; en ufak fark diskalifiye sebebi.
void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('vst_t1_zip_test');
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test('zip icerigi orijinal dosyayla bit-bit ayni', () async {
    final kaynak = File('${temp.path}/kayit_20260806_120000.mp4');
    // Rastgele ama tekrarlanabilir bir gövde — sıfırlardan farklı olsun ki
    // "içerik gerçekten taşınmış mı" testi anlamlı olsun.
    final icerik = List<int>.generate(512 * 1024, (i) => (i * 31 + 7) % 256);
    await kaynak.writeAsBytes(icerik);

    final zip = await LifeboxService.zipleDosya(
      kaynak.path,
      '${temp.path}/kayit.zip',
    );

    expect(await zip.exists(), isTrue);

    final arsiv = ZipDecoder().decodeBytes(await zip.readAsBytes());
    expect(arsiv.files, hasLength(1));
    expect(arsiv.files.single.name, 'kayit_20260806_120000.mp4');
    expect(arsiv.files.single.readBytes(), equals(icerik));
  });

  test('sikistirma KAPALI — sikistirilabilir icerik bile kuculmez', () async {
    // Tamamı sıfır olan gövde deflate ile ~1000 kat küçülürdü. Boyutun
    // korunması, `CompressionType.none` yolunun gerçekten kullanıldığının
    // (yani dosyanın belleğe alınıp yeniden kodlanmadığının) kanıtı.
    final kaynak = File('${temp.path}/sifirlar.mp4');
    await kaynak.writeAsBytes(List<int>.filled(1024 * 1024, 0));

    final zip = await LifeboxService.zipleDosya(
      kaynak.path,
      '${temp.path}/sifirlar.zip',
    );

    expect(await zip.length(), greaterThanOrEqualTo(1024 * 1024));
  });

  test('ayni zip ikinci kez uretilmez (tekrar paylasim ucuz)', () async {
    final kaynak = File('${temp.path}/kayit.mp4');
    await kaynak.writeAsBytes(List<int>.filled(1024, 1));
    final zipYolu = '${temp.path}/kayit.zip';

    final ilk = await LifeboxService.zipleDosya(kaynak.path, zipYolu);
    final ilkZaman = await ilk.lastModified();

    await Future<void>.delayed(const Duration(milliseconds: 20));
    final ikinci = await LifeboxService.zipleDosya(kaynak.path, zipYolu);

    expect(await ikinci.lastModified(), ilkZaman);
  });
}
