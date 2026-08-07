import 'package:dio/dio.dart';

/// HLS master playlist'indeki tek bir kalite seçeneği.
class HlsVariant {
  /// `#EXT-X-STREAM-INF:BANDWIDTH=...` — bit/saniye.
  final int bandwidthBps;

  /// `NAME=1080p` (opsiyonel, sunucuya bağlı).
  final String? name;

  /// `RESOLUTION=1920x1080` (opsiyonel).
  final String? resolution;

  /// Alt playlist'in mutlak adresi.
  final String url;

  const HlsVariant({
    required this.bandwidthBps,
    required this.url,
    this.name,
    this.resolution,
  });

  double get mbps => bandwidthBps / 1e6;

  /// UI/log için kısa ad: "1080p" ya da "1920x1080", ikisi de yoksa hız.
  String get etiket =>
      name ?? resolution ?? '${mbps.toStringAsFixed(1)} Mbps';

  @override
  String toString() => '$etiket (${mbps.toStringAsFixed(2)} Mbps)';
}

/// Kaydedilecek HLS varyantını **QoD durumuna göre** seçer.
///
/// **Neden gerekli:** Şartname 4.2 — *"Mobil uygulamanın streaming sunucusuna
/// bağlanıp anlık bant genişliğine en uygun videoyu stream etmesi
/// gerekmektedir. QoD başarısız olur ve düşük bant genişliğinde kalınırken
/// yüksek çözünürlüklü videoyu indirmeye çalışılırsa streaming'e ayrılan süre
/// yetmeyeceği için canlı demo aşaması başarısız olacaktır."*
///
/// ffmpeg bunu KENDİLİĞİNDEN yapmaz. Master playlist verildiğinde varyantların
/// hepsini görür ama varsayılan akış seçimi her zaman **en yüksek** olanı alır
/// ve akış ortasında kalite değiştirmez. (Yarışma playlist'i ile ffmpeg 8.1.1
/// üzerinde doğrulandı: 1080p/240p listesinde ağ koşulundan bağımsız olarak
/// 1080p seçiliyor.) Bu yüzden varyantı burada seçip ffmpeg'e doğrudan alt
/// playlist URL'ini veriyoruz.
///
/// **Neden ölçüme değil QoD'ye bakıyoruz** (7 Ağustos kararı): Yarışma SIM'inin
/// hızları sabit ve önceden biliniyor — QoD'siz 256 kbit/s, QoD'li 8 Mbit/s.
/// Ölçüme dayalı seçim hem gereksiz hem tehlikeliydi: ölçüm QoD'siz durumda
/// zaten zaman aşımına düşüyor ve "ölçüm yok" hâli en yüksek varyanta
/// yönlendiriyordu (256 kbit'te 1080p = 68 dakika, ekran donmuş görünüyordu).
///
/// Kalite tercihi bilinçli olarak **agresif**: QoD varsa her zaman en yüksek.
/// Akış VOD (`#EXT-X-PLAYLIST-TYPE:VOD` + `#EXT-X-ENDLIST`) olduğu için gerçek
/// zamanlı yetişme zorunluluğu yok — 8 Mbit'lik hatta 9.16 Mbps'lik yayın
/// inebilir, sadece video süresinden biraz uzun sürer (114 sn video ≈ 130 sn).
/// Hakem, Lifebox'a yüklediğimiz kaydı da ayrı bir inference'a sokuyor (Final
/// Yarışma Senaryosu md. 5), yani kaydın çözünürlüğü doğrudan puanlanıyor:
/// 240p bir tercih değil, QoD hiç kurulamazsa devreye giren fallback'tir.
class HlsVariantService {
  HlsVariantService({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 5),
              receiveTimeout: const Duration(seconds: 8),
            ));

  final Dio _dio;

  /// Master playlist gövdesini varyantlara ayırır — **yüksekten düşüğe sıralı**.
  ///
  /// Gövde master değilse (varyant satırı yoksa, yani doğrudan medya
  /// playlist'iyse) boş liste döner.
  static List<HlsVariant> parseMaster(String body, Uri baseUrl) {
    const etiketOneki = '#EXT-X-STREAM-INF:';
    final satirlar = body.split('\n').map((l) => l.trim()).toList();
    final variants = <HlsVariant>[];

    for (var i = 0; i < satirlar.length; i++) {
      if (!satirlar[i].startsWith(etiketOneki)) continue;
      final attrs = _parseAttributes(satirlar[i].substring(etiketOneki.length));
      final bandwidth = int.tryParse(attrs['BANDWIDTH'] ?? '');
      if (bandwidth == null) continue;

      // Etiketten sonraki ilk yorum-olmayan satır varyantın adresidir.
      String? uri;
      for (var j = i + 1; j < satirlar.length; j++) {
        if (satirlar[j].isEmpty || satirlar[j].startsWith('#')) continue;
        uri = satirlar[j];
        break;
      }
      if (uri == null) continue;

      variants.add(HlsVariant(
        bandwidthBps: bandwidth,
        name: attrs['NAME'],
        resolution: attrs['RESOLUTION'],
        url: baseUrl.resolve(uri).toString(),
      ));
    }

    variants.sort((a, b) => b.bandwidthBps.compareTo(a.bandwidthBps));
    return variants;
  }

  /// `BANDWIDTH=9155202,NAME=1080p,CODECS="avc1.4d,mp4a.40"` → harita.
  ///
  /// Tırnak içindeki virgüller ayraç DEĞİLDİR (`CODECS` değeri virgül içerir),
  /// bu yüzden düz `split(',')` kullanılamaz.
  static Map<String, String> _parseAttributes(String satir) {
    final parcalar = <String>[];
    final tampon = StringBuffer();
    var tirnakta = false;

    for (var i = 0; i < satir.length; i++) {
      final ch = satir[i];
      if (ch == '"') {
        tirnakta = !tirnakta;
        continue;
      }
      if (ch == ',' && !tirnakta) {
        parcalar.add(tampon.toString());
        tampon.clear();
        continue;
      }
      tampon.write(ch);
    }
    if (tampon.isNotEmpty) parcalar.add(tampon.toString());

    final sonuc = <String, String>{};
    for (final p in parcalar) {
      final esittir = p.indexOf('=');
      if (esittir <= 0) continue;
      sonuc[p.substring(0, esittir).trim().toUpperCase()] =
          p.substring(esittir + 1).trim();
    }
    return sonuc;
  }

  /// QoD açıksa **en yüksek**, değilse **en düşük** varyantı seçer.
  ///
  /// Ara bir değer yok, çünkü yarışma SIM'inde ara bir hız yok: QoD ya var
  /// (8 Mbit → 1080p rahat iner) ya yok (256 kbit → 1080p 68 dakika sürer,
  /// tek gerçekçi seçenek 240p).
  static HlsVariant? selectForQod({
    required List<HlsVariant> varyantlar,
    required bool qodAktif,
  }) {
    if (varyantlar.isEmpty) return null;
    // parseMaster listeyi yüksekten düşüğe sıralı döndürür.
    return qodAktif ? varyantlar.first : varyantlar.last;
  }

  /// Kaydın hangi adresten alınacağını çözer.
  ///
  /// Ağ/parse hatasında sessizce master URL'e düşer — kayıt hiç başlamamaktansa
  /// ffmpeg'in kendi seçimiyle devam etmesi yeğdir.
  Future<HlsVariant?> resolveVariant(
    String masterUrl, {
    required bool qodAktif,
  }) async {
    try {
      final response = await _dio.get<String>(masterUrl);
      final variants = parseMaster(response.data ?? '', Uri.parse(masterUrl));
      return selectForQod(varyantlar: variants, qodAktif: qodAktif);
    } catch (_) {
      return null;
    }
  }

  /// Medya playlist gövdesindeki TÜM `#EXTINF:x.xx,` sürelerini toplar —
  /// VOD akışın gerçek TOPLAM süresi (saniye). Hiç `#EXTINF` yoksa null.
  ///
  /// **Neden gerekli:** ffmpeg, VOD kaynağını gerçek zamanlı okumadan
  /// (`-re` yok, bkz. `VideoRecordingService`) indirip remux ediyor — QoD ile
  /// bant genişliği arttıkça indirme, videonun kendi süresinden çok daha KISA
  /// sürede bitebiliyor (bu normal). Ama ffmpeg'in HLS demuxer'ı bir ağ
  /// kesintisini "akış bitti" sanıp ERKEN sonlanırsa da SUCCESS döner ve
  /// elimizde sessizce EKSİK bir dosya kalır — ikisini ayırt etmenin tek yolu,
  /// kayıttan SONRA gerçek dosya süresini playlist'in TOPLAM süresiyle
  /// karşılaştırmak (bkz. `VideoRecordingService._dogrulaSure`).
  static double? sumSegmentDurations(String mediaPlaylistBody) {
    final extinf = RegExp(r'#EXTINF:\s*([0-9]+(?:\.[0-9]+)?)');
    double toplam = 0;
    var bulundu = false;
    for (final eslesme in extinf.allMatches(mediaPlaylistBody)) {
      final deger = double.tryParse(eslesme.group(1)!);
      if (deger != null) {
        toplam += deger;
        bulundu = true;
      }
    }
    return bulundu ? toplam : null;
  }

  /// [variant]'ın medya playlist'ini indirip TOPLAM VOD süresini (saniye)
  /// döner — kayıt öncesi "beklenen süre" referansı. Ağ/parse hatasında null
  /// (doğrulama atlanır, kayıt yine de devam eder — referans yoksa
  /// engellemek yanlış tarafta hataya düşmek olur).
  Future<double?> fetchExpectedDuration(HlsVariant variant) async {
    try {
      final response = await _dio.get<String>(variant.url);
      return sumSegmentDurations(response.data ?? '');
    } catch (_) {
      return null;
    }
  }
}
