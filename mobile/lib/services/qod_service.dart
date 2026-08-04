import 'package:dio/dio.dart';

import '../models/qod_session.dart';
import 'api_client.dart';

/// mobile-integration.md 2.4 — `POST /api/qod/start`.
///
/// Süre/IP/profil parametresi GÖNDERİLMEZ (hepsi backend'de sabit).
/// Sunucu her durumda 200 döner; başarı `success` alanından okunur.
/// `success:false` puan kaybettirmez, akış devam eder (bkz. sözleşme 3).
class QodService {
  final Dio _dio = ApiClient.instance.dio;

  Future<QodSession> start(String flowId) async {
    try {
      final response = await _dio.post('/api/qod/start', data: {'flow_id': flowId});
      final success = response.data['success'] as bool? ?? false;
      final alreadyActive = response.data['already_active'] as bool? ?? false;
      return QodSession(
        // Sözleşme: already_active:true → başarı say.
        outcome: (success || alreadyActive) ? QodOutcome.success : QodOutcome.failed,
        alreadyActive: alreadyActive,
        sessionId: response.data['sessionId'] as String?,
        qosStatus: response.data['qosStatus'] as String?,
      );
    } on DioException {
      // 404 (flow düştü) dahil her hata: akış kilitlenmez, düşük kalitede devam.
      return const QodSession(outcome: QodOutcome.failed);
    }
  }
}
