import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// NV giriş ekranının lacivert hero bölümü: merkezden yayılan sinyal
/// halkaları + ufka doğru daralan yol motifi. Saf dekoratif.
class HeroBackgroundPainter extends CustomPainter {
  const HeroBackgroundPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.30);

    final ringPaint = Paint()..style = PaintingStyle.stroke..strokeWidth = 1.2;
    for (var i = 1; i <= 4; i++) {
      ringPaint.color = Colors.white.withValues(alpha: 0.14 - i * 0.022);
      canvas.drawCircle(center, 34.0 * i, ringPaint);
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
      final t0 = i / dashCount;
      final t1 = t0 + (0.5 / dashCount);
      final p0 = Offset.lerp(bottomCenter, vanish, t0)!;
      final p1 = Offset.lerp(bottomCenter, vanish, t1)!;
      canvas.drawLine(p0, p1, dashPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Ortasında sarı ikon rozeti bulunan hero arka planı — NV ekranı üst kısmı.
class HeroHeader extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: CustomPaint(painter: const HeroBackgroundPainter()),
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
                ),
                child: Icon(icon, color: AppTheme.navy, size: 34),
              ),
              const SizedBox(height: 16),
              RichText(
                text: TextSpan(
                  style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
                  children: [
                    TextSpan(text: titleWhite, style: const TextStyle(color: Colors.white)),
                    TextSpan(text: ' $titleYellow', style: const TextStyle(color: AppTheme.turkcellYellow)),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 13),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
