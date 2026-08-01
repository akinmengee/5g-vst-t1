"""Ultralytics / MediaPipe modellerinin test amaçlı sahte (stub) karşılıkları.

Amaç: `CurrentModelService`'in ROI akışı mantığını, gerçek modellerin ne bulduğuna
bağlı olmadan test edebilmek. Gerçek modellerle çalışan bir testte "tespit yok"
sonucu, mantığın bozuk olduğu anlamına mı yoksa görüntüde gerçekten bir şey
olmadığı anlamına mı gelir ayırt edilemez — stub'lar bu belirsizliği kaldırır.
"""

import numpy as np


class ConfValue(float):
    """Ultralytics'te `box.conf` bir tensor'dür: hem `float(conf)` hem `conf[0]` çalışır."""

    def __getitem__(self, index):
        return float(self)


class XyxyRow(list):
    """`box.xyxy[0]` bir tensor'dür: hem iterable hem `.tolist()` destekler."""

    def tolist(self):
        return list(self)


class StubBox:
    def __init__(self, conf: float, cls: int = 0, xyxy=(0, 0, 10, 10)) -> None:
        self.conf = ConfValue(conf)
        self.cls = cls
        self.xyxy = [XyxyRow(xyxy)]


class StubProbs:
    def __init__(self, top1: int, top1conf: float) -> None:
        self.top1 = top1

        class _Conf:
            def item(self_inner):
                return top1conf

        self.top1conf = _Conf()


class StubResult:
    def __init__(self, boxes=None, names=None, probs=None, keypoints=None) -> None:
        self.boxes = boxes if boxes is not None else []
        self.names = names or {}
        self.probs = probs
        self.keypoints = keypoints


class StubDetectionModel:
    """Her çağrıda sabit bir sonuç döndüren nesne tespit modeli."""

    def __init__(self, result: StubResult) -> None:
        self._result = result
        self.cagri_sayisi = 0

    def __call__(self, frame, **kwargs):
        self.cagri_sayisi += 1
        return [self._result]


class StubClassifierModel:
    def __init__(self, etiket: str, confidence: float) -> None:
        self._result = StubResult(names={0: etiket}, probs=StubProbs(0, confidence))
        self.cagri_sayisi = 0

    def __call__(self, frame, **kwargs):
        self.cagri_sayisi += 1
        return [self._result]


class StubKeypoints:
    def __init__(self, data) -> None:
        self.data = data


class StubBoxesWithXyxy:
    """`bakinma_olc` hem `r.boxes.xyxy.tolist()` hem `len(r.boxes)` kullanır."""

    def __init__(self, kutular) -> None:
        self._kutular = kutular
        self.xyxy = self

    def tolist(self):
        return self._kutular

    def __len__(self):
        return len(self._kutular)


class StubRegistry:
    """`ModelRegistry` yerine geçen, testte istenen modelleri döndüren kayıt defteri."""

    def __init__(self, models: dict | None = None, face_landmarker=None, slalom=None) -> None:
        self._models = models or {}
        self.face_landmarker = face_landmarker
        self.slalom = slalom
        self.device = "cpu"
        self.eksikler: list[str] = []

    def yolo(self, ad: str):
        return self._models.get(ad)


def kisi_iceren_detector(conf: float = 0.9, roi_boyut=(200, 300)) -> StubDetectionModel:
    """Kabin kırpmanın çalışması için ROI ortasında bir kişi kutusu döndürür."""
    h, w = roi_boyut
    kutu = (w * 0.3, h * 0.2, w * 0.7, h * 0.9)
    return StubDetectionModel(StubResult(boxes=[StubBox(conf, cls=0, xyxy=kutu)]))


def bos_detector() -> StubDetectionModel:
    return StubDetectionModel(StubResult(boxes=[]))


def sahte_roi(w: int = 300, h: int = 200) -> np.ndarray:
    return np.full((h, w, 3), 128, dtype=np.uint8)
