import 'package:flutter/services.dart';

/// MainActivity.kt'deki native koda köprü: NV `/authorize` isteği atılırken
/// process'i geçici olarak hücresel (SIM) ağa bind eder.
///
/// [unbind] HER ZAMAN çağrılmalı — [bindToCellular] `false` dönse bile.
/// Native taraf, Dart tarafı beklemekten vazgeçtikten sonra bağlamayı yapmış
/// olabilir; o bağlama temizlenmezse `bindProcessToNetwork` yüzünden
/// uygulamanın TAMAMI ölü bir ağa bağlı kalır ve hiçbir istek çıkamaz
/// (7 Ağustos: backend sağlamken login isteği bile gönderilemedi).
class CellularNetworkService {
  static const _channel = MethodChannel('com.vstt1.teknofest_mobile/cellular_network');

  /// Native taraf en geç `MainActivity.CELLULAR_REQUEST_TIMEOUT_MS` (5 sn)
  /// içinde kesin cevap verir. Buradaki pay bilerek ondan UZUN: daha kısa
  /// olursa Dart "başarısız" sanır, native taraf ise sonradan bağlar ve
  /// bağlama asılı kalır. Yine de sonsuz bekleme olmasın diye bir tavan var.
  static const _bindTimeout = Duration(seconds: 8);

  Future<bool> bindToCellular() async {
    try {
      final result = await _channel
          .invokeMethod<bool>('bindCellular')
          .timeout(_bindTimeout, onTimeout: () => false);
      return result ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      // Android dışı platform (Windows/Chrome üzerinde geliştirme) — no-op.
      return false;
    }
  }

  /// Bağlamayı bırakır. Idempotent ve güvenli: bağlama yoksa native tarafta
  /// no-op'tur, hata fırlatmaz. Şüphe duyulan her yerde çağrılabilir —
  /// bayat bir bağlamayı temizlemenin maliyeti yok, temizlememenin maliyeti
  /// uygulamanın tüm ağının ölmesi.
  Future<void> unbind() async {
    try {
      await _channel
          .invokeMethod('unbind')
          .timeout(const Duration(seconds: 2), onTimeout: () => null);
    } on PlatformException {
      // yut, unbind kritik değil
    } on MissingPluginException {
      // Android dışı platform — no-op.
    }
  }
}
