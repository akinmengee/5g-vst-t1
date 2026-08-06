import 'package:flutter/material.dart';

import '../models/qod_session.dart';
import '../services/bandwidth_probe_service.dart';
import '../theme/app_theme.dart';
import 'accent_card.dart';

/// Open Gateway Demo UX Kılavuzu → "03 Quality-on-Demand'i aç" / HOME SEKMESİ
/// · "QOD SESSİON" KARTI. mobile-integration.md 2.4: parametre gönderilmez,
/// profil/süre backend'de sabittir (teknofest2026); `success:false` akışı
/// kilitlemez, puan kaybı yoktur.
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

  Color get _accentColor => switch (session.outcome) {
        QodOutcome.idle => AppTheme.idle,
        QodOutcome.success => AppTheme.success,
        QodOutcome.failed => AppTheme.warning,
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
                  Text('QoD Session',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                ],
              ),
              _statusChip(),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(Icons.tune, size: 13, color: AppTheme.inkSoft),
              const SizedBox(width: 5),
              const Text('profil: ', style: TextStyle(color: AppTheme.inkSoft, fontSize: 12)),
              const Text(
                'teknofest2026',
                style: TextStyle(
                  color: AppTheme.ink,
                  fontSize: 12,
                  fontFamily: AppTheme.monoFamily,
                ),
              ),
              if (session.sessionId != null) ...[
                const SizedBox(width: 12),
                const Icon(Icons.link, size: 13, color: AppTheme.inkSoft),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    session.sessionId!,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontFamily: AppTheme.monoFamily,
                      color: AppTheme.ink,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              // Başarısızsa yeniden denenebilir (sözleşme: akış kilitlenmez).
              onPressed:
                  loading || session.outcome == QodOutcome.success ? null : onStart,
              icon: loading
                  ? const SizedBox(
                      width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(session.outcome == QodOutcome.success ? Icons.check : Icons.speed,
                      size: 19),
              label: Text(switch (session.outcome) {
                QodOutcome.idle => 'QoD Aç',
                QodOutcome.success =>
                  session.alreadyActive ? 'QoD zaten aktifti' : 'QoD tetiklendi',
                QodOutcome.failed => 'QoD başarısız — tekrar dene',
              }),
            ),
          ),
          if (session.outcome == QodOutcome.failed) ...[
            const SizedBox(height: 8),
            const Text(
              'QoD açılamadı — akış düşük kalitede devam ediyor (puan kaybı yok, '
              'sadece +5 kaçtı).',
              style: TextStyle(fontSize: 12, color: AppTheme.inkSoft),
            ),
          ],
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

  Widget _statusChip() {
    final (color, label) = switch (session.outcome) {
      QodOutcome.idle => (AppTheme.inkSoft, 'IDLE'),
      QodOutcome.success => (AppTheme.success, session.qosStatus ?? 'REQUESTED'),
      QodOutcome.failed => (AppTheme.warning, 'DEVAM'),
    };
    return PillBadge(color: color, label: label);
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
          Text('İndirme hızı ölçülüyor…',
              style: TextStyle(fontSize: 12, color: AppTheme.inkSoft)),
        ],
      );
    }
    if (before == null) return const SizedBox.shrink();

    final maxMbps = [before!.mbps, after?.mbps ?? 0].reduce((a, b) => a > b ? a : b);
    final deltaPct = (after != null && before!.mbps > 0)
        ? ((after!.mbps - before!.mbps) / before!.mbps * 100)
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text('Gerçek indirme hızı ölçümü',
                  style: TextStyle(fontSize: 12, color: AppTheme.inkSoft)),
            ),
            if (deltaPct != null)
              PillBadge(
                color: deltaPct >= 0 ? AppTheme.success : AppTheme.warning,
                label: '${deltaPct >= 0 ? '+' : ''}${deltaPct.toStringAsFixed(0)}%',
                fontSize: 11.5,
              ),
          ],
        ),
        const SizedBox(height: 8),
        _bar('Önce', before!.mbps, maxMbps, AppTheme.navy.withValues(alpha: 0.30)),
        const SizedBox(height: 6),
        if (after != null)
          _bar('Sonra', after!.mbps, maxMbps, AppTheme.turkcellYellow)
        else if (measuring)
          const Row(
            children: [
              SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
              SizedBox(width: 8),
              Text('Sonra ölçülüyor…', style: TextStyle(fontSize: 12, color: AppTheme.inkSoft)),
            ],
          ),
      ],
    );
  }

  Widget _bar(String label, double mbps, double maxMbps, Color color) {
    final fraction = maxMbps <= 0 ? 0.0 : (mbps / maxMbps).clamp(0.05, 1.0).toDouble();
    return Row(
      children: [
        SizedBox(
            width: 40,
            child: Text(label,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500))),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: fraction),
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOutCubic,
              builder: (context, value, _) => LinearProgressIndicator(
                value: value,
                minHeight: 10,
                backgroundColor: Colors.black.withValues(alpha: 0.06),
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 72,
          child: Text(
            '${mbps.toStringAsFixed(1)} Mbps',
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}
