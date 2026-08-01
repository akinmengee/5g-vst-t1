"""Tespit eşikleri — plan Mimari Kararlar madde 8.

FTR'deki `predict.py`'de sabit kodlanmış olan tüm eşikler burada toplandı.
Amaç: yeni modeller geldiğinde veya saha koşulları değiştiğinde "sweet spot"
aramasının koda dokunmadan yapılabilmesi.

Değerler FTR'de fiilen kullanılan ve doğrulanan başlangıç değerleridir; test
sırasında ayarlanacaktır.
"""

from pydantic import BaseModel, Field


class DetectionThresholds(BaseModel):
    # --- YOLO güven eşikleri (predict.py: ESIK) ---
    sigara_conf: float = 0.45
    telefon_conf: float = 0.45
    su_conf: float = 0.45
    kemer_conf: float = 0.50
    kisi_conf: float = 0.20
    arac_conf: float = 0.45

    # --- Zamansal ardışıklık (predict.py: ARDISIK_GEREK, KEMER_GEREK) ---
    ardisik_gerek: int = Field(
        default=2, description="Bir eylemin kabulü için gereken ardışık örnek sayısı"
    )
    kemer_gerek: int = Field(
        default=10, description="Emniyet kemeri ihlali için gereken ardışık örnek sayısı"
    )
    kemer_fail_safe_gorulme: int = Field(
        default=3,
        description=(
            "Kemer bu sayıda net görülmüşse, ihlal hiç bildirilmez (global affetme). "
            "predict.py'deki `len(kemer_var) < 3` kontrolünün karşılığı."
        ),
    )

    # --- Esneme / MAR (predict.py: ORAN_ESIK, PLATO_GEREK, HAREKET_ESIK) ---
    mar_oran_esik: float = 2.0
    mar_plato_gerek: int = 8
    mar_hareket_esik: float = 1.5
    mar_baseline_min_ornek: int = Field(
        default=12,
        description=(
            "Kişisel MAR taban değeri (medyan) hesaplanmadan önce toplanacak asgari örnek. "
            "Batch versiyonda tüm videonun medyanı alınıyordu; streaming'de bu warm-up gerekli."
        ),
    )

    # --- Kafa dönüşü (predict.py: DONUK_OFFSET, T_ARKAYA, T_ETRAFA_MIN) ---
    donuk_offset: float = 0.30
    t_arkaya: float = 4.0
    t_etrafa_min: float = 1.2

    # --- Olay kapısı (predict.py: 3sn cooldown, ±1.5sn çakışma marjı) ---
    cooldown_saniye: float = 3.0
    cakisma_marji_saniye: float = 1.5

    # --- Araç özniteliği oylaması (predict.py: kasa/renk/plaka oylama kuralları) ---
    kasa_min_conf: float = 0.40
    kasa_oy_sayisi: int = 5
    kasa_analiz_frekansi: int = Field(
        default=15, description="Kaç ROI'de bir kasa tipi modeli çalıştırılsın"
    )
    kasa_min_genislik: int = Field(
        default=150, description="Bu genişlikten dar araçlarda kasa tahmini yapılmaz"
    )
    renk_min_conf: float = 0.50
    renk_oy_sayisi: int = 5
    renk_analiz_frekansi: int = 3
    plaka_analiz_frekansi: int = 2
    plaka_dedektor_conf: float = 0.30
    plaka_karakter_conf: float = 0.10
    plaka_min_skor: float = Field(
        default=2.0, description="Plaka kesinleşmesi için gereken kümülatif oy skoru"
    )
    plaka_min_genislik: int = 50

    # --- Nesne tespiti (teknocan / bilgisayar) ---
    teknocan_conf: float = 0.60
    teknocan_gerek: int = 10
    bilgisayar_gerek: int = 5

    # --- Slalom ---
    slalom_min_ornek: int = 45
    slalom_prob_esik: float = 0.40
    slalom_gerek: int = 3
    slalom_min_hareket: float = Field(
        default=10.0,
        description="Fiziksel ön kontrol: normalize edilmiş toplam sağa/sola kayma alt sınırı",
    )

    # --- Oturum hafızası ---
    oturum_ttl_saniye: float = Field(
        default=120.0,
        description=(
            "Bu süre boyunca yeni ROI gelmeyen oturumlar hafızadan düşürülür. "
            "Canlı serviste bellek sızıntısını önler (Kod İncelemesi madde 5)."
        ),
    )


thresholds = DetectionThresholds()
