"""Yarışma imajının giriş noktası — FTR Bölüm 6.

Girdi/çıktı yolları SABİTTİR ve ortam tespiti yapılmaz: hangi makinede
çalıştığına bakıp davranış değiştirmek (hostname/IP/dosya varlığı kontrolü)
diskalifiye sebebidir. Program bir servis değildir; işini bitirip çıkar.

Hata durumunda bile geçerli bir results.json bırakılır — hakem tarafında
"dosya yok" ile "tespit yok" ayırt edilemez, boş ama şema-geçerli çıktı
kısmi puanı korur.
"""

import json
import os
import sys
import traceback

sys.path.append(os.path.abspath(os.path.dirname(__file__)))

from src.predict import run_inference
from src.utils import arac_bilgisi_olustur, sonuc_birlestir

INPUT_PATH = "/app/data/input/video.mp4"
OUTPUT_PATH = "/app/data/output/results.json"


def _bos_sonuc() -> dict:
    return sonuc_birlestir(
        os.path.basename(INPUT_PATH),
        arac_bilgisi_olustur("sedan", "", "beyaz", 0.0),
        [],
    )


def _yaz(sonuc: dict) -> None:
    os.makedirs(os.path.dirname(OUTPUT_PATH), exist_ok=True)
    with open(OUTPUT_PATH, "w", encoding="utf-8") as f:
        json.dump(sonuc, f, ensure_ascii=False, indent=2)


def main() -> int:
    print(f"Cikarim basliyor: {INPUT_PATH}", flush=True)
    try:
        if not os.path.exists(INPUT_PATH):
            print(f"UYARI: girdi videosu bulunamadi -> {INPUT_PATH}", flush=True)
            _yaz(_bos_sonuc())
            return 1

        sonuc = run_inference(INPUT_PATH)
        _yaz(sonuc)
        tespit_sayisi = len(sonuc.get("tespitler", []))
        print(f"Tamamlandi: {OUTPUT_PATH} ({tespit_sayisi} tespit)", flush=True)
        return 0

    except Exception:
        # Tam stack trace stderr'e; backend bunu job loguna alıyor.
        traceback.print_exc()
        _yaz(_bos_sonuc())
        print(f"Hata sonrasi bos cikti yazildi: {OUTPUT_PATH}", flush=True)
        return 1


if __name__ == "__main__":
    sys.exit(main())
