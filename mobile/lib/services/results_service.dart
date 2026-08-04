import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

import '../models/ai_result.dart';
import 'api_client.dart';

class UploadResult {
  final bool success;
  final String? jobId;
  final String? errorMessage;

  const UploadResult({required this.success, this.jobId, this.errorMessage});
}

class FetchResultResponse {
  final AiResultStatus status;
  final AiResult? result;
  final String? resultsSha256;

  const FetchResultResponse({required this.status, this.result, this.resultsSha256});
}

/// mobile-integration.md § 2.5, 2.6.
class ResultsService {
  final Dio _dio = ApiClient.instance.dio;

  Future<UploadResult> uploadVideo({
    required String flowId,
    required String filePath,
  }) async {
    try {
      final formData = FormData.fromMap({
        'flow_id': flowId,
        'video': await MultipartFile.fromFile(filePath, filename: 'video.mp4'),
      });
      // Video birkaç yüz MB olabilir (5 dk 1080p) — upload timeout'u ayrıca
      // uzun tutuluyor, RetryInterceptor sadece bağlantı hatalarında devreye
      // giriyor (yarım kalan büyük upload'ı baştan denemez).
      final response = await _dio.post(
        '/api/videos/upload',
        data: formData,
        options: Options(sendTimeout: const Duration(minutes: 3)),
      );
      return UploadResult(success: true, jobId: response.data['job_id'] as String?);
    } on DioException catch (e) {
      return UploadResult(
        success: false,
        errorMessage: backendDetail(e) ?? e.message ?? 'Yükleme başarısız',
      );
    } on FileSystemException catch (e) {
      return UploadResult(success: false, errorMessage: e.message);
    }
  }

  Future<FetchResultResponse> fetchResult(String jobId) async {
    try {
      final response = await _dio.get('/api/videos/$jobId/result');
      final statusStr = response.data['status'] as String? ?? 'PROCESSING';
      final status = switch (statusStr) {
        'DONE' => AiResultStatus.done,
        'FAILED' => AiResultStatus.failed,
        _ => AiResultStatus.processing,
      };
      final resultsJson = response.data['results'] as Map<String, dynamic>?;
      return FetchResultResponse(
        status: status,
        result: resultsJson != null ? AiResult.fromJson(resultsJson) : null,
        resultsSha256: resultsJson != null ? _sha256Of(resultsJson) : null,
      );
    } on DioException catch (e) {
      // Sözleşme § 2.6: bilinmeyen/süresi dolmuş job_id → 404. Bunu
      // "processing" saymak sonsuza dek pollemek demek olurdu; kullanıcıya
      // hata gösterilip yeniden yükleme denenebilmeli. Diğer (geçici ağ)
      // hatalarında polling devam eder.
      if (e.response?.statusCode == 404) {
        return const FetchResultResponse(status: AiResultStatus.failed);
      }
      return const FetchResultResponse(status: AiResultStatus.processing);
    }
  }

  /// mobile-integration.md § 1 adım 8: "results JSON içeriğinin SHA256'sını
  /// hesaplayıp ekranda göster" — resmi akış diyagramı adım 17. Bu hash'i
  /// yalnızca mobil üretir (backend karşılık gelen bir hash hesaplamıyor),
  /// dolayısıyla karşılaştırılacak bir referans yok: ayrıştırılmış Map'in
  /// compact `jsonEncode` hali üzerinden hesaplanıyor.
  String _sha256Of(Map<String, dynamic> results) {
    return sha256.convert(utf8.encode(jsonEncode(results))).toString();
  }
}
