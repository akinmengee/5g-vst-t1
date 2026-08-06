import 'package:flutter/material.dart';

import '../models/trace_entry.dart';
import '../services/trace_log.dart';
import '../theme/app_theme.dart';
import '../widgets/accent_card.dart';
import '../widgets/empty_state.dart';

/// Open Gateway Demo UX Kılavuzu → "07 Trace": her NV/QoD/upload/AI çağrısını
/// şeffaf şekilde gösterir. [TraceLog]'u dinler (gerçek modda Dio
/// interceptor'ından, mock modda servislerin kendi kayıtlarından beslenir).
class TraceTab extends StatelessWidget {
  final TraceLog traceLog;

  const TraceTab({super.key, required this.traceLog});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: traceLog,
      builder: (context, _) {
        if (traceLog.entries.isEmpty) {
          return const EmptyState(
            icon: Icons.route_outlined,
            title: 'Henüz kayıt yok',
            subtitle: 'NV, QoD, upload ve AI çağrıları burada listelenecek.',
          );
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                const StepBadge('07'),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('Open Gateway İz Kaydı',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppTheme.navy.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'toplam ${(traceLog.totalDuration.inMilliseconds / 1000).toStringAsFixed(1)}s',
                    style: const TextStyle(
                      color: AppTheme.inkSoft,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            AccentCard(
              accentColor: AppTheme.navy,
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (final (i, entry) in traceLog.entries.indexed) ...[
                    if (i > 0) const Divider(height: 1),
                    _TraceRow(entry: entry),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _TraceRow extends StatelessWidget {
  final TraceEntry entry;
  const _TraceRow({required this.entry});

  Color get _methodColor => switch (entry.method) {
        'POST' => AppTheme.catPassenger,
        'GET' => AppTheme.catObject,
        'PUT' || 'PATCH' => AppTheme.warning,
        'DELETE' => AppTheme.danger,
        _ => AppTheme.inkSoft,
      };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        children: [
          _statusIcon(),
          const SizedBox(width: 10),
          Container(
            width: 44,
            padding: const EdgeInsets.symmetric(vertical: 2),
            decoration: BoxDecoration(
              color: _methodColor.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(5),
            ),
            alignment: Alignment.center,
            child: Text(
              entry.method,
              style: TextStyle(
                fontFamily: AppTheme.monoFamily,
                fontWeight: FontWeight.w500,
                fontSize: 10.5,
                color: _methodColor,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              entry.path,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: AppTheme.monoFamily,
                fontSize: 12,
                color: AppTheme.ink,
              ),
            ),
          ),
          if (entry.duration != null)
            Text(
              '${entry.duration!.inMilliseconds} ms',
              style: const TextStyle(
                color: AppTheme.inkSoft,
                fontSize: 11.5,
                fontFamily: AppTheme.monoFamily,
              ),
            ),
          const SizedBox(width: 8),
          if (entry.statusCode != null) _statusChip(entry.statusCode!, entry.status),
        ],
      ),
    );
  }

  Widget _statusIcon() {
    switch (entry.status) {
      case TraceStatus.success:
        return const Icon(Icons.check_circle, color: AppTheme.success, size: 17);
      case TraceStatus.error:
        return const Icon(Icons.cancel, color: AppTheme.danger, size: 17);
      case TraceStatus.pending:
        return const SizedBox(
          width: 15,
          height: 15,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
    }
  }

  Widget _statusChip(int code, TraceStatus status) {
    final color = status == TraceStatus.error ? AppTheme.danger : AppTheme.success;
    return PillBadge(color: color, label: '$code');
  }
}
