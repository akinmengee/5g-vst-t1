import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

import '../config/app_config.dart';
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
    if (AppConfig.useMock) {
      await Future.delayed(const Duration(milliseconds: 800));
      ApiClient.instance.traceLog.record(
        method: 'POST',
        path: '/api/videos/upload',
        duration: const Duration(milliseconds: 780),
        statusCode: 202,
      );
      return const UploadResult(success: true, jobId: 'mock-job-1');
    }

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
      final detail = e.response?.data is Map ? e.response?.data['detail'] as String? : null;
      return UploadResult(success: false, errorMessage: detail ?? e.message ?? 'Yükleme başarısız');
    } on FileSystemException catch (e) {
      return UploadResult(success: false, errorMessage: e.message);
    }
  }

  Future<FetchResultResponse> fetchResult(String jobId) async {
    if (AppConfig.useMock) {
      await Future.delayed(const Duration(milliseconds: 500));
      ApiClient.instance.traceLog.record(
        method: 'GET',
        path: '/api/videos/$jobId/result',
        duration: const Duration(milliseconds: 480),
        statusCode: 200,
      );
      return FetchResultResponse(
        status: AiResultStatus.done,
        result: AiResult.fromJson(_mockResultsJson),
        resultsSha256: _sha256Of(_mockResultsJson),
      );
    }

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
    } on DioException {
      return const FetchResultResponse(status: AiResultStatus.processing);
    }
  }

  /// mobile-integration.md § 1 adım 8: "results JSON içeriğinin SHA256'sını
  /// hesaplayıp ekranda göster". Backend'in tam olarak hangi serileştirmeyi
  /// kullandığı (boşluk/anahtar sırası) belgede belirtilmemiş — burada
  /// `jsonDecode` ile ayrıştırılan Map'in `jsonEncode` ile derli toplu
  /// (compact) haline göre hesaplıyoruz. Akın'ın backend'deki hash'iyle bire
  /// bir örtüşmezse (whitespace/sıralama farkı ihtimali) format burada
  /// güncellenir.
  String _sha256Of(Map<String, dynamic> results) {
    return sha256.convert(utf8.encode(jsonEncode(results))).toString();
  }
}

const _mockResultsJson = {
  'video_id': 'video.mp4',
  'arac_bilgisi': {'tip': 'sedan', 'plaka': '34ABC123', 'renk': 'beyaz', 'confidence_score': 0.94},
  'tespitler': [
    {'zaman_saniye': 14.5, 'kategori': 'sofor_eylemi', 'etiket': 'telefonla_konusma', 'confidence_score': 0.89},
    {'zaman_saniye': 22.0, 'kategori': 'sofor_eylemi', 'etiket': 'emniyet_kemeri_ihlali', 'confidence_score': 0.91},
  ],
};
