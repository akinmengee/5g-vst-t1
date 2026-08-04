"""Saf görüntü işleme / hesaplama yardımcıları — FTR'deki `predict.py`'den taşındı.

Buradaki fonksiyonlar global model değişkenlerine bağlı DEĞİLDİR; ihtiyaç duydukları
model parametre olarak verilir. Böylece hem test edilebilirler hem de model
yüklenememiş olsa bile servis bunları güvenle atlayabilir.

Algoritmalar (CLAHE + perspektif düzeltme, MAR, poz sapması, slalom fizik ön
kontrolü) FTR'de doğrulanmış haliyle korunmuştur.
"""

import re

import cv2
import numpy as np
import torch

# --- Sabit landmark/keypoint indeksleri (predict.py ile aynı) ---
NOSE, LSHO, RSHO = 0, 5, 6
UST_DUDAK, ALT_DUDAK, SOL_KOSE, SAG_KOSE = 13, 14, 78, 308

PLATE_PATTERN = re.compile(
    r"(0[1-9]|[1-7][0-9]|8[01])"
    r"((\s?[A-Z]\s?)(\d{4,5})|(\s?[A-Z]{2}\s?)(\d{3,4})|(\s?[A-Z]{3}\s?)(\d{2,3}))"
)


def order_points(pts: np.ndarray) -> np.ndarray:
    rect = np.zeros((4, 2), dtype="float32")
    s = pts.sum(axis=1)
    rect[0] = pts[np.argmin(s)]
    rect[2] = pts[np.argmax(s)]
    diff = np.diff(pts, axis=1)
    rect[1] = pts[np.argmin(diff)]
    rect[3] = pts[np.argmax(diff)]
    return rect


def smart_sharpen(img: np.ndarray) -> np.ndarray:
    """LAB renk uzayında CLAHE ile kontrast iyileştirme."""
    lab = cv2.cvtColor(img, cv2.COLOR_BGR2LAB)
    l_channel, a, b = cv2.split(lab)
    clahe = cv2.createCLAHE(clipLimit=2.5, tileGridSize=(8, 8))
    cl = clahe.apply(l_channel)
    merged = cv2.merge((cl, a, b))
    return cv2.cvtColor(merged, cv2.COLOR_LAB2BGR)


def warp_plate(plate_roi: np.ndarray) -> np.ndarray:
    """Plaka kırpımını büyütüp, köşeleri bulup perspektif bozulmasını düzeltir."""
    buyuk = cv2.resize(plate_roi, None, fx=3, fy=3, interpolation=cv2.INTER_CUBIC)
    gray = cv2.cvtColor(buyuk, cv2.COLOR_BGR2GRAY)
    bfilter = cv2.bilateralFilter(gray, 11, 17, 17)
    edged = cv2.Canny(bfilter, 30, 200)
    contours, _ = cv2.findContours(edged.copy(), cv2.RETR_TREE, cv2.CHAIN_APPROX_SIMPLE)
    contours = sorted(contours, key=cv2.contourArea, reverse=True)[:10]

    screen_cnt = None
    for c in contours:
        peri = cv2.arcLength(c, True)
        approx = cv2.approxPolyDP(c, 0.02 * peri, True)
        if len(approx) == 4:
            screen_cnt = approx
            break
    if screen_cnt is None:
        return smart_sharpen(buyuk)

    rect = order_points(screen_cnt.reshape(4, 2))
    (tl, tr, br, bl) = rect
    width_a = np.sqrt(((br[0] - bl[0]) ** 2) + ((br[1] - bl[1]) ** 2))
    width_b = np.sqrt(((tr[0] - tl[0]) ** 2) + ((tr[1] - tl[1]) ** 2))
    max_width = max(int(width_a), int(width_b))
    height_a = np.sqrt(((tr[0] - br[0]) ** 2) + ((tr[1] - br[1]) ** 2))
    height_b = np.sqrt(((tl[0] - bl[0]) ** 2) + ((tl[1] - bl[1]) ** 2))
    max_height = max(int(height_a), int(height_b))
    if max_width <= 0 or max_height <= 0:
        return smart_sharpen(buyuk)

    dst = np.array(
        [[0, 0], [max_width - 1, 0], [max_width - 1, max_height - 1], [0, max_height - 1]],
        dtype="float32",
    )
    m = cv2.getPerspectiveTransform(rect, dst)
    warped = cv2.warpPerspective(buyuk, m, (max_width, max_height))
    return smart_sharpen(warped)


