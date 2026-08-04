enum AiResultStatus { idle, processing, done, failed }

class VehicleInfo {
  final String? tip;
  final String? plaka;
  final String? renk;
  final double? confidenceScore;

  const VehicleInfo({this.tip, this.plaka, this.renk, this.confidenceScore});

  factory VehicleInfo.fromJson(Map<String, dynamic> json) {
    return VehicleInfo(
      tip: json['tip'] as String?,
      plaka: json['plaka'] as String?,
      renk: json['renk'] as String?,
      confidenceScore: (json['confidence_score'] as num?)?.toDouble(),
    );
  }
}

class Detection {
  final double? zamanSaniye;
  final String? kategori;
  final String? etiket;
  final double? confidenceScore;

  const Detection({this.zamanSaniye, this.kategori, this.etiket, this.confidenceScore});

  factory Detection.fromJson(Map<String, dynamic> json) {
    return Detection(
      zamanSaniye: (json['zaman_saniye'] as num?)?.toDouble(),
      kategori: json['kategori'] as String?,
      etiket: json['etiket'] as String?,
      confidenceScore: (json['confidence_score'] as num?)?.toDouble(),
    );
  }
}

/// FTR'de (5G_VST_T1_FTR.pdf) tarif edilen results.json şeması. Atamert'in AI
/// çıktısı bu alan adlarını değiştirirse sadece burası güncellenir.
class AiResult {
  final String? videoId;
  final VehicleInfo? vehicleInfo;
  final List<Detection> detections;
  final Map<String, dynamic> raw;

  const AiResult({
    this.videoId,
    this.vehicleInfo,
    this.detections = const [],
    this.raw = const {},
  });

  factory AiResult.fromJson(Map<String, dynamic> json) {
    final aracBilgisi = json['arac_bilgisi'] as Map<String, dynamic>?;
    final tespitler = json['tespitler'] as List<dynamic>?;
    return AiResult(
      videoId: json['video_id'] as String?,
      vehicleInfo: aracBilgisi != null ? VehicleInfo.fromJson(aracBilgisi) : null,
      detections: tespitler
              ?.whereType<Map<String, dynamic>>()
              .map(Detection.fromJson)
              .toList() ??
          const [],
      raw: json,
    );
  }
}
