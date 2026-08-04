import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teknofest_mobile/app.dart';
import 'package:teknofest_mobile/config/app_config.dart';

void main() {
  testWidgets('NV ekrani acilista numara girisi ve Dogrula butonu gosterir', (tester) async {
    await tester.pumpWidget(const TeknofestApp());

    expect(find.text('Numaranı doğrula'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Doğrula'), findsOneWidget);
  });

  testWidgets('sandbox test numarasi hazir gelir ve ulke kodu ayri gosterilir', (tester) async {
    await tester.pumpWidget(const TeknofestApp());

    // Sözleşme § 5: sandbox numarası +905390000020. Ülke kodu form alanının
    // dışında sabit duruyor, alanda yalnızca yerel kısım var.
    expect(find.text('+90'), findsOneWidget);
    final alan = tester.widget<TextField>(find.byType(TextField));
    expect(alan.controller?.text, AppConfig.sandboxTestPhoneNumber.substring(3));
  });
}
