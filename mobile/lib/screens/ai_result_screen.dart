import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../config/app_config.dart';
import '../models/ai_result.dart';
import '../models/recording_item.dart';
import '../services/results_fingerprint.dart';
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

/// Tespitin saniye cinsinden zamanını (`Detection.zamanSaniye`) video
/// oynatıcıdaki `seekTo` çağrısı için `Duration`'a çevirir. Ayrı bir
/// top-level fonksiyon: hem `_ResultContentState._tespitiGoster` içinde
/// kullanılıyor hem de yuvarlama davranışı (`ai_result_screen_test.dart`)
/// bağımsız test edilebiliyor.
Duration saniyeyeGoreKonum(double saniye) =>
    Duration(milliseconds: (saniye * 1000).round());

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

/// Tam job_id (36 karakterlik UUID) bu dar satırda `Expanded` metni
/// karakter karakter satır kırdırıyordu (Row, Expanded'a kalan yeri en son
/// veriyor — sınırsız genişlikteki bu Text önce tüm satırı yiyordu). Liste
/// satırında yalnızca kısa bir önizleme yeterli; tam kimlik zaten burada
/// gösterilmiyordu (detay ekranında da yok), o yüzden bilgi kaybı yok.
String _kisaJobId(String? jobId) {
  if (jobId == null || jobId.isEmpty) return '';
  return jobId.length > 8 ? '${jobId.substring(0, 8)}…' : jobId;
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
              _kisaJobId(item.jobId),
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
      govde = _ProcessingState(
        startedAt: item.processingStartedAt,
        baglantiSorunu: controller.aiBaglantiSorunu,
      );
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

/// Sonuç içeriği: araç kartı + kanıt/zaman çizelgesi + video önizleme +
/// gruplu tespitler + SHA256 + ham JSON.
class _ResultContent extends StatefulWidget {
  final RecordingItem item;

  const _ResultContent({required this.item});

  @override
  State<_ResultContent> createState() => _ResultContentState();
}

class _ResultContentState extends State<_ResultContent> {
  // ── Tespit-bağlantılı donuk video önizleme ────────────────────────────────
  //
  // Kayıt zaten cihazda yerel bir MP4 olarak duruyor (widget.item.path) — bir
  // tespite dokununca ek indirme olmadan o saniyeye zıplayıp donuk bir kare
  // gösteriyoruz; "Oynat"a basılırsa oradan devam ediyor.
  VideoPlayerController? _videoController;
  Detection? _secilenTespit;
  bool _videoYukleniyor = false;
  String? _videoHata;

  // Video kartı sayfanın üst kısmında (başlık + araç kartından hemen sonra)
  // olduğu için, bir tespite dokununca ekranı SAYFANIN EN BAŞINA kaydırmak
  // — belirli bir widget'ı `Scrollable.ensureVisible` ile hedeflemekten daha
  // basit ve güvenilir (7 Ağustos: ensureVisible kullanıcıya göre çalışmıyor
  // gibi görünüyordu; "en yukarı kaydırsın yeterli" isteği üzerine sadeleşti).
  final ScrollController _scrollController = ScrollController();

  // 7 Ağustos bug'ı: ilk birkaç tespit çalışıp sonrakiler tepki vermiyordu.
  // Kök sebep — "controller zaten var" dalında HİÇBİR eşzamanlılık koruması
  // yoktu (yalnızca "controller henüz yok" dalı `_videoYukleniyor` ile
  // korunuyordu). Kullanıcı listede hızlı dokunduğunda aynı controller'a
  // ÜST ÜSTE `seekTo`/`pause` çağrıları gidiyordu — video_player'ın Android
  // tarafı (ExoPlayer) örtüşen seek'lerde tıkanabiliyor, bu noktadan sonra
  // `await`'ler hiç dönmüyor, TÜM sonraki dokunuşlar sessizce etkisiz
  // kalıyordu. Çözüm: TEK bir meşguliyet bayrağı + "en son isteğe kilitlen"
  // kuyruğu — asla iki native çağrı üst üste binmez, ama hiçbir dokunuş da
  // kaybolmaz (meşgulken gelen istekler _beklemedekiTespit'e yazılır, iş
  // bitince en son o uygulanır).
  bool _videoMesgul = false;
  Detection? _beklemedekiTespit;

  @override
  void initState() {
    super.initState();
    // Ekran ilk açıldığında en güçlü tespitin anı otomatik donuk gösterilir —
    // kullanıcı hiç dokunmadan en önemli anı görür. Kaydırma YOK: kart zaten
    // doğal konumunda, ekran yeni açıldı.
    final top = _highestConfidence(widget.item.aiResult?.detections ?? const []);
    if (top != null) {
      unawaited(_tespitiGoster(top, scrollToVideo: false));
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _tespitiGoster(Detection d, {bool scrollToVideo = true}) async {
    if (d.zamanSaniye == null) return;
    if (!mounted) return;
    setState(() => _secilenTespit = d);

    if (scrollToVideo && _scrollController.hasClients) {
      // Video decode'unu beklemeden HEMEN kaydır — soğuk ilk yüklemede
      // kullanıcı decoder süresi kadar beklemeden video kartını görsün.
      // Video kartı sayfanın üst kısmında olduğu için sayfanın en başına
      // kaydırmak yeterli (bkz. _scrollController dokümantasyonu).
      unawaited(_scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
      ));
    }

    // Zaten bir seek/init sürüyorsa native tarafa ÜST ÜSTE çağrı gitmesin —
    // en son istenen tespiti hatırla, iş bitince ona uygulanır (bkz.
    // _videoMesgul dokümantasyonu). Hiçbir dokunuş kaybolmaz, ama asla iki
    // işlem aynı anda çakışmaz.
    if (_videoMesgul) {
      _beklemedekiTespit = d;
      return;
    }
    await _videoyuHedefeGetir(d);
  }

  Future<void> _videoyuHedefeGetir(Detection d) async {
    _videoMesgul = true;
    try {
      final hedef = saniyeyeGoreKonum(d.zamanSaniye!);

      if (_videoController == null) {
        setState(() {
          _videoYukleniyor = true;
          _videoHata = null;
        });
        final controller = VideoPlayerController.file(File(widget.item.path));
        // await'ten ÖNCE ata: init sırasında widget dispose olursa (iş
        // değişti, sekmeden çıkıldı) dispose()'un temizleyecek bir şeyi
        // olsun — video_card.dart:_initPlayer ile aynı örüntü.
        _videoController = controller;
        try {
          await controller.initialize();
          final sinirli =
              hedef > controller.value.duration ? controller.value.duration : hedef;
          await controller.seekTo(sinirli);
          await controller.pause();
          if (!mounted) return;
          setState(() => _videoYukleniyor = false);
        } catch (e) {
          if (!mounted) return;
          setState(() {
            _videoHata = '$e';
            _videoYukleniyor = false;
          });
        }
      } else {
        final c = _videoController!;
        final sinirli = hedef > c.value.duration ? c.value.duration : hedef;
        // Yeni dokunuşta HER ZAMAN kes ve donuk kareye geç — oynatma
        // sürüyor olsa bile "bu tespite dokun -> o anı gör" önceliklidir.
        await c.pause();
        await c.seekTo(sinirli);
        if (mounted) setState(() {});
      }
    } finally {
      _videoMesgul = false;
      final sonraki = _beklemedekiTespit;
      _beklemedekiTespit = null;
      if (sonraki != null && mounted) {
        unawaited(_videoyuHedefeGetir(sonraki));
      }
    }
  }

  void _oynatDurdur() {
    final c = _videoController;
    if (c == null || !c.value.isInitialized) return;
    c.value.isPlaying ? c.pause() : c.play();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final result = item.aiResult!;
    final topDetection = _highestConfidence(result.detections);

    return RefreshIndicator(
      onRefresh: () => context.read<SessionController>().refreshAiResults(),
      color: AppTheme.navy,
      child: ListView(
        controller: _scrollController,
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
          // Video önizleme kanıt kartının içinde olduğu için (dokununca en
          // başa kaydırıyoruz) bu kart araç/plaka kartından ÖNCE geliyor —
          // kaydırma sonrası kullanıcı önce videoyu görsün, plaka kartını
          // aramasın (7 Ağustos: sıra tam tersiydi, kullanıcı isteğiyle
          // değişti).
          if (topDetection != null) ...[
            Entrance(
                delayMs: 60, child: _evidenceCard(topDetection, result.detections)),
            const SizedBox(height: 12),
          ],
          if (result.vehicleInfo != null)
            Entrance(delayMs: 120, child: _VehicleCard(info: result.vehicleInfo!)),
          const SizedBox(height: 16),
          Entrance(
            delayMs: 180,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: _groupedDetections(result.detections),
            ),
          ),
          if (item.resultsMd5 != null) ...[
            const SizedBox(height: 16),
            Entrance(delayMs: 240, child: _Md5Card(item: item)),
          ],
          if (item.resultsSha256 != null) ...[
            const SizedBox(height: 12),
            Entrance(delayMs: 280, child: _sha256Card(context, item.resultsSha256!)),
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

  /// results.json'un SHA256'sı — **bilgi amaçlı**.
  ///
  /// Etiketin bu kadar açık olması bilinçli: Final Yarışma Senaryosu'ndaki
  /// SHA256 gerekliliği *"ürettikleri **imajın** SHA256 parmak izi"* — yani
  /// Docker imajına ait, ayrıca ibraz edilen bambaşka bir değer. Ekranda kısaca
  /// "SHA256" yazsaydı hakem bunu imaj hash'i sanabilirdi.
  Widget _sha256Card(BuildContext context, String hash) {
    return AccentCard(
      accentColor: AppTheme.idle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Row(
                  children: [
                    Icon(Icons.tag, size: 18, color: AppTheme.inkSoft),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'results.json SHA256 (bilgi amaçlı)',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: AppTheme.inkSoft,
                        ),
                      ),
                    ),
                  ],
                ),
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
                color: AppTheme.inkSoft,
              ),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Bu değer yukarıdaki "Lifebox\'a gönder" paketine MD5 ile birlikte zaten dahil.',
            style: TextStyle(fontSize: 11, color: AppTheme.inkSoft),
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
          // Tutarlılık için: aşağıdaki liste satırları ve zaman çizelgesi
          // noktaları da tıklanabilir, en belirgin kart tıklanamaz kalırsa
          // kafa karıştırır.
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: top.zamanSaniye == null ? null : () => _tespitiGoster(top),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: kategoriRenk(top.kategori).withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child:
                      Icon(iconFor(top.etiket), color: kategoriRenk(top.kategori), size: 25),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(prettyLabel(top.etiket),
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 15)),
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
          ),
          const SizedBox(height: 14),
          // Tespit anını gösteren donuk video önizleme — zaman çizelgesinin
          // HEMEN ÜSTÜNDE, sabit yükseklikte (dört durumda da aynı boy).
          _VideoOnizlemeKarti(
            controller: _videoController,
            yukleniyor: _videoYukleniyor,
            hata: _videoHata,
            secilenTespit: _secilenTespit,
            onPlayPause: _oynatDurdur,
          ),
          const SizedBox(height: 10),
          const Text('Video zaman çizelgesi',
              style: TextStyle(fontSize: 11, color: AppTheme.inkSoft)),
          const SizedBox(height: 6),
          _DetectionTimeline(
            detections: all,
            maxTime: maxTime <= 0 ? 1 : maxTime,
            selected: _secilenTespit,
            onSelect: _tespitiGoster,
          ),
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
    // `Detection` nesneleri `done` bir iş için asla yeniden yaratılmıyor
    // (refreshAiResults yalnızca `processing` işleri sorguluyor) — identity
    // karşılaştırması güvenli.
    final secili = identical(d, _secilenTespit);
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: d.zamanSaniye == null ? null : () => _tespitiGoster(d),
      child: Container(
        color: secili ? renk.withValues(alpha: 0.06) : Colors.transparent,
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
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
            if (secili) ...[
              Icon(Icons.play_circle_fill, size: 16, color: renk),
              const SizedBox(width: 6),
            ],
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

/// results.json'un MD5 parmak izi + Lifebox paylaşımı.
///
/// Organizasyonun istediği biçim: JSON boşluksuz yazılır, MD5'i alınır, ilk
/// 7 karakter gösterilir. Kalan 25 karakter parola alanı gibi maskeli durur;
/// karta dokununca açılır. Gizlemenin amacı güvenlik değil okunabilirlik —
/// 32 karakterlik bir dizi ekranda gereksiz yer kaplıyor ve jüriye okunması
/// gereken şey zaten ilk 7 karakter (git'in kısa commit hash mantığı).
class _Md5Card extends StatefulWidget {
  final RecordingItem item;

  const _Md5Card({required this.item});

  @override
  State<_Md5Card> createState() => _Md5CardState();
}

class _Md5CardState extends State<_Md5Card> {
  bool _acik = false;

  @override
  Widget build(BuildContext context) {
    final hash = widget.item.resultsMd5!;
    return AccentCard(
      accentColor: AppTheme.success,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.fingerprint, size: 20, color: AppTheme.navy),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('Sonuç parmak izi (MD5)',
                    style: TextStyle(fontWeight: FontWeight.w700)),
              ),
              IconButton(
                icon: const Icon(Icons.copy, size: 18),
                tooltip: 'Tam değeri kopyala',
                visualDensity: VisualDensity.compact,
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: hash));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('MD5 panoya kopyalandı')),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Dokununca aç/kapa — parola alanı mantığı.
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => setState(() => _acik = !_acik),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.background,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _acik ? hash : ResultsFingerprint.maskele(hash),
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontFamily: AppTheme.monoFamily,
                        height: 1.4,
                        color: AppTheme.ink,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    _acik ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                    size: 17,
                    color: AppTheme.inkSoft,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _acik
                ? 'Gizlemek için dokun'
                : 'Tam değeri görmek için dokun — ilk 7 karakter kısa kimlik',
            style: const TextStyle(fontSize: 11, color: AppTheme.inkSoft),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.navy,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: () async {
                final mesaj = await context
                    .read<SessionController>()
                    .shareResultsBundle(widget.item);
                if (context.mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text(mesaj)));
                }
              },
              icon: const Icon(Icons.cloud_upload_outlined, size: 18),
              label: const Text('results.json + MD5 + SHA256\'yı Lifebox\'a gönder'),
            ),
          ),
        ],
      ),
    );
  }
}

