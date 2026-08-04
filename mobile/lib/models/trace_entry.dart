enum TraceStatus { pending, success, error }

/// Open Gateway Demo UX Kılavuzu → "07 Trace": her adımın (NV/QoD/upload/AI)
/// gerçek istek/yanıt izini şeffaf şekilde gösterir. Mock modda da aynı
/// şekilde doldurulur ki demo sırasında görünüm tutarlı olsun.
class TraceEntry {
  final String method;
  final String path;
  final DateTime startedAt;
  Duration? duration;
  int? statusCode;
  TraceStatus status;

  TraceEntry({
    required this.method,
    required this.path,
    required this.startedAt,
    this.duration,
    this.statusCode,
    this.status = TraceStatus.pending,
  });
}
