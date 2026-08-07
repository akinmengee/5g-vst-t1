import 'package:flutter_test/flutter_test.dart';
import 'package:teknofest_mobile/config/app_config.dart';

/// 7 Ağustos: yarışma hızını simüle eden iki test-only bayrak eklendi
/// (TEST_REALTIME_PACE, TEST_UPLOAD_KBPS). Bu test, bir --dart-define
/// VERİLMEDEN ikisinin de KAPALI olduğunu kilitliyor — yarışma build'inin
/// yanlışlıkla yavaşlatılmış gitmesine karşı tek satırlık bir güvence.
void main() {
  test('test bayraklari varsayilan olarak KAPALI', () {
    expect(AppConfig.testRealtimePace, isFalse);
    expect(AppConfig.testUploadThrottleKbps, 0);
  });
}
