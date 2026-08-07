import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../config/app_config.dart';
import '../models/ai_result.dart';
import '../models/recording_item.dart';
import '../state/session_controller.dart';
import '../theme/app_theme.dart';
import 'accent_card.dart';

/// Open Gateway Demo UX Kılavuzu → "04 Videoyu başlat", "05 Videoyu backend'e
/// yükle" adımları + Lifebox paylaşımı. Oynatma (ekranda gösterim, adaptif
/// ABR) ile kayıt (arkaplanda ffmpeg ile MP4'e remux) birbirinden bağımsız.
///
/// Kayıt istenildiği kadar başlatılıp durdurulabilir; biten her kayıt
/// aşağıdaki listeye düşer. Her kaydın yanındaki baloncuklar: Lifebox'a
/// paylaş, backend'e yükle, (yüklendiyse) AI sonucuna git.
class VideoCard extends StatefulWidget {
  final SessionController controller;

  /// Yüklenmiş bir kaydın AI sonucuna atlamak için (Home, AI sekmesine geçer).
  final void Function(String jobId)? onOpenResult;

  const VideoCard({super.key, required this.controller, this.onOpenResult});

  @override
  State<VideoCard> createState() => _VideoCardState();
}

class _VideoCardState extends State<VideoCard> with AutomaticKeepAliveClientMixin {
  VideoPlayerController? _playerController;
  bool _playerReady = false;
  String? _playerError;

  /// Final günü organizasyonun vereceği yeni akış adresi buraya yapıştırılır.
  late final TextEditingController _urlController =
      TextEditingController(text: widget.controller.streamUrl);

