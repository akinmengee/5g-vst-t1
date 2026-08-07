import 'ai_result.dart';

enum UploadState { none, uploading, uploaded, failed }

/// Tek bir stream kaydının tüm yaşam döngüsü: dosya -> (Lifebox / backend
/// upload) -> AI işi -> sonuç. VideoCard'daki kayıt listesi ve AI Sonucu
/// sekmesindeki iş listesi aynı nesneleri paylaşır — durum tek yerde yaşar.
class RecordingItem {
  final String path;
  final String name;
  final DateTime createdAt;
  final Duration duration;
  int? sizeBytes;

  /// true: ffprobe ile ölçülen gerçek süre, HLS playlist'inin beklenen
  /// TOPLAM süresinden belirgin şekilde kısa çıktı — muhtemelen ağ/QoD
  /// kesintisiyle kayıt erken bitti (bkz. `VideoRecordingService._dogrulaSure`).
  /// Dosya yine de listeye eklenir (tamamen gizlemek daha kötü) ama bu
  /// bayrak UI'da net bir uyarı ve upload öncesi onay diyaloğu tetikler.
  bool supheliSure = false;
  double? beklenenSaniye;
  double? gercekSaniye;

  UploadState uploadState = UploadState.none;
  String? uploadError;

  /// Backend'in verdiği iş numarası; upload başarılı olana dek null.
  String? jobId;
  AiResultStatus aiStatus = AiResultStatus.idle;
  AiResult? aiResult;

  /// Upload başarılı olup iş PROCESSING'e geçtiği an — AI Sonucu ekranındaki
  /// canlı sayaç bu andan itibaren sayar (yarışma kuralı: maks. 10 dk).
  DateTime? processingStartedAt;

  /// Lifebox'a yüklenecek results.json metni: boşluksuz (minified).
  /// Aşağıdaki iki hash tam olarak BU metinden üretilir — dosya ile parmak
  /// izinin ayrışması bu sayede imkânsız.
  String? resultsJsonMinified;

  /// Organizasyonun istediği parmak izi: [resultsJsonMinified]'in MD5'i
  /// (32 hex karakter). Ekranda ilk 7 karakteri açık, gerisi maskeli gösterilir.
  String? resultsMd5;

  /// Aynı metnin SHA256'sı — bilgi amaçlı. Yarışmanın istediği SHA256 Docker
  /// İMAJINA ait ayrı bir değerdir, bu değil.
  String? resultsSha256;

  RecordingItem({
    required this.path,
    required this.name,
    required this.createdAt,
    this.duration = Duration.zero,
    this.sizeBytes,
  });

  bool get uploaded => uploadState == UploadState.uploaded;

  String get saat {
    String iki(int v) => v.toString().padLeft(2, '0');
    return '${iki(createdAt.hour)}:${iki(createdAt.minute)}:${iki(createdAt.second)}';
  }

  String? get boyutMetni {
    final b = sizeBytes;
    if (b == null || b <= 0) return null;
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(0)} KB';
    return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String? get sureMetni {
    if (duration == Duration.zero) return null;
    final m = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}
