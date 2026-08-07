import 'package:flutter_test/flutter_test.dart';
import 'package:teknofest_mobile/models/recording_item.dart';
import 'package:teknofest_mobile/state/session_controller.dart';

/// 7 Ağustos: "upload işi bittikten sonra qod kapansın" isteğinin en riskli
/// kısmı — QoD'yi durdurmak Turkcell tarafında cihazın TÜM veri bağlantısını
/// resetliyor, yani BAŞKA bir kayıt/yükleme sürerken durdurursak onu da
/// koparırız. Bu test paketi yalnızca o karar mantığını (network'süz, saf
/// fonksiyon) doğruluyor — gerçek `_qodService.stop()` çağrısı ayrı.
void main() {
  group('SessionController.qodDurdurmaGuvenli', () {
    test('QoD basarisizsa/aktif degilse asla durdurma', () {
      expect(
        SessionController.qodDurdurmaGuvenli(
          qodBasarili: false,
          recording: false,
          digerYuklemeDurumlari: const [],
        ),
        isFalse,
      );
    });

    test('aktif bir kayit surerken durdurma', () {
      expect(
        SessionController.qodDurdurmaGuvenli(
          qodBasarili: true,
          recording: true,
          digerYuklemeDurumlari: const [],
        ),
        isFalse,
      );
    });

    test('baska bir kayit hala yukleniyorsa durdurma (en kritik durum)', () {
      // Bu, tam da "başka bir yüklemeyi koparma" riskinin kendisi.
      expect(
        SessionController.qodDurdurmaGuvenli(
          qodBasarili: true,
          recording: false,
          digerYuklemeDurumlari: const [UploadState.uploading],
        ),
        isFalse,
      );
    });

    test('birden fazla kayit varsa TEK biri yukleniyor olsa bile durdurma', () {
      expect(
        SessionController.qodDurdurmaGuvenli(
          qodBasarili: true,
          recording: false,
          digerYuklemeDurumlari: const [
            UploadState.uploaded,
            UploadState.uploading,
            UploadState.none,
          ],
        ),
        isFalse,
      );
    });

    test('hicbir aktif kayit/yukleme yoksa GUVENLI', () {
      expect(
        SessionController.qodDurdurmaGuvenli(
          qodBasarili: true,
          recording: false,
          digerYuklemeDurumlari: const [
            UploadState.uploaded,
            UploadState.failed,
            UploadState.none,
          ],
        ),
        isTrue,
      );
    });

    test('tek kayit basariyla yuklendiyse ve baska is yoksa GUVENLI', () {
      expect(
        SessionController.qodDurdurmaGuvenli(
          qodBasarili: true,
          recording: false,
          digerYuklemeDurumlari: const [UploadState.uploaded],
        ),
        isTrue,
      );
    });
  });
}
