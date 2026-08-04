import cv2
import numpy as np
from ultralytics import YOLO
import re
from collections import Counter, deque
import json
import os

import warnings
import mediapipe as mp
from mediapipe.tasks import python as mp_python
from mediapipe.tasks.python import vision as mp_vision
import torch
import torch.nn as nn

from src.utils import tespit_olustur, arac_bilgisi_olustur, sonuc_birlestir

warnings.filterwarnings("ignore", message="X does not have valid feature names")

class SlalomLSTM(nn.Module):
    def __init__(self, input_size=1, hidden_size=128, num_layers=2):
        super(SlalomLSTM, self).__init__()
        self.hidden_size = hidden_size
        self.num_layers = num_layers
        self.lstm = nn.LSTM(input_size, hidden_size, num_layers, batch_first=True)
        self.fc = nn.Linear(hidden_size, 1)
        
    def forward(self, x):
        h0 = torch.zeros(self.num_layers, x.size(0), self.hidden_size).to(x.device)
        c0 = torch.zeros(self.num_layers, x.size(0), self.hidden_size).to(x.device)
        out, _ = self.lstm(x, (h0, c0))
        out = out[:, -1, :] 
        out = self.fc(out)
        return out

# === HELPER FUNCTIONS FROM pipe.py ===
def order_points(pts):
    rect = np.zeros((4, 2), dtype="float32")
    s = pts.sum(axis=1)
    rect[0] = pts[np.argmin(s)]
    rect[2] = pts[np.argmax(s)]
    diff = np.diff(pts, axis=1)
    rect[1] = pts[np.argmin(diff)]
    rect[3] = pts[np.argmax(diff)]
    return rect

def smart_sharpen(img):
    lab = cv2.cvtColor(img, cv2.COLOR_BGR2LAB)
    l_channel, a, b = cv2.split(lab)
    clahe = cv2.createCLAHE(clipLimit=2.5, tileGridSize=(8,8))
    cl = clahe.apply(l_channel)
    merged = cv2.merge((cl, a, b))
    return cv2.cvtColor(merged, cv2.COLOR_LAB2BGR)

def warp_plate(plate_roi):
    buyuk = cv2.resize(plate_roi, None, fx=3, fy=3, interpolation=cv2.INTER_CUBIC)
    gray = cv2.cvtColor(buyuk, cv2.COLOR_BGR2GRAY)
    bfilter = cv2.bilateralFilter(gray, 11, 17, 17)
    edged = cv2.Canny(bfilter, 30, 200)
    contours, _ = cv2.findContours(edged.copy(), cv2.RETR_TREE, cv2.CHAIN_APPROX_SIMPLE)
    contours = sorted(contours, key=cv2.contourArea, reverse=True)[:10]
    screenCnt = None
    for c in contours:
        peri = cv2.arcLength(c, True)
        approx = cv2.approxPolyDP(c, 0.02 * peri, True)
        if len(approx) == 4:
            screenCnt = approx
            break
    if screenCnt is None:
        return smart_sharpen(buyuk)
    pts = screenCnt.reshape(4, 2)
    rect = order_points(pts)
    (tl, tr, br, bl) = rect
    widthA = np.sqrt(((br[0] - bl[0]) ** 2) + ((br[1] - bl[1]) ** 2))
    widthB = np.sqrt(((tr[0] - tl[0]) ** 2) + ((tr[1] - tl[1]) ** 2))
    maxWidth = max(int(widthA), int(widthB))
    heightA = np.sqrt(((tr[0] - br[0]) ** 2) + ((tr[1] - br[1]) ** 2))
    heightB = np.sqrt(((tl[0] - bl[0]) ** 2) + ((tl[1] - bl[1]) ** 2))
    maxHeight = max(int(heightA), int(heightB))
    dst = np.array([
        [0, 0],
        [maxWidth - 1, 0],
        [maxWidth - 1, maxHeight - 1],
        [0, maxHeight - 1]], dtype="float32")
    M = cv2.getPerspectiveTransform(rect, dst)
    warped = cv2.warpPerspective(buyuk, M, (maxWidth, maxHeight))
    return smart_sharpen(warped)

PLATE_PATTERN = re.compile(r"(0[1-9]|[1-7][0-9]|8[01])((\s?[A-Z]\s?)(\d{4,5})|(\s?[A-Z]{2}\s?)(\d{3,4})|(\s?[A-Z]{3}\s?)(\d{2,3}))")
def correct_plate(metin):
    if len(metin) < 6 or len(metin) > 9:
        return metin
    to_letter = {'0': 'O', '1': 'I', '2': 'Z', '4': 'A', '5': 'S', '8': 'B', '6': 'G'}
    to_number = {'O': '0', 'Q': '0', 'D': '0', 'I': '1', 'L': '1', 'Z': '2', 'A': '4', 'S': '5', 'B': '8', 'G': '6'}
    best_text = metin
    min_changes = 999
    for letter_length in [1, 2, 3]:
        if 2 + letter_length >= len(metin): continue
        number_length = len(metin) - 2 - letter_length
        if number_length < 2 or number_length > 5: continue
        city_code = metin[:2]
        letters = metin[2:2+letter_length]
        numbers = metin[2+letter_length:]
        changes = 0
        new_city = ""
        for c in city_code:
            if c.isalpha():
                if c in to_number: new_city += to_number[c]; changes += 1
                else: changes += 99; new_city += c
            else: new_city += c
        new_letters = ""
        for c in letters:
            if c.isdigit():
                if c in to_letter: new_letters += to_letter[c]; changes += 1
                else: changes += 99; new_letters += c
            else: new_letters += c
        new_numbers = ""
        for c in numbers:
            if c.isalpha():
                if c in to_number: new_numbers += to_number[c]; changes += 1
                else: changes += 99; new_numbers += c
            else: new_numbers += c
        candidate = new_city + new_letters + new_numbers
        if PLATE_PATTERN.fullmatch(candidate):
            if changes < min_changes:
                min_changes = changes
                best_text = candidate
    return best_text.replace(" ", "")

# ==========================================
# 1. AŞAMA: MODELLERİN VE KURALLARIN YÜKLENMESİ
# ==========================================
WEIGHTS_DIR = "/app/models" if os.path.exists("/app/models") else "weights"
detector_model = YOLO(os.path.join(WEIGHTS_DIR, 'yolov8s.pt'))
classifier_model = YOLO(os.path.join(WEIGHTS_DIR, 'kasa_modeli.pt'))
color_model = YOLO(os.path.join(WEIGHTS_DIR, 'renk_modeli.pt'))
plate_model = YOLO(os.path.join(WEIGHTS_DIR, 'plaka_modeli.pt'))
character_model = YOLO(os.path.join(WEIGHTS_DIR, 'karakter_modeli.pt'))

slalom_device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
slalom_model = SlalomLSTM(input_size=1, hidden_size=128, num_layers=2)
slalom_model.load_state_dict(torch.load(os.path.join(WEIGHTS_DIR, 'slalom_lstm.pt'), map_location=slalom_device, weights_only=True))
slalom_model.to(slalom_device)
slalom_model.eval()
teknocan_model = YOLO(os.path.join(WEIGHTS_DIR, 'teknocan.pt'))

# AYRI model ornegi: detector_model ana dongude .track(persist=True) ile arac takibi
# icin kullaniliyor; bulucu ise sofor_kirp() ve yolcu tespiti icinde DUZ predict() ile
# cagriliyor. Ayni model nesnesini hem track() hem duz predict() icin kullanmak,
# track()'in kalici (persist=True) ic durumunu sifirliyor (bkz. test_yolcu.py) -- iki
# ayri model ornegi bu karismayi onluyor.
bulucu = YOLO(os.path.join(WEIGHTS_DIR, 'yolov8s.pt'))
poz = YOLO(os.path.join(WEIGHTS_DIR, "yolov8n-pose.pt"))
# Yolcu (tek-sinif "yolcu") modeli -- ID takipli (BoT-SORT, varsayilan) ile arac ROI'si
# icinde calisir; kendi ozel model dosyasi oldugu icin ayri bir ornek olmasi baska hicbir
# karisma riski tasimiyor.
yolcu_model = YOLO(os.path.join(WEIGHTS_DIR, "yolcu.pt"))
# Sigara/telefon artik Masaustu/Models klasorundeki K1-K16 kural setiyle calisiyor --
# kendi ozel poz modelini (s-pose, n-pose'tan farkli) kullanir; bakinma'nin kullandigi
# "poz" (n-pose) ile karismasin diye ayri bir ornek.
sigara_model = YOLO(os.path.join(WEIGHTS_DIR, "sigara.pt"))
telefon_model = YOLO(os.path.join(WEIGHTS_DIR, "telefon.pt"))
poz_s = YOLO(os.path.join(WEIGHTS_DIR, "yolov8s-pose.pt"))
modeller = {
    "su":      YOLO(os.path.join(WEIGHTS_DIR, "su.pt")),
    "kemer":   YOLO(os.path.join(WEIGHTS_DIR, "kemer.pt")),
    "esneme":  YOLO(os.path.join(WEIGHTS_DIR, "esneme.pt"))
}
TASK_YOLU = os.path.join(WEIGHTS_DIR, "face_landmarker.task")
secenek = mp_vision.FaceLandmarkerOptions(
    base_options=mp_python.BaseOptions(model_asset_path=TASK_YOLU),
    running_mode=mp_vision.RunningMode.IMAGE, num_faces=1,
)
yuz_dedektor = mp_vision.FaceLandmarker.create_from_options(secenek)

