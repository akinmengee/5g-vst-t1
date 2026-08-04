import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../config/app_config.dart';
import '../state/session_controller.dart';
import '../theme/app_theme.dart';
import 'accent_card.dart';

/// Open Gateway Demo UX Kılavuzu → "04 Videoyu başlat", "05 Videoyu backend'e
/// yükle" adımları + Lifebox paylaşımı. Oynatma (ekranda gösterim, adaptif
/// ABR) ile kayıt (arkaplanda ffmpeg ile MP4'e remux) birbirinden bağımsız
/// çalışıyor — biri diğerini bloklamaz.
class VideoCard extends StatefulWidget {
  final SessionController controller;

  const VideoCard({super.key, required this.controller});

  @override
  State<VideoCard> createState() => _VideoCardState();
}

class _VideoCardState extends State<VideoCard> with AutomaticKeepAliveClientMixin {
  VideoPlayerController? _playerController;
  bool _playerReady = false;
  String? _playerError;

  // Home <-> AI Result sekmeleri arasında geçişte oynatıcının (ve kayıt
  // durumunun görsel önizlemesinin) sıfırlanmaması için — TabBarView
  // varsayılan olarak görünmeyen sekmenin State'ini korumaz.
  @override
  bool get wantKeepAlive => true;

  // Controller'a ayrıca abone OLMUYORUZ: HomeScreen zaten context.watch ile
  // dinliyor ve her notifyListeners'ta bu widget'ı yeniden kuruyor. İkinci bir
  // dinleyici aynı olaylarda ikinci bir rebuild yolu açardı.

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
    _playerController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final stage = widget.controller.videoStage;
    return AccentCard(
      accentColor: _accentColorFor(stage),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              StepBadge('04'),
              SizedBox(width: 8),
              Text('TEKNOFEST — Stream', style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Stack(
              children: [
                _buildPreview(),
                if (_playerReady) const Positioned(top: 8, left: 8, child: _LiveBadge()),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _buildRecordingControls(stage),
          if (stage == VideoStage.failed && widget.controller.videoErrorMessage != null) ...[
            const SizedBox(height: 8),
            Text(
              widget.controller.videoErrorMessage!,
              style: const TextStyle(color: Colors.red, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  Color _accentColorFor(VideoStage stage) => switch (stage) {
        VideoStage.idle => Colors.grey.shade300,
        VideoStage.recording => Colors.red,
        VideoStage.recorded => AppTheme.turkcellYellow,
        VideoStage.uploading => Colors.orange,
        VideoStage.uploaded => Colors.green,
        VideoStage.failed => Colors.red,
      };

  Widget _buildPreview() {
    if (_playerError != null) {
      return Container(
        height: 160,
        width: double.infinity,
        color: Colors.red.shade50,
        padding: const EdgeInsets.all(16),
        child: Center(
          child: Text(
            'Oynatma hatası: $_playerError',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.red, fontSize: 12),
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
      color: AppTheme.navy,
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
              ),
              child: const Icon(Icons.live_tv, color: AppTheme.turkcellYellow, size: 28),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.turkcellYellow,
                foregroundColor: AppTheme.navy,
              ),
              onPressed: _initPlayer,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Teknofest Start (HLS)'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecordingControls(VideoStage stage) {
    switch (stage) {
      case VideoStage.idle:
        return SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            onPressed: () => widget.controller.startRecording(widget.controller.streamUrl),
            icon: const Icon(Icons.fiber_manual_record),
            label: const Text(
              'Kaydı Başlat (maks. 5 dk)',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        );
      case VideoStage.recording:
        final elapsed = widget.controller.recordingElapsed;
        final remaining = AppConfig.maxRecordingDuration - elapsed;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
                Text(
                  'Kaydediliyor  ${_fmt(elapsed)}  ·  ~${_fmtBytes(widget.controller.recordingBytes)}',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
                const Spacer(),
                Text('kalan ${_fmt(remaining)}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
              ],
            ),
            const SizedBox(height: 6),
            LinearProgressIndicator(
              value: elapsed.inMilliseconds /
                  AppConfig.maxRecordingDuration.inMilliseconds,
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: widget.controller.stopRecordingEarly,
                icon: const Icon(Icons.stop),
                label: const Text('Kaydı Bitir'),
              ),
            ),
          ],
        );
      case VideoStage.recorded:
        return Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: widget.controller.uploadAndTriggerAi,
                icon: const Icon(Icons.cloud_upload),
                label: const Text('Backend\'e Yükle'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: widget.controller.shareToLifebox,
                icon: const Icon(Icons.share),
                label: const Text('Lifebox'),
              ),
            ),
          ],
        );
      case VideoStage.uploading:
        return const Row(
          children: [
            SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 8),
            Text('Backend\'e yükleniyor…'),
          ],
        );
      case VideoStage.uploaded:
        return Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 18),
            const SizedBox(width: 6),
            const Expanded(child: Text('Yüklendi — AI Result sekmesine geçin')),
            OutlinedButton.icon(
              onPressed: widget.controller.shareToLifebox,
              icon: const Icon(Icons.share),
              label: const Text('Lifebox'),
            ),
          ],
        );
      case VideoStage.failed:
        return FilledButton.icon(
          onPressed: () => widget.controller.startRecording(widget.controller.streamUrl),
          icon: const Icon(Icons.refresh),
          label: const Text('Tekrar Dene'),
        );
    }
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String _fmtBytes(int bytes) {
    if (bytes <= 0) return '0MB';
    final mb = bytes / (1024 * 1024);
    return '${mb.toStringAsFixed(1)}MB';
  }
}

class _LiveBadge extends StatelessWidget {
  const _LiveBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.red.shade600,
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, color: Colors.white, size: 8),
          SizedBox(width: 4),
          Text(
            'LIVE',
            style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
