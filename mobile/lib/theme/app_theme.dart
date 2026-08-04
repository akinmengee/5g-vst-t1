import 'package:flutter/material.dart';

/// Open Gateway Demo UX Kılavuzu'ndaki resmi demo ile aynı dilde: lacivert +
/// Turkcell sarısı vurgu, beyaz kartlar üzerinde temiz düzen. Hakemler zaten
/// bu görünüme (referans doküman) aşina olacak.
class AppTheme {
  AppTheme._();

  static const navy = Color(0xFF0A1F44);
  static const turkcellYellow = Color(0xFFFFCB05);
  static const background = Color(0xFFF4F5F7);

  static ThemeData light() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: navy,
      brightness: Brightness.light,
    ).copyWith(
      primary: navy,
      secondary: turkcellYellow,
      onSecondary: navy,
      surface: Colors.white,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: background,
      appBarTheme: const AppBarTheme(
        backgroundColor: navy,
        foregroundColor: Colors.white,
        centerTitle: false,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.black.withValues(alpha: 0.06)),
        ),
        margin: EdgeInsets.zero,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: navy,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: navy,
          side: const BorderSide(color: navy),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.12)),
        ),
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: turkcellYellow,
        unselectedLabelColor: Colors.white70,
        indicatorColor: turkcellYellow,
      ),
      chipTheme: const ChipThemeData(
        labelStyle: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 11),
        padding: EdgeInsets.symmetric(horizontal: 8),
      ),
      textTheme: ThemeData.light().textTheme.apply(
            bodyColor: const Color(0xFF1A1A1A),
            displayColor: navy,
          ),
    );
  }
}

/// Lacivert yüzeylerde ince nokta dokusu ("Nokta matrisi" — en sakin, en
/// güvenli seçenek). Saf dekoratif; performans için tek sefer boyanıp
/// widget ağacında sabit kalır.
class DotMatrixPainter extends CustomPainter {
  const DotMatrixPainter();

  static const _spacing = 14.0;
  static const _radius = 1.0;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white.withValues(alpha: 0.06);
    for (double y = 0; y < size.height; y += _spacing) {
      for (double x = 0; x < size.width; x += _spacing) {
        canvas.drawCircle(Offset(x, y), _radius, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class DotMatrixBackground extends StatelessWidget {
  final Widget child;
  const DotMatrixBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: CustomPaint(painter: const DotMatrixPainter())),
        child,
      ],
    );
  }
}

/// Adım rozetleri (Open Gateway Demo UX Kılavuzu: 01 Doğrula → 07 Trace) için
/// tutarlı bir görsel dil — sarı daire içinde numara.
class StepBadge extends StatelessWidget {
  final String number;
  const StepBadge(this.number, {super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: AppTheme.turkcellYellow,
        shape: BoxShape.circle,
      ),
      child: Text(
        number,
        style: const TextStyle(
          color: AppTheme.navy,
          fontWeight: FontWeight.bold,
          fontSize: 13,
        ),
      ),
    );
  }
}
