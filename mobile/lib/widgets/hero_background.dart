import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// NV giriş ekranının lacivert hero bölümü: merkezden yayılan sinyal
/// halkaları + ufka doğru daralan yol motifi. Halkalar yavaşça dışa doğru
/// yayılır (şebeke sinyali hissi) — saf dekoratif, düşük maliyetli tek
/// AnimationController.
class HeroBackgroundPainter extends CustomPainter {
  /// 0..1 arası döngüsel faz — halkaların "nefes alması".
  final double phase;

  const HeroBackgroundPainter({this.phase = 0});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.30);

    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    for (var i = 1; i <= 4; i++) {
      // Her halka fazla birlikte hafifçe büyür ve dışarı doğru sönümlenir.
      final t = (phase + i * 0.18) % 1.0;
      final radius = 34.0 * i + t * 10;
      final alpha = (0.16 - i * 0.022) * (1.0 - t * 0.45);
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
      // Şerit çizgileri ufka doğru hafifçe akar — yolculuk hissi.
      final drift = phase * (1.0 / dashCount);
      final t0 = (i / dashCount + drift) % 1.0;
      final t1 = t0 + (0.5 / dashCount);
      final p0 = Offset.lerp(bottomCenter, vanish, t0)!;
      final p1 = Offset.lerp(bottomCenter, vanish, t1.clamp(0.0, 1.0))!;
      canvas.drawLine(p0, p1, dashPaint);
    }
  }

  @override
  bool shouldRepaint(covariant HeroBackgroundPainter oldDelegate) =>
      oldDelegate.phase != phase;
}

/// Ortasında sarı ikon rozeti bulunan hero arka planı — NV ekranı üst kısmı.
class HeroHeader extends StatefulWidget {
  final IconData icon;
  final String titleWhite;
  final String titleYellow;
  final String subtitle;

  const HeroHeader({
    super.key,
    this.icon = Icons.wifi,
    required this.titleWhite,
    required this.titleYellow,
    required this.subtitle,
  });

  @override
  State<HeroHeader> createState() => _HeroHeaderState();
}

class _HeroHeaderState extends State<HeroHeader> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 6))
      ..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) =>
                CustomPaint(painter: HeroBackgroundPainter(phase: _controller.value)),
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
