"""
schema.py - FTR cikti semasi. PDF bolum 4.3 'Konsolide Cikti' ile birebir.
Hem sofor_eylemi (B-grubu) hem arac_bilgisi (A-grubu) tek JSON'da birlesir.
TUM etiketler ASCII + kucuk harf. Anahtarlar birebir: zaman_saniye, kategori, etiket, confidence_score.
"""

def tespit_olustur(zaman_saniye, kategori, etiket, confidence_score):
    """Tek bir tespit kaydi (sofor_eylemi / nesneler / yolcular)."""
    return {
        "zaman_saniye": round(float(zaman_saniye), 1),
        "kategori": kategori,                       # "sofor_eylemi" | "nesneler" | "yolcular"
        "etiket": etiket,                           # ASCII kucuk harf (orn: telefonla_konusma)
        "confidence_score": round(float(confidence_score), 2),
    }

def arac_bilgisi_olustur(tip, plaka, renk, confidence_score):
    """Arac bilgisi nesnesi (A-grubu doldurur)."""
    return {
        "tip": tip,                                 # sedan/suv/hatchback/pickup/minibus/panelvan/kamyon
        "plaka": plaka,                             # 34ABC123 (regex'e uygun, bosluksuz)
        "renk": renk,                               # beyaz/siyah/gri/kirmizi/mavi/sari/yesil/turuncu/kahverengi
        "confidence_score": round(float(confidence_score), 2),
    }

def sonuc_birlestir(video_id, arac_bilgisi, tespitler):
    """Final results.json govdesi. main.py bunu cagirir."""
    return {
        "video_id": video_id,
        "arac_bilgisi": arac_bilgisi,
        "tespitler": tespitler,
    }

# Gecerli etiketler (dogrulama icin - yanlis etiket = puan kaybi)
GECERLI_SOFOR_EYLEMI = {
    "arkaya_bakma", "esneme", "sigara_icme", "su_icme",
    "telefonla_konusma", "slalom", "etrafa_bakinma", "emniyet_kemeri_ihlali",
}
GECERLI_NESNELER = {"teknocan", "bilgisayar"}
GECERLI_YOLCULAR = {"arka_koltuk_1", "arka_koltuk_2", "on_koltuk"}
