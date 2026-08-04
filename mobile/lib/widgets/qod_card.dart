import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../models/qod_session.dart';
import '../services/bandwidth_probe_service.dart';
import '../theme/app_theme.dart';
import 'accent_card.dart';

/// Open Gateway Demo UX Kılavuzu → "03 Quality-on-Demand'i aç" / HOME SEKMESİ
/// · "QOD SESSİON" KARTI. Profil sabit: teknofest2026.
class QodCard extends StatelessWidget {
  final QodSession session;
  final bool loading;
  final VoidCallback onStart;
  final BandwidthSample? bandwidthBefore;
  final BandwidthSample? bandwidthAfter;
  final bool bandwidthMeasuring;

  const QodCard({
    super.key,
    required this.session,
    required this.loading,
    required this.onStart,
    this.bandwidthBefore,
    this.bandwidthAfter,
    this.bandwidthMeasuring = false,
  });

  Color get _accentColor => switch (session.status) {
        QodStatus.idle => Colors.grey.shade300,
        QodStatus.requested => Colors.orange,
        QodStatus.available => Colors.green,
        QodStatus.unavailable => Colors.red,
      };

  @override
  Widget build(BuildContext context) {
    return AccentCard(
      accentColor: _accentColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: const [
                  StepBadge('03'),
                  SizedBox(width: 8),
                  Text('QoD Session', style: TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
              _statusChip(session.status),
            ],
          ),
          const SizedBox(height: 4),
          const Text('profil: teknofest2026', style: TextStyle(color: Colors.grey, fontSize: 12)),
          if (session.sessionId != null) ...[
            const SizedBox(height: 4),
            Text('session: ${session.sessionId}', style: const TextStyle(fontSize: 12)),
          ],
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: loading || session.status != QodStatus.idle ? null : onStart,
            icon: loading
                ? const SizedBox(
                    width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.speed),
            label: Text(session.status == QodStatus.idle ? 'QoD Aç' : 'QoD tetiklendi'),
          ),
          if (bandwidthMeasuring || bandwidthBefore != null) ...[
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 12),
            _BandwidthImpact(
              measuring: bandwidthMeasuring,
              before: bandwidthBefore,
              after: bandwidthAfter,
            ),
          ],
        ],
      ),
    );
  }

  Widget _statusChip(QodStatus status) {
    final (color, label) = switch (status) {
      QodStatus.idle => (Colors.grey, 'IDLE'),
      QodStatus.requested => (Colors.orange, 'REQUESTED'),
      QodStatus.available => (Colors.green, 'AVAILABLE'),
      QodStatus.unavailable => (Colors.red, 'UNAVAILABLE'),
    };
    return Chip(
      label: Text(label, style: const TextStyle(fontSize: 11, color: Colors.white)),
      backgroundColor: color,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}

/// Gerçek ölçüm: aynı HLS akışından indirilen bir segmentin QoD öncesi/sonrası
/// indirme hızı (Mbps). Şartname 4.1: "ağ kalitesi arttığında ... başarım
/// artışını bu API kullanımı ile kanıtlayacaklardır."
class _BandwidthImpact extends StatelessWidget {
  final bool measuring;
  final BandwidthSample? before;
  final BandwidthSample? after;

  const _BandwidthImpact({required this.measuring, this.before, this.after});

  @override
  Widget build(BuildContext context) {
    if (before == null && measuring) {
      return const Row(
        children: [
          SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
          SizedBox(width: 8),
          Text('İndirme hızı ölçülüyor…', style: TextStyle(fontSize: 12, color: Colors.grey)),
        ],
      );
    }
    if (before == null) return const SizedBox.shrink();

    final maxMbps = [before!.mbps, after?.mbps ?? 0].reduce((a, b) => a > b ? a : b);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Gerçek indirme hızı ölçümü', style: TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 8),
        _bar('Önce', before!.mbps, maxMbps, AppTheme.navy.withValues(alpha: 0.25)),
        const SizedBox(height: 6),
        if (after != null)
          _bar('Sonra', after!.mbps, maxMbps, AppTheme.turkcellYellow)
        else if (measuring)
          const Row(
            children: [
              SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
              SizedBox(width: 8),
              Text('Sonra ölçülüyor…', style: TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
        if (after != null && AppConfig.useMock) ...[
          const SizedBox(height: 8),
          const Text(
            'Not: mock modda QoD çağrısı da simüle — bu fark ağ dalgalanmasından '
            'olabilir, gerçek backend bağlanınca bu ölçüm QoD\'nin kanıtı olur.',
            style: TextStyle(fontSize: 10.5, color: Colors.grey, fontStyle: FontStyle.italic),
          ),
        ],
      ],
    );
  }

  Widget _bar(String label, double mbps, double maxMbps, Color color) {
    final fraction = maxMbps <= 0 ? 0.0 : (mbps / maxMbps).clamp(0.05, 1.0);
    return Row(
      children: [
        SizedBox(width: 40, child: Text(label, style: const TextStyle(fontSize: 12))),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 10,
              backgroundColor: Colors.black.withValues(alpha: 0.06),
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 64,
          child: Text(
            '${mbps.toStringAsFixed(1)} Mb',
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}
