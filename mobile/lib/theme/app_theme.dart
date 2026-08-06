import 'package:flutter/material.dart';

/// Open Gateway Demo UX Kılavuzu'ndaki resmi demo ile aynı dilde: lacivert +
/// Turkcell sarısı vurgu, beyaz kartlar üzerinde temiz düzen. Hakemler zaten
/// bu görünüme (referans doküman) aşina olacak.
///
/// Tipografi: gövde metinleri Inter (assets/fonts), hash/kod/plaka gibi teknik
/// değerler JetBrains Mono — ikisi de pakete gömülü, demo günü internet
/// gerekmez.
class AppTheme {
  AppTheme._();

  // ── Marka renkleri ─────────────────────────────────────────────────────────
  static const navy = Color(0xFF0A1F44);
  static const navyBright = Color(0xFF16306B); // gradyan ucu / vurgulu yüzey
  static const turkcellYellow = Color(0xFFFFCB05);
  static const background = Color(0xFFF4F6FA);

  // Durum renkleri — kartların sol kenar vurgusu ve rozetlerde ortak dil.
  static const success = Color(0xFF1E9E5A);
  static const warning = Color(0xFFE8850C);
  static const danger = Color(0xFFD93025);

  /// Henüz başlamamış/pasif durum vurgusu (ör. QoD tetiklenmeden önce,
  /// kayıt başlamadan önce). Material'ın saf grisi yerine lacivert tonuna
  /// hafifçe kaçan, markaya ait bir nötr — kartlar arasında "bu da bir
  /// durum rengi" tutarlılığını korur.
  static const idle = Color(0xFFE2E4E9);

  // Metin renkleri
  static const ink = Color(0xFF17233B);
  static const inkSoft = Color(0xFF5B6478);

  // Kategori renkleri (AI sonucu + zaman çizelgesi lejantı)
  static const catDriver = Color(0xFFD93025); // sofor_eylemi
  static const catPassenger = Color(0xFF2C6BED); // yolcular
  static const catObject = Color(0xFF0E9488); // nesneler

  static const monoFamily = 'JetBrains Mono';

  /// Üst blok (AppBar + adım çubuğu) tek parça görünsün diye ortak gradyan.
  static const headerGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [navy, navyBright],
  );

  static ThemeData light() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: navy,
      brightness: Brightness.light,
    ).copyWith(
      primary: navy,
      secondary: turkcellYellow,
      onSecondary: navy,
      surface: Colors.white,
      error: danger,
    );

    final base = ThemeData(useMaterial3: true, fontFamily: 'Inter');

    return ThemeData(
      useMaterial3: true,
      fontFamily: 'Inter',
      colorScheme: colorScheme,
      scaffoldBackgroundColor: background,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        centerTitle: false,
        elevation: 0,
        titleTextStyle: TextStyle(
          fontFamily: 'Inter',
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: Colors.black.withValues(alpha: 0.06)),
        ),
        margin: EdgeInsets.zero,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: navy,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
          textStyle: const TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.w600,
            fontSize: 14.5,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: navy,
          side: BorderSide(color: navy.withValues(alpha: 0.35), width: 1.4),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
          textStyle: const TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.w600,
            fontSize: 14.5,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: navyBright,
          textStyle: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: background,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.12)),
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: turkcellYellow,
        unselectedLabelColor: Colors.white70,
        indicatorColor: turkcellYellow,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: Colors.transparent,
        labelStyle: const TextStyle(
          fontFamily: 'Inter',
          fontWeight: FontWeight.w700,
          fontSize: 13.5,
        ),
        unselectedLabelStyle: const TextStyle(
          fontFamily: 'Inter',
          fontWeight: FontWeight.w500,
          fontSize: 13.5,
        ),
        overlayColor: WidgetStatePropertyAll(Colors.white.withValues(alpha: 0.06)),
      ),
      chipTheme: const ChipThemeData(
        labelStyle: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 11),
        padding: EdgeInsets.symmetric(horizontal: 8),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: navy,
        contentTextStyle: const TextStyle(fontFamily: 'Inter', color: Colors.white, fontSize: 13.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      dividerTheme: DividerThemeData(color: Colors.black.withValues(alpha: 0.07), space: 1),
      listTileTheme: const ListTileThemeData(iconColor: inkSoft),
      textTheme: base.textTheme
          .apply(bodyColor: ink, displayColor: navy)
          .copyWith(
            titleLarge: base.textTheme.titleLarge?.copyWith(
              color: navy,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
            ),
            titleMedium: base.textTheme.titleMedium?.copyWith(
              color: ink,
              fontWeight: FontWeight.w600,
            ),
            bodyMedium: base.textTheme.bodyMedium?.copyWith(color: ink, height: 1.35),
            bodySmall: base.textTheme.bodySmall?.copyWith(color: inkSoft),
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

/// Giriş (NV) ekranı dışındaki ekranların ortak arka planı: 5G ışık hüzmesi
/// görseli, hafif saydam — içerik (beyaz kartlar) her zaman öncelikli okunur
/// kalsın diye düşük opaklıkta.
class AppBackground extends StatelessWidget {
  final Widget child;
  const AppBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: Opacity(
            opacity: 0.22,
            child: Image.asset(
              'assets/images/app_background.jpg',
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
            ),
          ),
        ),
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
      decoration: BoxDecoration(
        color: AppTheme.turkcellYellow,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: AppTheme.turkcellYellow.withValues(alpha: 0.35),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        number,
        style: const TextStyle(
          color: AppTheme.navy,
          fontWeight: FontWeight.w800,
          fontSize: 13,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

/// Durum rozeti: tinted arka plan (rengin %10 opaklığı) + kalın küçük metin,
/// isteğe bağlı önde ikon. QoD/İz/SHA256 kartlarında ayrı ayrı el yazımı
/// aynı `Container(BoxDecoration(...))` bloğu tekrar etmesin diye tek
/// yerden — renk/köşe/yazı tipi buradan değişince her yerde birlikte değişir.
class PillBadge extends StatelessWidget {
  final Color color;
  final String label;
  final IconData? icon;
  final double fontSize;

  const PillBadge({
    super.key,
    required this.color,
    required this.label,
    this.icon,
    this.fontSize = 11,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: fontSize + 2.5, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: fontSize,
              letterSpacing: 0.3,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// NV → Home gibi "kapı" geçişleri için yumuşak fade + hafif yukarı kayma.
/// MaterialPageRoute'un ani kesmesi yerine demo videosunda akıcı görünür.
Route<T> fadeSlideRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    transitionDuration: const Duration(milliseconds: 420),
    pageBuilder: (_, _, _) => page,
    transitionsBuilder: (_, animation, _, child) {
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.03),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}
