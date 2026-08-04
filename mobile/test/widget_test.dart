import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:teknofest_mobile/app.dart';
import 'package:teknofest_mobile/config/app_config.dart';

/// Mock akış testi `USE_MOCK=true` derleme bayrağını ister (varsayılan false —
/// gerçek backend modu). Çalıştırma:
///
/// ```
/// flutter test --dart-define=USE_MOCK=true            # mock UI akışı dahil
/// flutter test                                        # yalnızca mock istemeyenler
/// ```
void main() {
  testWidgets('NV ekranı açılışta numara girişi ve Doğrula butonu gösterir', (tester) async {
    await tester.pumpWidget(const TeknofestApp());

    expect(find.text('Numaranı doğrula'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Doğrula'), findsOneWidget);
    // Sandbox numarası alan içinde hazır gelir (UX Kılavuzu test numarası).
    expect(find.textContaining('5390000020'), findsOneWidget);
  });

  testWidgets(
    'Mock NV akışı: Doğrula -> login -> status polling -> Home',
    skip: !AppConfig.useMock,
    (tester) async {
      await tester.pumpWidget(const TeknofestApp());

      await tester.tap(find.widgetWithText(FilledButton, 'Doğrula'));

      // Mock zamanlaması: login ~600ms + cellular bind timeout'u (test
      // ortamında kanal yanıtsızdır, 3 sn'de düşer) + ~1 sn aralıklı status
      // polling (2. denemede "verified"). Sahte saati adım adım ilerlet.
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 500));
      }

      // Auth-gate: Home açıldı, sözleşme adımları görünür durumda.
      expect(find.text('QoD Session'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'QoD Aç'), findsOneWidget);
    },
  );
}
