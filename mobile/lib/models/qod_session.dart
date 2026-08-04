/// Backend sözleşmesi: `POST /api/qod/start` hiçbir parametre almaz (süre/IP/
/// profil backend'de sabit) — `flow_id` dışında gönderilecek bir şey yok.
enum QodStatus { idle, requested, available, unavailable }

class QodSession {
  final QodStatus status;
  final String? sessionId;

  const QodSession({this.status = QodStatus.idle, this.sessionId});
}
