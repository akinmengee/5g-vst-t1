/// Yarışma günü değişecek tek yer burası: backend adresi.
///
/// Adres `--dart-define` ile çalıştırma zamanında verilir; kod düzenlemeden
/// ortam değiştirilebilir (yarışma günü yanlış sabitle build alma riski yok):
///
/// ```
/// flutter run                                          # localhost'taki backend
/// flutter run --dart-define=BACKEND_URL=http://192.168.1.50:8000
/// ```
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

  /// Kayıt alınacak HLS akışı. Varsayılan, Faz 2 test akışıdır; final günü
  /// gerçek streaming server adresi verilecek.
  ///
  /// Backend adresi gibi bu da `--dart-define` ile çalıştırma zamanında
  /// veriliyor — final günü adres değişirse KOD DÜZENLENMESİ gerekmez
  /// (7 Ağustos 21:00 dondurmasından sonra kaynağa dokunmak istemiyoruz):
  ///
  /// ```
  /// flutter build apk --dart-define=HLS_URL=https://.../playlist.m3u8
  /// ```
  static const String testHlsUrl = String.fromEnvironment(
    'HLS_URL',
    defaultValue:
        'https://teknofest-arge-turkcell.ercdn.net/hls/4/pZ/faz2/faz2.smil/playlist.m3u8',
  );

  /// Şartname: "maksimum 5 dakika içerisinde videonun tamamını kaydetmesi".
  static const Duration maxRecordingDuration = Duration(minutes: 5);

  /// Sözleşme § 2.3 / § 2.6: NV durumu ~1 sn, sonuç 1-2 sn arayla pollenir.
  static const Duration nvPollInterval = Duration(seconds: 1);
  static const Duration aiPollInterval = Duration(seconds: 2);

  /// mobile-integration.md 2.3: 60 sn'de sonuç gelmezse timeout gösterilir.
  static const Duration nvPollTimeout = Duration(seconds: 60);
}