def check_slalom(xs):
    if len(xs) < 45:
        return False, 0.0
        
    tum_deltalar = []
    for i in range(1, len(xs)):
        mf = xs[i][0] - xs[i-1][0]
        gw = xs[i][1] if xs[i][1] > 0 else 1
        nd = (mf / gw) * 100.0
        tum_deltalar.append(nd)
        
    pozitif_hareket = sum(d for d in tum_deltalar if d > 0)
    negatif_hareket = sum(abs(d) for d in tum_deltalar if d < 0)
    
    if pozitif_hareket < 10 or negatif_hareket < 10:
        return False, 0.0
        
    windows_to_test = [xs[-45:]]
    if len(xs) >= 90:
        windows_to_test.append(xs[-90::2][:45])
        
    best_prob = 0.0
    for window in windows_to_test:
        if len(window) < 45:
            continue
            
        deltalar = []
        for i in range(1, 45):
            merkez_farki = window[i][0] - window[i-1][0]
            genislik = window[i][1] if window[i][1] > 0 else 1
            normalize_delta = (merkez_farki / genislik) * 100.0
            deltalar.append(round(normalize_delta, 4))
        
        features = np.array(deltalar, dtype=np.float32).reshape(1, 44, 1)
        features_t = torch.tensor(features).to(slalom_device)
        
        with torch.no_grad():
            out = slalom_model(features_t)
            prob = torch.sigmoid(out).item()
            
        if prob > best_prob:
            best_prob = prob
            
        if prob >= 0.40:
            return True, round(prob, 2)
            
    return False, best_prob

# === HELPER FUNCTIONS FROM predict.py ===
KISI_ESIK = 0.20
BUYUTME = 3
ESIK = {"su": 0.45, "kemer": 0.50, "esneme": 0.50}
ARDISIK_GEREK = 2
KEMER_GEREK = 10
ORAN_ESIK = 2.0; PLATO_GEREK = 8; HAREKET_ESIK = 1.5
DONUK_OFFSET = 0.30; T_ARKAYA = 4.0; T_ETRAFA_MIN = 1.2
NOSE, LSHO, RSHO = 0, 5, 6

# === SIGARA + TELEFON (Masaustu/Models klasorundeki K1-K16 kural seti, ayni degerler) ===
SIGTEL_MIN_ARAC_ORANI = 0.010   # K3: arac kadrajin en az bu kadarini kaplamali
SIGTEL_MIN_KIRPIM = 48          # K2: bu boyutun altindaki kirpimda olcum guvenilmez
SIGTEL_KENAR_PAYI = 0.04        # K4: kutu kirpim kenarina bu kadar yakinsa supheli
SIGTEL_GUCLU_CONF = 0.70        # K5: tek karede bu guven -> hemen kanit
SIGTEL_PENCERE_SN = 1.5         # K6: kanit biriktirme penceresi
SIGTEL_KANIT_ESIGI = 1.0        # K6: pencerede toplanmasi gereken agirlik
SIGTEL_SOGUMA_SN = 3.0          # K7: ayni olay bu sure icinde tekrar raporlanmaz

SIGARA_ZAYIF_CONF = 0.30        # K5: bu altindaki tespitler yok sayilir
SIGARA_KIRPIM_BUYUTME = 3       # kirpim modele verilmeden once kac kat buyutulur

TELEFON_ZAYIF_CONF = 0.25       # K5
TELEFON_TEPE_CONF = 0.50        # K15: pencerede en az bir kare bu guveni asmali
TELEFON_HEDEF_GENISLIK = 640    # kirpim modele verilmeden once bu genislige olceklenir
TELEFON_MAKS_ZOOM = 8.0
TELEFON_KARANLIK_ESIK = 70      # K16: bu parlakligin altinda CLAHE devreye girer
TELEFON_KULAK_YAKIN = 0.75      # K8: "telefon kulakta" esigi (omuz genisligi kati)
TELEFON_KULAK_ORTA = 1.20       # K8: bu kata kadar "kulaga dogru"
TELEFON_EL_YAKIN = 1.20         # K9: "telefon elde" esigi
TELEFON_EL_UZAK = 2.50          # K9: bu katin ustunde telefon surucunun elinde degil
TELEFON_MAKS_TEL_KAFA = 2.50    # K11: telefon kenari kafa genisliginin bu katini asamaz
TELEFON_KP_ESIK = 0.30          # keypoint guven esigi
TELEFON_ALT_KONUS = "telefonla_konusma"
TELEFON_ALT_OYNA = "telefonla_oynama"  # NOT: FTR semasinda gecerli tek etiket
                                        # "telefonla_konusma" -- "oynama" durumunda da
                                        # ayni (tek gecerli) etiketle raporlanir, alt_etiket
                                        # sadece dahili karar/ayirt etme icin kullanilir.

# === YOLCU (test_yolcu.py ile ayni, dogrulanmis degerler) ===
YOLCU_KISI_ESIK = 0.25     # arac ROI'si icinde kisi tespiti icin taban guven
YOLCU_CAR_ESIK = 0.35      # arac kutusu icin guven
YOLCU_ROI_PAD_ORAN = 0.05
YOLCU_SOFOR_DUP_ORAN = 0.5
YOLCU_LOCK_MIN_CONF = 0.25
YOLCU_SOFOR_YENIDEN_KAZANIM_ORANI = 0.20
YOLCU_ARDISIK_GEREK = 2    # kilitleme icin 2 ardisik (islenen) kare yeterli
UST_DUDAK, ALT_DUDAK, SOL_KOSE, SAG_KOSE = 13, 14, 78, 308

def sofor_kirp(frame):
    sonuc = bulucu(frame, conf=0.20, verbose=False)[0]
    H, W = frame.shape[:2]; kisiler = []; en_arac, ea = None, 0
    for k in sonuc.boxes:
        sid = int(k.cls); g = float(k.conf); kutu = k.xyxy[0].tolist()
        if sid == 0 and g >= KISI_ESIK:
            kisiler.append((g, kutu, (kutu[2]-kutu[0])*(kutu[3]-kutu[1])))
        elif sid in (2, 7) and g > ea:
            ea, en_arac = g, kutu
    secilen = None
    if kisiler:
        if en_arac is not None:
            ax1, ay1, ax2, ay2 = en_arac
            ic = [(g, k, a) for g, k, a in kisiler if ax1 <= (k[0]+k[2])/2 <= ax2 and ay1 <= (k[1]+k[3])/2 <= ay2]
            aday = ic if ic else kisiler
        else:
            aday = kisiler
        secilen = max(aday, key=lambda t: t[2])[1] if aday else None
    if secilen is not None:
        x1, y1, x2, y2 = [int(v) for v in secilen]
        px, py = int((x2-x1)*0.15), int((y2-y1)*0.15)
        x1, y1 = max(0, x1-px), max(0, y1-py); x2, y2 = min(W, x2+px), min(H, y2+py)
    elif en_arac is not None:
        ax1, ay1, ax2, ay2 = [int(v) for v in en_arac]; aw, ah = ax2-ax1, ay2-ay1
        x1 = ax1+int(aw*0.45); x2 = ax2; y1 = ay1+int(ah*0.10); y2 = ay1+int(ah*0.60)
    else:
        return None, 0, 0
    kirpik = frame[y1:y2, x1:x2]
    if kirpik.size == 0: return None, 0, 0
    return cv2.resize(kirpik, None, fx=BUYUTME, fy=BUYUTME, interpolation=cv2.INTER_CUBIC), x1, y1

def yolo_bul(model, bolge, esik, tek_sinif0=False):
    sonuc = model(bolge, conf=esik, verbose=False)[0]
    if tek_sinif0:
        g = 0.0
        for k in sonuc.boxes:
            if int(k.cls) == 0 and float(k.conf) > g: g = float(k.conf)
        return g
    return max([float(k.conf) for k in sonuc.boxes], default=0.0)

def mar_hesapla(lm):
    ust = np.array([lm[UST_DUDAK].x, lm[UST_DUDAK].y]); alt = np.array([lm[ALT_DUDAK].x, lm[ALT_DUDAK].y])
    sol = np.array([lm[SOL_KOSE].x, lm[SOL_KOSE].y]); sag = np.array([lm[SAG_KOSE].x, lm[SAG_KOSE].y])
    d = np.linalg.norm(ust-alt); y = np.linalg.norm(sol-sag)
    return d/y if y > 1e-6 else 0.0

def esneme_mar(yuz_sonuc):
    if not yuz_sonuc or not yuz_sonuc.face_landmarks: return None
    return mar_hesapla(yuz_sonuc.face_landmarks[0])

