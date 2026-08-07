/// mobile-integration.md 2.4: `/api/qod/start` her durumda 200 döner;
/// başarı `success` alanından okunur, Turkcell durumları `qosStatus`tan gelir.
enum QodOutcome { idle, success, failed }

class QodSession {
  final QodOutcome outcome;

  /// true: sunucuda zaten aktif bir QoD oturumu vardı — başarı sayılır.
  final bool alreadyActive;

  final String? sessionId;
  final String? qosStatus; // "REQUESTED" | null

  /// Turkcell'in GERÇEKTEN verdiği oturum süresi (saniye) — talep ettiğimizden
  /// kısa olabilir. Kritik: oturum bittiği anda cihazın veri bağlantısı
  /// kopuyor (7 Ağustos ölçümü, 3 bağımsız oturumda saniyesi saniyesine),
  /// yani bu değer "kaydı ve yüklemeyi ne kadar sürede bitirmemiz gerekiyor"
  /// demek. Canlı demoda kırpılma olursa anında görebilmek için gösteriliyor.
  final int? duration;

  const QodSession({
    this.outcome = QodOutcome.idle,
    this.alreadyActive = false,
    this.sessionId,
    this.qosStatus,
    this.duration,
  });

  bool get succeeded => outcome == QodOutcome.success;
}
