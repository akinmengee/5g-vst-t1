# Backend'in kendi imajı — ML bağımlılığı yok, bu yüzden küçük ve hızlı build
# olur. AI imajıyla (ai/Dockerfile) karıştırma: o ayrı, GPU'lu, hakemin de
# bağımsız çalıştıracağı imaj.
#
# Bu container kendi içinden `docker run` ile host'taki AI imajını tetikler
# (Docker-outside-of-Docker, S2/G3 kararı — bkz. README "Deploy"). Bunun için:
#   1) host'un /var/run/docker.sock'u bu container'a mount edilmeli,
#   2) JOB_STORAGE_PATH, host'taki GERÇEK path ile BİREBİR aynı olmalı ve o
#      path host'tan bu container'a bind-mount edilmeli — aksi halde backend
#      job path'lerini doğru üretir ama host'taki docker daemon'ı mount
#      isteğinde o path'i host üzerinde bulamaz/yanlış klasörü bulur, AI
#      container'ı sessizce boş/yanlış girdiyle çalışır (bkz. app/services/
#      orchestration/ai_runner.py — path'ler doğrudan JOB_STORAGE_PATH'ten
#      türetiliyor, backend içindeki path'i değil host path'ini gönderiyor).

# --- docker CLI'ı minimal, ayrı bir imajdan al (daemon'ı değil, yalnızca istemciyi) ---
FROM docker:27-cli AS dockercli

FROM python:3.12-slim
COPY --from=dockercli /usr/local/bin/docker /usr/local/bin/docker

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app ./app

# Bilinçli olarak root: docker.sock'a erişim için ek grup/permission
# eşleştirmesi gerektirmiyor. Bu VM yalnızca yarışma süresince, tek amaçla
# çalışıyor — çok kullanıcılı/kalıcı bir prod ortamı değil.
EXPOSE 8080
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8080"]
