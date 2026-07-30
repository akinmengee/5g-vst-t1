# FTR teslimindeki Dockerfile deseni referans alındı (nvidia/cuda temel imaj,
# aynı GPU'lu model ağırlıkları burada da çalışacak).
FROM nvidia/cuda:12.1.0-base-ubuntu22.04

RUN apt-get update && apt-get install -y \
    python3 \
    python3-pip \
    ffmpeg \
    libsm6 \
    libxext6 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY requirements.txt .
RUN pip3 install --no-cache-dir -r requirements.txt

COPY app/ /app/app/
COPY weights/ /app/weights/

ENV MODEL_DIR=/app/weights
ENV PYTHONPATH=/app

EXPOSE 8000

CMD ["python3", "-m", "uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
