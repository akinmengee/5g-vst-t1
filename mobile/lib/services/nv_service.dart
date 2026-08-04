import 'package:dio/dio.dart';

import '../config/app_config.dart';
import 'api_client.dart';

/// mobile-integration.md § 2.1, 2.3. Bu servis atomik iki işlem sunar;
/// WebView'i açma/kapatma ve polling döngüsü SessionController'da — çünkü
/// UI (WebView'i göstermek) ile koordine olmaları gerekiyor.
class LoginResult {
  final bool success;
  final String? flowId;
  final String? authorizeUrl;
  final String? errorMessage;

  const LoginResult({required this.success, this.flowId, this.authorizeUrl, this.errorMessage});
}

enum AuthPollStatus { pending, verified, rejected, error, notFound }

class AuthPollResult {
  final AuthPollStatus status;
  final bool? devicePhoneNumberVerified;
  final String? errorCode;
  final String? message;

  const AuthPollResult({
    required this.status,
    this.devicePhoneNumberVerified,
    this.errorCode,
    this.message,
  });
}

/// Şartname/backend: cihaz WiFi'deyken NV kesin başarısız olur. Bu kod
/// gelirse kullanıcıya "mobil veriyi açın" mesajı gösterilmeli.
const kWifiErrorCode = 'NUMBER_VERIFICATION.USER_NOT_AUTHENTICATED_BY_MOBILE_NETWORK';

class NvService {
  final Dio _dio = ApiClient.instance.dio;

  Future<LoginResult> startLogin(String phoneNumber) async {
    if (AppConfig.useMock) return _mockStartLogin(phoneNumber);

    try {
      final response = await _dio.post('/api/auth/login', data: {'phoneNumber': phoneNumber});
      return LoginResult(
        success: true,
        flowId: response.data['flow_id'] as String?,
        authorizeUrl: response.data['authorize_url'] as String?,
      );
    } on DioException catch (e) {
      final detail = e.response?.data is Map ? e.response?.data['detail'] as String? : null;
      return LoginResult(success: false, errorMessage: detail ?? e.message ?? 'Giriş başarısız');
    }
  }

  Future<AuthPollResult> checkStatus(String flowId) async {
    if (AppConfig.useMock) return const AuthPollResult(status: AuthPollStatus.verified);

    try {
      final response = await _dio.get('/api/auth/status/$flowId');
      final raw = response.data['status'] as String? ?? 'pending';
      return AuthPollResult(
        status: switch (raw) {
          'verified' => AuthPollStatus.verified,
          'rejected' => AuthPollStatus.rejected,
          'error' => AuthPollStatus.error,
          _ => AuthPollStatus.pending,
        },
        devicePhoneNumberVerified: response.data['devicePhoneNumberVerified'] as bool?,
        errorCode: response.data['error_code'] as String?,
        message: response.data['message'] as String?,
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return const AuthPollResult(status: AuthPollStatus.notFound);
      }
      return const AuthPollResult(status: AuthPollStatus.pending);
    }
  }

  Future<LoginResult> _mockStartLogin(String phoneNumber) async {
    await Future.delayed(const Duration(milliseconds: 500));
    ApiClient.instance.traceLog.record(
      method: 'POST',
      path: '/api/auth/login',
      duration: const Duration(milliseconds: 210),
      statusCode: 200,
    );
    return LoginResult(
      success: true,
      flowId: 'mock-flow-${DateTime.now().millisecondsSinceEpoch}',
      authorizeUrl: null,
    );
  }
}
