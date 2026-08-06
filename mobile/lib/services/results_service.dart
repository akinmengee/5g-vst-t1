import 'dart:io';

import 'package:dio/dio.dart';

import '../models/ai_result.dart';
import 'api_client.dart';

class UploadResult {
  final bool success;
  final String? jobId;
  final String? errorMessage;

  const UploadResult({required this.success, this.jobId, this.errorMessage});
}

/// mobile-integration.md → "2.5 /api/videos/upload" + "2.6 /api/videos/{job_id}/result".
class ResultsService {
  final Dio _dio;

  /// [dio] yalnızca testler için: gerçek uygulamada paylaşılan [ApiClient]
  /// örneği (trace + retry interceptor'ları ile) kullanılır.
  ResultsService({Dio? dio}) : _dio = dio ?? ApiClient.instance.dio;

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
      final message = e.response?.statusCode == 404
          ? 'Oturum (flow) süresi dolmuş — NV\'den yeniden başlayın'
          : (e.message ?? 'Yükleme başarısız');
      return UploadResult(success: false, errorMessage: message);
    } on FileSystemException catch (e) {
      return UploadResult(success: false, errorMessage: e.message);
    }
  }

  /// [pollFailed]: bu sorgu backend'e ULAŞAMADI (ağ hatası, 5xx, bozuk gövde).
  /// Durum bilerek `processing` bırakılır ki polling denemeye devam etsin, ama
  /// çağıran bunun bir BAŞARISIZLIK olduğunu bilmek zorunda: aksi halde kopmuş
  /// bir bağlantı ekranda sonsuza dek "AI videoyu işliyor" olarak görünür
  /// (6 Ağustos gecesi gerçekleşen hata: backend işi 7 dk'da bitirmişti, ama
  /// telefon o sırada backend'e ulaşamadığı için sonucu hiç öğrenemedi).
  Future<({AiResultStatus status, AiResult? result, bool pollFailed})> fetchResult(
    String jobId,
  ) async {
    try {
      final response = await _dio.get('/api/videos/$jobId/result');
      final statusStr = response.data['status'] as String? ?? 'PROCESSING';
      final status = switch (statusStr) {
        'DONE' => AiResultStatus.done,
        'FAILED' => AiResultStatus.failed,
        _ => AiResultStatus.processing,
      };
      final resultsJson = response.data['results'] as Map<String, dynamic>?;
      return (
        status: status,
        result: resultsJson != null ? AiResult.fromJson(resultsJson) : null,
        pollFailed: false,
      );
    } on DioException catch (e) {
      // Bilinmeyen/süresi dolmuş job (404) "hâlâ işleniyor" DEĞİLDİR — öyle
      // sayılırsa polling sonsuza dek döner.
      if (e.response?.statusCode == 404) {
        return (status: AiResultStatus.failed, result: null, pollFailed: false);
      }
      return (status: AiResultStatus.processing, result: null, pollFailed: true);
    } catch (_) {
      // DioException OLMAYAN istisna (ör. beklenmeyen gövde şeklinde cast
      // hatası). Buradan dışarı sızarsa SessionController'ın polling döngüsü
      // sessizce ölür ve ekran sonsuza dek "işleniyor"da kalır — bu yüzden
      // yutup "sorgu başarısız" olarak raporluyoruz.
      return (status: AiResultStatus.processing, result: null, pollFailed: true);
    }
  }
}

