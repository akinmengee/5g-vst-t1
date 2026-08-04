import 'package:flutter/services.dart';

/// MainActivity.kt'deki native koda köprü: NV `/authorize` isteği atılırken
/// process'i geçici olarak hücresel (SIM) ağa bind eder. İstek bitince
/// [unbind] çağrılmalı, yoksa cihazın tüm trafiği cellular'da kalır.
class CellularNetworkService {
  static const _channel = MethodChannel('com.vstt1.teknofest_mobile/cellular_network');

  Future<bool> bindToCellular() async {
    try {
      // Native taraf herhangi bir sebeple yanıt vermezse NV akışı sonsuza dek
      // beklememeli: bind başarısız sayılır, doğrulama yine denenir (cihaz
      // zaten mobil verideyse bind şart değildir).
      final result = await _channel
          .invokeMethod<bool>('bindCellular')
          .timeout(const Duration(seconds: 3), onTimeout: () => false);
      return result ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      // Android dışı platform (macOS/Chrome üzerinde geliştirme) — no-op.
      return false;
    }
  }

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
