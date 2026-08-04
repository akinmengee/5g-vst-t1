/// mobile-integration.md 2.4: `/api/qod/start` her durumda 200 döner;
/// başarı `success` alanından okunur, Turkcell durumları `qosStatus`tan gelir.
enum QodOutcome { idle, success, failed }

class QodSession {
  final QodOutcome outcome;

  /// true: sunucuda zaten aktif bir QoD oturumu vardı — başarı sayılır.
  final bool alreadyActive;

  final String? sessionId;
  final String? qosStatus; // "REQUESTED" | null

  const QodSession({
    this.outcome = QodOutcome.idle,
    this.alreadyActive = false,
    this.sessionId,
    this.qosStatus,
  });

  bool get succeeded => outcome == QodOutcome.success;
}
