import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Lifebox'ın resmi bir upload API'si/SDK'sı paylaşılmadı (bkz.
/// mobile-final-sprint memory notu). Bu yüzden şimdilik Android'in native
/// share sheet'i üzerinden MP4'ü Lifebox uygulamasına gönderiyoruz —
/// kullanıcı share menüsünden Lifebox'ı seçip kendi hesabına yüklüyor.
/// Akın/Atamert'ten resmi bir API gelirse burası otomatik upload'a çevrilir.
class LifeboxService {
  Future<void> shareVideo(String filePath) async {
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(filePath, mimeType: 'video/mp4')],
        text: 'VST-T1 · TEKNOFEST 5G final kaydı — Lifebox\'a yüklemek için seçin',
      ),
    );
  }

  /// results.json dışa aktarma: içerik geçici bir dosyaya yazılır ve share
  /// sheet açılır — kullanıcı Dosyalar/Drive/WhatsApp ile "indirir".
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
}