  // Home <-> AI Result sekmeleri arasında geçişte oynatıcının (ve kayıt
  // durumunun görsel önizlemesinin) sıfırlanmaması için — TabBarView
  // varsayılan olarak görünmeyen sekmenin State'ini korumaz.
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _initPlayer() async {
    final controller = VideoPlayerController.networkUrl(
      Uri.parse(widget.controller.streamUrl),
      formatHint: VideoFormat.hls,
    );
    _playerController = controller;
    try {
      await controller.initialize();
      await controller.play();
      setState(() => _playerReady = true);
    } catch (e) {
      setState(() => _playerError = '$e');
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _playerController?.dispose();
    _urlController.dispose();
    super.dispose();
  }

  /// Adres değişince açık oynatıcı eski akışı göstermeye devam etmesin.
  void _resetPlayer() {
    _playerController?.dispose();
    _playerController = null;
    _playerReady = false;
    _playerError = null;
  }

  void _applyUrl(String url) {
    widget.controller.setStreamUrl(url);
    setState(_resetPlayer);
  }

  void _restoreDefaultUrl() {
    widget.controller.streamUrlVarsayilanaDon();
    _urlController.text = widget.controller.streamUrl;
    setState(_resetPlayer);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final c = widget.controller;
    return AccentCard(
      accentColor: c.recording ? AppTheme.danger : AppTheme.idle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const StepBadge('04'),
              const SizedBox(width: 8),
              const Text('TEKNOFEST — Stream',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              const Spacer(),
              if (c.recording) const _RecChip(),
            ],
          ),
          const SizedBox(height: 10),
          _buildUrlField(c),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              children: [
                _buildPreview(),
                if (c.recording)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      height: 3,
                      color: Colors.black.withValues(alpha: 0.25),
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: (c.recordingElapsed.inMilliseconds /
                                AppConfig.maxRecordingDuration.inMilliseconds)
                            .clamp(0.0, 1.0),
                        child: Container(color: AppTheme.danger),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _buildRecordToggle(c),
          if (c.recordingError != null) ...[
            const SizedBox(height: 8),
            Text(
              c.recordingError!,
              style: const TextStyle(color: AppTheme.danger, fontSize: 12),
            ),
          ],
          const SizedBox(height: 14),
          _buildRecordingsList(c),
        ],
      ),
    );
  }

  // ---- Akış adresi ---------------------------------------------------------

  /// Final günü organizasyon yeni bir akış adresi verecek (protokol aynı,
  /// base'den sonrası değişiyor). Canlı demoda yeniden derleme yapamayacağımız
  /// için adres buradan girilebiliyor; "Faz 2" butonu test akışına döndürür.
  Widget _buildUrlField(SessionController c) {
    final uyari = SessionController.streamUrlUyarisi(_urlController.text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.link, size: 14, color: AppTheme.inkSoft),
            const SizedBox(width: 5),
            const Text(
              'AKIŞ ADRESİ',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: AppTheme.inkSoft,
              ),
            ),
            const Spacer(),
            if (!c.streamUrlVarsayilan)
              TextButton(
                onPressed: c.recording ? null : _restoreDefaultUrl,
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                child: const Text('Faz 2 test yayını', style: TextStyle(fontSize: 11.5)),
              ),
          ],
        ),
        const SizedBox(height: 4),
        TextField(
          controller: _urlController,
          // Kayıt sürerken adres değişmesin — ortada kaynak değiştirmek
          // ffmpeg'i yarım kalmış bir dosyayla bırakır.
          enabled: !c.recording,
          keyboardType: TextInputType.url,
          autocorrect: false,
          style: const TextStyle(fontFamily: AppTheme.monoFamily, fontSize: 11.5),
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            hintText: 'https://.../playlist.m3u8',
            hintStyle: const TextStyle(fontSize: 11.5, color: AppTheme.inkSoft),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onChanged: (v) {
            _applyUrl(v);
            setState(() {}); // uyarı metni anlık güncellensin
          },
        ),
        if (uyari != null) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(Icons.info_outline, size: 13, color: AppTheme.warning),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  uyari,
                  style: const TextStyle(fontSize: 11, color: AppTheme.warning),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  // ---- Kayıt başlat/durdur -------------------------------------------------

  Widget _buildRecordToggle(SessionController c) {
    if (c.recording) {
      final remaining = AppConfig.maxRecordingDuration - c.recordingElapsed;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Kaydediliyor', style: TextStyle(fontWeight: FontWeight.w600)),
              const Spacer(),
              Text(
                '${_fmt(c.recordingElapsed)} / kalan ${_fmt(remaining)}',
                style: const TextStyle(
                  fontFamily: AppTheme.monoFamily,
                  fontSize: 12.5,
                  color: AppTheme.inkSoft,
                ),
              ),
            ],
          ),
          // Şartname 4.2: kayıt, o anki bant genişliğine en uygun varyanttan
          // alınıyor. Seçimi görünür kılıyoruz — canlı demoda hakemin bunu
          // doğrulayabilmesi için (QoD başarılıysa yüksek, değilse düşük).
          if (c.secilenVaryant != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.network_check, size: 14, color: AppTheme.inkSoft),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    'Bant genişliğine göre seçilen kalite: '
                    '${c.secilenVaryant!.etiket}',
                    style: const TextStyle(fontSize: 11.5, color: AppTheme.inkSoft),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: c.stopRecordingEarly,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.danger,
                side: const BorderSide(color: AppTheme.danger),
              ),
              icon: const Icon(Icons.stop, size: 18),
              label: const Text('Kaydı Bitir'),
            ),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.danger,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: () => _kaydiBaslat(c),
            icon: const Icon(Icons.fiber_manual_record, size: 18),
            label: Text(c.recordings.isEmpty ? 'Kaydı Başlat' : 'Yeni Kayıt Başlat'),
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Maks. 5 dakika',
          style: TextStyle(fontSize: 11, color: AppTheme.inkSoft),
        ),
      ],
    );
  }

  /// QoD açılmadan kayda başlanıyorsa önce onay ister.
  ///
  /// Engellemiyoruz (kullanıcı bilerek devam edebilmeli) ama kazara olmasına
  /// da izin vermiyoruz: QoD'siz hat 256 kbit ve kayıt zorunlu olarak 240p'ye
  /// düşüyor. Hakem, Lifebox'a yüklediğimiz kaydı da ayrı bir inference'a
  /// soktuğu için (Final Yarışma Senaryosu md. 5) bu doğrudan puan kaybı.
  Future<void> _kaydiBaslat(SessionController c) async {
    if (!c.qodSession.succeeded) {
      final devam = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('QoD açılmadı'),
          content: const Text(
            'Bağlantı 256 kbit\'te kalacağı için kayıt 240p\'ye düşecek ve '
            'AI sonucu düşük kalitede olacak.\n\n'
            'Önce QoD kartından oturumu açman önerilir. Yine de devam edilsin mi?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Yine de kaydet'),
            ),
          ],
        ),
      );
      if (devam != true) return;
    }
    await c.startRecording(c.streamUrl);
  }

  /// Süresi şüpheli (muhtemelen ağ/QoD kesintisiyle erken bitmiş) bir kaydı
  /// Lifebox'a/backend'e göndermeden önce BİLİNÇLİ onay ister — sözleşme
  /// diğer benzer uyarılarla (ör. QoD atlandı diyaloğu) aynı desen:
  /// engellemiyoruz, ama kazara "eksik" bir video gönderilmesin.
  Future<bool> _supheliOnayAl(RecordingItem item) async {
    final beklenen = item.beklenenSaniye?.toStringAsFixed(0) ?? '?';
    final gercek = item.gercekSaniye?.toStringAsFixed(0) ?? '?';
    final devam = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Kayıt eksik olabilir'),
        content: Text(
          'Beklenen süre $beklenen sn, ölçülen gerçek süre $gercek sn — '
          'muhtemelen kayıt sırasında bağlantı kesintiye uğradı (QoD oturumu '
          'bitmiş olabilir).\n\nYine de bu kaydı göndermek istiyor musun? '
          'Emin değilsen önce yeni bir kayıt almanı öneririz.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
            child: const Text('Yine de gönder'),
          ),
        ],
      ),
    );
    return devam ?? false;
  }

  // ---- Kayıt listesi -------------------------------------------------------

  Widget _buildRecordingsList(SessionController c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.video_library_outlined, size: 15, color: AppTheme.inkSoft),
            const SizedBox(width: 6),
            Text(
              'KAYITLAR · ${c.recordings.length}',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: AppTheme.inkSoft,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (c.recordings.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: Text(
              'Henüz kayıt yok — istediğin kadar kayıt alıp buradan '
              'Lifebox\'a ya da backend\'e gönderebilirsin.',
              style: TextStyle(fontSize: 12, color: AppTheme.inkSoft),
            ),
          )
        else
          for (final (i, item) in c.recordings.indexed) ...[
            if (i > 0) const Divider(height: 1),
            _RecordingTile(
              item: item,
              onUpload: () async {
                if (item.supheliSure && !await _supheliOnayAl(item)) return;
                c.uploadRecording(item);
              },
              onLifebox: () async {
                if (item.supheliSure && !await _supheliOnayAl(item)) return;
                if (!mounted) return;
                if (kIsWeb) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Paylaşım menüsü yalnızca telefonda açılır')));
                } else {
                  c.shareToLifebox(item);
                }
              },
              onOpenResult: item.jobId == null
                  ? null
                  : () => widget.onOpenResult?.call(item.jobId!),
            ),
          ],
      ],
    );
  }

  // ---- Önizleme ------------------------------------------------------------

  Widget _buildPreview() {
    if (_playerError != null) {
      return Container(
        height: 160,
        width: double.infinity,
        color: const Color(0xFFFDECEC),
        padding: const EdgeInsets.all(16),
        child: Center(
          child: Text(
            'Oynatma hatası: $_playerError',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppTheme.danger, fontSize: 12),
          ),
        ),
      );
    }
    if (_playerReady && _playerController != null) {
      return AspectRatio(
        aspectRatio: _playerController!.value.aspectRatio,
        child: VideoPlayer(_playerController!),
      );
    }
    return Container(
      height: 180,
      width: double.infinity,
      decoration: const BoxDecoration(gradient: AppTheme.headerGradient),
      child: DotMatrixBackground(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                ),
                // Bilinçli seçim: hemen altındaki buton zaten Icons.play_arrow
                // taşıyor — burada "TV" değil "sinyal/yayın" hissi veren bir
                // ikon kullanıyoruz ki ikisi tekrar etmesin.
                child: const Icon(Icons.sensors, color: AppTheme.turkcellYellow, size: 28),
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.turkcellYellow,
                  foregroundColor: AppTheme.navy,
                ),
                onPressed: _initPlayer,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Yayını Başlat (HLS)'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

