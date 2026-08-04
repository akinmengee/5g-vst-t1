"""Model yükleme katmanı — Kod İncelemesi Bulguları madde 2 ve 4'ün çözümü.

FTR'deki `predict.py` tüm modelleri **modül import anında** yüklüyordu; bir dosya
eksik veya bozuksa import patlıyor ve `main.py`'deki try/except devreye giremiyordu.
Burada her model tek tek, hata yakalanarak yüklenir: eksik bir model diğerlerini
düşürmez, servis o yeteneği kapatıp çalışmaya devam eder.

Model klasörü de artık çalışma dizinine göre değil, `settings.model_dir`
(env: `MODEL_DIR`) üzerinden çözülür.
"""

import logging
from pathlib import Path
from typing import Any

import torch

from app.core.config import settings
from app.services.vehicle_ai.slalom_net import SlalomLSTM

logger = logging.getLogger(__name__)

YOLO_DOSYALARI = {
    "detector": "yolov8s.pt",
    "kasa": "kasa_modeli.pt",
    "renk": "renk_modeli.pt",
    "plaka": "plaka_modeli.pt",
    "karakter": "karakter_modeli.pt",
    "teknocan": "teknocan.pt",
    "poz": "yolov8n-pose.pt",
    "sigara": "sigara_v1.pt",
    "telefon": "telefon_temiz_v1.pt",
    "su": "su_v2.pt",
    "kemer": "kemer_v3.pt",
}
FACE_LANDMARKER_DOSYASI = "face_landmarker.task"
SLALOM_DOSYASI = "slalom_lstm.pt"


class ModelRegistry:
    """Tüm modelleri yükler ve erişim sağlar. Yüklenemeyenler `eksikler`de listelenir."""

    def __init__(self, model_dir: Path | None = None) -> None:
        self.model_dir = Path(model_dir) if model_dir else settings.model_dir
        self.device = "cuda" if torch.cuda.is_available() else "cpu"
        self.eksikler: list[str] = []

        self._yolo: dict[str, Any] = {}
        self.face_landmarker: Any | None = None
        self.slalom: SlalomLSTM | None = None

        self._load_yolo_models()
        self.face_landmarker = self._load_face_landmarker()
        self.slalom = self._load_slalom()

        if self.eksikler:
            logger.warning("Yüklenemeyen modeller: %s", ", ".join(self.eksikler))
        logger.info("Model yükleme tamamlandı (device=%s)", self.device)

    def yolo(self, ad: str) -> Any | None:
        return self._yolo.get(ad)

    def _load_yolo_models(self) -> None:
        from ultralytics import YOLO

        for ad, dosya in YOLO_DOSYALARI.items():
            yol = self.model_dir / dosya
            try:
                model = YOLO(str(yol))
                model.to(self.device)
                self._yolo[ad] = model
            except Exception:
                logger.exception("YOLO modeli yüklenemedi: %s", yol)
                self.eksikler.append(dosya)

    def _load_face_landmarker(self) -> Any | None:
        yol = self.model_dir / FACE_LANDMARKER_DOSYASI
        try:
            from mediapipe.tasks import python as mp_python
            from mediapipe.tasks.python import vision as mp_vision

            options = mp_vision.FaceLandmarkerOptions(
                base_options=mp_python.BaseOptions(model_asset_path=str(yol)),
                running_mode=mp_vision.RunningMode.IMAGE,
                num_faces=1,
            )
            return mp_vision.FaceLandmarker.create_from_options(options)
        except Exception:
            logger.exception("MediaPipe face landmarker yüklenemedi: %s", yol)
            self.eksikler.append(FACE_LANDMARKER_DOSYASI)
            return None

    def _load_slalom(self) -> SlalomLSTM | None:
        yol = self.model_dir / SLALOM_DOSYASI
        try:
            model = SlalomLSTM()
            state = torch.load(str(yol), map_location=self.device, weights_only=True)
            model.load_state_dict(state)
            model.to(self.device)
            model.eval()
            return model
        except Exception:
            logger.exception("Slalom LSTM yüklenemedi: %s", yol)
            self.eksikler.append(SLALOM_DOSYASI)
            return None
