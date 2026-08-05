import os
import sys
import json

sys.path.append(os.path.abspath(os.path.dirname(__file__)))

from src.predict import run_inference


def main():
    input_path = "/app/data/input/video.mp4"
    output_path = "/app/data/output/results.json"

    if not os.path.exists(input_path):
        print(f"Hata: Girdi videosu bulunamadi -> {input_path}")
        sys.exit(1)

    print("Yol Guvenligi Yapay Zeka Cikarim Islemi Baslatildi...")

    try:
        output_data = run_inference(input_path)

        os.makedirs(os.path.dirname(output_path), exist_ok=True)
        with open(output_path, "w", encoding="utf-8") as f:
            json.dump(output_data, f, ensure_ascii=False, indent=2)

        print(f"Islem basariyla tamamlandi. Cikti kaydedildi: {output_path}")

    except Exception as e:
        print(f"Model calistirilirken bir hata ile karsilasildi: {str(e)}")
        sys.exit(1)


if __name__ == "__main__":
    main()
