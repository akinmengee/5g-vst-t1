import 'package:flutter_test/flutter_test.dart';
import 'package:teknofest_mobile/config/app_config.dart';
import 'package:teknofest_mobile/state/session_controller.dart';

/// Final günü organizasyon FARKLI bir akış adresi verecek (protokol aynı,
/// base'den sonrası değişiyor). Canlı demoda uygulamayı yeniden derleyemeyiz,
/// bu yüzden adres çalışma zamanında girilebilir olmak zorunda.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('setStreamUrl', () {
    test('varsayilan Faz2 test akisidir', () {
      final c = SessionController();
      addTearDown(c.dispose);

      expect(c.streamUrl, AppConfig.testHlsUrl);
      expect(c.streamUrlVarsayilan, isTrue);
    });

    test('yeni adres kaydedilir ve artik varsayilan degildir', () {
      final c = SessionController();
      addTearDown(c.dispose);

      c.setStreamUrl('https://ornek.local/hls/final/playlist.m3u8');

      expect(c.streamUrl, 'https://ornek.local/hls/final/playlist.m3u8');
      expect(c.streamUrlVarsayilan, isFalse);
    });

    test('bastaki/sondaki bosluklar temizlenir (yapistirma kazasi)', () {
      final c = SessionController();
      addTearDown(c.dispose);

      c.setStreamUrl('  https://ornek.local/a.m3u8  ');

      expect(c.streamUrl, 'https://ornek.local/a.m3u8');
    });

    test('bos deger adresi SILMEZ (yanlislikla temizlemeye karsi)', () {
      final c = SessionController();
      addTearDown(c.dispose);
      c.setStreamUrl('https://ornek.local/a.m3u8');

      c.setStreamUrl('   ');

      expect(c.streamUrl, 'https://ornek.local/a.m3u8');
    });

    test('varsayilana donus calisir', () {
      final c = SessionController();
      addTearDown(c.dispose);
      c.setStreamUrl('https://ornek.local/a.m3u8');

      c.streamUrlVarsayilanaDon();

      expect(c.streamUrl, AppConfig.testHlsUrl);
      expect(c.streamUrlVarsayilan, isTrue);
    });

    test('adres degisince onceki varyant secimi temizlenir', () {
      // Yeni akışın varyantları farklı olabilir; eski seçimi göstermeye
      // devam etmek canlı demoda yanlış bilgi verirdi.
      final c = SessionController();
      addTearDown(c.dispose);

      c.setStreamUrl('https://ornek.local/baska/playlist.m3u8');

      expect(c.secilenVaryant, isNull);
    });
  });

  group('streamUrlUyarisi — yumuşak doğrulama (kaydı ENGELLEMEZ)', () {
    test('gecerli HLS adresinde uyari yok', () {
      expect(
        SessionController.streamUrlUyarisi(
          'https://teknofest-arge-turkcell.ercdn.net/hls/4/pZ/faz2/faz2.smil/playlist.m3u8',
        ),
        isNull,
      );
    });

    test('http de kabul edilir', () {
      expect(SessionController.streamUrlUyarisi('http://ornek.local/a.m3u8'), isNull);
    });

    test('bos adres uyari verir', () {
      expect(SessionController.streamUrlUyarisi('  '), isNotNull);
    });

    test('sema yoksa uyari verir', () {
      expect(SessionController.streamUrlUyarisi('ornek.local/a.m3u8'), isNotNull);
    });

    test('m3u8 olmayan adres UYARIR ama bu bir hata degil', () {
      // Final günü beklemediğimiz bir biçim gelirse uygulama kilitlenmesin:
      // uyarı metni döner, kayıt yine de denenebilir.
      final uyari = SessionController.streamUrlUyarisi('https://ornek.local/video.mp4');
      expect(uyari, isNotNull);
      expect(uyari, contains('m3u8'));
    });
  });
}
