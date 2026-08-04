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
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
                Text(
                  'toplam ${(traceLog.totalDuration.inMilliseconds / 1000).toStringAsFixed(1)}s',
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 12),
            AccentCard(
              accentColor: AppTheme.navy,
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (final entry in traceLog.entries) _TraceRow(entry: entry),
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

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          _statusIcon(),
          const SizedBox(width: 10),
          Expanded(
            child: RichText(
              overflow: TextOverflow.ellipsis,
              text: TextSpan(
                style: DefaultTextStyle.of(context).style,
                children: [
                  TextSpan(
                    text: '${entry.method} ',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                  ),
                  TextSpan(
                    text: entry.path,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
          if (entry.duration != null)
            Text(
              '${entry.duration!.inMilliseconds} ms',
              style: const TextStyle(
                color: Colors.grey,
                fontSize: 12,
                fontFeatures: [FontFeature.tabularFigures()],
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
        return const Icon(Icons.check_circle, color: Colors.green, size: 18);
      case TraceStatus.error:
        return const Icon(Icons.cancel, color: Colors.red, size: 18);
      case TraceStatus.pending:
        return const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
    }
  }

  Widget _statusChip(int code, TraceStatus status) {
    final color = status == TraceStatus.error ? Colors.red : Colors.green;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '$code',
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
          fontSize: 11,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}