def correct_plate(metin: str) -> str:
    """O/0, I/1 gibi karakter karışıklıklarını Türk plaka formatına göre düzeltir."""
    if len(metin) < 6 or len(metin) > 9:
        return metin
    to_letter = {"0": "O", "1": "I", "2": "Z", "4": "A", "5": "S", "8": "B", "6": "G"}
    to_number = {
        "O": "0", "Q": "0", "D": "0", "I": "1", "L": "1",
        "Z": "2", "A": "4", "S": "5", "B": "8", "G": "6",
    }
    best_text = metin
    min_changes = 999

    for letter_length in (1, 2, 3):
        if 2 + letter_length >= len(metin):
            continue
        number_length = len(metin) - 2 - letter_length
        if number_length < 2 or number_length > 5:
            continue

        changes = 0
        new_city = ""
        for c in metin[:2]:
            if c.isalpha():
                if c in to_number:
                    new_city += to_number[c]
                    changes += 1
                else:
                    changes += 99
                    new_city += c
            else:
                new_city += c

        new_letters = ""
        for c in metin[2 : 2 + letter_length]:
            if c.isdigit():
                if c in to_letter:
                    new_letters += to_letter[c]
                    changes += 1
                else:
                    changes += 99
                    new_letters += c
            else:
                new_letters += c

        new_numbers = ""
        for c in metin[2 + letter_length :]:
            if c.isalpha():
                if c in to_number:
                    new_numbers += to_number[c]
                    changes += 1
                else:
                    changes += 99
                    new_numbers += c
            else:
                new_numbers += c

        candidate = new_city + new_letters + new_numbers
        if PLATE_PATTERN.fullmatch(candidate) and changes < min_changes:
            min_changes = changes
            best_text = candidate

    return best_text.replace(" ", "")


def mar_hesapla(landmarks) -> float:
    """Mouth Aspect Ratio — dikey dudak açıklığının yatay ağız genişliğine oranı."""
    ust = np.array([landmarks[UST_DUDAK].x, landmarks[UST_DUDAK].y])
    alt = np.array([landmarks[ALT_DUDAK].x, landmarks[ALT_DUDAK].y])
    sol = np.array([landmarks[SOL_KOSE].x, landmarks[SOL_KOSE].y])
    sag = np.array([landmarks[SAG_KOSE].x, landmarks[SAG_KOSE].y])
    dikey = np.linalg.norm(ust - alt)
    yatay = np.linalg.norm(sol - sag)
    return float(dikey / yatay) if yatay > 1e-6 else 0.0


def esneme_mar(face_landmarker, bolge: np.ndarray) -> float | None:
    if face_landmarker is None:
        return None
    import mediapipe as mp

    rgb = cv2.cvtColor(bolge, cv2.COLOR_BGR2RGB)
    mp_img = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)
    res = face_landmarker.detect(mp_img)
    if not res.face_landmarks:
        return None
    return mar_hesapla(res.face_landmarks[0])


def bakinma_olc(poz_model, bolge: np.ndarray) -> float | None:
    """Burun noktasının omuz orta noktasına göre normalize yatay sapması."""
    if poz_model is None:
        return None
    r = poz_model(bolge, conf=0.25, verbose=False)[0]
    if r.keypoints is None or r.boxes is None or len(r.boxes) == 0:
        return None

    kutular = r.boxes.xyxy.tolist()
    i = max(
        range(len(kutular)),
        key=lambda j: (kutular[j][2] - kutular[j][0]) * (kutular[j][3] - kutular[j][1]),
    )
    kp = r.keypoints.data[i].tolist()

    def gorunur(n: int) -> bool:
        return kp[n][2] >= 0.30

    if gorunur(LSHO) and gorunur(RSHO) and gorunur(NOSE):
        omuz_orta = (kp[LSHO][0] + kp[RSHO][0]) / 2
        omuz_genislik = abs(kp[RSHO][0] - kp[LSHO][0])
        if omuz_genislik > 1e-3:
            return float((kp[NOSE][0] - omuz_orta) / omuz_genislik)
    return None


def yolo_bul(model, bolge: np.ndarray, esik: float, tek_sinif0: bool = False) -> float:
    """Verilen bölgede modelin en yüksek güven skorunu döndürür (yoksa 0.0)."""
    if model is None:
        return 0.0
    sonuc = model(bolge, conf=esik, verbose=False)[0]
    if tek_sinif0:
        en_iyi = 0.0
        for k in sonuc.boxes:
            if int(k.cls) == 0 and float(k.conf) > en_iyi:
                en_iyi = float(k.conf)
        return en_iyi
    return max((float(k.conf) for k in sonuc.boxes), default=0.0)


