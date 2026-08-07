import 'dart:async';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';

import '../config/app_config.dart';

/// [incomplete]: ffmpeg SUCCESS döndü (dosya var, bozuk değil) ama gerçek
/// süresi beklenenden belirgin şekilde kısa — muhtemelen ağ/QoD kesintisiyle
/// akış erken bitti. Bkz. `VideoRecordingService._dogrulaSure`.
enum RecordingStatus { idle, recording, completed, incomplete, failed, cancelled }

class RecordingResult {
  final RecordingStatus status;
  final String? filePath;
  final String? errorMessage;

  /// Yalnızca [RecordingStatus.incomplete]'de dolu — playlist toplamından
  /// hesaplanan beklenen süre ile ffprobe'un ölçtüğü gerçek süre (saniye).
  final double? expectedSeconds;
  final double? actualSeconds;

  const RecordingResult({
    required this.status,
    this.filePath,
    this.errorMessage,
    this.expectedSeconds,
    this.actualSeconds,
  });
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

  /// Cihazdaki TÜM yerel kayıtları siler (dosya + varsa .txt yan dosyaları
  /// değil, yalnızca .mp4). Her başarılı NV sonrası çağrılır: aynı numarayla
  /// tekrar tekrar test edilse bile Home hep temiz bir listeyle açılsın,
  /// önceki oturumdan kalan dosyalar demo sırasında karışıklık yaratmasın.
  Future<void> deleteAllRecordings() async {
    if (kIsWeb) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final files = await dir
          .list()
          .where((e) => e is File && e.path.endsWith('.mp4'))
          .cast<File>()
          .toList();
      for (final f in files) {
        try {
          await f.delete();
        } catch (_) {
          // Tek dosya silinemezse (ör. hâlâ açık) diğerlerini engellemesin.
        }
      }
    } catch (_) {
      // Dizine erişilemiyorsa sessizce geç — kritik bir akış değil.
    }
  }

  Future<RecordingResult> startRecording({
    required String hlsUrl,
    void Function(Duration elapsed)? onProgress,
    /// HLS medya playlist'inin `#EXTINF` toplamından hesaplanan, akışın
    /// GERÇEKTE ne kadar sürmesi gerektiği (saniye) — bkz.
    /// `HlsVariantService.fetchExpectedDuration`. Verilmezse (null) süre
    /// doğrulaması ATLANIR, sonuç her zaman `completed` sayılır (eski
    /// davranış) — referans yoksa "eksik" demek yanlış tarafta hataya
    /// düşmek olur.
    double? expectedDurationSeconds,
  }) async {
    // ffmpeg_kit yalnızca mobil platformlarda var — web'de (tarayıcı
    // önizlemesi) kayıt açıkça hata verir, sessizce takılı kalmaz.
    if (kIsWeb) {
      return const RecordingResult(
        status: RecordingStatus.failed,
        errorMessage: 'HLS kaydı yalnızca Android cihazda çalışır (ffmpeg).',
      );
    }

    final outputPath = await _outputPath();

    final maxSeconds = AppConfig.maxRecordingDuration.inSeconds;
    // -t ile sunucu tarafında da sert bir üst sınır var; buton ile manuel
    // durdurma da destekleniyor (cancelRecording).
    //
    // SADECE TEST İÇİN: AppConfig.testRealtimePace true ise -re eklenir —
    // ffmpeg VOD'u max hızda değil, stream'in KENDİ bit hızında okur. Bu,
    // yarışma SIM'inin QoD'siz (256 kbit) durumunu gerçekçi test etmeyi
    // sağlar (test SIM'imiz çok hızlı olduğu için bu fark normalde hiç
    // görünmüyor). -re bir GİRDİ seçeneği olduğu için -i'DEN ÖNCE durmalı.
    // Yarışma build'inde bu bayrak hiç verilmez, komut eskisiyle birebir aynı.
    final gercekZamanli = AppConfig.testRealtimePace ? '-re ' : '';
    final command = '-y $gercekZamanli-i "$hlsUrl" -t $maxSeconds -c copy "$outputPath"';

    final completer = Completer<RecordingResult>();

    final session = await FFmpegKit.executeAsync(
      command,
      (session) async {
        final returnCode = await session.getReturnCode();
        if (completer.isCompleted) return;
        if (ReturnCode.isSuccess(returnCode)) {
          final eksikSonuc =
              await _dogrulaSure(outputPath, expectedDurationSeconds);
          completer.complete(
            eksikSonuc ??
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

  /// ffmpeg SUCCESS döndüğünde bile dosya EKSİK olabilir: VOD kaynağı gerçek
  /// zamanlı okunmuyor (`-re` yok) — QoD ile bant genişliği arttıkça indirme
  /// videonun kendi süresinden çok daha KISA sürede bitebiliyor (bu normal,
  /// bilinçli tasarım). Ama HLS demuxer'ı bir ağ kesintisini (ör. QoD
  /// oturumu bitip veri bağlantısı resetlenmesi) "akış bitti" sanıp ERKEN
  /// sonlanırsa da SUCCESS döner — tek ayırt edici, dosyanın GERÇEK süresini
  /// ffprobe ile ölçüp playlist'in TOPLAM süresiyle karşılaştırmak.
  ///
  /// null döner (doğrulama geçti/atlandı) ya da [RecordingStatus.incomplete]
  /// taşıyan bir sonuç döner. ffprobe'un kendisi başarısız olursa da null
  /// döner — doğrulayamamak "eksik" demek değildir, akışı engellemeyelim.
  Future<RecordingResult?> _dogrulaSure(
    String outputPath,
    double? expectedDurationSeconds,
  ) async {
    if (expectedDurationSeconds == null) return null;
    try {
      final session = await FFprobeKit.getMediaInformation(outputPath);
      final actual =
          double.tryParse(session.getMediaInformation()?.getDuration() ?? '');
      if (actual == null) return null;
      // %90 tolerans: HLS segment yuvarlamaları / son segment kırpılması
      // normal bir birkaç saniyelik fark yaratabilir, bu bir "eksik dosya"
      // değildir.
      if (actual < expectedDurationSeconds * 0.9) {
        return RecordingResult(
          status: RecordingStatus.incomplete,
          filePath: outputPath,
          expectedSeconds: expectedDurationSeconds,
          actualSeconds: actual,
        );
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Kullanıcı 5 dk dolmadan manuel "kaydı bitir" derse.
  Future<void> stopRecording() async {
    if (_activeSessionId != null) {
      await FFmpegKit.cancel(_activeSessionId);
      _activeSessionId = null;
    }
  }
}
