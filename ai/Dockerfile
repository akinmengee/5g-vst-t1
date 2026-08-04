# FTR Bölüm 5/6: CUDA tabanlı imaj, GPU'da (Tesla T4) çalışacak.
FROM nvidia/cuda:12.1.0-base-ubuntu22.04

RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 \
    python3-pip \
    ffmpeg \
    libsm6 \
    libxext6 \
    libgl1 \
    libgles2 \
    libegl1 \
    libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Bağımlılıklar önce: kaynak kod değişince bu katman cache'ten gelir.
#
# Temizlik AYNI katmanda yapılmalı — sonraki bir RUN'da silmek imajı
# küçültmez (katmanlar toplanır, silinen dosya alttaki katmanda kalır).
# 8 GB imaj limiti (FTR Bölüm 5) bu yüzden burada kazanılıyor.
COPY requirements.txt .
RUN pip3 install --no-cache-dir -r requirements.txt \
    # ultralytics opencv-python, mediapipe opencv-contrib-python çeker; ikisi de
    # headless sürümle aynı `cv2` modülünü sağlar. Üç kopya taşımanın anlamı yok
    # (imajda GUI yok — headless zaten doğru olan).
    && pip3 uninstall -y opencv-python opencv-contrib-python \
    # triton yalnızca torch.compile/inductor içindir; YOLO çıkarımı kullanmıyor.
    && pip3 uninstall -y triton \
    # C++ eklentisi derlemiyoruz: başlıklar ve test yardımcıları gereksiz.
    && rm -rf /usr/local/lib/python3.10/dist-packages/torch/include \
              /usr/local/lib/python3.10/dist-packages/torch/test \
              /usr/local/lib/python3.10/dist-packages/torch/testing \
    && find /usr/local/lib/python3.10/dist-packages -name "__pycache__" -type d -prune -exec rm -rf {} + \
    && find /usr/local/lib/python3.10/dist-packages -name "*.pyc" -delete

# Model ağırlıkları /app/models altında olmalı (FTR spesifikasyonu).
# predict.py bu yolu kendisi bekliyor (WEIGHTS_DIR).
#
# YALNIZCA predict.py'nin gerçekten yüklediği 16 dosya kopyalanır. weights/
# klasöründeki yolov8m.pt (50MB), yolov8n.pt, yolov8s-cls.pt hiçbir yerde
# kullanılmıyor — imaj limiti varken ölü ağırlık taşınmaz.
COPY weights/esneme.pt weights/face_landmarker.task weights/karakter_modeli.pt \
     weights/kasa_modeli.pt weights/kemer.pt weights/plaka_modeli.pt \
     weights/renk_modeli.pt weights/sigara.pt weights/slalom_lstm.pt \
     weights/su.pt weights/teknocan.pt weights/telefon.pt weights/yolcu.pt \
     weights/yolov8n-pose.pt weights/yolov8s-pose.pt weights/yolov8s.pt \
     /app/models/

COPY src/ /app/src/
COPY main.py .

# Hakem bu klasörleri dışarıdan mount eder; imajda hazır bulunmaları gerekir.
RUN mkdir -p /app/data/input /app/data/output

# Ultralytics, yazılabilir bir config dizini arar; HOME yoksa uyarı üretip
# beklenmedik yollara yazmaya çalışır.
ENV YOLO_CONFIG_DIR=/tmp/Ultralytics
ENV PYTHONUNBUFFERED=1

# Servis değil, tek seferlik iş: işini bitirir ve çıkar.
CMD ["python3", "main.py"]
