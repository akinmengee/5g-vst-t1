import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/ai_result.dart';
import '../models/recording_item.dart';
import '../state/session_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/accent_card.dart';
import '../widgets/empty_state.dart';
import '../widgets/entrance.dart';

/// Open Gateway Demo UX Kılavuzu → "06 AI sonucunu gör" / AI RESULT SEKMESİ.
/// Yüklenen HER video ayrı bir AI işidir: önce iş listesi görünür, bir işe
/// dokununca o videonun sonucu (plaka rozeti, tespitler, SHA256) açılır.
/// results.json indirilebilir (paylaşım menüsü üzerinden).
class AiResultTab extends StatefulWidget {
  const AiResultTab({super.key});

  @override
  State<AiResultTab> createState() => AiResultTabState();
}

// ── Kategori görsel dili (tek yerden) ────────────────────────────────────────

Color kategoriRenk(String? kategori) => switch (kategori) {
      'sofor_eylemi' => AppTheme.catDriver,
      'yolcular' => AppTheme.catPassenger,
      'nesneler' => AppTheme.catObject,
      _ => AppTheme.inkSoft,
    };

String kategoriAd(String? kategori) => switch (kategori) {
      'sofor_eylemi' => 'Sürücü Eylemi',
      'yolcular' => 'Yolcular',
      'nesneler' => 'Nesneler',
      _ => kategori ?? '-',
    };

const _kategoriSirasi = ['sofor_eylemi', 'yolcular', 'nesneler'];

class AiResultTabState extends State<AiResultTab> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SessionController>().refreshAiResults();
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SessionController>();
    final secili = controller.selectedRecording;

    final Widget icerik;
    final String anahtar;
    if (secili == null) {
      icerik = _JobList(controller: controller);
      anahtar = 'liste-${controller.uploadedJobs.length}';
    } else {
      icerik = _JobDetail(controller: controller, item: secili);
      anahtar = 'detay-${secili.jobId}-${secili.aiStatus}';
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: KeyedSubtree(key: ValueKey(anahtar), child: icerik),
    );
  }
}

// ── İş listesi ───────────────────────────────────────────────────────────────

class _JobList extends StatelessWidget {
  final SessionController controller;

  const _JobList({required this.controller});

