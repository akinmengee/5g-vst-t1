import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:teknofest_mobile/models/ai_result.dart';
import 'package:teknofest_mobile/models/recording_item.dart';
import 'package:teknofest_mobile/screens/ai_result_screen.dart';
import 'package:teknofest_mobile/state/session_controller.dart';

/// Bug (arkadaşımızın 6 Ağustos ekran görüntüsüyle bildirdiği): "AI
/// Sonuçları" listesindeki satırda tam job_id (36 karakterlik UUID),
/// `Expanded` metninden SONRA sınırsız genişlikte render ediliyordu. Row,
/// esnek olmayan çocukları önce doğal genişliklerinde ölçtüğü için dar bir
/// telefon ekranında UUID neredeyse tüm satırı yiyor, `Expanded` içindeki
/// "HH:MM:SS kaydı" metnine kalan yer o kadar daralıyordu ki her karakter
/// ayrı satıra düşüyordu.
void main() {
  // Gerçek bir telefon genişliği (çoğu Android cihazda mantıksal genişlik
  // ~360-412dp) — hata yalnızca dar ekranda ortaya çıkıyordu, testin
  // varsayılan 800px genişlikte geçmemesi (yanlış bir güven vermemesi)
  // için bilerek daraltıyoruz.
  Future<void> darEkran(WidgetTester tester) async {
    // 430: gerçekçi bir telefon genişliği, AMA _JobList'in üst başlık
    // satırındaki (ai_result_screen.dart:104, bu testin kapsamı dışında)
    // ayrı bir taşmayı tetiklemeyecek kadar geniş — o taşma test ortamının
    // özel fontu (Inter) yüklemeden yedek fontla ölçmesinden kaynaklanıyor
    // olabilir (flutter_test_config.dart yok), gerçek cihazda doğrulanmadı.
    tester.view.physicalSize = const Size(430, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  RecordingItem uzunUuidliIs() {
    final item = RecordingItem(
      path: '/tmp/kayit_20260806_235523.mp4',
      name: 'kayit_20260806_235523.mp4',
      createdAt: DateTime(2026, 8, 6, 23, 55, 23),
    );
    item.jobId = '5ebbef94-2875-49f0-a8bb-12f4317710f9'; // gerçek bug'daki ID
    // `processing` DEĞİL: AiResultTab.initState() processing durumundaki
    // işleri gerçek backend'e poll'lamaya çalışıp bir Timer kuruyor — bu izole
    // layout testinde ağa hiç dokunmak istemiyoruz. Kök neden (jobId
    // metninin genişliği) durumdan bağımsız, `done` ile de aynen üretiliyor.
    item.aiStatus = AiResultStatus.done;
    return item;
  }

  testWidgets(
    'uzun job_id, dar ekranda "saat kaydı" metnini karakter karakter kırdırmıyor',
    (tester) async {
      await darEkran(tester);

      final controller = SessionController();
      controller.recordings.add(uzunUuidliIs());

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: controller,
          child: const MaterialApp(home: Scaffold(body: AiResultTab())),
        ),
      );
      await tester.pumpAndSettle();

      final metinBul = find.textContaining('23:55:23');
      expect(metinBul, findsOneWidget,
          reason: '"HH:MM:SS kaydı" tek bir Text widget olarak bulunmalı '
              '(kırılmış olsa bile widget hâlâ tek — kanıt render '
              'yüksekliğinde, bkz. aşağıdaki assert)');

      // Kırılma widget ağacında değil, RenderParagraph'ın çizim
      // yüksekliğinde görünür: satır başına ~17px (fontSize 13.5), sağlıklı
      // 1 satırlık metin ~20px'i geçmez. Eski (düzeltilmemiş) kodda "23:55:23
      // kaydı" 12+ karaktere bölünüp ~200px'e çıkardı — bu eşik onu yakalar.
      final yukseklik = tester.getSize(metinBul).height;
      expect(yukseklik, lessThan(24),
          reason: 'Metin tek satıra sığmalı; $yukseklik px, karakter '
              'karakter kırıldığını (çoklu satır) gösteriyor olabilir.');
    },
  );

  testWidgets('_kisaJobId davranışı: liste satırında tam UUID görünmüyor',
      (tester) async {
    await darEkran(tester);

    final controller = SessionController();
    controller.recordings.add(uzunUuidliIs());

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: const MaterialApp(home: Scaffold(body: AiResultTab())),
      ),
    );
    await tester.pumpAndSettle();

    // Tam UUID artık ekranda YOK (kısaltıldı) — tam metni arayan bir test
    // bulamamalı.
    expect(find.text('5ebbef94-2875-49f0-a8bb-12f4317710f9'), findsNothing);
    // Kısaltılmış önizleme (ilk 8 karakter + …) görünüyor olmalı.
    expect(find.textContaining('5ebbef94'), findsOneWidget);
  });
}