/// AI işlerken gösterilen bekleme durumu — canlı bir sayaçla ne kadar
/// süredir işlendiğini gösterir. Final Yarışma Senaryosu § 5: her inference
/// için tanınan üst sınır 10 dakika; sayaç bu tavana yaklaştıkça (7 dk
/// sonrası sarı, 9 dk sonrası kırmızı) renk değiştirerek erken uyarı verir.
class _ProcessingState extends StatefulWidget {
  final DateTime? startedAt;

  /// Arka arkaya birkaç sonuç sorgusu backend'e ulaşamadıysa true. Bu durumda
  /// "AI çalışıyor" demek YANLIŞ olur: AI çoktan bitmiş olabilir, biz sadece
  /// öğrenemiyoruzdur (6 Ağustos: iş 7 dk'da bitti, telefon hiç haberdar
  /// olamadı çünkü bağlantı kopmuştu ve ekran yine "işliyor" diyordu).
  final bool baglantiSorunu;

  const _ProcessingState({required this.startedAt, this.baglantiSorunu = false});

  @override
  State<_ProcessingState> createState() => _ProcessingStateState();
}

class _ProcessingStateState extends State<_ProcessingState>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  )..repeat(reverse: true);

  Timer? _ticker;
  Duration _elapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    _tick();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    final started = widget.startedAt;
    if (!mounted) return;
    setState(() {
      _elapsed = started == null ? Duration.zero : DateTime.now().difference(started);
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final maxMs = AppConfig.aiProcessingTimeout.inMilliseconds;
    final fraction = widget.startedAt == null
        ? 0.0
        : (_elapsed.inMilliseconds / maxMs).clamp(0.0, 1.0);
    final asildi = _elapsed >= AppConfig.aiProcessingTimeout;

    final renk = (asildi || widget.baglantiSorunu)
        ? AppTheme.danger
        : fraction >= 0.7
            ? AppTheme.warning
            : AppTheme.navy;

    final dakika = _elapsed.inMinutes.toString().padLeft(2, '0');
    final saniye = _elapsed.inSeconds.remainder(60).toString().padLeft(2, '0');

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: AccentCard(
          accentColor: renk,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedBuilder(
                animation: _pulse,
                builder: (context, child) {
                  final t = _pulse.value;
                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: 58 + t * 10,
                        height: 58 + t * 10,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: renk.withValues(alpha: 0.08 * (1 - t)),
                        ),
                      ),
                      child!,
                    ],
                  );
                },
                child: Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: renk.withValues(alpha: 0.10),
                  ),
                  child: Icon(Icons.auto_awesome, color: renk, size: 26),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                widget.baglantiSorunu
                    ? 'Backend\'e ulaşılamıyor'
                    : 'AI videoyu işliyor',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15.5,
                  color: widget.baglantiSorunu ? AppTheme.danger : AppTheme.ink,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                widget.baglantiSorunu
                    ? 'Sonuç hazır olabilir ama sorgulayamıyoruz. Bağlantıyı '
                        '(hücresel veri) kontrol edin — otomatik denemeye devam ediliyor.'
                    : 'Tespitler hazır olduğunda otomatik görünecek',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppTheme.inkSoft, fontSize: 12.5),
              ),
              const SizedBox(height: 22),
              Text(
                '$dakika:$saniye',
                style: TextStyle(
                  fontFamily: AppTheme.monoFamily,
                  fontSize: 36,
                  fontWeight: FontWeight.w700,
                  color: renk,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: fraction,
                  minHeight: 5,
                  backgroundColor: AppTheme.background,
                  valueColor: AlwaysStoppedAnimation(renk),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                asildi
                    ? 'Beklenenden uzun sürüyor — backend tarafında zaman aşımı yakında düşecek'
                    : 'Yarışma kuralı: inference başına maksimum 10 dakika',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  color: asildi ? AppTheme.danger : AppTheme.inkSoft,
                  fontWeight: asildi ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
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

  /// Şu an video önizlemesinde donuk gösterilen tespit — o noktanın çizelgede
  /// büyütülüp çerçevelenmesi için (bkz. `_ResultContentState._secilenTespit`).
  final Detection? selected;

  /// Bir noktaya dokununca çağrılır (`_ResultContentState._tespitiGoster`).
  final void Function(Detection)? onSelect;

  const _DetectionTimeline({
    required this.detections,
    required this.maxTime,
    this.selected,
    this.onSelect,
  });

  // Görsel işaretçi yalnızca 4px genişliğinde — parmakla dokunmak için çok
  // dar. Görünmez ama daha geniş bir dokunma alanı (bu sabit), işaretçiyi
  // ortalayarak sarar.
  static const double _dokunmaAlani = 28;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: _dokunmaAlani,
              child: Stack(
                clipBehavior: Clip.none,
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
                        // İşaretçinin (4px) görsel merkezini koruyarak
                        // etrafına _dokunmaAlani genişliğinde bir kutu koyar.
                        left: (d.zamanSaniye! / maxTime).clamp(0.0, 1.0) *
                                (constraints.maxWidth - 4) +
                            2 -
                            _dokunmaAlani / 2,
                        width: _dokunmaAlani,
                        height: _dokunmaAlani,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: onSelect == null ? null : () => onSelect!(d),
                          child: Center(
                            child: _TimelineIsaretci(
                              renk: kategoriRenk(d.kategori),
                              secili: identical(d, selected),
                            ),
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

/// Zaman çizelgesindeki tek bir tespit işaretçisi — seçiliyken büyür ve
/// çerçevelenir (bkz. `_DetectionTimeline`).
class _TimelineIsaretci extends StatelessWidget {
  final Color renk;
  final bool secili;

  const _TimelineIsaretci({required this.renk, required this.secili});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: secili ? 7 : 4,
      height: secili ? 24 : 20,
      decoration: BoxDecoration(
        color: renk,
        borderRadius: BorderRadius.circular(3),
        border: secili ? Border.all(color: AppTheme.navy, width: 1.5) : null,
        boxShadow: secili
            ? [BoxShadow(color: renk.withValues(alpha: 0.5), blurRadius: 4)]
            : null,
      ),
    );
  }
}

/// Tespit anını gösteren donuk video önizleme — `widget.item.path`'teki
/// yerel MP4'ten, kaydırma/network olmadan. Dört durum, HEPSİ AYNI sabit
/// yükseklikte (`_ResultContentState._videoKartYuksekligi`) — kart state
/// değiştikçe boy zıplamasın (sayfa en başa kaydırıldığı için scroll hedefi
/// bu widget'a bağlı değil artık, ama boyut kararlılığı yine de önemli).
///
/// `BoxFit.cover` BİLİNÇLİ OLARAK KULLANILMIYOR: kırpma, tespit edilen olayı
/// tam da görmek istediğimiz kare dışına atabilir — amaç "görsel doğrulama"
/// olduğu için bir `Center`+`AspectRatio` (letterbox/"contain") kullanılıyor,
/// dikey ya da yatay kayıt fark etmeksizin kare tam görünür.
class _VideoOnizlemeKarti extends StatelessWidget {
  static const double yukseklik = 200;

  final VideoPlayerController? controller;
  final bool yukleniyor;
  final String? hata;
  final Detection? secilenTespit;
  final VoidCallback onPlayPause;

  const _VideoOnizlemeKarti({
    required this.controller,
    required this.yukleniyor,
    required this.hata,
    required this.secilenTespit,
    required this.onPlayPause,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        height: yukseklik,
        width: double.infinity,
        child: _icerik(),
      ),
    );
  }

  Widget _icerik() {
    if (hata != null) {
      return Container(
        color: const Color(0xFFFDECEC),
        padding: const EdgeInsets.all(16),
        child: Center(
          child: Text(
            'Video oynatılamadı: $hata',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppTheme.danger, fontSize: 12),
          ),
        ),
      );
    }

    final c = controller;
    if (c != null && c.value.isInitialized) {
      return AnimatedBuilder(
        animation: c,
        builder: (context, _) {
          final konum = c.value.position;
          final sure = c.value.duration;
          return Container(
            color: AppTheme.navy,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Center(
                  child: AspectRatio(
                    aspectRatio: c.value.aspectRatio,
                    child: VideoPlayer(c),
                  ),
                ),
                Positioned.fill(
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: onPlayPause,
                      child: Center(
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 150),
                          opacity: c.value.isPlaying ? 0.0 : 1.0,
                          child: Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.35),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.play_arrow,
                                color: Colors.white, size: 30),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (secilenTespit != null)
                  Positioned(
                    left: 8,
                    bottom: 8,
                    child: _etiketRozeti(secilenTespit!),
                  ),
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: _konumRozeti(konum, sure),
                ),
              ],
            ),
          );
        },
      );
    }

    if (yukleniyor) {
      return Container(
        color: AppTheme.navy,
        child: const Center(
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white70),
          ),
        ),
      );
    }

    // Boş yer tutucu — henüz hiçbir tespite dokunulmadı (ve en güçlü tespit
    // yoksa initState de otomatik yüklemedi).
    return Container(
      color: AppTheme.navy,
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.movie_creation_outlined, color: Colors.white38, size: 28),
            SizedBox(height: 8),
            Text(
              'Bir tespite dokunarak o anı görüntüle',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _etiketRozeti(Detection d) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration:
                BoxDecoration(color: kategoriRenk(d.kategori), shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            '${prettyLabel(d.etiket)} · ${d.zamanSaniye?.toStringAsFixed(1) ?? '-'}s',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _konumRozeti(Duration konum, Duration sure) {
    String fmt(Duration d) {
      final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
      final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
      return '$m:$s';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '${fmt(konum)} / ${fmt(sure)}',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontFamily: AppTheme.monoFamily,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}
