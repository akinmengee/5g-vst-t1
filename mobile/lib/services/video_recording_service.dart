import 'dart:async';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:path_provider/path_provider.dart';

import '../config/app_config.dart';

enum RecordingStatus { idle, recording, completed, failed, cancelled }

class RecordingResult {
  final RecordingStatus status;
  final String? filePath;
  final String? errorMessage;

  const RecordingResult({required this.status, this.filePath, this.errorMessage});
}

/// Şartname: "streaming sunucusuna bağlanıp maksimum 5 dakika içerisinde
/// videonun tamamını kaydetmesi ve MP4 olarak dışa aktarması". HLS akışını
/// ekranda göstermek [video_player] paketinin işi (adaptif bitrate'i
/// ExoPlayer otomatik yönetiyor); bu servis AYNI akışı paralel olarak MP4'e
/// remux ediyor (`-c copy`, transcode yok — hız ve pil için önemli).
class VideoRecordingService {
  int? _activeSessionId;

  Future<String> _outputPath() async {
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/video.mp4';
  }

  Future<RecordingResult> startRecording({
    required String hlsUrl,
    void Function(Duration elapsed, int bytesWritten)? onProgress,
  }) async {
    final outputPath = await _outputPath();
    final outFile = File(outputPath);
    if (await outFile.exists()) {
      await outFile.delete();
    }

    final maxSeconds = AppConfig.maxRecordingDuration.inSeconds;
    // -t ile sunucu tarafında da sert bir üst sınır var; buton ile manuel
    // durdurma da destekleniyor (cancelRecording).
    final command =
        '-y -i "$hlsUrl" -t $maxSeconds -c copy "$outputPath"';

    final completer = Completer<RecordingResult>();

    final session = await FFmpegKit.executeAsync(
      command,
      (session) async {
        final returnCode = await session.getReturnCode();
        if (completer.isCompleted) return;
        if (ReturnCode.isSuccess(returnCode)) {
          completer.complete(
            RecordingResult(status: RecordingStatus.completed, filePath: outputPath),
          );
        } else if (ReturnCode.isCancel(returnCode)) {
          completer.complete(
            RecordingResult(status: RecordingStatus.cancelled, filePath: outputPath),
          );
        } else {
          final logs = await session.getFailStackTrace();
          completer.complete(
            RecordingResult(
              status: RecordingStatus.failed,
              errorMessage: logs ?? 'ffmpeg kayıt başarısız (kod: $returnCode)',
            ),
          );
        }
      },
      null,
      (statistics) {
        // Diskteki gerçek dosya boyutu — uydurma bir sayı değil, ffmpeg'in
        // o an yazdığı video.mp4'ün gerçek boyutu.
        final bytes = outFile.existsSync() ? outFile.lengthSync() : 0;
        onProgress?.call(Duration(milliseconds: statistics.getTime()), bytes);
      },
    );

    _activeSessionId = session.getSessionId();
    return completer.future;
  }

  /// Kullanıcı 5 dk dolmadan manuel "kaydı bitir" derse.
  Future<void> stopRecording() async {
    if (_activeSessionId != null) {
      await FFmpegKit.cancel(_activeSessionId);
      _activeSessionId = null;
    }
  }
}