def kabin_kirp(detector_model, frame: np.ndarray, kisi_conf: float, buyutme: int = 3):
    """Sürücü/kabin bölgesini izole eder (predict.py: `sofor_kirp`).

    Önce kişi kutusu aranır; yoksa aracın sağ-üst kadranı (sürücü koltuğu bölgesi)
    yaklaşık olarak kırpılır.
    """
    if detector_model is None:
        return None

    sonuc = detector_model(frame, conf=0.20, verbose=False)[0]
    h, w = frame.shape[:2]
    kisiler = []
    en_arac, en_arac_conf = None, 0.0

    for k in sonuc.boxes:
        sinif = int(k.cls)
        guven = float(k.conf)
        kutu = k.xyxy[0].tolist()
        if sinif == 0 and guven >= kisi_conf:
            kisiler.append((guven, kutu, (kutu[2] - kutu[0]) * (kutu[3] - kutu[1])))
        elif sinif in (2, 7) and guven > en_arac_conf:
            en_arac_conf, en_arac = guven, kutu

    secilen = None
    if kisiler:
        if en_arac is not None:
            ax1, ay1, ax2, ay2 = en_arac
            icerdekiler = [
                (g, k, a)
                for g, k, a in kisiler
                if ax1 <= (k[0] + k[2]) / 2 <= ax2 and ay1 <= (k[1] + k[3]) / 2 <= ay2
            ]
            adaylar = icerdekiler if icerdekiler else kisiler
        else:
            adaylar = kisiler
        secilen = max(adaylar, key=lambda t: t[2])[1] if adaylar else None

    if secilen is not None:
        x1, y1, x2, y2 = (int(v) for v in secilen)
        px, py = int((x2 - x1) * 0.15), int((y2 - y1) * 0.15)
        x1, y1 = max(0, x1 - px), max(0, y1 - py)
        x2, y2 = min(w, x2 + px), min(h, y2 + py)
    elif en_arac is not None:
        ax1, ay1, ax2, ay2 = (int(v) for v in en_arac)
        aw, ah = ax2 - ax1, ay2 - ay1
        x1, x2 = ax1 + int(aw * 0.45), ax2
        y1, y2 = ay1 + int(ah * 0.10), ay1 + int(ah * 0.60)
    else:
        return None

    kirpik = frame[y1:y2, x1:x2]
    if kirpik.size == 0:
        return None
    return cv2.resize(kirpik, None, fx=buyutme, fy=buyutme, interpolation=cv2.INTER_CUBIC)


def check_slalom(
    slalom_model,
    device: str,
    trajectory: list[tuple[float, float]],
    min_ornek: int,
    prob_esik: float,
    min_hareket: float,
) -> tuple[bool, float]:
    """Araç merkezinin yatay kayma dizisinden slalom tespiti.

    Önce fiziksel ön kontrol (araç kendi genişliğinin belirli oranı kadar hem sağa
    hem sola savrulmuş mu), ardından çift pencereli (multi-scale) LSTM değerlendirmesi.
    `trajectory`: [(merkez_x, arac_genisligi), ...] — tam kareye göre koordinatlar.
    """
    if slalom_model is None or len(trajectory) < min_ornek:
        return False, 0.0

    deltalar_tum = []
    for i in range(1, len(trajectory)):
        kayma = trajectory[i][0] - trajectory[i - 1][0]
        genislik = trajectory[i][1] if trajectory[i][1] > 0 else 1
        deltalar_tum.append((kayma / genislik) * 100.0)

    pozitif = sum(d for d in deltalar_tum if d > 0)
    negatif = sum(abs(d) for d in deltalar_tum if d < 0)
    if pozitif < min_hareket or negatif < min_hareket:
        return False, 0.0

    pencereler = [trajectory[-min_ornek:]]
    if len(trajectory) >= min_ornek * 2:
        pencereler.append(trajectory[-min_ornek * 2 :: 2][:min_ornek])

    en_iyi = 0.0
    for pencere in pencereler:
        if len(pencere) < min_ornek:
            continue
        deltalar = []
        for i in range(1, min_ornek):
            kayma = pencere[i][0] - pencere[i - 1][0]
            genislik = pencere[i][1] if pencere[i][1] > 0 else 1
            deltalar.append(round((kayma / genislik) * 100.0, 4))

        features = np.array(deltalar, dtype=np.float32).reshape(1, min_ornek - 1, 1)
        with torch.no_grad():
            out = slalom_model(torch.tensor(features).to(device))
            prob = torch.sigmoid(out).item()

        en_iyi = max(en_iyi, prob)
        if prob >= prob_esik:
            return True, round(prob, 2)

    return False, en_iyi
