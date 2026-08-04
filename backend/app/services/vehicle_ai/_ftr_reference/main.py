"""
main.py - 5G FTR Programin giris noktasi
FTR kurallarina uygun olarak sabit girdi ve cikti yollarini kullanir.
Hata durumlarinda cokmeyi engellemek icin try-except bloklari barindirir.
"""

import os
import sys
import json

# src klasorundeki modullere erisim icin yol ekle
sys.path.append(os.path.abspath(os.path.dirname(__file__)))

from src.predict import run_inference
from src.utils import arac_bilgisi_olustur, sonuc_birlestir

# FTR Dokumani Bolum 6 geregi sabit yollar kullanilmalidir.
# Ortam kontrolu yapmak diskalifiye sebebidir!
INPUT_PATH = "/app/data/input/video.mp4"
OUTPUT_PATH = "/app/data/output/results.json"

def main():
    print("Yol Guvenligi Yapay Zeka Cikarim Islemi Baslatildi...")
    print(f"Girdi videosu: {INPUT_PATH}")

    # Cikti klasorunu garanti altina al
    os.makedirs(os.path.dirname(OUTPUT_PATH), exist_ok=True)

    try:
        if not os.path.exists(INPUT_PATH):
            print(f"UYARI: Girdi videosu bulunamadi -> {INPUT_PATH}")
            # Video yoksa bos ama gecerli bir FTR JSON'i olustur
            bos_arac = arac_bilgisi_olustur("sedan", "", "beyaz", 0.0)
            sonuc = sonuc_birlestir(os.path.basename(INPUT_PATH), bos_arac, [])
        else:
            # Asil cikarim islemini tetikle
            sonuc = run_inference(INPUT_PATH)

        # Sonuclari standart JSON formatinda diske yaz
        with open(OUTPUT_PATH, "w", encoding="utf-8") as f:
            json.dump(sonuc, f, ensure_ascii=False, indent=2)

        print(f"Islem basariyla tamamlandi. Cikti kaydedildi: {OUTPUT_PATH}")

    except Exception as e:
        print(f"Model calistirilirken bir hata ile karsilasildi: {str(e)}")
        # Cokme durumunda gecerli bos cikti birak
        bos_arac = arac_bilgisi_olustur("sedan", "", "beyaz", 0.0)
        bos_sonuc = sonuc_birlestir(os.path.basename(INPUT_PATH), bos_arac, [])
        with open(OUTPUT_PATH, "w", encoding="utf-8") as f:
            json.dump(bos_sonuc, f, ensure_ascii=False, indent=2)
        print(f"Bos cikti yazildi: {OUTPUT_PATH}")

if __name__ == "__main__":
    main()