/// Tek kayıt satırı: ad + durum + eylem baloncukları (Lifebox / yükle / AI).
class _RecordingTile extends StatelessWidget {
  final RecordingItem item;
  final VoidCallback onUpload;
  final VoidCallback onLifebox;
  final VoidCallback? onOpenResult;

  const _RecordingTile({
    required this.item,
    required this.onUpload,
    required this.onLifebox,
    this.onOpenResult,
  });

  String get _durumMetni {
    // Şüpheli süre uyarısı her zaman ÖNCELİKLİ gösterilir — kullanıcı
    // "Yüklendi" gibi normal bir durum metniyle bunun eksik bir kayıt
    // olduğunu gözden kaçırmasın.
    if (item.supheliSure) {
      final gercek = item.gercekSaniye?.toStringAsFixed(0) ?? '?';
      final beklenen = item.beklenenSaniye?.toStringAsFixed(0) ?? '?';
      return '⚠ Eksik olabilir · $gercek/$beklenen sn';
    }
    if (item.uploadState == UploadState.uploading) return 'Backend\'e yükleniyor…';
    if (item.uploadState == UploadState.failed) {
      return item.uploadError ?? 'Yükleme başarısız — tekrar dene';
    }
    if (item.uploaded) {
      return switch (item.aiStatus) {
        AiResultStatus.processing => 'Yüklendi · AI işliyor…',
        AiResultStatus.done => 'Yüklendi · AI sonucu hazır',
        AiResultStatus.failed => 'Yüklendi · AI başarısız',
        _ => 'Yüklendi',
      };
    }
    final parcalar = [
      if (item.sureMetni != null) item.sureMetni!,
      if (item.boyutMetni != null) item.boyutMetni!,
    ];
    return parcalar.isEmpty ? 'Hazır' : parcalar.join(' · ');
  }

