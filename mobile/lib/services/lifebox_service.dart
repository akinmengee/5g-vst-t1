import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Lifebox'ın resmi bir upload API'si/SDK'sı paylaşılmadı. Bu yüzden Android'in
/// native share sheet'i üzerinden dosyayı Lifebox uygulamasına gönderiyoruz —
/// kullanıcı share menüsünden Lifebox'ı seçip kendi hesabına yüklüyor.
class LifeboxService {
  /// Videoyu ZIP kabuğuna sarıp paylaşır.
  ///
  /// **Neden ZIP:** Lifebox, ham video dosyalarını "galeri unsuru" sayıp
  /// yeniden kodlayabiliyor — çözünürlük/boyut değişiyor (organizasyonun
  /// 3 Ağustos Q&A'sinde açıkça uyarıldı). Hakem, Lifebox'tan indirdiği
  /// videoyu bizim AI imajımızdan geçirip canlı demoda gösterdiğimiz sonuçla
  /// karşılaştırıyor; dosya değişmişse sonuçlar tutmaz ve bu **diskalifiye
  /// sebebi**. ZIP, dosyanın bit-bit aynı kalmasını garantiler.
  Future<void> shareVideo(String filePath) async {
    final zip = await _ziple(filePath);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(zip.path, mimeType: 'application/zip')],
        text: 'VST-T1 · TEKNOFEST 5G final kaydı — Lifebox\'a yüklemek için seçin',
      ),
    );
  }

  static Future<File> _ziple(String filePath) async {
    final dir = await getTemporaryDirectory();
    final ad = filePath.split(RegExp(r'[/\\]')).last;
    final zipYolu = '${dir.path}/${ad.replaceAll(RegExp(r'\.mp4$'), '')}.zip';
    return zipleDosya(filePath, zipYolu);
  }

  /// Dosyayı SIKIŞTIRMADAN (`CompressionType.none`) bir ZIP'e koyar.
  ///
  /// Sıkıştırma bilinçli olarak kapalı: MP4 zaten sıkıştırılmış, deflate
  /// kazanç sağlamaz. Dahası `archive` paketinde deflate yolu tüm dosyayı
  /// `OutputMemoryStream`'e alıyor — 100+ MB'lık bir kayıtta telefonda
  /// bellek sorunu demek. `none` yolunda veri akış olarak geçer.
  ///
  /// Hedef zip zaten varsa yeniden üretilmez: kayıt dosyaları zaman damgalı
  /// ve değişmez, aynı kayıt tekrar paylaşılabilir.
  static Future<File> zipleDosya(String filePath, String zipYolu) async {
    final zip = File(zipYolu);
    if (await zip.exists()) return zip;

    final ad = filePath.split(RegExp(r'[/\\]')).last;
    final encoder = ZipFileEncoder();
    encoder.create(zip.path);
    final girdi = InputFileStream(filePath);
    try {
      encoder.addArchiveFile(
        ArchiveFile.stream(ad, girdi)..compression = CompressionType.none,
      );
    } finally {
      await girdi.close();
      await encoder.close();
    }
    return zip;
  }

  /// results.json dışa aktarma: içerik geçici bir dosyaya yazılır ve share
  /// sheet açılır — kullanıcı Dosyalar/Drive/WhatsApp ile "indirir".
  /// (Burada ZIP yok: JSON metin dosyası, Lifebox'ın yeniden kodlama sorunu
  /// yalnızca medya dosyaları için geçerli.)
  Future<void> shareJson({required String fileName, required String content}) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$fileName');
    await file.writeAsString(content);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'application/json')],
        text: 'VST-T1 · TEKNOFEST 5G — AI sonuç dosyası ($fileName)',
      ),
    );
  }

  /// AI sonucunu ve parmak izlerini **TEK paylaşım işleminde** gönderir.
  ///
  /// Neden tek işlem: Lifebox'ın resmî API/SDK'sı paylaşılmadığı için hedef
  /// klasörü seçemiyoruz — üçünü aynı anda göndermek, aynı yere düşmeleri
  /// için elimizdeki en iyi güvence. Ayrıca canlı demoda tek dokunuş yeterli
  /// oluyor, ayrı adımları karıştırma riski kalmıyor.
  ///
  /// [jsonIcerik], [md5Hash] ve [sha256Hash] birbirine bağlıdır: her ikisi de
  /// tam olarak bu metnin hash'i olmalı (bkz. `ResultsFingerprint.of` ve
  /// session_controller'daki sha256 hesaplaması), yoksa hakem karşılaştırması
  /// tutmaz.
  Future<void> shareResultsWithHash({
    required String jsonFileName,
    required String jsonIcerik,
    required String md5Hash,
    required String sha256Hash,
  }) async {
    final dir = await getTemporaryDirectory();

    final jsonFile = File('${dir.path}/$jsonFileName');
    await jsonFile.writeAsString(jsonIcerik);

    // Yalnızca hash — hakem `md5sum`/`sha256sum results.json` çıktısıyla
    // birebir karşılaştırabilsin diye başka hiçbir metin yok.
    final md5File = File('${dir.path}/$jsonFileName.md5.txt');
    await md5File.writeAsString(md5Hash);

    final sha256File = File('${dir.path}/$jsonFileName.sha256.txt');
    await sha256File.writeAsString(sha256Hash);

    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile(jsonFile.path, mimeType: 'application/json'),
          XFile(md5File.path, mimeType: 'text/plain'),
          XFile(sha256File.path, mimeType: 'text/plain'),
        ],
        text: 'VST-T1 · TEKNOFEST 5G — AI sonucu + MD5 + SHA256 parmak izi',
      ),
    );
  }
}
