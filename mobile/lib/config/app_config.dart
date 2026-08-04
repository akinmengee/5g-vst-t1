/// Yarışma günü değişecek tek yer burası: backend adresi ve mock modu.
///
/// Akın'ın backend'i hazır olana kadar [useMock] true kalmalı — bu sayede
/// mobil akışın tamamı (NV -> QoD -> stream -> upload -> AI result) gerçek
/// bir sunucu olmadan da uçtan uca denenebilir.
class AppConfig {
  AppConfig._();

  /// Akın'ın backend sözleşmesi (mobile-integration.md, 3 Ağu 2026):
  /// `http://<VM_IP>:8080`, endpoint yolları `/api/...` ile başlıyor (bu
  /// yüzden burada `/api` YOK, servislerin kendi path'lerinde var). VM IP
  /// netleşince tek değişecek satır burası.
  static const String backendBaseUrl = 'http://localhost:8000';

  /// true iken NvService/QodService/VideoService gerçek ağ çağrısı yapmaz,
  /// UX kılavuzundaki akışı simüle eden sahte gecikmeli yanıtlar döner.
  static const bool useMock = true;

  /// Open Gateway Demo UX Kılavuzu'ndaki sandbox test numarası.
  static const String sandboxTestPhoneNumber = '+905390000020';

  /// Faz 2 test HLS akışı (final günü gerçek streaming server URL'i ile
  /// değişecek).
  static const String testHlsUrl =
      'https://teknofest-arge-turkcell.ercdn.net/hls/4/pZ/faz2/faz2.smil/playlist.m3u8';

  /// Şartname: "maksimum 5 dakika içerisinde videonun tamamını kaydetmesi".
  static const Duration maxRecordingDuration = Duration(minutes: 5);
}
