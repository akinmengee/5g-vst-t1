import 'dart:io';

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

/// mobile-integration.md → "2.5 /api/videos/upload" + "2.6 /api/videos/{job_id}/result".
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
      // Her upload ayrı bir iş: job başına ayrı polling sayacı ve sonuçta
      // görünecek video adı tutulur (çoklu kayıt akışı gerçekle aynı olsun).
      final jobId = 'mock-job-${++_mockJobSeq}';
      _mockPolls[jobId] = 0;
      _mockVideoNames[jobId] = filePath.split(RegExp(r'[/\\]')).last;
      return UploadResult(success: true, jobId: jobId);
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
      final message = e.response?.statusCode == 404
          ? 'Oturum (flow) süresi dolmuş — NV\'den yeniden başlayın'
          : (e.message ?? 'Yükleme başarısız');
      return UploadResult(success: false, errorMessage: message);
    } on FileSystemException catch (e) {
      return UploadResult(success: false, errorMessage: e.message);
    }
  }

  int _mockJobSeq = 0;
  final Map<String, int> _mockPolls = {};
  final Map<String, String> _mockVideoNames = {};

  Future<({AiResultStatus status, AiResult? result})> fetchResult(String jobId) async {
    if (AppConfig.useMock) {
      await Future.delayed(const Duration(milliseconds: 500));
      final count = (_mockPolls[jobId] ?? 0) + 1;
      _mockPolls[jobId] = count;
      // Sözleşme 4: PROCESSING -> DONE geçişi 2-3 sn gecikmeyle simüle edilir.
      final done = count >= 2;
      ApiClient.instance.traceLog.record(
        method: 'GET',
        path: '/api/videos/$jobId/result',
        duration: const Duration(milliseconds: 480),
        statusCode: 200,
      );
      return (
        status: done ? AiResultStatus.done : AiResultStatus.processing,
        result: done
            ? AiResult.fromJson({
                ..._mockResultsJson,
                'video_id': _mockVideoNames[jobId] ?? 'video.mp4',
              })
            : null,
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
      return (
        status: status,
        result: resultsJson != null ? AiResult.fromJson(resultsJson) : null,
      );
    } on DioException catch (e) {
      // Bilinmeyen/süresi dolmuş job (404) "hâlâ işleniyor" DEĞİLDİR — öyle
      // sayılırsa polling sonsuza dek döner. Geçici ağ hataları processing
      // kalır ki polling denemeye devam etsin.
      if (e.response?.statusCode == 404) {
        return (status: AiResultStatus.failed, result: null);
      }
      return (status: AiResultStatus.processing, result: null);
    }
  }
}

/// faz2_gt.json'daki gerçek dağılıma benzer örnek: aynı etiket farklı
/// zamanlarda TEKRAR eder (sözleşme 2.6: "normaldir").
const _mockResultsJson = {
  'video_id': 'video.mp4',
  'arac_bilgisi': {'tip': 'suv', 'plaka': '34TC8532', 'renk': 'siyah', 'confidence_score': 0.94},
  'tespitler': [
    {'zaman_saniye': 0.9, 'kategori': 'sofor_eylemi', 'etiket': 'esneme', 'confidence_score': 0.71},
    {'zaman_saniye': 4.3, 'kategori': 'nesneler', 'etiket': 'teknocan', 'confidence_score': 0.83},
    {'zaman_saniye': 6.0, 'kategori': 'yolcular', 'etiket': 'arka_koltuk_2', 'confidence_score': 0.66},
    {'zaman_saniye': 11.1, 'kategori': 'sofor_eylemi', 'etiket': 'telefonla_konusma', 'confidence_score': 0.78},
    {'zaman_saniye': 16.0, 'kategori': 'yolcular', 'etiket': 'arka_koltuk_2', 'confidence_score': 0.69},
    {'zaman_saniye': 25.3, 'kategori': 'sofor_eylemi', 'etiket': 'emniyet_kemeri_ihlali', 'confidence_score': 0.55},
    {'zaman_saniye': 28.9, 'kategori': 'sofor_eylemi', 'etiket': 'su_icme', 'confidence_score': 0.62},
    {'zaman_saniye': 38.1, 'kategori': 'sofor_eylemi', 'etiket': 'sigara_icme', 'confidence_score': 0.64},
    {'zaman_saniye': 45.9, 'kategori': 'sofor_eylemi', 'etiket': 'sigara_icme', 'confidence_score': 0.58},
  ],
};
