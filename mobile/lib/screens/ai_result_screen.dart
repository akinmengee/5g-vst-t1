import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/ai_result.dart';
import '../state/session_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/accent_card.dart';
import '../widgets/empty_state.dart';

/// Open Gateway Demo UX Kılavuzu → "06 AI sonucunu gör" / AI RESULT SEKMESİ.
/// HomeScreen'in ikinci sekmesi olarak kullanılıyor (kendi Scaffold'u yok);
/// yenile butonu HomeScreen'in AppBar'ında.
///
/// Sonucu bu ekran ÇEKMEZ: upload biter bitmez SessionController periyodik
/// polling'i kendisi başlatır (sözleşme § 2.6), burası yalnızca gösterir.
class AiResultTab extends StatelessWidget {
  const AiResultTab({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SessionController>();

    if (controller.aiStatus == AiResultStatus.idle) {
      return const EmptyState(
        icon: Icons.camera_alt_outlined,
        title: 'Henüz kayıt yok',
        subtitle: 'Video yüklendikten sonra AI sonucu burada görünecek.',
      );
    }
    if (controller.aiStatus == AiResultStatus.processing) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('AI videoyu işliyor'),
          ],
        ),
      );
    }
    if (controller.aiStatus == AiResultStatus.failed) {
      return const EmptyState(
        icon: Icons.error_outline,
        title: 'AI işlemi başarısız oldu',
        subtitle: 'Sağ üstteki yenile butonuyla tekrar deneyebilirsiniz.',
      );
    }

    final result = controller.aiResult;
    if (result == null) {
      return const EmptyState(icon: Icons.search_off, title: 'Sonuç bulunamadı');
    }

    final topDetection = _highestConfidence(result.detections);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: const [
            StepBadge('06'),
            SizedBox(width: 8),
            Text('AI Sonucu', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        const SizedBox(height: 12),
        if (controller.aiResultSha256 != null) _hashRow(controller.aiResultSha256!),
        if (controller.aiResultSha256 != null) const SizedBox(height: 12),
        if (result.vehicleInfo != null) _vehicleCard(result.vehicleInfo!),
        if (topDetection != null) ...[
          const SizedBox(height: 12),
          _evidenceCard(topDetection, result.detections),
        ],
        const SizedBox(height: 16),
        Text('Tespitler (${result.detections.length})',
            style: const TextStyle(fontWeight: FontWeight.bold)),
        ...result.detections.map(_detectionTile),
        const SizedBox(height: 16),
        ExpansionTile(
          title: const Text('Ham JSON'),
          children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: SelectableText(const JsonEncoder.withIndent('  ').convert(result.raw)),
            ),
          ],
        ),
      ],
    );
  }

  Detection? _highestConfidence(List<Detection> detections) {
    if (detections.isEmpty) return null;
    return detections.reduce(
      (a, b) => (b.confidenceScore ?? 0) > (a.confidenceScore ?? 0) ? b : a,
    );
  }

  /// mobile-integration.md § 1 adım 8: results JSON'ın SHA256'sı ekranda
  /// görünür olmalı.
  Widget _hashRow(String sha256) {
    return AccentCard(
      accentColor: Colors.grey.shade400,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          const Icon(Icons.fingerprint, size: 18, color: Colors.grey),
          const SizedBox(width: 8),
          const Text('SHA256', style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold)),
          const SizedBox(width: 8),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SelectableText(
                sha256,
                style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _vehicleCard(VehicleInfo info) {
    return AccentCard(
      accentColor: AppTheme.navy,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Araç Bilgisi', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('Tip: ${info.tip ?? '-'}'),
          Text('Plaka: ${info.plaka ?? '-'}'),
          Text('Renk: ${info.renk ?? '-'}'),
          if (info.confidenceScore != null)
            Text('Güven: ${(info.confidenceScore! * 100).toStringAsFixed(0)}%'),
        ],
      ),
    );
  }

  Widget _evidenceCard(Detection top, List<Detection> all) {
    final maxTime = all
            .map((d) => d.zamanSaniye ?? 0)
            .fold<double>(0, (a, b) => a > b ? a : b) *
        1.05;

    return AccentCard(
      accentColor: AppTheme.turkcellYellow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              StepBadge('06'),
              SizedBox(width: 8),
              Text('Kanıt Karesi', style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppTheme.navy,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(_iconFor(top.etiket), color: AppTheme.turkcellYellow, size: 26),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_prettyLabel(top.etiket), style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(
                      't = ${top.zamanSaniye?.toStringAsFixed(1) ?? '-'}s · ${_prettyLabel(top.kategori)}',
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (top.confidenceScore != null)
                Text(
                  top.confidenceScore!.toStringAsFixed(2),
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.navy,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          const Text('Video zaman çizelgesi', style: TextStyle(fontSize: 11, color: Colors.grey)),
          const SizedBox(height: 6),
          _DetectionTimeline(detections: all, maxTime: maxTime <= 0 ? 1 : maxTime),
        ],
      ),
    );
  }

  IconData _iconFor(String? etiket) {
    switch (etiket) {
      case 'sigara_icme':
        return Icons.smoking_rooms;
      case 'telefonla_konusma':
        return Icons.phone_in_talk;
      case 'su_icme':
        return Icons.local_drink;
      case 'esneme':
        return Icons.bedtime;
      case 'emniyet_kemeri_ihlali':
        return Icons.warning_amber;
      case 'etrafa_bakinma':
      case 'arkaya_bakma':
        return Icons.visibility;
      case 'slalom':
        return Icons.alt_route;
      case 'teknocan':
      case 'bilgisayar':
        return Icons.devices_other;
      default:
        return Icons.report_problem;
    }
  }

  String _prettyLabel(String? raw) {
    if (raw == null || raw.isEmpty) return '-';
    return raw.replaceAll('_', ' ');
  }

  Widget _detectionTile(Detection d) {
    return ListTile(
      dense: true,
      leading: Text(d.zamanSaniye != null ? '${d.zamanSaniye!.toStringAsFixed(1)}s' : '-'),
      title: Text(d.etiket ?? '-'),
      subtitle: Text(d.kategori ?? '-'),
      trailing:
          d.confidenceScore != null ? Text('${(d.confidenceScore! * 100).toStringAsFixed(0)}%') : null,
    );
  }
}

class _DetectionTimeline extends StatelessWidget {
  final List<Detection> detections;
  final double maxTime;

  const _DetectionTimeline({required this.detections, required this.maxTime});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SizedBox(
          height: 20,
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              Container(
                height: 6,
                width: constraints.maxWidth,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              for (final d in detections)
                if (d.zamanSaniye != null)
                  Positioned(
                    left: (d.zamanSaniye! / maxTime).clamp(0.0, 1.0) * (constraints.maxWidth - 4),
                    child: Container(
                      width: 4,
                      height: 20,
                      decoration: BoxDecoration(
                        color: (d.confidenceScore ?? 0) >= 0.8
                            ? Colors.green
                            : AppTheme.turkcellYellow,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
            ],
          ),
        );
      },
    );
  }
}
