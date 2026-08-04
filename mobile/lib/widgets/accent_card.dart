import 'package:flutter/material.dart';

/// Referans tasarımdaki "Sol kenar" kart vurgusu: durum rengine göre değişen
/// 4dp sol kenarlık + beyaz kart gövdesi. Tüm ana kartlarda (Session/QoD/
/// Video/Trace) kullanılan ortak kabuk.
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
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border(left: BorderSide(color: accentColor, width: 4)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(padding: padding, child: child),
    );
  }
}
