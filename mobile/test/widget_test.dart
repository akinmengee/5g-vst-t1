import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:teknofest_mobile/app.dart';

void main() {
  testWidgets('NV ekranı açılışta numara girişi ve Doğrula butonu gösterir', (tester) async {
    await tester.pumpWidget(const TeknofestApp());

    expect(find.text('Numaranı doğrula'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Doğrula'), findsOneWidget);
  });

  testWidgets('telefon alani BOS acilir — yanlis numara on-doldurulmaz',
      (tester) async {
    // Eskiden UX Kılavuzu'ndaki test numarası hazır geliyordu. Gerçek SIM
    // geldikten sonra kaldırıldı: yarışma günü elimizdeki hattın numarası
    // girilecek ve başka bir numara önceden dolu gelirse doğrulama sessizce
    // reddedilir. `--dart-define=PHONE=...` verilmedikçe alan boş olmalı.
    await tester.pumpWidget(const TeknofestApp());

    final alan = tester.widget<TextField>(find.byType(TextField).first);
    expect(alan.controller!.text, isEmpty);
  });
}
