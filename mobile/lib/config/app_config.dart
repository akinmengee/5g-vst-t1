/// Yarışma günü değişecek tek yer burası: backend adresi.
///
/// `--dart-define` ile çalıştırma zamanında verilir; kod düzenlemeden
/// değiştirilebilir (yarışma günü yanlış sabitle build alma riski yok):
///
/// ```
/// flutter run                                          # localhost:8000
/// flutter run --dart-define=BACKEND_URL=http://192.168.1.50:8000
/// ```
///
/// Sahte (mock) veri modu YOKTUR: her çağrı gerçek backend'e gider. Backend
/// kendi tarafında `USE_MOCK_5G=true` ile çalışırken bile HTTP akışının tamamı
/// (WebView + callback + polling) gerçektir — taklit edilen yalnızca Turkcell'in
/// kendisidir, bizim kodumuz değil.
class AppConfig {
  AppConfig._();

  /// Backend sözleşmesi (docs/mobile-integration.md): endpoint yolları `/api/...`
  /// ile başlar, bu yüzden burada `/api` YOK — servislerin kendi path'lerinde var.
  ///
  /// Gerçek telefonda `localhost` TELEFONUN kendisini işaret eder, backend'in
  /// çalıştığı bilgisayarı değil — cihazla test ederken makinenin LAN IP'sini
  /// verin. Backend'in `PUBLIC_BASE_URL`'i de aynı adres olmalı, çünkü mock
  /// onay sayfası WebView'i o adres üzerinden callback'e yönlendiriyor.
  static const String backendBaseUrl = String.fromEnvironment(
    'BACKEND_URL',
    defaultValue: 'http://localhost:8000',
  );

  /// Open Gateway Demo UX Kılavuzu'ndaki sandbox test numarası.
  static const String sandboxTestPhoneNumber = '+905390000020';

  /// Faz 2 test HLS akışı (final günü gerçek streaming server URL'i ile
  /// değişecek).
  static const String testHlsUrl =
      'https://teknofest-arge-turkcell.ercdn.net/hls/4/pZ/faz2/faz2.smil/playlist.m3u8';

  /// Şartname: "maksimum 5 dakika içerisinde videonun tamamını kaydetmesi".
  static const Duration maxRecordingDuration = Duration(minutes: 5);

  /// Sözleşme § 2.3 / § 2.6: NV durumu ~1 sn, AI sonucu 1-2 sn arayla pollenir.
  static const Duration authPollInterval = Duration(seconds: 1);
  static const Duration aiPollInterval = Duration(seconds: 2);

  /// Sözleşme § 2.3: 60 sn'de sonuç gelmezse timeout göster.
  static const Duration authPollTimeout = Duration(seconds: 60);
}
