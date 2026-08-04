import 'package:flutter/material.dart';

/// Referans tasarımdaki "Sol kenar" kart vurgusu: durum rengine göre değişen
/// 4dp sol kenarlık + beyaz kart gövdesi. Tüm ana kartlarda (Session/QoD/
/// Video/Trace/AI) kullanılan ortak kabuk. Durum rengi değişimi animasyonlu —
/// ör. kayıt kartı griden kırmızıya yumuşak geçer.
class AccentCard extends StatelessWidget {
  final Color accentColor;
  final Widget child;
  final EdgeInsetsGeometry padding;

  const AccentCard({
    super.key,
    required this.accentColor,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border(left: BorderSide(color: accentColor, width: 4)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(padding: padding, child: child),
    );
  }
}
