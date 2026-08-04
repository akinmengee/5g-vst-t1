/// Backend sözleşmesi: `POST /api/qod/start` hiçbir parametre almaz (süre/IP/
/// profil backend'de sabit) — `flow_id` dışında gönderilecek bir şey yok.
enum QodStatus { idle, requested, available, unavailable }

class QodSession {
  final QodStatus status;
  final String? sessionId;

  const QodSession({this.status = QodStatus.idle, this.sessionId});

  QodSession copyWith({QodStatus? status, String? sessionId}) {
    return QodSession(
      status: status ?? this.status,
      sessionId: sessionId ?? this.sessionId,
    );
  }

  bool get succeeded => status == QodStatus.available || status == QodStatus.requested;
}
