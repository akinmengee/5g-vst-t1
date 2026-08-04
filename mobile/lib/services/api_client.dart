import 'package:dio/dio.dart';

import '../config/app_config.dart';
import 'trace_log.dart';

/// Şartname: "Mobil uygulama ve backend arasında, ağ koşullarından
/// kaynaklanabilecek gecikmeleri test etmeli ve önlemini almalı." Bu yüzden
/// her istek için makul timeout + bağlantı hatalarında otomatik kısa retry.
class RetryInterceptor extends Interceptor {
  final int maxRetries;
  final Duration retryDelay;

  RetryInterceptor({this.maxRetries = 2, this.retryDelay = const Duration(seconds: 1)});

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final requestOptions = err.requestOptions;
    final attempt = (requestOptions.extra['retryAttempt'] as int?) ?? 0;

    final isRetryable = err.type == DioExceptionType.connectionTimeout ||
        err.type == DioExceptionType.sendTimeout ||
        err.type == DioExceptionType.receiveTimeout ||
        err.type == DioExceptionType.connectionError;

    if (isRetryable && attempt < maxRetries) {
      await Future.delayed(retryDelay * (attempt + 1));
      requestOptions.extra['retryAttempt'] = attempt + 1;
      try {
        final dio = Dio()..options = requestOptions.copyWith().toBaseOptions();
        final response = await dio.fetch(requestOptions);
        return handler.resolve(response);
      } catch (_) {
        // düşsün, aşağıdaki handler.next(err) çalışsın
      }
    }
    handler.next(err);
  }
}

extension on RequestOptions {
  BaseOptions toBaseOptions() {
    return BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: connectTimeout,
      sendTimeout: sendTimeout,
      receiveTimeout: receiveTimeout,
      headers: headers,
    );
  }
}

class ApiClient {
  static final ApiClient instance = ApiClient._();
  late final Dio dio;
  final TraceLog traceLog = TraceLog();

  ApiClient._() {
    dio = Dio(
      BaseOptions(
        baseUrl: AppConfig.backendBaseUrl,
        connectTimeout: const Duration(seconds: 8),
        sendTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 15),
      ),
    );
    // Trace, retry'den ÖNCE eklenir ki her deneme değil sadece dış-yüzey
    // istek/yanıt görünsün (retry içteki `dio.fetch` ayrı bir Dio ile gider).
    dio.interceptors.add(TraceInterceptor(traceLog));
    dio.interceptors.add(RetryInterceptor());
  }
}
