import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// NV akışının o anki durumuna göre arka planın "ruh hali" — animasyon artık
/// salt dekoratif değil, ekranda gerçekte ne olduğunu yansıtıyor:
/// - [idle]: henüz "Doğrula"ya basılmadı, sakin/yavaş nabız.
/// - [connecting]: WebView açık, şebekeden doğrulanıyor — hızlanmış, daha
///   parlak nabız ("bağlanıyor" hissi).
/// - [verified]: doğrulama başarılı — merkezden yola doğru TEK SEFERLİK bir
///   ışık patlaması oynar (bkz. [HeroHeader]'daki `_burstController`).
enum SignalMood { idle, connecting, verified }

/// NV giriş ekranının lacivert hero bölümü: merkezden yayılan sinyal
/// halkaları + ufka doğru daralan yol motifi. Halkalar yavaşça dışa doğru
/// yayılır (şebeke sinyali hissi) — düşük maliyetli tek AnimationController
/// üstüne, doğrulama anında tek seferlik bir patlama efekti eklenir.
class HeroBackgroundPainter extends CustomPainter {
  /// 0..1 arası döngüsel faz — halkaların "nefes alması". Hızı [mood]'a göre
  /// [_HeroHeaderState] tarafından ayarlanır (bu painter yalnızca çizer).
  final double phase;

  final SignalMood mood;

  /// [SignalMood.verified] anına özel, 0..1 arası TEK SEFERLİK ilerleme
  /// (0 = patlama henüz başlamadı, 1 = tamamen söndü). Diğer mood'larda 0.
  final double burstProgress;

  const HeroBackgroundPainter({
    this.phase = 0,
    this.mood = SignalMood.idle,
    this.burstProgress = 0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.30);

    // connecting'de halkalar daha parlak — "aktif bağlantı" hissi.
    final parlaklik = mood == SignalMood.connecting ? 1.7 : 1.0;

    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    for (var i = 1; i <= 4; i++) {
      // Her halka fazla birlikte hafifçe büyür ve dışarı doğru sönümlenir.
      final t = (phase + i * 0.18) % 1.0;
      final radius = 34.0 * i + t * 10;
      final alpha = (0.16 - i * 0.022) * (1.0 - t * 0.45) * parlaklik;
      ringPaint.color = Colors.white.withValues(alpha: alpha.clamp(0.0, 1.0));
      canvas.drawCircle(center, radius, ringPaint);
    }

    final vanish = Offset(size.width / 2, size.height * 0.58);
    final roadBottom = size.height;
    final roadPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.16)
      ..strokeWidth = 1.5;
    canvas.drawLine(Offset(size.width * 0.26, roadBottom), vanish, roadPaint);
    canvas.drawLine(Offset(size.width * 0.74, roadBottom), vanish, roadPaint);

    final dashPaint = Paint()
      ..color = AppTheme.turkcellYellow.withValues(alpha: 0.75)
      ..strokeWidth = 3;
    const dashCount = 7;
    final bottomCenter = Offset(size.width / 2, roadBottom);
    for (var i = 0; i < dashCount; i++) {
      // Şerit çizgileri ufka doğru hafifçe akar — yolculuk hissi. Loop
      // controller'ın süresi connecting'de kısaldığı için `phase` daha hızlı
      // ilerler, dolayısıyla şeritler otomatik olarak da hızlanmış görünür.
      final drift = phase * (1.0 / dashCount);
      final t0 = (i / dashCount + drift) % 1.0;
      final t1 = t0 + (0.5 / dashCount);
      final p0 = Offset.lerp(bottomCenter, vanish, t0)!;
      final p1 = Offset.lerp(bottomCenter, vanish, t1.clamp(0.0, 1.0))!;
      canvas.drawLine(p0, p1, dashPaint);
    }

    // Doğrulama başarılı: merkezden yola doğru genişleyen, sönümlenen tek
    // bir ışık halkası — "kutlama" anı. burstProgress 0'dan 1'e giderken
    // yarıçap büyür, kalınlık incelir, alfa söner.
    if (burstProgress > 0) {
      final burstRadius = burstProgress * size.height * 0.62;
      final burstAlpha = (1.0 - burstProgress).clamp(0.0, 1.0);
      final burstPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.0 * (1.0 - burstProgress) + 0.6
        ..color = AppTheme.turkcellYellow.withValues(alpha: burstAlpha * 0.9);
      canvas.drawCircle(center, burstRadius, burstPaint);
    }
  }

  @override
  bool shouldRepaint(covariant HeroBackgroundPainter oldDelegate) =>
      oldDelegate.phase != phase ||
      oldDelegate.mood != mood ||
      oldDelegate.burstProgress != burstProgress;
}

