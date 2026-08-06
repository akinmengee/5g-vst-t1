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

  UploadState uploadState = UploadState.none;
  String? uploadError;

  /// Backend'in verdiği iş numarası; upload başarılı olana dek null.
  String? jobId;
  AiResultStatus aiStatus = AiResultStatus.idle;
  AiResult? aiResult;

  /// Upload başarılı olup iş PROCESSING'e geçtiği an — AI Sonucu ekranındaki
  /// canlı sayaç bu andan itibaren sayar (yarışma kuralı: maks. 10 dk).
  DateTime? processingStartedAt;

  /// Sonuç JSON'unun SHA256'sı — sonuç geldiğinde BİR KEZ hesaplanır
  /// (ekran her çizilişinde yeniden hesaplanmaz).
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
