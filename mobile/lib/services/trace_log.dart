import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../models/trace_entry.dart';

/// Tüm NV/QoD/upload/AI çağrılarının tek ortak izi. Gerçek modda
/// [TraceInterceptor] üzerinden, mock modda servislerin kendi
/// `record()` çağrılarından besleniyor — ikisi de aynı görünümü üretir.
class TraceLog extends ChangeNotifier {
  final List<TraceEntry> entries = [];

  TraceEntry start(String method, String path) {
    final entry = TraceEntry(method: method, path: path, startedAt: DateTime.now());
    entries.add(entry);
    notifyListeners();
    return entry;
  }

  void complete(TraceEntry entry, {int? statusCode, bool error = false}) {
    entry.duration = DateTime.now().difference(entry.startedAt);
    entry.statusCode = statusCode;
    entry.status = error ? TraceStatus.error : TraceStatus.success;
    notifyListeners();
  }

  /// Mock servisler için: tamamlanmış bir çağrıyı doğrudan (simüle edilmiş
  /// süreyle) ekler.
  void record({
    required String method,
    required String path,
    required Duration duration,
    required int statusCode,
  }) {
    entries.add(TraceEntry(
      method: method,
      path: path,
      startedAt: DateTime.now().subtract(duration),
      duration: duration,
      statusCode: statusCode,
      status: TraceStatus.success,
    ));
    notifyListeners();
  }

  Duration get totalDuration {
    if (entries.isEmpty) return Duration.zero;
    final durations = entries.where((e) => e.duration != null).map((e) => e.duration!);
    if (durations.isEmpty) return Duration.zero;
    return durations.reduce((a, b) => a + b);
  }
}

class TraceInterceptor extends Interceptor {
  final TraceLog traceLog;
  TraceInterceptor(this.traceLog);

  static const _kEntryKey = 'traceEntry';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.extra[_kEntryKey] = traceLog.start(options.method, options.path);
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final entry = response.requestOptions.extra[_kEntryKey] as TraceEntry?;
    if (entry != null) {
      traceLog.complete(entry, statusCode: response.statusCode);
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final entry = err.requestOptions.extra[_kEntryKey] as TraceEntry?;
    if (entry != null) {
      traceLog.complete(entry, statusCode: err.response?.statusCode, error: true);
    }
    handler.next(err);
  }
}
