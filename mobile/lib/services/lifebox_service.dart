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
        text: 'TEKNOFEST 5G final kaydı — Lifebox\'a yüklemek için seçin',
      ),
    );
  }
}