def su_bul(model, bolge, esik, yuz_sonuc):
    sonuc = model(bolge, conf=esik, verbose=False)[0]
    H, W = bolge.shape[:2]
    
    agiz_merkez_x, agiz_merkez_y = None, None
    if yuz_sonuc and yuz_sonuc.face_landmarks:
        lm = yuz_sonuc.face_landmarks[0]
        agiz_merkez_x = (lm[13].x + lm[14].x + lm[78].x + lm[308].x) / 4 * W
        agiz_merkez_y = (lm[13].y + lm[14].y + lm[78].y + lm[308].y) / 4 * H
    
    en_iyi_g = 0.0
    en_iyi_kutu = None
    for k in sonuc.boxes:
        bx1, by1, bx2, by2 = k.xyxy[0].tolist()
        g = float(k.conf)
        
        # 1. Kutu Boyutu: Şişe şoförün yarısı kadar büyük olamaz (Devasa gölgeleri engeller)
        if (bx2 - bx1) > W * 0.35 or (by2 - by1) > H * 0.45:
            continue
            
        # 2. Ağız Hizası: Şişe ağza yakın olmalı (Eğer ağız görünüyorsa!)
        if agiz_merkez_x is not None:
            tolerans_x = W * 0.15
            tolerans_y = H * 0.15
            if not ((bx1 - tolerans_x <= agiz_merkez_x <= bx2 + tolerans_x) and \
                    (by1 - tolerans_y <= agiz_merkez_y <= by2 + tolerans_y)):
                continue
                
        if g > en_iyi_g:
            en_iyi_g = g
            en_iyi_kutu = (bx1, by1, bx2, by2)
                
    return en_iyi_g, en_iyi_kutu

def bakinma_olc(bolge):
    r = poz(bolge, conf=0.25, verbose=False)[0]
    if r.keypoints is None or r.boxes is None or len(r.boxes) == 0: return None
    ku = r.boxes.xyxy.tolist()
    i = max(range(len(ku)), key=lambda j: (ku[j][2]-ku[j][0])*(ku[j][3]-ku[j][1]))
    kp = r.keypoints.data[i].tolist(); gor = lambda n: kp[n][2] >= 0.30
    if gor(LSHO) and gor(RSHO) and gor(NOSE):
        smid = (kp[LSHO][0]+kp[RSHO][0])/2; sw = abs(kp[RSHO][0]-kp[LSHO][0])
        if sw > 1e-3: return (kp[NOSE][0]-smid)/sw
    return None

def ardisik_seg(varlik, gerek):
    seg = []; i = 0; n = len(varlik)
    while i < n:
        if varlik[i][1] is not None:
            j = i
            while j+1 < n and varlik[j+1][1] is not None: j += 1
            if (j-i+1) >= gerek:
                tepe = max(varlik[k][1] for k in range(i, j+1))
                seg.append((varlik[i][0], tepe))
            i = j+1
        else: i += 1
    return seg

def esneme_seg(mar_kayit):
    if not mar_kayit: return []
    marlar = [m for _, m in mar_kayit]; taban = float(np.median(marlar))
    oranlar = [(m/taban if taban > 1e-6 else 0) for _, m in mar_kayit]
    acik = set(i for i, o in enumerate(oranlar) if o >= ORAN_ESIK)
    out = []; i = 0; n = len(mar_kayit)
    while i < n:
        if i in acik:
            j = i
            while j+1 < n and (j+1) in acik: j += 1
            if (j-i+1) >= PLATO_GEREK:
                tepe = max(oranlar[i:j+1])
                giris = oranlar[i-1] if i > 0 else oranlar[i]; cikis = oranlar[j+1] if j+1 < n else oranlar[j]
                if tepe - min(giris, cikis) >= HAREKET_ESIK:
                    out.append(((mar_kayit[i][0]+mar_kayit[j][0])/2, tepe))
            i = j+1
        else: i += 1
    return out

def bakinma_seg(off_kayit, dt):
    durum = [(sn, ('L' if o < 0 else 'R') if (o is not None and abs(o) >= DONUK_OFFSET) else None) for sn, o in off_kayit]
    out = []; i = 0; n = len(durum)
    while i < n:
        if durum[i][1] is not None:
            j = i; yon = durum[i][1]
            while j+1 < n and durum[j+1][1] == yon: j += 1
            sure = (durum[j][0]-durum[i][0]) + dt; orta = (durum[i][0]+durum[j][0])/2
            if sure >= T_ARKAYA: out.append(("arkaya_bakma", orta, sure))
            elif sure >= T_ETRAFA_MIN: out.append(("etrafa_bakinma", orta, sure))
            i = j+1
        else: i += 1
    return out

# === SIGARA + TELEFON ORTAK YARDIMCILAR (Masaustu/Models mantigi) ===
def _sigtel_kutu_agirligi(a, kirpim_boyu, arac_orani, kutu, bolge):
    """K2/K3/K4 -- olcum kalitesi kontrolleri, sigara ve telefon icin ortak."""
    if kirpim_boyu < SIGTEL_MIN_KIRPIM:
        a *= 0.35
    elif kirpim_boyu < SIGTEL_MIN_KIRPIM * 2:
        a *= 0.70
    if arac_orani < SIGTEL_MIN_ARAC_ORANI * 2:
        a *= 0.60
    if kutu is not None:
        bw = max(bolge[2]-bolge[0], 1); bh = max(bolge[3]-bolge[1], 1)
        gx = min(kutu[0]-bolge[0], bolge[2]-kutu[2]) / bw
        gy = min(kutu[1]-bolge[1], bolge[3]-kutu[3]) / bh
        if min(gx, gy) < SIGTEL_KENAR_PAYI:
            a *= 0.50
    return a

def _sigtel_kirp(frame, bolge):
    H, W = frame.shape[:2]
    x1, y1 = max(int(bolge[0]), 0), max(int(bolge[1]), 0)
    x2, y2 = min(int(bolge[2]), W), min(int(bolge[3]), H)
    if x2-x1 < 12 or y2-y1 < 12:
        return None, None
    return frame[y1:y2, x1:x2], (x1, y1)

def _iou(a, b):
    if a is None or b is None:
        return 0.0
    x1, y1 = max(a[0], b[0]), max(a[1], b[1])
    x2, y2 = min(a[2], b[2]), min(a[3], b[3])
    if x2 <= x1 or y2 <= y1:
        return 0.0
    kesisim = (x2-x1) * (y2-y1)
    alan = (a[2]-a[0])*(a[3]-a[1]) + (b[2]-b[0])*(b[3]-b[1]) - kesisim
    return kesisim / max(alan, 1e-6)

# --- SIGARA ---
def sigara_surucu_bolgesi(frame, arac):
    """(kutu, yontem) -- once poz_s ile arac icinde kisi aranir (hassas kirpim),
    bulunamazsa on cam geometrisi (soldan direksiyon, onden bakis -> sofor sagda)."""
    ax1, ay1, ax2, ay2 = arac
    aw, ah = ax2-ax1, ay2-ay1
    r = poz_s(frame, conf=0.25, verbose=False)[0]
    for b in r.boxes:
        x1, y1, x2, y2 = [float(v) for v in b.xyxy[0]]
        if x1 >= ax1 - aw*0.1 and x2 <= ax2 + aw*0.1 and y1 >= ay1 - ah*0.1:
            pay_x, pay_y = (x2-x1)*0.35, (y2-y1)*0.30
            return [x1-pay_x, y1-pay_y, x2+pay_x, y2+pay_y*0.5], "poz"
    return [ax1+aw*0.28, ay1+ah*0.03, ax2-aw*0.03, ay1+ah*0.50], "geometri"

def sigara_kirpimda_ara(frame, bolge):
    kirpim, ofs = _sigtel_kirp(frame, bolge)
    if kirpim is None:
        return 0.0, None, 0
    x1, y1 = ofs
    kb = min(kirpim.shape[0], kirpim.shape[1])
    buyuk = cv2.resize(kirpim, None, fx=SIGARA_KIRPIM_BUYUTME, fy=SIGARA_KIRPIM_BUYUTME,
                       interpolation=cv2.INTER_CUBIC)
    r = sigara_model(buyuk, conf=SIGARA_ZAYIF_CONF, verbose=False)[0]
    if not len(r.boxes):
        return 0.0, None, kb
    b = r.boxes[int(r.boxes.conf.argmax())]
    c = float(b.conf[0])
    bx = [float(v)/SIGARA_KIRPIM_BUYUTME for v in b.xyxy[0]]
    mutlak = [x1+bx[0], y1+bx[1], x1+bx[2], y1+bx[3]]
    return c, mutlak, kb

def sigara_isle(frame, en_arac, kare_alani):
    """Bir kare icin (agirlik, conf) dondurur. en_arac None -> (0.0, 0.0) (K1)."""
    if en_arac is None:
        return 0.0, 0.0
    arac_orani = ((en_arac[2]-en_arac[0]) * (en_arac[3]-en_arac[1])) / kare_alani
    bolge, _ = sigara_surucu_bolgesi(frame, en_arac)
    conf, kutu, kb = sigara_kirpimda_ara(frame, bolge)
    if conf < SIGARA_ZAYIF_CONF:
        return 0.0, conf
    a = _sigtel_kutu_agirligi(conf, kb, arac_orani, kutu, bolge)
    return a, conf

