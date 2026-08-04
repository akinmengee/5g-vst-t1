import 'dart:async';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
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
///
/// Her kayıt BENZERSİZ bir dosyaya yazılır (`kayit_YYYYAAGG_SSDDSS.mp4`) —
/// kullanıcı istediği kadar kayıt alıp listeden yönetebilir.
class VideoRecordingService {
  int? _activeSessionId;
  int _webMockSayac = 0;

  static String _damga(DateTime t) {
    String iki(int v) => v.toString().padLeft(2, '0');
    return '${t.year}${iki(t.month)}${iki(t.day)}_${iki(t.hour)}${iki(t.minute)}${iki(t.second)}';
  }

  Future<String> _outputPath() async {
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/kayit_${_damga(DateTime.now())}.mp4';
  }

  /// Cihazda daha önce alınmış kayıtları bulur (uygulama yeniden açıldığında
  /// liste kaybolmasın). Web'de dosya sistemi yok — boş döner.
  Future<List<File>> listExistingRecordings() async {
    if (kIsWeb) return const [];
    try {
      final dir = await getApplicationDocumentsDirectory();
      final files = await dir
          .list()
          .where((e) => e is File && e.path.endsWith('.mp4'))
          .cast<File>()
          .toList();
      files.sort((a, b) => b.path.compareTo(a.path)); // damgalı ad = yeni üstte
      return files;
    } catch (_) {
      return const [];
    }
  }

  Future<RecordingResult> startRecording({
    required String hlsUrl,
    void Function(Duration elapsed)? onProgress,
  }) async {
    // Web önizlemede (Chrome/web-server) ffmpeg_kit yok — mock moddayken
    // kayıt 3 sn'lik simülasyonla tamamlanır ki NV→QoD→kayıt→upload→AI akışı
    // tarayıcıda uçtan uca gezilebilsin. Gerçek cihazda (Android) bu blok
    // hiç çalışmaz; mock kapalıyken de web'de gerçekçi bir hata verilir.
    if (kIsWeb) {
      if (!AppConfig.useMock) {
        return const RecordingResult(
          status: RecordingStatus.failed,
          errorMessage: 'HLS kaydı yalnızca Android cihazda çalışır (ffmpeg).',
        );
      }
      _webMockSayac++;
      for (var i = 1; i <= 3; i++) {
        await Future.delayed(const Duration(seconds: 1));
        onProgress?.call(Duration(seconds: i));
      }
      return RecordingResult(
        status: RecordingStatus.completed,
        filePath: 'kayit_web_$_webMockSayac.mp4',
      );
    }

    final outputPath = await _outputPath();

    final maxSeconds = AppConfig.maxRecordingDuration.inSeconds;
    // -t ile sunucu tarafında da sert bir üst sınır var; buton ile manuel
    // durdurma da destekleniyor (cancelRecording).
    final command = '-y -i "$hlsUrl" -t $maxSeconds -c copy "$outputPath"';

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
        onProgress?.call(Duration(milliseconds: statistics.getTime()));
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
