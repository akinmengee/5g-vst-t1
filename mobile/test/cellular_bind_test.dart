import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teknofest_mobile/services/cellular_network_service.dart';

/// 7 Ağustos gecesi yaşanan arızanın regresyon testleri.
///
/// Belirti: uygulama backend'e HİÇBİR istek gönderemiyordu ("connection
/// failed"), oysa aynı anda telefonun tarayıcısından `/health` sorunsuz
/// açılıyordu. Sebep: NV akışındaki `bindProcessToNetwork` bağlaması —
/// TÜM uygulamayı bir Network'e bağlıyor — temizlenmeden asılı kalıp
/// bayatlıyordu.
///
/// Kök nedenlerden biri Dart tarafındaydı: bind çağrısının bekleme payı
/// (3 sn) native tarafın kendi zaman aşımından (5 sn) KISAYDI. Arada kalan
/// pencerede Dart "başarısız" sanıp unbind'i atlıyor, native taraf ise
/// bağlamayı yapıyordu → kimsenin temizlemediği kalıcı bağlama.

const _kanal = MethodChannel('com.vstt1.teknofest_mobile/cellular_network');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<String> cagrilar;
  final servis = CellularNetworkService();

  /// [gecikme] kadar bekleyip [cevap] dönen sahte native taraf.
  void nativeTarafi({
    required Object? cevap,
    Duration gecikme = Duration.zero,
    Object? firlat,
  }) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_kanal, (call) async {
      cagrilar.add(call.method);
      if (gecikme > Duration.zero) await Future<void>.delayed(gecikme);
      if (firlat != null) throw firlat;
      return cevap;
    });
  }

  setUp(() => cagrilar = []);

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_kanal, null);
  });

  group('bindToCellular', () {
    test('native true dönerse bağlama başarılı sayılır', () async {
      nativeTarafi(cevap: true);
      expect(await servis.bindToCellular(), isTrue);
      expect(cagrilar, ['bindCellular']);
    });

    test('native false (hücresel ağ yok) çökertmez', () async {
      nativeTarafi(cevap: false);
      expect(await servis.bindToCellular(), isFalse);
    });

    test('native tarafın 5 sn\'lik penceresi Dart payının İÇİNDE kalır', () async {
      // Kritik regresyon: Dart payı eskiden 3 sn'ydi ve native taraf 5 sn'ye
      // kadar cevap verebiliyordu. Aradaki 2 sn'lik pencerede Dart pes edip
      // "false" diyor, native taraf ise bağlamayı yapıyordu — bağlama kimse
      // tarafından temizlenmiyordu. Artık pay 8 sn: native her cevabı yetişir.
      nativeTarafi(cevap: true, gecikme: const Duration(seconds: 5));

      final basladi = DateTime.now();
      final sonuc = await servis.bindToCellular();

      expect(sonuc, isTrue,
          reason: '5 sn\'de gelen native cevap zaman aşımına düşmemeli');
      expect(DateTime.now().difference(basladi).inSeconds, lessThan(8));
    });

    test('PlatformException yutulur (akış kilitlenmez)', () async {
      nativeTarafi(
        cevap: null,
        firlat: PlatformException(code: 'CELLULAR_BIND_FAILED'),
      );
      expect(await servis.bindToCellular(), isFalse);
    });

    test('MissingPluginException yutulur (Android dışı platform)', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_kanal, null); // handler yok = eklenti yok
      expect(await servis.bindToCellular(), isFalse);
    });
  });

  group('unbind — her koşulda güvenli', () {
    test('normal durumda native unbind çağrılır', () async {
      nativeTarafi(cevap: null);
      await servis.unbind();
      expect(cagrilar, ['unbind']);
    });

    test('native hata fırlatsa bile istisna DIŞARI sızmaz', () async {
      // Sızarsa submitPhoneNumber'daki finally patlar ve NV akışı kilitlenir.
      nativeTarafi(cevap: null, firlat: PlatformException(code: 'HATA'));
      await expectLater(servis.unbind(), completes);
    });

    test('eklenti yokken (Windows/web) çökertmez', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_kanal, null);
      await expectLater(servis.unbind(), completes);
    });

    test('native takılırsa 2 sn\'de kendini kurtarır (akış donmaz)', () async {
      nativeTarafi(cevap: null, gecikme: const Duration(seconds: 30));

      final basladi = DateTime.now();
      await servis.unbind();

      expect(DateTime.now().difference(basladi).inSeconds, lessThan(5),
          reason: 'unbind kritik değil; sonsuza dek beklenmemeli');
    });

    test('art arda çağırmak güvenli (idempotent)', () async {
      nativeTarafi(cevap: null);
      await servis.unbind();
      await servis.unbind();
      await servis.unbind();
      expect(cagrilar, ['unbind', 'unbind', 'unbind']);
    });
  });
}
