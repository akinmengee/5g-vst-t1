"""Route testleri için AI çalıştırıcı sahteleri.

Bunlar "mock veri" DEĞİLDİR: sabit bir örnek results.json döndürüp gerçek AI
çıktısını taklit etmezler. Testin kontrol ettiği bir DAVRANIŞ üretirler
(başarı / gecikme / hata) ki backend'in orkestrasyonu — PROCESSING→DONE→FAILED
geçişleri — gerçek imajı dakikalarca çalıştırmadan doğrulanabilsin.

results.json içeriği testin kendisi tarafından verilir; hangi tespitin
üretildiği backend'in değil AI imajının sorumluluğudur.
"""

import asyncio
import json
from pathlib import Path

from app.services.orchestration.ai_runner import AiRunnerError

# Şema-geçerli en küçük çıktı. Gerçek AI'ın ne bulacağını iddia etmez;
# yalnızca backend'in bir results.json'ı okuyup şemadan geçirebildiğini gösterir.
ORNEK_SONUC = {
    "video_id": "video.mp4",
    "arac_bilgisi": {
        "tip": "sedan",
        "plaka": "34ABC123",
        "renk": "beyaz",
        "confidence_score": 0.9,
    },
    "tespitler": [
        {
            "zaman_saniye": 1.5,
            "kategori": "sofor_eylemi",
            "etiket": "telefonla_konusma",
            "confidence_score": 0.8,
        }
    ],
}


class BasariliRunner:
    """results.json yazar. `gecikme` ile PROCESSING durumu test edilebilir."""

    def __init__(self, gecikme: float = 0.0, sonuc: dict | None = None) -> None:
        self._gecikme = gecikme
        self._sonuc = sonuc if sonuc is not None else ORNEK_SONUC

    async def run(self, job_id: str, input_video_path: Path, output_dir: Path) -> None:
        if self._gecikme:
            await asyncio.sleep(self._gecikme)
        output_dir.mkdir(parents=True, exist_ok=True)
        (output_dir / "results.json").write_text(
            json.dumps(self._sonuc, ensure_ascii=False), encoding="utf-8"
        )


class PatlayanRunner:
    """AI imajının başarısız olduğu durum (timeout, çökme, eksik çıktı)."""

    async def run(self, job_id: str, input_video_path: Path, output_dir: Path) -> None:
        raise AiRunnerError("kasıtlı test hatası")