# --- TELEFON ---
class _Poz:
    """Surucunun poz bilgisi -- tum koordinatlar orijinal kare olceginde."""
    def __init__(self, kutu, kp):
        self.kutu = kutu
        self.kp = kp

    def _nokta(self, i):
        x, y, c = self.kp[i]
        return (float(x), float(y)) if c >= TELEFON_KP_ESIK else None

    @property
    def bilekler(self):
        return [p for p in (self._nokta(9), self._nokta(10)) if p]

    @property
    def kulaklar(self):
        return [p for p in (self._nokta(3), self._nokta(4)) if p]

    @property
    def kafa_noktalari(self):
        n = [self._nokta(i) for i in (0, 1, 2, 3, 4)]
        return [p for p in n if p]

    @property
    def olcek(self):
        o = [p for p in (self._nokta(5), self._nokta(6)) if p]
        if len(o) == 2:
            d = float(np.hypot(o[0][0]-o[1][0], o[0][1]-o[1][1]))
            if d > 4:
                return d
        return max((self.kutu[2]-self.kutu[0]) * 0.35, 8.0)

    @property
    def kafa_genisligi(self):
        k = self.kulaklar
        if len(k) == 2:
            d = float(np.hypot(k[0][0]-k[1][0], k[0][1]-k[1][1]))
            if d > 4:
                return d
        return self.olcek * 0.55

    @property
    def omuz_y(self):
        o = [p for p in (self._nokta(5), self._nokta(6)) if p]
        return float(np.mean([p[1] for p in o])) if o else None

def telefon_kabin_bolgesi(arac):
    """1. gecis: aracin ust yarisinin TAMAMI (on cam + yan camlar)."""
    ax1, ay1, ax2, ay2 = arac
    aw, ah = ax2-ax1, ay2-ay1
    return [ax1-aw*0.02, ay1-ah*0.02, ax2+aw*0.02, ay1+ah*0.62]

def telefon_on_cam_bolgesi(arac):
    """Poz bulunamayinca kullanilan yedek: on camin sofor tarafi."""
    ax1, ay1, ax2, ay2 = arac
    aw, ah = ax2-ax1, ay2-ay1
    return [ax1+aw*0.22, ay1+ah*0.02, ax2-aw*0.02, ay1+ah*0.52]

def telefon_hazirla(kirpim):
    """Uyarlanabilir yakinlastirma + K16 dusuk isik iyilestirmesi (CLAHE)."""
    h, w = kirpim.shape[:2]
    z = float(np.clip(TELEFON_HEDEF_GENISLIK / max(w, 1), 1.0, TELEFON_MAKS_ZOOM))
    buyuk = (cv2.resize(kirpim, None, fx=z, fy=z, interpolation=cv2.INTER_CUBIC)
             if z > 1.001 else kirpim.copy())
    karanlik = float(buyuk.mean()) < TELEFON_KARANLIK_ESIK
    if karanlik:
        lab = cv2.cvtColor(buyuk, cv2.COLOR_BGR2LAB)
        l, a, b = cv2.split(lab)
        l = cv2.createCLAHE(clipLimit=2.5, tileGridSize=(8, 8)).apply(l)
        buyuk = cv2.cvtColor(cv2.merge((l, a, b)), cv2.COLOR_LAB2BGR)
    return buyuk, z, karanlik

def telefon_poz_bul(buyuk, ofs, z):
    """K13: kirpimdaki kisiler icinde sofor tarafindakini secer."""
    rp = poz_s(buyuk, conf=0.25, verbose=False)[0]
    if not len(rp.boxes) or rp.keypoints is None:
        return None
    ox, oy = ofs
    geri = lambda k: [ox+k[0]/z, oy+k[1]/z, ox+k[2]/z, oy+k[3]/z]
    kw = buyuk.shape[1]
    adaylar = []
    for i, b in enumerate(rp.boxes):
        bx = [float(v) for v in b.xyxy[0]]
        alan = (bx[2]-bx[0]) * (bx[3]-bx[1])
        merkez = (bx[0]+bx[2]) / 2
        puan = alan * (1.6 if merkez > kw*0.45 else 1.0)
        kp = rp.keypoints.data[i].cpu().numpy().astype(float)
        kp[:, 0] = ox + kp[:, 0]/z
        kp[:, 1] = oy + kp[:, 1]/z
        adaylar.append((puan, _Poz(geri(bx), kp)))
    return max(adaylar, key=lambda a: a[0])[1]

def telefon_kirpimda_ara(frame, arac):
    """IKI GECISLI kirpim: 1) arac ust yarisi -> poz bul, 2) sofor etrafi dar
    kirpilip telefon modeline verilir. Doner: (conf, kutu, kirpim_kisa_kenar,
    poz, yontem, bolge)."""
    genis = telefon_kabin_bolgesi(arac)
    k1, ofs1 = _sigtel_kirp(frame, genis)
    if k1 is None:
        return 0.0, None, 0, None, "gecersiz", genis
    b1, z1, _ = telefon_hazirla(k1)
    poz = telefon_poz_bul(b1, ofs1, z1)

    if poz is not None:
        x1, y1, x2, y2 = poz.kutu
        px, py = (x2-x1)*0.40, (y2-y1)*0.35
        bolge, yontem = [x1-px, y1-py, x2+px, y2+py*0.6], "poz"
    else:
        bolge, yontem = telefon_on_cam_bolgesi(arac), "geometri"

    k2, ofs2 = _sigtel_kirp(frame, bolge)
    if k2 is None:
        return 0.0, None, 0, poz, yontem, bolge
    kb = min(k2.shape[0], k2.shape[1])
    b2, z2, _ = telefon_hazirla(k2)

    conf, kutu = 0.0, None
    rt = telefon_model(b2, conf=TELEFON_ZAYIF_CONF, verbose=False)[0]
    if len(rt.boxes):
        b = rt.boxes[int(rt.boxes.conf.argmax())]
        conf = float(b.conf[0])
        bx = [float(v) for v in b.xyxy[0]]
        kutu = [ofs2[0]+bx[0]/z2, ofs2[1]+bx[1]/z2, ofs2[0]+bx[2]/z2, ofs2[1]+bx[3]/z2]
    return conf, kutu, kb, poz, yontem, bolge

def telefon_poz_kontrolu(poz, kutu, bolge):
    """K8/K9/K10/K11 -- poz tabanli kontroller. Poz/keypoint yoksa deger None
    (o kontrol notr kalir)."""
    d = {"kulak_orani": None, "tel_kulak_orani": None, "el_orani": None,
         "omuz_ustu": None, "kafa_g": None, "ust_bolge": None,
         "surucu_var": poz is not None, "govdede": None}
    if kutu is not None:
        by = bolge[1] + (bolge[3]-bolge[1]) * 0.45
        d["ust_bolge"] = ((kutu[1]+kutu[3])/2) < by
    if poz is None:
        return d
    olcek = poz.olcek
    d["kafa_g"] = poz.kafa_genisligi
    bilekler, kafa = poz.bilekler, poz.kafa_noktalari

    if bilekler and kafa:
        hedef = poz.kulaklar or kafa
        d["kulak_orani"] = min(np.hypot(b[0]-h[0], b[1]-h[1]) / olcek
                                for b in bilekler for h in hedef)
    if kutu is None:
        return d
    cx, cy = (kutu[0]+kutu[2])/2, (kutu[1]+kutu[3])/2

    if kafa:
        hedef = poz.kulaklar or kafa
        d["tel_kulak_orani"] = min(np.hypot(cx-h[0], cy-h[1]) / olcek for h in hedef)

    if bilekler:
        d["el_orani"] = min(np.hypot(cx-b[0], cy-b[1]) / olcek for b in bilekler)
    else:
        x1, y1, x2, y2 = poz.kutu
        px, py = (x2-x1)*0.25, (y2-y1)*0.25
        d["govdede"] = (x1-px) <= cx <= (x2+px) and (y1-py) <= cy <= (y2+py)

    oy = poz.omuz_y
    if oy is not None:
        d["omuz_ustu"] = cy < oy
    return d

