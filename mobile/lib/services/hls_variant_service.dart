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

/// Kaydedilecek HLS varyantını ölçülen bant genişliğine göre seçer.
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
class HlsVariantService {
  HlsVariantService({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 5),
              receiveTimeout: const Duration(seconds: 8),
            ));

  final Dio _dio;

  /// Ölçüm ile varyant arasında bırakılan pay.
  ///
  /// Neden gerçek-zaman kapasitesi arıyoruz: kayıt penceresi 5 dakika ve
  /// videonun uzunluğu önceden bilinmiyor — en kötü durumda videonun da ~5
  /// dakika olduğunu varsaymalıyız, yani pencerede hiç bolluk yok. O yüzden
  /// varyantın en az gerçek zamanlı indirilebilir olmasını şart koşuyoruz.
  ///
  /// Üstüne bu pay: bant genişliği örneği tek bir segment indirmesinden
  /// geliyor (TCP yavaş başlangıcı + anlık dalgalanma), tam güvenilmez.
  ///
  /// Takas bilinçli: düşük varyanta gereksiz düşmek AI doğruluğunu düşürür
  /// (240p'de sigara/telefon/kemer tespiti çok zor), ama kaydı hiç
  /// tamamlayamamak canlı demonun AI puanının tamamını kaybettirir.
  static const double guvenlikPayi = 0.85;

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

  /// Ölçülen bant genişliğine sığan **en yüksek** varyantı seçer (standart ABR
  /// başlangıç-varyant kuralı). Hiçbiri sığmıyorsa en düşüğünü döner: kayıt
  /// hiç alınamamaktansa düşük çözünürlükle alınsın.
  ///
  /// [measuredMbps] null ise ölçüm yok demektir; bu durumda kalite kaybetmemek
  /// için en yükseği seçeriz (ffmpeg'in zaten yapacağı şey).
  static HlsVariant? selectForBandwidth(
    List<HlsVariant> variants,
    double? measuredMbps,
  ) {
    if (variants.isEmpty) return null;
    if (measuredMbps == null || measuredMbps <= 0) return variants.first;

    final butce = measuredMbps * guvenlikPayi;
    for (final v in variants) {
      // Liste yüksekten düşüğe sıralı — sığan ilk varyant en iyisidir.
      if (v.mbps <= butce) return v;
    }
    return variants.last;
  }

  /// Kaydın hangi adresten alınacağını çözer.
  ///
  /// Ağ/parse hatasında sessizce master URL'e düşer — kayıt hiç başlamamaktansa
  /// ffmpeg'in kendi seçimiyle devam etmesi yeğdir.
  Future<HlsVariant?> resolveVariant(
    String masterUrl,
    double? measuredMbps,
  ) async {
    try {
      final response = await _dio.get<String>(masterUrl);
      final variants = parseMaster(response.data ?? '', Uri.parse(masterUrl));
      return selectForBandwidth(variants, measuredMbps);
    } catch (_) {
      return null;
    }
  }
}
