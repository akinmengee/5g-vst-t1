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

  /// Backend adresi. Endpoint yolları `/api/...` ile başladığı için burada
  /// `/api` YOK — servislerin kendi path'lerinde var.
  ///
  /// Gerçek telefonda `localhost` TELEFONUN kendisini işaret eder, backend'in
  /// çalıştığı bilgisayarı değil — cihazla test ederken makinenin LAN IP'sini
  /// (ya da yarışma VM'inin adresini) verin.
  static const String backendBaseUrl = String.fromEnvironment(
    'BACKEND_URL',
    defaultValue: 'http://localhost:8000',
  );

  /// NV ekranındaki telefon alanının başlangıç değeri. **Varsayılan boş** —
  /// yarışma günü elimizdeki SIM'in numarası girilecek ve yanlış bir numarayı
  /// önceden doldurmak, doğrulamanın sessizce reddedilmesine yol açar.
  /// Tekrarlı testlerde kolaylık için: `--dart-define=PHONE=+90...`
  static const String varsayilanTelefon = String.fromEnvironment('PHONE');

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

  /// Final Yarışma Senaryosu § 5: "Her inference için maksimum 10 dakikalık
  /// süre tanınacak" — backend'deki `job_timeout_seconds` ile birebir aynı
  /// değer. AI Sonucu ekranındaki sayaç bu tavana göre renk değiştirir.
  static const Duration aiProcessingTimeout = Duration(minutes: 10);

  // ── SADECE TEST İÇİN — yarışma hızını simüle etme ────────────────────────
  //
  // Test SIM'imiz çok hızlı (QoD açık/kapalı fark etmiyor), ama yarışma
  // SIM'i QoD'siz 256 kbit/s, QoD'li 8 Mbit/s ile sınırlı olacak. ffmpeg'in
  // gerçek video indirmesi Dart'tan tamamen görünmez/erişilemez olduğu için
  // (native bir kütüphane, kendi ham soket HTTP fetch'ini yapıyor) bu iki
  // bayrak yalnızca YAKLAŞIK bir gerçekçilik sağlar — kesin kbps kontrolü
  // değil. VARSAYILAN HER ZAMAN KAPALI: bir --dart-define VERİLMEDEN asla
  // etkinleşmezler, yarışma build'inde bu satırlar hiç yazılmayacak.

  /// true ise ffmpeg kaydı stream'in KENDİ bit hızında okur (`-re` bayrağı,
  /// bkz. `VideoRecordingService`) — max hızda değil. QoD'siz senaryoyu
  /// (240p ~289 kbps, gerçek 256 kbit'e çok yakın) gerçekçi test etmeyi
  /// sağlar. 1080p/8 Mbit senaryosunu TAM taklit etmez (1080p'nin kendi biti
  /// ~9.15 Mbps, hedeften biraz yüksek) ama yine de gerçekçi bir yavaşlama
  /// verir. YARIŞMA BUILD'İNDE ASLA VERİLMEMELİ — gereksiz yavaşlatır.
  static const bool testRealtimePace = bool.fromEnvironment('TEST_REALTIME_PACE');

  /// >0 ise backend'e giden yüklemeler bu hıza (kbit/s) yapay olarak
  /// kısıtlanır (bkz. `TestThrottleInterceptor`). 0 = kapalı. Amaç ilerleme
  /// çubuğunu güzelleştirmek değil, "yavaş bir yüklemede zaman aşımı/AI-poll
  /// dayanıklılığı/QoD süresi dolması gibi senaryolar gerçekten çalışıyor
  /// mu" sorusuna cevap vermek. YARIŞMA BUILD'İNDE ASLA VERİLMEMELİ.
  static const int testUploadThrottleKbps =
      int.fromEnvironment('TEST_UPLOAD_KBPS', defaultValue: 0);
}
