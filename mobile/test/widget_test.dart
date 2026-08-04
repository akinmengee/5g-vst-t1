import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:teknofest_mobile/app.dart';

void main() {
  testWidgets('NV ekranı açılışta MSISDN girişi ve Sign in butonu gösterir', (tester) async {
    await tester.pumpWidget(const TeknofestApp());

    expect(find.text('Verify your number'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Sign in'), findsOneWidget);
  });
}
