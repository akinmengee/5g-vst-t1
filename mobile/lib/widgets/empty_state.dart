import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Boş/bekleme durumları için tutarlı görsel dil — lacivert tonlu ikon
/// balonu + kısa açıklama (referans tasarımdaki "Boş durum çizimi" stili).
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;

  const EmptyState({super.key, required this.icon, required this.title, this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.navy.withValues(alpha: 0.05),
                border: Border.all(color: AppTheme.navy.withValues(alpha: 0.10), width: 1.5),
              ),
              child: Icon(icon, size: 30, color: AppTheme.navy.withValues(alpha: 0.45)),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 15.5,
                color: AppTheme.ink,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 5),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppTheme.inkSoft, fontSize: 12.5, height: 1.4),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
