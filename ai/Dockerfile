# ============================================================
# 1. AŞAMA: DERLEME (build) -- pip/apt kalıntıları son imaja hiç taşınmaz
# ============================================================
FROM nvidia/cuda:12.1.0-base-ubuntu22.04 AS builder

RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 \
    python3-pip \
    python3-venv \
    && rm -rf /var/lib/apt/lists/*

# Bagimliliklari izole bir venv'e kuruyoruz -- sadece bu klasor son imaja kopyalanacak
RUN python3 -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

COPY requirements.txt .
RUN pip3 install --no-cache-dir -r requirements.txt \
    # NCCL sadece coklu-GPU (kartlar arasi) haberlesme icin -- bu pipeline tek GPU'da
    # calisiyor, hic kullanilmiyor. Cikarim performansini (cuDNN/cuBLAS'a dokunmuyoruz)
    # etkilemeden ~200-300MB dusuruyor. Paket adi CUDA surumune gore degisebildigi icin
    # (nvidia-nccl-cu12/cu13) ikisini de dener, hangisi kuruluysa onu kaldirir, hata
    # verirse build'i kesmez.
    && (pip3 uninstall -y nvidia-nccl-cu12 nvidia-nccl-cu13 || true) \
    && find /opt/venv -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true \
    && find /opt/venv -name "*.pyc" -delete

# ============================================================
# 2. AŞAMA: ÇALIŞMA ZAMANI (runtime) -- sadece calismak icin gerekenler
# ============================================================
FROM nvidia/cuda:12.1.0-base-ubuntu22.04

RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 \
    ffmpeg \
    libsm6 \
    libxext6 \
    libgl1 \
    libgles2 \
    libglib2.0-0 \
    libegl1 \
    libegl1-mesa \
    && rm -rf /var/lib/apt/lists/*

# Derleme asamasinda hazirlanan venv'i (pip, build araclari, cache olmadan) kopyala
COPY --from=builder /opt/venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

WORKDIR /app
RUN mkdir -p /app/data/input /app/data/output /app/src /app/models

# Modellerimizi FTR dokumaninda belirtilen /app/models yoluna kopyaliyoruz
COPY weights/ /app/models/

# Moduler kaynak kodlarimizi kopyaliyoruz
COPY src/ /app/src/
COPY main.py .

# Konteyner ayaga kalktiginda otomatik calisacak komut
CMD ["python3", "main.py"]
