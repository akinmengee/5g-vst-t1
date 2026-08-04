import 'package:flutter_test/flutter_test.dart';
import 'package:teknofest_mobile/models/ai_result.dart';

/// docs/mobile-integration.md § 2.6'daki `results` gövdesinin birebir kopyası.
/// Backend bu şemayı değiştirirse burası kırılır — sözleşmenin mobil tarafındaki
/// bekçisi bu test.
const _sozlesmedekiOrnek = {
  'video_id': 'video.mp4',
  'arac_bilgisi': {
    'tip': 'sedan',
    'plaka': '34ABC123',
    'renk': 'beyaz',
    'confidence_score': 0.94,
  },
  'tespitler': [
    {
      'zaman_saniye': 14.5,
      'kategori': 'sofor_eylemi',
      'etiket': 'telefonla_konusma',
      'confidence_score': 0.89,
    },
  ],
};

void main() {
  test('sozlesmedeki results govdesi tam olarak ayristirilir', () {
    final sonuc = AiResult.fromJson(Map<String, dynamic>.from(_sozlesmedekiOrnek));

    expect(sonuc.videoId, 'video.mp4');
    expect(sonuc.vehicleInfo?.tip, 'sedan');
    expect(sonuc.vehicleInfo?.plaka, '34ABC123');
    expect(sonuc.vehicleInfo?.confidenceScore, 0.94);
    expect(sonuc.detections, hasLength(1));
    expect(sonuc.detections.first.etiket, 'telefonla_konusma');
    expect(sonuc.detections.first.zamanSaniye, 14.5);
    expect(sonuc.detections.first.kategori, 'sofor_eylemi');
  });

  test('ayni etiket farkli zamanlarda tekrar edebilir', () {
    // Sözleşme § 2.6: "aynı etiket farklı zamanlarda TEKRAR EDEBİLİR,
    // normaldir" — tespitler tekilleştirilmemeli.
    final sonuc = AiResult.fromJson({
      'tespitler': [
        {'zaman_saniye': 10.0, 'etiket': 'sigara_icme'},
        {'zaman_saniye': 25.0, 'etiket': 'sigara_icme'},
      ],
    });

    expect(sonuc.detections, hasLength(2));
    expect(sonuc.detections.map((d) => d.zamanSaniye), [10.0, 25.0]);
  });

  test('eksik alanlar cokme yerine null verir', () {
    // AI tarafı henüz teslim edilmedi; alanların bir kısmı eksik gelirse
    // ekran çökmemeli, "-" göstermeli.
    final sonuc = AiResult.fromJson({'video_id': 'video.mp4'});

    expect(sonuc.vehicleInfo, isNull);
    expect(sonuc.detections, isEmpty);
    expect(sonuc.videoId, 'video.mp4');
  });

  test('tam sayi gelen confidence degeri double olarak okunur', () {
    // JSON'da 1 (int) gelirse `as double` cast'i patlardı; num üzerinden
    // okunduğu için sorun yok.
    final sonuc = AiResult.fromJson({
      'tespitler': [
        {'zaman_saniye': 3, 'etiket': 'esneme', 'confidence_score': 1},
      ],
    });

    expect(sonuc.detections.first.confidenceScore, 1.0);
    expect(sonuc.detections.first.zamanSaniye, 3.0);
  });
}
