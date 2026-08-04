import 'package:dio/dio.dart';

import '../config/app_config.dart';
import 'api_client.dart';

/// mobile-integration.md 2.1 — `POST /api/auth/login` cevabı.
class NvLoginResult {
  final String? flowId;
  final String? authorizeUrl;
  final String? errorMessage;

  const NvLoginResult({this.flowId, this.authorizeUrl, this.errorMessage});

  bool get success => flowId != null;
}

/// mobile-integration.md 2.3 — `GET /api/auth/status/{flow_id}` cevabı.
class NvStatusResult {
  final String status; // pending | verified | rejected | error
  final String? errorCode;
  final String? message;

  const NvStatusResult({required this.status, this.errorCode, this.message});
}

/// mobile-integration.md → "2.1 /api/auth/login" + "2.3 /api/auth/status".
///
/// OAuth mantığının tamamı backend'dedir; mobil yalnızca:
/// 1) login ile `flow_id` + `authorize_url` alır,
/// 2) `authorize_url`'i OLDUĞU GİBİ bir uygulama-içi WebView'de açar
///    (redirect zincirini WebView kendisi takip eder, URL parse edilmez),
/// 3) status'u ~1 sn arayla polleyerek sonucu öğrenir.
class NvService {
  final Dio _dio = ApiClient.instance.dio;

  Future<NvLoginResult> login(String phoneNumber) async {
    if (AppConfig.useMock) {
      await Future.delayed(const Duration(milliseconds: 600));
      ApiClient.instance.traceLog.record(
        method: 'POST',
        path: '/api/auth/login',
        duration: const Duration(milliseconds: 180),
        statusCode: 200,
      );
      // Mock'ta WebView adımı atlanır (authorizeUrl null) — durum polling'i
      // yine çalışır ki gerçek akışla aynı kod yolu denensin.
      return NvLoginResult(
        flowId: 'mock-flow-${DateTime.now().millisecondsSinceEpoch % 100000}',
        authorizeUrl: null,
      );
    }

    try {
      final response = await _dio.post(
        '/api/auth/login',
        data: {'phoneNumber': phoneNumber},
      );
      return NvLoginResult(
        flowId: response.data['flow_id'] as String?,
        authorizeUrl: response.data['authorize_url'] as String?,
      );
    } on DioException catch (e) {
      final message = e.response?.statusCode == 422
          ? 'Telefon numarası +90... (E.164) formatında olmalı'
          : (e.message ?? 'Backend\'e ulaşılamadı');
      return NvLoginResult(errorMessage: message);
    }
  }

  int _mockPollCount = 0;

  Future<NvStatusResult> fetchStatus(String flowId) async {
    if (AppConfig.useMock) {
      await Future.delayed(const Duration(milliseconds: 300));
      _mockPollCount++;
      final verified = _mockPollCount >= 2; // ~2 sn "pending" simülasyonu
      ApiClient.instance.traceLog.record(
        method: 'GET',
        path: '/api/auth/status/$flowId',
        duration: const Duration(milliseconds: 120),
        statusCode: 200,
      );
      return NvStatusResult(status: verified ? 'verified' : 'pending');
    }

    try {
      final response = await _dio.get('/api/auth/status/$flowId');
      return NvStatusResult(
        status: response.data['status'] as String? ?? 'pending',
        errorCode: response.data['error_code'] as String?,
        message: response.data['message'] as String?,
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        // Flow süresi doldu (~20 dk) — login'den baştan başlanmalı.
        return const NvStatusResult(
          status: 'error',
          message: 'Oturum süresi doldu, lütfen yeniden giriş yapın',
        );
      }
      // Geçici ağ hatası: pending say, polling devam etsin.
      return const NvStatusResult(status: 'pending');
    }
  }

  void resetMockState() => _mockPollCount = 0;
}
