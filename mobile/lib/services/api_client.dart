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

    // FormData tek kullanımlık bir akıştır (MultipartFile.fromFile dosyayı
    // stream'ler): aynı gövdeyi ikinci kez göndermek sessizce başarısız olur.
    // Video yüklemesinin yeniden denemesi bu yüzden burada değil, kullanıcıya
    // gösterilen "Tekrar Dene" akışında.
    final isReplayable = requestOptions.data is! FormData;
    final isRetryable = err.type == DioExceptionType.connectionTimeout ||
        err.type == DioExceptionType.sendTimeout ||
        err.type == DioExceptionType.receiveTimeout ||
        err.type == DioExceptionType.connectionError;

    if (isReplayable && isRetryable && attempt < maxRetries) {
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

/// Sözleşme § 3: tüm hata gövdeleri FastAPI standardıdır — `{"detail": "..."}`.
///
/// Validasyon hatalarında (§ 2.1'deki 422: bozuk telefon formatı) FastAPI
/// `detail`'i bir STRING değil hata listesi olarak döndürür; doğrudan String'e
/// cast etmek orada tip hatası fırlatır. Bu yüzden tek yerde ve tip-güvenli.
String? backendDetail(DioException e) {
  final data = e.response?.data;
  if (data is! Map) return null;
  final detail = data['detail'];
  return detail is String ? detail : null;
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
