import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:teknofest_mobile/app.dart';

void main() {
  testWidgets('NV ekranı açılışta numara girişi ve Doğrula butonu gösterir', (tester) async {
    await tester.pumpWidget(const TeknofestApp());

    expect(find.text('Numaranı doğrula'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Doğrula'), findsOneWidget);
    // Sandbox numarası alan içinde hazır gelir (UX Kılavuzu test numarası).
    expect(find.textContaining('5390000020'), findsOneWidget);
  });
}