/// Ortasında sarı ikon rozeti bulunan hero arka planı — NV ekranı üst kısmı.
class HeroHeader extends StatefulWidget {
  final IconData icon;
  final String titleWhite;
  final String titleYellow;
  final String subtitle;

  /// Arka planın o anki "ruh hali" (bkz. [SignalMood]). Varsayılan [idle] —
  /// bu parametreyi vermeyen çağıranlar eski (salt dekoratif) davranışı
  /// aynen görür.
  final SignalMood mood;

  const HeroHeader({
    super.key,
    this.icon = Icons.wifi,
    required this.titleWhite,
    required this.titleYellow,
    required this.subtitle,
    this.mood = SignalMood.idle,
  });

  @override
  State<HeroHeader> createState() => _HeroHeaderState();
}

class _HeroHeaderState extends State<HeroHeader> with TickerProviderStateMixin {
  // Döngüsel nabız — idle'da yavaş, connecting'de hızlı (bkz. didUpdateWidget).
  late final AnimationController _loopController;
  // Tek seferlik "doğrulandı" patlaması — yalnızca idle/connecting -> verified
  // GEÇİŞİNDE bir kez ileri sarılır, başka hiçbir zaman tetiklenmez.
  late final AnimationController _burstController;

  static const _idleDuration = Duration(seconds: 6);
  static const _connectingDuration = Duration(milliseconds: 2200);

  @override
  void initState() {
    super.initState();
    _loopController = AnimationController(
      vsync: this,
      duration: widget.mood == SignalMood.connecting ? _connectingDuration : _idleDuration,
    )..repeat();
    _burstController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
    if (widget.mood == SignalMood.verified) _burstController.forward();
  }

  @override
  void didUpdateWidget(covariant HeroHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mood == widget.mood) return;

    // connecting <-> idle: nabız hızını değiştir. AnimationController'ın
    // süresi animasyon sürerken canlı değiştirilemediği için yeniden
    // başlatıyoruz — döngüsel bir animasyonda küçük bir faz atlaması fark
    // edilmez.
    _loopController.duration =
        widget.mood == SignalMood.connecting ? _connectingDuration : _idleDuration;
    if (widget.mood != SignalMood.verified) {
      _loopController.repeat();
    }

    // Yalnızca BAŞKA bir mood'dan verified'a geçişte patlamayı ateşle —
    // widget zaten verified'ken yeniden build olursa (ör. sayfa başka bir
    // sebeple rebuild olduysa) tekrar tekrar patlamasın.
    if (widget.mood == SignalMood.verified && oldWidget.mood != SignalMood.verified) {
      _burstController
        ..reset()
        ..forward();
    }
  }

  @override
  void dispose() {
    _loopController.dispose();
    _burstController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: AnimatedBuilder(
            animation: Listenable.merge([_loopController, _burstController]),
            builder: (context, _) => CustomPaint(
              painter: HeroBackgroundPainter(
                phase: _loopController.value,
                mood: widget.mood,
                burstProgress: widget.mood == SignalMood.verified ? _burstController.value : 0,
              ),
            ),
          ),
        ),
        Positioned(
          top: 48,
          left: 0,
          right: 0,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: AppTheme.turkcellYellow,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.turkcellYellow.withValues(alpha: 0.35),
                      blurRadius: 24,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Icon(widget.icon, color: AppTheme.navy, size: 34),
              ),
              const SizedBox(height: 16),
              RichText(
                text: TextSpan(
                  style: const TextStyle(
                    fontSize: 27,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'Inter',
                    letterSpacing: -0.5,
                  ),
                  children: [
                    TextSpan(text: widget.titleWhite, style: const TextStyle(color: Colors.white)),
                    TextSpan(
                        text: ' ${widget.titleYellow}',
                        style: const TextStyle(color: AppTheme.turkcellYellow)),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Text(
                widget.subtitle,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.72),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
