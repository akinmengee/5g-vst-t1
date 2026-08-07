import 'package:flutter_test/flutter_test.dart';
import 'package:teknofest_mobile/screens/ai_result_screen.dart';

/// 7 Ağustos: AI Sonucu ekranında bir tespite dokununca video o saniyeye
/// zıplıyor (`saniyeyeGoreKonum` -> `VideoPlayerController.seekTo`).
/// Gerçek video decode/seek/scroll davranışı bu repoda yerleşik örüntüyle
/// tutarlı şekilde (video_card.dart'ın da hiç testi yok) OTOMATİK TEST
/// KAPSAMI DIŞI — yalnızca saniye -> Duration dönüşüm matematiği burada
/// doğrulanıyor.
void main() {
  group('saniyeyeGoreKonum', () {
    test('tam saniyeyi dogru donusturur', () {
      expect(saniyeyeGoreKonum(2.0), const Duration(seconds: 2));
    });

    test('ondalikli saniyeyi milisaniyeye kayip olmadan cevirir', () {
      // 7 Ağustos gerçek örneği: "1 dakika 54 saniyelik video" senaryosunda
      // görülen türden bir segment süresi.
      expect(saniyeyeGoreKonum(1.536), const Duration(milliseconds: 1536));
    });

    test('yuvarlama en yakin milisaniyeye yapilir (kesme degil)', () {
      // 0.1234 sn = 123.4 ms -> en yakin tam milisaniyeye yuvarlanir (123),
      // kesme (floor) olsaydi da 123 cikardi; asagidaki ornek yuvarlama
      // yonunu (yukari) asil ayirt eden durum.
      expect(saniyeyeGoreKonum(0.1235), const Duration(milliseconds: 124));
      expect(saniyeyeGoreKonum(0.1234), const Duration(milliseconds: 123));
    });

    test('sifir saniye sifir Duration doner', () {
      expect(saniyeyeGoreKonum(0), Duration.zero);
    });

    test('buyuk bir video suresini (114 sn = 1:54) dogru cevirir', () {
      expect(saniyeyeGoreKonum(114.0), const Duration(minutes: 1, seconds: 54));
    });
  });
}