def telefon_agirlik(conf, kirpim_boyu, arac_orani, kutu, bolge, pk, onceki_kutu):
    """Ham guveni olcum kosullarina ve poz kanitina gore agirliklandirir, olayin
    turunu (konusma/oynama) belirler. Doner: (agirlik, alt_etiket)."""
    if conf < TELEFON_ZAYIF_CONF:                                          # K5
        return 0.0, None
    a = conf

    if kirpim_boyu < SIGTEL_MIN_KIRPIM:                                    # K2
        a *= 0.35
    elif kirpim_boyu < SIGTEL_MIN_KIRPIM * 2:
        a *= 0.70

    if arac_orani < SIGTEL_MIN_ARAC_ORANI * 2:                             # K3
        a *= 0.60

    if kutu is not None:                                                   # K4
        bw = max(bolge[2]-bolge[0], 1); bh = max(bolge[3]-bolge[1], 1)
        gx = min(kutu[0]-bolge[0], bolge[2]-kutu[2]) / bw
        gy = min(kutu[1]-bolge[1], bolge[3]-kutu[3]) / bh
        if min(gx, gy) < SIGTEL_KENAR_PAYI:
            a *= 0.50

    if not pk["surucu_var"]:                                               # K14 SERT KAPI
        return 0.0, None

    el = pk["el_orani"]                                                    # K9
    if el is not None:
        if el <= TELEFON_EL_YAKIN:
            a *= 1.20
        elif el >= TELEFON_EL_UZAK:
            a *= 0.35
        else:
            a *= 0.85
    elif pk["govdede"] is False:
        a *= 0.40

    alt = None                                                             # K8 + K10
    kulak = pk["kulak_orani"]
    tk = pk["tel_kulak_orani"]

    if pk["omuz_ustu"] is False:
        alt = TELEFON_ALT_OYNA
    elif tk is not None and tk <= TELEFON_KULAK_YAKIN:
        a *= 1.35 if (kulak is not None and kulak <= TELEFON_KULAK_ORTA) else 1.25
        alt = TELEFON_ALT_KONUS
    elif tk is not None and tk <= TELEFON_KULAK_ORTA and pk["omuz_ustu"]:
        a *= 1.15; alt = TELEFON_ALT_KONUS
    elif tk is not None:
        alt = TELEFON_ALT_OYNA
    elif pk["omuz_ustu"] is True:
        if el is not None:
            a *= 1.10
        alt = TELEFON_ALT_KONUS
    elif pk["ust_bolge"] is True:
        alt = TELEFON_ALT_KONUS
    elif pk["ust_bolge"] is False:
        alt = TELEFON_ALT_OYNA

    if kutu is not None and pk["kafa_g"]:                                  # K11
        kenar = max(kutu[2]-kutu[0], kutu[3]-kutu[1])
        if kenar > TELEFON_MAKS_TEL_KAFA * pk["kafa_g"]:
            a *= 0.45

    iou = _iou(kutu, onceki_kutu)                                          # K12
    if iou >= 0.30:
        a *= 1.15
    elif onceki_kutu is not None and iou == 0.0:
        a *= 0.90

    return min(a, conf * 1.6), alt

def telefon_isle(frame, en_arac, kare_alani, onceki_kutu):
    """Bir kare icin (agirlik, conf, alt_etiket, kutu) dondurur."""
    if en_arac is None:
        return 0.0, 0.0, None, None
    arac_orani = ((en_arac[2]-en_arac[0]) * (en_arac[3]-en_arac[1])) / kare_alani
    conf, kutu, kb, poz, yontem, bolge = telefon_kirpimda_ara(frame, en_arac)
    pk = telefon_poz_kontrolu(poz, kutu, bolge)
    a, alt = telefon_agirlik(conf, kb, arac_orani, kutu, bolge, pk, onceki_kutu)
    return a, conf, alt, kutu

def map_type(val):
    if not val: return "sedan"
    return val.lower().strip()

def map_color(val):
    if not val: return "beyaz"
    return val.lower().strip()

