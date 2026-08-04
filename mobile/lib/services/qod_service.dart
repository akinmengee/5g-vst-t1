import 'package:dio/dio.dart';

import '../models/qod_session.dart';
import 'api_client.dart';

/// mobile-integration.md § 2.4: `POST /api/qod/start` sadece `flow_id` alır —
/// süre/IP/profil backend'de sabit. Yanıt her zaman 200 (Turkcell hatası HTTP
/// hatasına çevrilmez); `success:false` puan kaybettirmez, akış devam eder.
class QodService {
  final Dio _dio = ApiClient.instance.dio;

  Future<QodSession> startSession({required String flowId}) async {
    try {
      final response = await _dio.post('/api/qod/start', data: {'flow_id': flowId});
      final success = (response.data['success'] as bool? ?? false) ||
          (response.data['already_active'] as bool? ?? false);
      final qosStatus = response.data['qosStatus'] as String?;
      return QodSession(
        status: success ? _parseStatus(qosStatus) : QodStatus.unavailable,
        sessionId: response.data['sessionId'] as String?,
      );
    } on DioException {
      return const QodSession(status: QodStatus.unavailable);
    }
  }

  QodStatus _parseStatus(String? value) {
    switch (value) {
      case 'AVAILABLE':
        return QodStatus.available;
      case 'REQUESTED':
        return QodStatus.requested;
      default:
        return QodStatus.requested;
    }
  }
}