  Color get _durumRengi {
    if (item.supheliSure) return AppTheme.danger;
    if (item.uploadState == UploadState.failed) return AppTheme.danger;
    if (item.aiStatus == AiResultStatus.done) return AppTheme.success;
    if (item.uploadState == UploadState.uploading ||
        item.aiStatus == AiResultStatus.processing) {
      return AppTheme.warning;
    }
    return AppTheme.inkSoft;
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onOpenResult,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: (item.supheliSure ? AppTheme.danger : AppTheme.navy)
                    .withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                item.supheliSure ? Icons.warning_amber_rounded : Icons.movie_outlined,
                color: item.supheliSure ? AppTheme.danger : AppTheme.navy,
                size: 18,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${item.saat} kaydı',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _durumMetni,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: _durumRengi),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            _Bubble(
              icon: Icons.share,
              tooltip: 'Lifebox\'a paylaş',
              color: AppTheme.navy,
              onTap: onLifebox,
            ),
            const SizedBox(width: 6),
            _uploadBubble(),
            if (onOpenResult != null && item.aiStatus != AiResultStatus.idle) ...[
              const SizedBox(width: 6),
              _Bubble(
                icon: Icons.auto_awesome,
                tooltip: 'AI sonucunu gör',
                color: item.aiStatus == AiResultStatus.done
                    ? AppTheme.success
                    : AppTheme.warning,
                onTap: onOpenResult!,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _uploadBubble() {
    return switch (item.uploadState) {
      UploadState.uploading => const _Bubble.spinner(),
      UploadState.uploaded => const _Bubble(
          icon: Icons.cloud_done,
          tooltip: 'Backend\'e yüklendi',
          color: AppTheme.success,
          onTap: null,
        ),
      UploadState.failed => _Bubble(
          icon: Icons.refresh,
          tooltip: 'Yüklemeyi tekrar dene',
          color: AppTheme.danger,
          onTap: onUpload,
        ),
      UploadState.none => _Bubble(
          icon: Icons.cloud_upload_outlined,
          tooltip: 'Backend\'e yükle',
          color: AppTheme.catPassenger,
          onTap: onUpload,
        ),
    };
  }
}

/// Küçük yuvarlak eylem butonu ("baloncuk").
class _Bubble extends StatelessWidget {
  final IconData? icon;
  final String? tooltip;
  final Color color;
  final VoidCallback? onTap;
  final bool spinner;

  const _Bubble({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onTap,
  }) : spinner = false;

  const _Bubble.spinner()
      : icon = null,
        tooltip = 'Yükleniyor…',
        color = AppTheme.warning,
        onTap = null,
        spinner = true;

  @override
  Widget build(BuildContext context) {
    final govde = Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: color.withValues(alpha: onTap == null && !spinner ? 0.14 : 0.10),
        shape: BoxShape.circle,
      ),
      child: spinner
          ? Padding(
              padding: const EdgeInsets.all(8),
              child: CircularProgressIndicator(strokeWidth: 2, color: color),
            )
          : Icon(icon, size: 16, color: color),
    );
    final tik = onTap == null
        ? govde
        : InkWell(customBorder: const CircleBorder(), onTap: onTap, child: govde);
    return tooltip == null ? tik : Tooltip(message: tooltip!, child: tik);
  }
}

/// Yanıp sönen kırmızı kayıt rozeti — kayıt sürerken kart başlığında durur.
class _RecChip extends StatefulWidget {
  const _RecChip();

  @override
  State<_RecChip> createState() => _RecChipState();
}

class _RecChipState extends State<_RecChip> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 800))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.danger.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FadeTransition(
            opacity: Tween(begin: 0.25, end: 1.0).animate(_controller),
            child: Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(color: AppTheme.danger, shape: BoxShape.circle),
            ),
          ),
          const SizedBox(width: 5),
          const Text(
            'REC',
            style: TextStyle(
              color: AppTheme.danger,
              fontWeight: FontWeight.w800,
              fontSize: 11,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}