# === ANA ÇIKARIM (run_inference) ===
def run_inference(video_path):
    video_name = os.path.basename(video_path)
    cap = cv2.VideoCapture(video_path)
    fps = cap.get(cv2.CAP_PROP_FPS)
    if fps <= 0: fps = 30.0
    
    global_frame_count = 0

    # Görselleştirme videosu (kutu çizilmiş çıktı) yalnızca yerel hata ayıklama
    # içindir: DEBUG_VIDEO=1 ile açılır. Yarışma koşusunda kapalıdır — her kareyi
    # yeniden kodlamak süre ve disk harcar, girdi klasörü de salt-okunur mount
    # edilebilir. Bu bir ortam TESPİTİ değil, açıkça verilen bir hata ayıklama
    # anahtarıdır; varsayılan davranış her yerde aynıdır.
    out_video = None
    if os.environ.get("DEBUG_VIDEO") == "1":
        out_video = cv2.VideoWriter(
            os.path.join(os.path.dirname(video_path), "PREDICT_GERCEK_Cikti.mp4"),
            cv2.VideoWriter_fourcc(*'mp4v'), fps,
            (int(cap.get(cv2.CAP_PROP_FRAME_WIDTH)), int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT)))
        )
    son_su_kutu = None
    son_su_g = 0.0
    son_su_zamani = -999
    
    vehicle_memory = {}  
    color_memory = {}
    plate_memory = {}  
    finalized_plates = {}
    finalized_types = {}
    finalized_colors = {}
    vehicle_confidences = {}
    vehicle_events = [] 
    vehicle_frame_counts = {}
    vehicle_trajectories = {}
    slalom_detected_vehicles = set()
    slalom_memory = {}
    teknocan_memory = {}
    finalized_teknocans = set()
    laptop_memory = {}
    finalized_laptops = set()
    
    atlama = 1
    atlama_yolcu = max(1, int(round(fps/2)))
    dt = atlama/fps
    yolo_kayit = {ad: [] for ad in modeller}
    mar_kayit = []  # hibrit esneme: son ~5 saniyelik ham MAR (agiz aciklik) gecmisi
    MAR_PENCERE = max(10, round(5 / dt))
    off_kayit = []
    surucu_var_kayit = []
    
    # YOLCU: ID takipli (BoT-SORT) surekli-kimlik durumu -- test_yolcu.py ile ayni
    yolcu_sofor_id = None
    yolcu_sofor_son_konum = None
    yolcu_id_role = {}          # track_id -> koltuk ("on_koltuk" | "arka_koltuk_1" | "arka_koltuk_2")
    yolcu_ardisik_sayac = {}    # track_id -> kesintisiz (islenen kare bazinda) gorulme sayaci
    yolcu_ardisik_son_kare = {} # track_id -> en son goruldugu islenen-kare sirasi
    yolcu_kilitli_roller = set()  # bir koltuk bir kez JSON'a yazildi mi (video basina en fazla 1)
    yolcu_islenen_kare_sirasi = 0

    # SIGARA + TELEFON: zamansal kanit birikimi durumu (K6/K7/K12/K15)
    sigara_pencere = deque()       # (sn, agirlik)
    sigara_son_olay = -99.0
    telefon_pencere = deque()      # (sn, agirlik, alt_etiket, conf)
    telefon_son_olay = -99.0
    telefon_onceki_kutu = None

    while cap.isOpened():
        ret, frame = cap.read()
        if not ret:
            break
        global_frame_count += 1
        is_processed_frame = (global_frame_count % atlama == 0)
        
        # --- CAR BOXES PASS ---
        detector_results = detector_model.track(frame, classes=[2, 7, 63], conf=0.45, persist=True, verbose=False)
        current_car_boxes = []
        for result in detector_results:
            for box in result.boxes:
                if int(box.cls[0].item()) in [2, 7]:
                    current_car_boxes.append(tuple(map(int, box.xyxy[0])))

        # --- 1. TEKNOCAN ---
        if global_frame_count % 2 == 0:
            teknocan_results = teknocan_model.track(frame, conf=0.6, persist=True, verbose=False)
            for t_res in teknocan_results:
                for t_box in t_res.boxes:
                    if t_box.id is None: continue
                    t_id = int(t_box.id.item())
                    conf = float(t_box.conf[0])
                    if t_id not in finalized_teknocans:
                        teknocan_memory[t_id] = teknocan_memory.get(t_id, 0) + 1
                        if teknocan_memory[t_id] == 10:
                            zaman_saniye = global_frame_count / fps
                            tx1, ty1, tx2, ty2 = map(int, t_box.xyxy[0])
                            cx, cy = (tx1+tx2)/2, (ty1+ty2)/2
                            is_inside = any(c[0] <= cx <= c[2] and c[1] <= cy <= c[3] for c in current_car_boxes)
                            lbl = "teknocan_ici" if is_inside else "teknocan_disi"
                            vehicle_events.append(tespit_olustur(zaman_saniye, "nesneler", lbl, conf))
                            finalized_teknocans.add(t_id)
                        elif teknocan_memory[t_id] > 10:
                            finalized_teknocans.add(t_id)
        
        # --- 2. LAPTOP (bilgisayar) ve ARAÇ ---
        for result in detector_results:
            for box in result.boxes:
                if box.id is None: continue
                v_id = int(box.id.item())
                class_id = int(box.cls[0].item())
                ax1, ay1, ax2, ay2 = map(int, box.xyxy[0])
                conf = float(box.conf[0])
                
                if class_id == 63:
                    if v_id not in finalized_laptops:
                        laptop_memory[v_id] = laptop_memory.get(v_id, 0) + 1
                        if laptop_memory[v_id] == 5:
                            zaman_saniye = global_frame_count / fps
                            cx, cy = (ax1+ax2)/2, (ay1+ay2)/2
                            is_inside = any(c[0] <= cx <= c[2] and c[1] <= cy <= c[3] for c in current_car_boxes)
                            lbl = "bilgisayar_ici" if is_inside else "bilgisayar_disi"
                            vehicle_events.append(tespit_olustur(zaman_saniye, "nesneler", lbl, conf))
                            finalized_laptops.add(v_id)
                        elif laptop_memory[v_id] > 5:
                            finalized_laptops.add(v_id)
                    continue
                    
                vehicle_id = v_id
                w_vehicle = ax2 - ax1 
                h_vehicle = ay2 - ay1 
                
                pad_x = int(w_vehicle * 0.05)
                pad_y = int(h_vehicle * 0.05)
                p_ax1 = max(0, ax1 - pad_x)
                p_ay1 = max(0, ay1 - pad_y)
                p_ax2 = min(frame.shape[1], ax2 + pad_x)
                p_ay2 = min(frame.shape[0], ay2 + pad_y)
                vehicle_roi = frame[p_ay1:p_ay2, p_ax1:p_ax2]
                
                if vehicle_roi.size == 0: continue
                
                vehicle_frame_counts[vehicle_id] = vehicle_frame_counts.get(vehicle_id, 0) + 1
                
                cx = (ax1 + ax2) / 2
                if vehicle_id not in vehicle_trajectories: vehicle_trajectories[vehicle_id] = []
                vehicle_trajectories[vehicle_id].append((cx, w_vehicle))
                if len(vehicle_trajectories[vehicle_id]) > 90: vehicle_trajectories[vehicle_id].pop(0)
                
                if vehicle_id not in slalom_detected_vehicles:
                    is_slalom, slalom_conf = check_slalom(vehicle_trajectories[vehicle_id])
                    if is_slalom:
                        slalom_memory[vehicle_id] = slalom_memory.get(vehicle_id, 0) + 1
                        if slalom_memory[vehicle_id] == 3:
                            slalom_detected_vehicles.add(vehicle_id)
                            vehicle_events.append(tespit_olustur(global_frame_count / fps, "sofor_eylemi", "slalom", slalom_conf))
                
                if vehicle_id not in finalized_types:
                    if vehicle_frame_counts[vehicle_id] % 15 == 0 and w_vehicle > 150:
                        if vehicle_id not in vehicle_memory: vehicle_memory[vehicle_id] = []
                        if len(vehicle_memory[vehicle_id]) < 5:
                            expert_result = classifier_model(vehicle_roi, verbose=False)
                            type_idx = expert_result[0].probs.top1
                            type_conf = expert_result[0].probs.top1conf.item()
                            current_type = map_type(expert_result[0].names[type_idx])
                            if type_conf > 0.40:
                                vehicle_memory[vehicle_id].append((current_type, type_conf))
                    if vehicle_id in vehicle_memory and len(vehicle_memory[vehicle_id]) >= 5:
                        type_scores = {}
                        for t_type, t_conf in vehicle_memory[vehicle_id]:
                            type_scores[t_type] = type_scores.get(t_type, 0.0) + t_conf
                        final_type = max(type_scores, key=type_scores.get)
                        finalized_types[vehicle_id] = final_type
                        winning_confs = [item[1] for item in vehicle_memory[vehicle_id] if item[0] == final_type]
                        avg_conf = sum(winning_confs) / len(winning_confs)
                        if vehicle_id not in vehicle_confidences: vehicle_confidences[vehicle_id] = {}
                        vehicle_confidences[vehicle_id]['kasa'] = float(avg_conf)
                
                if vehicle_id not in finalized_colors:
                    if vehicle_frame_counts[vehicle_id] % 3 == 0:
                        color_result = color_model(vehicle_roi, verbose=False)
                        color_idx = color_result[0].probs.top1
                        color_conf = color_result[0].probs.top1conf.item()
                        current_color = map_color(color_result[0].names[color_idx])
                        if color_conf > 0.50:
                            if vehicle_id not in color_memory: color_memory[vehicle_id] = []
                            color_memory[vehicle_id].append((current_color, color_conf))
                    if vehicle_id in color_memory and len(color_memory[vehicle_id]) > 5:
                        colors_only = [item[0] for item in color_memory[vehicle_id]]
                        final_color = Counter(colors_only).most_common(1)[0][0]
                        finalized_colors[vehicle_id] = final_color
                        winning_confs = [item[1] for item in color_memory[vehicle_id] if item[0] == final_color]
                        avg_conf = sum(winning_confs) / len(winning_confs)
                        if vehicle_id not in vehicle_confidences: vehicle_confidences[vehicle_id] = {}
                        vehicle_confidences[vehicle_id]['renk'] = float(avg_conf)
                        del color_memory[vehicle_id]
                
                if vehicle_id not in plate_memory: plate_memory[vehicle_id] = {'votes': {}, 'frame_count': 0}
                plate_memory[vehicle_id]['frame_count'] += 1
                
                if vehicle_id not in finalized_plates:
                    if plate_memory[vehicle_id]['frame_count'] % 2 == 0:
                        plate_results = plate_model(vehicle_roi, conf=0.3, verbose=False)
                        for p_result in plate_results:
                            for p_box in p_result.boxes:
                                px1, py1, px2, py2 = map(int, p_box.xyxy[0])
                                plate_roi_crop = vehicle_roi[py1:py2, px1:px2]
                                if plate_roi_crop.size == 0 or plate_roi_crop.shape[1] < 50: continue
                                
                                enlarged_plate = warp_plate(plate_roi_crop)
                                character_results = character_model(enlarged_plate, conf=0.10, iou=0.50, verbose=False)
                                detected_letters = []
                                for c_result in character_results:
                                    for c_box in c_result.boxes:
                                        x1_char, y1_char, x2_char, y2_char = map(int, c_box.xyxy[0])
                                        char_class = c_result.names[int(c_box.cls)].upper()
                                        conf = float(c_box.conf[0])
                                        detected_letters.append((x1_char, char_class, conf))
                                if len(detected_letters) < 4: continue
                                detected_letters.sort(key=lambda x: x[0])
                                raw_text = "".join([letter[1] for letter in detected_letters])
                                clean_text = raw_text.replace("EUR", "").replace("BRASIL", "")
                                clean_text = correct_plate(clean_text)
                                average_conf = sum([letter[2] for letter in detected_letters]) / len(detected_letters)
                                if len(clean_text) >= 6 and PLATE_PATTERN.fullmatch(clean_text):
                                    plate_memory[vehicle_id]['votes'][clean_text] = plate_memory[vehicle_id]['votes'].get(clean_text, 0.0) + average_conf
                                    best_plate = max(plate_memory[vehicle_id]['votes'], key=plate_memory[vehicle_id]['votes'].get)
                                    current_score = plate_memory[vehicle_id]['votes'][best_plate]
                                    if current_score >= 2.0:
                                        finalized_plates[vehicle_id] = best_plate
                                        if vehicle_id not in vehicle_confidences: vehicle_confidences[vehicle_id] = {}
                                        vehicle_confidences[vehicle_id]['plaka'] = float(average_conf)

        # --- 3. ŞOFÖR EYLEMLERİ (predict.py) ---
        if global_frame_count % atlama == 0:
            sn = round(global_frame_count/fps, 1)
            bolge, kirp_x1, kirp_y1 = sofor_kirp(frame)
            surucu_var_kayit.append((sn, bolge is not None))
            
            # Kemer modeli için sadece arabayı kırp (En büyük arabayı al)
            araba_crop = frame
            if current_car_boxes:
                en_buyuk = max(current_car_boxes, key=lambda b: (b[2]-b[0])*(b[3]-b[1]))
                ax1, ay1, ax2, ay2 = en_buyuk
                pad_x, pad_y = int((ax2-ax1)*0.05), int((ay2-ay1)*0.05)
                p_ax1, p_ay1 = max(0, ax1 - pad_x), max(0, ay1 - pad_y)
                p_ax2, p_ay2 = min(frame.shape[1], ax2 + pad_x), min(frame.shape[0], ay2 + pad_y)
                araba_crop = frame[p_ay1:p_ay2, p_ax1:p_ax2]

            # --- SIGARA + TELEFON (Masaustu/Models K1-K16 mantigi) -- kendi arac/poz
            # bolgesini bagimsiz bulur, sofor_kirp()'in bolge'sine ihtiyac duymaz. ---
            en_arac_sigtel = en_buyuk if current_car_boxes else None
            kare_alani = frame.shape[0] * frame.shape[1]

            sig_a, sig_conf = sigara_isle(frame, en_arac_sigtel, kare_alani)
            if sig_a > 0:
                sigara_pencere.append((sn, sig_a))
            while sigara_pencere and sn - sigara_pencere[0][0] > SIGTEL_PENCERE_SN:
                sigara_pencere.popleft()
            sig_toplam = sum(x[1] for x in sigara_pencere)
            sig_guclu = sig_conf >= SIGTEL_GUCLU_CONF and sig_a >= SIGTEL_GUCLU_CONF * 0.7
            if (sig_guclu or sig_toplam >= SIGTEL_KANIT_ESIGI) and sn - sigara_son_olay > SIGTEL_SOGUMA_SN:
                vehicle_events.append(tespit_olustur(
                    sn, "sofor_eylemi", "sigara_icme", min(max(sig_conf, sig_toplam/2), 0.99)))
                sigara_son_olay = sn
                sigara_pencere.clear()

            tel_a, tel_conf, tel_alt, tel_kutu = telefon_isle(frame, en_arac_sigtel, kare_alani, telefon_onceki_kutu)
            telefon_onceki_kutu = tel_kutu if tel_a > 0 else None
            if tel_a > 0:
                telefon_pencere.append((sn, tel_a, tel_alt, tel_conf))
            while telefon_pencere and sn - telefon_pencere[0][0] > SIGTEL_PENCERE_SN:
                telefon_pencere.popleft()
            tel_toplam = sum(x[1] for x in telefon_pencere)
            tel_guclu = tel_conf >= SIGTEL_GUCLU_CONF and tel_a >= SIGTEL_GUCLU_CONF * 0.7
            tel_tepe = max([x[3] for x in telefon_pencere], default=0.0) >= TELEFON_TEPE_CONF
            if (tel_guclu or (tel_toplam >= SIGTEL_KANIT_ESIGI and tel_tepe)) and sn - telefon_son_olay > SIGTEL_SOGUMA_SN:
                # FTR semasinda gecerli tek etiket "telefonla_konusma" -- alt_etiket
                # (konusma/oynama) sadece dahili karar icindi, ikisi de bu etiketle raporlanir.
                vehicle_events.append(tespit_olustur(
                    sn, "sofor_eylemi", "telefonla_konusma", min(max(tel_conf, tel_toplam/2), 0.99)))
                telefon_son_olay = sn
                telefon_pencere.clear()

            if bolge is None:
                for ad in modeller:
                    if ad == "kemer": yolo_kayit[ad].append(None)
                    else: yolo_kayit[ad].append((sn, None))
                off_kayit.append((sn, None))
            else:
                rgb = cv2.cvtColor(bolge, cv2.COLOR_BGR2RGB)
                mp_img = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)
                yuz_sonuc = yuz_dedektor.detect(mp_img)

                for ad, model in modeller.items():
                    if ad == "kemer":
                        # Kemer modelini doğrudan şoför bölgesine (bolge) odaklayarak çalıştırıyoruz
                        res = model(bolge, conf=ESIK[ad], verbose=False)[0]
                        b_cls, b_conf = -1, 0.0
                        for k in res.boxes:
                            if float(k.conf) > b_conf:
                                b_conf, b_cls = float(k.conf), int(k.cls)
                        if b_cls != -1: yolo_kayit[ad].append((sn, b_cls, b_conf))
                        else: yolo_kayit[ad].append(None)
                    elif ad == "su":
                        g, kutu = su_bul(model, bolge, ESIK[ad], yuz_sonuc)
                        yolo_kayit[ad].append((sn, g if g>0 else None))
                        
                        if kutu is not None:
                            bx1, by1, bx2, by2 = kutu
                            # 3x büyütmeden geriye orijinal boyutlara dön
                            rx1 = int((bx1 / BUYUTME) + kirp_x1)
                            ry1 = int((by1 / BUYUTME) + kirp_y1)
                            rx2 = int((bx2 / BUYUTME) + kirp_x1)
                            ry2 = int((by2 / BUYUTME) + kirp_y1)
                            son_su_kutu = (rx1, ry1, rx2, ry2)
                            son_su_g = g
                            son_su_zamani = global_frame_count
                    elif ad == "esneme":
                        # HİBRİT KONTROL (test_esneme_hibrit.py mantığı): MAR (agiz aciklik
                        # orani, kisinin kendi son ~5sn'lik normaline gore) VEYA YOLO -- ikisinden
                        # biri onaylarsa esneme sayilir (el agzi kapatirsa MAR calismaz ama YOLO
                        # yine de yakalayabilir; YOLO kacirirsa MAR yakalayabilir).
                        g = yolo_bul(model, bolge, ESIK[ad], tek_sinif0=True)
                        yolo_onayi_var = g > 0

                        mar_onayi_var = False
                        if yuz_sonuc and yuz_sonuc.face_landmarks:
                            lm = yuz_sonuc.face_landmarks[0]
                            mar_degeri = abs(lm[ALT_DUDAK].y - lm[UST_DUDAK].y)
                            mar_kayit.append(mar_degeri)
                            if len(mar_kayit) > MAR_PENCERE:
                                mar_kayit.pop(0)
                            if len(mar_kayit) > 30:
                                taban = float(np.median(mar_kayit))
                                if taban < 1e-6: taban = 1e-6
                                oran = mar_degeri / taban
                                if oran >= ORAN_ESIK:
                                    mar_onayi_var = True

                        if yolo_onayi_var or mar_onayi_var:
                            esneme_g = g if yolo_onayi_var else 0.75
                            yolo_kayit[ad].append((sn, esneme_g))
                        else:
                            yolo_kayit[ad].append((sn, None))
                off_kayit.append((sn, bakinma_olc(bolge)))
                
        # --- 4. YOLCULAR (yolcu.pt + BoT-SORT ID takibi, test_yolcu.py'nin sofor
        # cozumleme/kilitleme mantigi -- ama rol ayrimi (on_koltuk/arka_koltuk_1/
        # arka_koltuk_2) predict.py'nin dikey-konum+boyut sezgisiyle, ID'ye kalici
        # baglanarak. Kilitlenen (2 ardisik islenen kare) koltuk ANINDA yazilir,
        # sofor JSON'a hic yazilmaz -- sadece sofor disi rolleri elemek icin kullanilir.) ---
        if global_frame_count % atlama_yolcu == 0:
            yolcu_islenen_kare_sirasi += 1
            en_arac = max(current_car_boxes, key=lambda b: (b[2]-b[0])*(b[3]-b[1])) if current_car_boxes else None
            if en_arac is not None:
                ax1, ay1, ax2, ay2 = en_arac
                ah = ay2 - ay1
                arac_orta = (ax1 + ax2) / 2
                arac_capraz = ((ax2-ax1)**2 + (ay2-ay1)**2) ** 0.5
                pad_x, pad_y = int((ax2-ax1)*YOLCU_ROI_PAD_ORAN), int((ay2-ay1)*YOLCU_ROI_PAD_ORAN)
                rx1, ry1 = max(0, ax1-pad_x), max(0, ay1-pad_y)
                rx2, ry2 = min(frame.shape[1], ax2+pad_x), min(frame.shape[0], ay2+pad_y)
                arac_roi = frame[ry1:ry2, rx1:rx2]

                if arac_roi.size > 0:
                    kisi_sonuc = yolcu_model.track(arac_roi, conf=YOLCU_KISI_ESIK, persist=True, verbose=False)[0]
                    ic_kisiler = []
                    if kisi_sonuc.boxes is not None:
                        for k in kisi_sonuc.boxes:
                            if k.id is None:
                                continue
                            kx1, ky1, kx2, ky2 = k.xyxy[0].tolist()
                            kx1, ky1, kx2, ky2 = kx1+rx1, ky1+ry1, kx2+rx1, ky2+ry1
                            ic_kisiler.append({
                                "id": int(k.id.item()), "kutu": (kx1, ky1, kx2, ky2),
                                "conf": float(k.conf), "merkez_x": (kx1+kx2)/2, "alt_y": ky2,
                                "alan": (kx2-kx1)*(ky2-ky1),
                            })

                    guvenilir_kisiler = [k for k in ic_kisiler if k["conf"] >= YOLCU_LOCK_MIN_CONF]

                    # --- SOFOR COZUMLEME (test_yolcu.py ile ayni) ---
                    sofor = None
                    if yolcu_sofor_id is not None:
                        sofor = next((b for b in guvenilir_kisiler if b["id"] == yolcu_sofor_id), None)
                        if sofor is None and yolcu_sofor_son_konum is not None:
                            adaylar = [b for b in guvenilir_kisiler if b["merkez_x"] > arac_orta]
                            if adaylar:
                                en_yakin = min(adaylar, key=lambda b: ((b["merkez_x"]-yolcu_sofor_son_konum[0])**2 + (b["alt_y"]-yolcu_sofor_son_konum[1])**2)**0.5)
                                d = ((en_yakin["merkez_x"]-yolcu_sofor_son_konum[0])**2 + (en_yakin["alt_y"]-yolcu_sofor_son_konum[1])**2)**0.5
                                if d <= arac_capraz * YOLCU_SOFOR_YENIDEN_KAZANIM_ORANI:
                                    sofor = en_yakin
                                    yolcu_sofor_id = sofor["id"]
                    elif guvenilir_kisiler:
                        sofor_adaylari = [b for b in guvenilir_kisiler if b["merkez_x"] > arac_orta]
                        if sofor_adaylari:
                            sofor = max(sofor_adaylari, key=lambda b: b["alan"])
                            yolcu_sofor_id = sofor["id"]

                    if sofor is not None:
                        yolcu_sofor_son_konum = (sofor["merkez_x"], sofor["alt_y"])

                    kalan = [b for b in guvenilir_kisiler if sofor is None or b["id"] != sofor["id"]]
                    if sofor is not None:
                        def _kesisim_orani(a, s):
                            x1, y1, x2, y2 = a; X1, Y1, X2, Y2 = s
                            ix1, iy1 = max(x1, X1), max(y1, Y1); ix2, iy2 = min(x2, X2), min(y2, Y2)
                            iw, ih = max(0, ix2-ix1), max(0, iy2-iy1)
                            alan = (x2-x1)*(y2-y1)
                            return (iw*ih)/alan if alan > 0 else 0.0
                        kalan = [b for b in kalan if _kesisim_orani(b["kutu"], sofor["kutu"]) < YOLCU_SOFOR_DUP_ORAN]

                    for b in kalan:
                        pid = b["id"]
                        if pid in yolcu_id_role:
                            koltuk = yolcu_id_role[pid]
                        else:
                            sofor_alani = sofor["alan"] if sofor is not None else b["alan"]
                            ust_oran = (b["alt_y"] - ay1) / ah if ah > 0 else 1.0
                            kucuk = b["alan"] < sofor_alani * 0.6
                            if ust_oran < 0.55 and kucuk:
                                koltuk = "arka_koltuk_1" if b["merkez_x"] < arac_orta else "arka_koltuk_2"
                            else:
                                koltuk = "on_koltuk"
                            yolcu_id_role[pid] = koltuk

                        onceki_kare = yolcu_ardisik_son_kare.get(pid)
                        if onceki_kare == yolcu_islenen_kare_sirasi - 1:
                            yolcu_ardisik_sayac[pid] = yolcu_ardisik_sayac.get(pid, 0) + 1
                        else:
                            yolcu_ardisik_sayac[pid] = 1
                        yolcu_ardisik_son_kare[pid] = yolcu_islenen_kare_sirasi

                        if yolcu_ardisik_sayac[pid] >= YOLCU_ARDISIK_GEREK and koltuk not in yolcu_kilitli_roller:
                            yolcu_kilitli_roller.add(koltuk)
                            vehicle_events.append(tespit_olustur(global_frame_count / fps, "yolcular", koltuk, b["conf"]))

        # VİDEO ÇİKTISI İÇİN KUTUYU ÇİZ (Atlama boşluklarında da görünmesi için)
        if son_su_kutu is not None and (global_frame_count - son_su_zamani) < (atlama * 3): # 3 işlem periyodu ekranda tut
            rx1, ry1, rx2, ry2 = son_su_kutu
            cv2.rectangle(frame, (rx1, ry1), (rx2, ry2), (0, 0, 255), 3)
            cv2.putText(frame, f"ONAY: su_icme {son_su_g:.2f}", (rx1, ry1-10), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 0, 255), 2)
            cv2.putText(frame, "PREDICT KILITLENDI!", (50, 50), cv2.FONT_HERSHEY_DUPLEX, 1.0, (0, 0, 255), 2)
            
        if out_video is not None:
            out_video.write(frame)

    cap.release()
    if out_video is not None:
        out_video.release()
    
    # === POST-PROCESSING (Şoför Eylemleri) ===
    # NOT: sigara/telefon artik CANLI olarak (kendi K6/K7 kanit penceresiyle) yukarida
    # vehicle_events'e yazildi -- burada tekrar islenmiyor.
    etiket_map = {"su": "su_icme", "esneme": "esneme"}
    kararlar = []
    for ad in ["su", "esneme"]:
        for (orta, tepe) in ardisik_seg(yolo_kayit[ad], ARDISIK_GEREK):
            kararlar.append((orta, "sofor_eylemi", etiket_map[ad], tepe))

    # === Yeni Kemer İhlali Mantığı (Çifte Doğrulama ve Ardışık 5 Kare) ===
    ihlal_zamani = None
    ortalama_guven = 0.0
    ardisik_kemer_yok = []
    kemer_var_sayaci = 0
    kemer_onaylandi = False

    # 1. ADIM: Video (veya periyot) boyunca model en az 2 kez "Kemer Var" dedi mi?
    for item in yolo_kayit["kemer"]:
        if item is not None:
            _, cls_id, _ = item
            if cls_id == 1:  # Sınıf 1: Kemer Var
                kemer_var_sayaci += 1
                if kemer_var_sayaci >= 2:
                    kemer_onaylandi = True
                    break
                
    # 2. ADIM: Eğer kemer varlığı onaylanmadıysa "Kemer Yok" sayısını kontrol et
    if not kemer_onaylandi:
        for item in yolo_kayit["kemer"]:
            if item is not None:
                sn, cls_id, conf = item
                if cls_id == 0:  # Sınıf 0: Kemer Yok
                    ardisik_kemer_yok.append((sn, conf))
                else:
                    ardisik_kemer_yok = [] # Kemer Var dendiyse sayacı sıfırla
            else:
                ardisik_kemer_yok = [] # Şoför/kemer tespit edilemediyse sayacı sıfırla
                
            # 3. ADIM: 5 kareyi bulduğumuz an ihlali yaz
            if len(ardisik_kemer_yok) >= 5:
                ihlal_zamani = ardisik_kemer_yok[0][0] # İhlalin ilk başladığı an
                ortalama_guven = sum(c for _, c in ardisik_kemer_yok) / len(ardisik_kemer_yok)
                break
                
        if ihlal_zamani is not None:
            kararlar.append((ihlal_zamani, "sofor_eylemi", "emniyet_kemeri_ihlali", round(ortalama_guven, 2)))

    for (et, orta, sure) in bakinma_seg([(s, o) for s, o in off_kayit if o is not None], dt):
        kararlar.append((orta, "sofor_eylemi", et, min(0.99, 0.5+sure/10)))

    # Çakışma Önleme (sigara/telefon artik canli yazildigi icin vehicle_events'ten de dahil edilir)
    bakinmalar = [k for k in kararlar if k[2] == "etrafa_bakinma"]
    digerleri = [k for k in kararlar if k[2] in ("sigara_icme", "su_icme")]
    digerleri += [(ev["zaman_saniye"], "sofor_eylemi", ev["etiket"])
                  for ev in vehicle_events
                  if ev["kategori"] == "sofor_eylemi" and ev["etiket"] in ("sigara_icme", "telefonla_konusma")]
    yeni_kararlar = [k for k in kararlar if k[2] != "etrafa_bakinma"]
    for b in bakinmalar:
        cakisiyor = False
        for d in digerleri:
            if abs(b[0] - d[0]) <= 1.5:
                cakisiyor = True; break
        if not cakisiyor: yeni_kararlar.append(b)
    kararlar = yeni_kararlar

    # 5-Saniye Kilit (Cooldown)
    kararlar.sort()
    son_zaman = {}
    for (sn, kat, et, guv) in kararlar:
        if et not in son_zaman or (sn - son_zaman[et]) >= 5.0:
            vehicle_events.append(tespit_olustur(sn, kat, et, guv))
            son_zaman[et] = sn

    # === Olayları Maksimum Adetle Sınırlama Filtresi ===
    filtered_events = []
    seen_counts = {}
    for ev in vehicle_events:
        etiket = ev["etiket"]
        
        # İçi/dışı olarak etiketlenmiş benzersiz olayların her biri maksimum 1 kez yazılır
        max_allowed = 1
            
        seen_counts[etiket] = seen_counts.get(etiket, 0) + 1
        if seen_counts[etiket] <= max_allowed:
            # Sonekleri temizle
            if etiket.startswith("teknocan_"): ev["etiket"] = "teknocan"
            if etiket.startswith("bilgisayar_"): ev["etiket"] = "bilgisayar"
            filtered_events.append(ev)
            
    vehicle_events = filtered_events

    # Yolcular artik CANLI olarak (kilitlendigi an) vehicle_events'e yazildi -- burada
    # ek bir post-processing adimina gerek yok.

    # === ARAÇ BİLGİSİ ===
    best_vid = None
    best_vid_score = -1
    for vid, plates in finalized_plates.items():
        if vid in finalized_types and vid in finalized_colors:
            c = vehicle_confidences.get(vid, {})
            score = c.get('kasa', 0) + c.get('renk', 0) + c.get('plaka', 0)
            if score > best_vid_score:
                best_vid_score = score
                best_vid = vid
                
    if best_vid is not None:
        c = vehicle_confidences.get(best_vid, {})
        ov_conf = (c.get('kasa', 0) + c.get('renk', 0) + c.get('plaka', 0)) / 3.0
        arac = arac_bilgisi_olustur(
            finalized_types[best_vid], 
            finalized_plates[best_vid], 
            finalized_colors[best_vid], 
            ov_conf
        )
    else:
        if finalized_types:
            v_t = list(finalized_types.values())[0]
            v_c = list(finalized_colors.values())[0] if finalized_colors else "beyaz"
            v_p = list(finalized_plates.values())[0] if finalized_plates else ""
            arac = arac_bilgisi_olustur(v_t, v_p, v_c, 0.50)
        else:
            arac = arac_bilgisi_olustur("sedan", "", "beyaz", 0.0)

    return sonuc_birlestir(video_name, arac, vehicle_events)