  @override
  Widget build(BuildContext context) {
    final jobs = controller.uploadedJobs;

    if (jobs.isEmpty) {
      return const EmptyState(
        icon: Icons.camera_alt_outlined,
        title: 'Henüz yüklenmiş video yok',
        subtitle:
            'Akış sekmesinden kayıt alıp bulut baloncuğuyla backend\'e yükleyin — '
            'her videonun AI sonucu burada listelenecek.',
      );
    }

    return RefreshIndicator(
      onRefresh: () => controller.refreshAiResults(),
      color: AppTheme.navy,
      child: ListView(
        padding: const EdgeInsets.all(16),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Entrance(
            child: Row(
              children: [
                const StepBadge('06'),
                const SizedBox(width: 8),
                Text('AI Sonuçları · ${jobs.length} video',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Entrance(
            delayMs: 60,
            child: AccentCard(
              accentColor: AppTheme.navy,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Column(
                children: [
                  for (final (i, item) in jobs.indexed) ...[
                    if (i > 0) const Divider(height: 1),
                    _JobRow(
                      item: item,
                      onTap: () => controller.selectJob(item.jobId!),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _JobRow extends StatelessWidget {
  final RecordingItem item;
  final VoidCallback onTap;

  const _JobRow({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final (renk, ikon, durum) = switch (item.aiStatus) {
      AiResultStatus.done => (AppTheme.success, Icons.auto_awesome, 'Sonuç hazır'),
      AiResultStatus.failed => (AppTheme.danger, Icons.error_outline, 'AI başarısız'),
      _ => (AppTheme.warning, Icons.hourglass_top, 'İşleniyor…'),
    };

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: renk.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(11),
              ),
              child: item.aiStatus == AiResultStatus.processing
                  ? Padding(
                      padding: const EdgeInsets.all(10),
                      child: CircularProgressIndicator(strokeWidth: 2, color: renk),
                    )
                  : Icon(ikon, color: renk, size: 19),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${item.saat} kaydı',
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(durum, style: TextStyle(fontSize: 11.5, color: renk)),
                      if (item.aiStatus == AiResultStatus.done &&
                          item.aiResult != null) ...[
                        const SizedBox(width: 6),
                        Text(
                          '· ${item.aiResult!.detections.length} tespit',
                          style:
                              const TextStyle(fontSize: 11.5, color: AppTheme.inkSoft),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            Text(
              item.jobId ?? '',
              style: const TextStyle(
                fontFamily: AppTheme.monoFamily,
                fontSize: 10,
                color: AppTheme.inkSoft,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, size: 18, color: AppTheme.inkSoft),
          ],
        ),
      ),
    );
  }
}

// ── Seçilen işin detayı ──────────────────────────────────────────────────────

class _JobDetail extends StatelessWidget {
  final SessionController controller;
  final RecordingItem item;

  const _JobDetail({required this.controller, required this.item});

  @override
  Widget build(BuildContext context) {
    final ustCubuk = Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Row(
        children: [
          TextButton.icon(
            onPressed: controller.clearSelectedJob,
            icon: const Icon(Icons.arrow_back, size: 17),
            label: Text('Videolar (${controller.uploadedJobs.length})'),
          ),
          const Spacer(),
          if (item.aiStatus == AiResultStatus.done)
            TextButton.icon(
              onPressed: () async {
                final mesaj = await controller.exportResultsJson(item);
                if (context.mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text(mesaj)));
                }
              },
              icon: const Icon(Icons.download, size: 17),
              label: const Text('results.json'),
            ),
        ],
      ),
    );

    final Widget govde;
    if (item.aiStatus == AiResultStatus.processing) {
      govde = const _ProcessingState();
    } else if (item.aiStatus == AiResultStatus.failed) {
      govde = const EmptyState(
        icon: Icons.error_outline,
        title: 'AI işlemi başarısız oldu',
        subtitle: 'Sağ üstteki yenile butonuyla tekrar deneyebilirsiniz.',
      );
    } else if (item.aiResult == null) {
      govde = const EmptyState(icon: Icons.search_off, title: 'Sonuç bulunamadı');
    } else {
      govde = _ResultContent(item: item);
    }

    return Column(
      children: [ustCubuk, Expanded(child: govde)],
    );
  }
}

/// Sonuç içeriği: araç kartı + kanıt/zaman çizelgesi + gruplu tespitler +
/// SHA256 + ham JSON.
class _ResultContent extends StatelessWidget {
  final RecordingItem item;

  const _ResultContent({required this.item});

  @override
  Widget build(BuildContext context) {
    final result = item.aiResult!;
    final topDetection = _highestConfidence(result.detections);

    return RefreshIndicator(
      onRefresh: () => context.read<SessionController>().refreshAiResults(),
      color: AppTheme.navy,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Entrance(
            child: Row(
              children: [
                const StepBadge('06'),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${item.saat} kaydı — AI Sonucu',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5),
                  ),
                ),
                _countChips(result.detections),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (result.vehicleInfo != null)
            Entrance(delayMs: 60, child: _VehicleCard(info: result.vehicleInfo!)),
          if (topDetection != null) ...[
            const SizedBox(height: 12),
            Entrance(
                delayMs: 120, child: _evidenceCard(topDetection, result.detections)),
          ],
          const SizedBox(height: 16),
          Entrance(
            delayMs: 180,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: _groupedDetections(result.detections),
            ),
          ),
          if (item.resultsSha256 != null) ...[
            const SizedBox(height: 16),
            Entrance(delayMs: 240, child: _sha256Card(context, item.resultsSha256!)),
          ],
          const SizedBox(height: 16),
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('Ham JSON',
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.navy,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: SelectableText(
                    const JsonEncoder.withIndent('  ').convert(result.raw),
                    style: const TextStyle(
                      fontFamily: AppTheme.monoFamily,
                      fontSize: 11,
                      color: Color(0xFFD6E1F5),
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  /// Kategori bazlı özet rozetleri — bir bakışta "9 tespit: 6 sürücü, 2 yolcu…"
  Widget _countChips(List<Detection> detections) {
    final counts = <String, int>{};
    for (final d in detections) {
      counts[d.kategori ?? '?'] = (counts[d.kategori ?? '?'] ?? 0) + 1;
    }
    final entries = [
      for (final k in _kategoriSirasi)
        if (counts.containsKey(k)) MapEntry(k, counts[k]!),
      for (final e in counts.entries)
        if (!_kategoriSirasi.contains(e.key)) e,
    ];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final e in entries) ...[
          Container(
            margin: const EdgeInsets.only(left: 4),
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: kategoriRenk(e.key).withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration:
                      BoxDecoration(color: kategoriRenk(e.key), shape: BoxShape.circle),
                ),
                const SizedBox(width: 4),
                Text(
                  '${e.value}',
                  style: TextStyle(
                    color: kategoriRenk(e.key),
                    fontWeight: FontWeight.w700,
                    fontSize: 11.5,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  /// mobile-integration.md adım 8: results JSON'unun SHA256'sı ekranda
  /// gösterilir (resmi akış diyagramı adım 17 — imaj hash'inden ayrı bir şey).
  Widget _sha256Card(BuildContext context, String hash) {
    return AccentCard(
      accentColor: AppTheme.success,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.fingerprint, size: 20, color: AppTheme.navy),
                  SizedBox(width: 8),
                  Text('Sonuç SHA256', style: TextStyle(fontWeight: FontWeight.w700)),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.copy, size: 18),
                tooltip: 'Kopyala',
                visualDensity: VisualDensity.compact,
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: hash));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('SHA256 panoya kopyalandı')),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: AppTheme.background,
              borderRadius: BorderRadius.circular(8),
            ),
            child: SelectableText(
              hash,
              style: const TextStyle(
                fontSize: 11.5,
                fontFamily: AppTheme.monoFamily,
                height: 1.5,
                color: AppTheme.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Detection? _highestConfidence(List<Detection> detections) {
    if (detections.isEmpty) return null;
    return detections.reduce(
      (a, b) => (b.confidenceScore ?? 0) > (a.confidenceScore ?? 0) ? b : a,
    );
  }

  Widget _evidenceCard(Detection top, List<Detection> all) {
    final maxTime = all
            .map((d) => d.zamanSaniye ?? 0)
            .fold<double>(0, (a, b) => a > b ? a : b) *
        1.05;

    final kategoriler = <String>{
      for (final d in all)
        if (d.kategori != null) d.kategori!,
    };

    return AccentCard(
      accentColor: AppTheme.turkcellYellow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('En güçlü tespit',
              style: TextStyle(fontSize: 11.5, color: AppTheme.inkSoft)),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: kategoriRenk(top.kategori).withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(iconFor(top.etiket), color: kategoriRenk(top.kategori), size: 25),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(prettyLabel(top.etiket),
                        style:
                            const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        _timeChip(top.zamanSaniye),
                        const SizedBox(width: 6),
                        Text(
                          kategoriAd(top.kategori),
                          style: TextStyle(
                            color: kategoriRenk(top.kategori),
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (top.confidenceScore != null)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '%${(top.confidenceScore! * 100).toStringAsFixed(0)}',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.navy,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                    const Text('güven',
                        style: TextStyle(fontSize: 10.5, color: AppTheme.inkSoft)),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 14),
          const Text('Video zaman çizelgesi',
              style: TextStyle(fontSize: 11, color: AppTheme.inkSoft)),
          const SizedBox(height: 6),
          _DetectionTimeline(detections: all, maxTime: maxTime <= 0 ? 1 : maxTime),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              for (final k in _kategoriSirasi)
                if (kategoriler.contains(k))
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration:
                            BoxDecoration(color: kategoriRenk(k), shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 4),
                      Text(kategoriAd(k),
                          style:
                              const TextStyle(fontSize: 10.5, color: AppTheme.inkSoft)),
                    ],
                  ),
            ],
          ),
        ],
      ),
    );
  }

  /// Tespitleri kategori başlıkları altında, zamana göre sıralı listeler.
  List<Widget> _groupedDetections(List<Detection> detections) {
    final gruplar = <String, List<Detection>>{};
    for (final d in detections) {
      gruplar.putIfAbsent(d.kategori ?? '?', () => []).add(d);
    }
    final sirali = [
      for (final k in _kategoriSirasi)
        if (gruplar.containsKey(k)) k,
      for (final k in gruplar.keys)
        if (!_kategoriSirasi.contains(k)) k,
    ];

    return [
      Text('Tespitler (${detections.length})',
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
      for (final k in sirali) ...[
        const SizedBox(height: 10),
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: kategoriRenk(k), shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(
              '${kategoriAd(k).toUpperCase()} · ${gruplar[k]!.length}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: kategoriRenk(k),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        AccentCard(
          accentColor: kategoriRenk(k).withValues(alpha: 0.5),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Column(
            children: [
              for (final (i, d) in (gruplar[k]!
                    ..sort((a, b) => (a.zamanSaniye ?? 0).compareTo(b.zamanSaniye ?? 0)))
                  .indexed) ...[
                if (i > 0) const Divider(height: 1),
                _detectionRow(d),
              ],
            ],
          ),
        ),
      ],
    ];
  }

  Widget _detectionRow(Detection d) {
    final renk = kategoriRenk(d.kategori);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: renk.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(iconFor(d.etiket), color: renk, size: 17),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              prettyLabel(d.etiket),
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
            ),
          ),
          _timeChip(d.zamanSaniye),
          if (d.confidenceScore != null) ...[
            const SizedBox(width: 10),
            SizedBox(
              width: 40,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '%${(d.confidenceScore! * 100).toStringAsFixed(0)}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(height: 3),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: d.confidenceScore!.clamp(0.0, 1.0),
                      minHeight: 3,
                      backgroundColor: Colors.black.withValues(alpha: 0.06),
                      valueColor: AlwaysStoppedAnimation(renk),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _timeChip(double? zaman) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppTheme.background,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        zaman != null ? '${zaman.toStringAsFixed(1)}s' : '-',
        style: const TextStyle(
          fontFamily: AppTheme.monoFamily,
          fontSize: 11,
          color: AppTheme.ink,
        ),
      ),
    );
  }
}

// ── Etiket → ikon/okunur ad (kategori genelinde ortak) ──────────────────────

IconData iconFor(String? etiket) {
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
      return Icons.smart_toy_outlined;
    case 'bilgisayar':
      return Icons.laptop_mac;
    case 'on_koltuk':
    case 'arka_koltuk_1':
    case 'arka_koltuk_2':
      return Icons.airline_seat_recline_normal;
    default:
      return Icons.report_problem;
  }
}

String prettyLabel(String? raw) {
  if (raw == null || raw.isEmpty) return '-';
  return raw.replaceAll('_', ' ');
}

/// AI işlerken gösterilen bekleme durumu.
class _ProcessingState extends StatelessWidget {
  const _ProcessingState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              const SizedBox(
                width: 64,
                height: 64,
                child: CircularProgressIndicator(strokeWidth: 3, color: AppTheme.navy),
              ),
              Icon(Icons.auto_awesome, color: AppTheme.navy.withValues(alpha: 0.7), size: 24),
            ],
          ),
          const SizedBox(height: 18),
          const Text('AI videoyu işliyor',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5)),
          const SizedBox(height: 5),
          const Text(
            'Tespitler hazır olduğunda otomatik görünecek',
            style: TextStyle(color: AppTheme.inkSoft, fontSize: 12.5),
          ),
        ],
      ),
    );
  }
}

/// Araç kimlik kartı: tip ikonu + gerçekçi TR plaka rozeti + renk örneği.
class _VehicleCard extends StatelessWidget {
  final VehicleInfo info;

  const _VehicleCard({required this.info});

  static const _renkMap = <String, Color>{
    'siyah': Color(0xFF1B1B1F),
    'beyaz': Colors.white,
    'gri': Color(0xFF9AA0A6),
    'kirmizi': Color(0xFFC5221F),
    'mavi': Color(0xFF1A73E8),
    'lacivert': Color(0xFF174EA6),
    'yesil': Color(0xFF188038),
    'sari': Color(0xFFF9AB00),
    'turuncu': Color(0xFFE8710A),
    'kahverengi': Color(0xFF6B4226),
    'bordo': Color(0xFF7B1F2B),
  };

  IconData get _tipIcon => switch (info.tip) {
        'suv' => Icons.directions_car,
        'sedan' => Icons.directions_car_filled,
        'hatchback' => Icons.directions_car_filled_outlined,
        'minibus' || 'minivan' => Icons.airport_shuttle,
        'kamyonet' || 'pickup' => Icons.local_shipping,
        _ => Icons.directions_car,
      };

  @override
  Widget build(BuildContext context) {
    final renkColor = _renkMap[info.renk?.toLowerCase()];
    return AccentCard(
      accentColor: AppTheme.navy,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Araç Bilgisi', style: TextStyle(fontWeight: FontWeight.w700)),
              const Spacer(),
              if (info.confidenceScore != null)
                Text(
                  'güven %${(info.confidenceScore! * 100).toStringAsFixed(0)}',
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppTheme.inkSoft,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: AppTheme.navy.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(_tipIcon, color: AppTheme.navy, size: 27),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (info.plaka != null) _PlateBadge(plate: info.plaka!),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text(
                          (info.tip ?? '-').toUpperCase(),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                            color: AppTheme.ink,
                          ),
                        ),
                        const SizedBox(width: 12),
                        if (renkColor != null)
                          Container(
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                              color: renkColor,
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: Colors.black.withValues(alpha: 0.15)),
                            ),
                          ),
                        if (renkColor != null) const SizedBox(width: 5),
                        Text(
                          info.renk ?? '-',
                          style: const TextStyle(fontSize: 12.5, color: AppTheme.inkSoft),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Gerçekçi TR plakası: mavi "TR" bandı + monospace plaka metni.
class _PlateBadge extends StatelessWidget {
  final String plate;

  const _PlateBadge({required this.plate});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF1B1B1F), width: 1.4),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 22,
            padding: const EdgeInsets.symmetric(vertical: 7),
            color: const Color(0xFF003399),
            alignment: Alignment.bottomCenter,
            child: const Text(
              'TR',
              style: TextStyle(
                color: Colors.white,
                fontSize: 8.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            child: Text(
              plate,
              style: const TextStyle(
                fontFamily: AppTheme.monoFamily,
                fontWeight: FontWeight.w500,
                fontSize: 16,
                letterSpacing: 2,
                color: Color(0xFF1B1B1F),
              ),
            ),
          ),
        ],
      ),
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
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
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
                        left: (d.zamanSaniye! / maxTime).clamp(0.0, 1.0) *
                            (constraints.maxWidth - 4),
                        child: Container(
                          width: 4,
                          height: 20,
                          decoration: BoxDecoration(
                            color: kategoriRenk(d.kategori),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                ],
              ),
            ),
            const SizedBox(height: 3),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('0s',
                    style: TextStyle(
                        fontSize: 9.5,
                        color: AppTheme.inkSoft,
                        fontFamily: AppTheme.monoFamily)),
                Text('${maxTime.toStringAsFixed(0)}s',
                    style: const TextStyle(
                        fontSize: 9.5,
                        color: AppTheme.inkSoft,
                        fontFamily: AppTheme.monoFamily)),
              ],
            ),
          ],
        );
      },
    );
  }
}
