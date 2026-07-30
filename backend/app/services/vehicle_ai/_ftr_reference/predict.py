import cv2
import numpy as np
from ultralytics import YOLO
import re
from collections import Counter
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

bulucu = detector_model
poz = YOLO(os.path.join(WEIGHTS_DIR, "yolov8n-pose.pt"))
modeller = {
    "sigara":  YOLO(os.path.join(WEIGHTS_DIR, "sigara_v1.pt")),
    "telefon": YOLO(os.path.join(WEIGHTS_DIR, "telefon_temiz_v1.pt")),
    "su":      YOLO(os.path.join(WEIGHTS_DIR, "su_v2.pt")),
    "kemer":   YOLO(os.path.join(WEIGHTS_DIR, "kemer_v3.pt")),
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
ESIK = {"sigara": 0.45, "telefon": 0.45, "su": 0.45, "kemer": 0.50}
ARDISIK_GEREK = 2
KEMER_GEREK = 10
ORAN_ESIK = 2.0; PLATO_GEREK = 8; HAREKET_ESIK = 1.5
DONUK_OFFSET = 0.30; T_ARKAYA = 4.0; T_ETRAFA_MIN = 1.2
NOSE, LSHO, RSHO = 0, 5, 6
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
        return None
    kirpik = frame[y1:y2, x1:x2]
    if kirpik.size == 0: return None
    return cv2.resize(kirpik, None, fx=BUYUTME, fy=BUYUTME, interpolation=cv2.INTER_CUBIC)

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

def esneme_mar(bolge):
    rgb = cv2.cvtColor(bolge, cv2.COLOR_BGR2RGB)
    mp_img = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)
    res = yuz_dedektor.detect(mp_img)
    if not res.face_landmarks: return None
    return mar_hesapla(res.face_landmarks[0])

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
                seg.append(((varlik[i][0]+varlik[j][0])/2, tepe))
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

    atlama = max(1, int(round(fps/4)))
    atlama_yolcu = max(1, int(round(fps/2)))
    dt = atlama/fps
    yolo_kayit = {ad: [] for ad in modeller}
    mar_kayit = []
    off_kayit = []
    surucu_var_kayit = []

    gorulme = {}
    best_conf = {}

    while cap.isOpened():
        ret, frame = cap.read()
        if not ret:
            break
        global_frame_count += 1

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
            bolge = sofor_kirp(frame)
            surucu_var_kayit.append((sn, bolge is not None))
            if bolge is None:
                for ad in modeller: yolo_kayit[ad].append((sn, None))
                mar_kayit.append((sn, None)); off_kayit.append((sn, None))
            else:
                for ad, model in modeller.items():
                    g = yolo_bul(model, bolge, ESIK[ad], tek_sinif0=(ad=="telefon"))
                    yolo_kayit[ad].append((sn, g if g>0 else None))
                mar_kayit.append((sn, esneme_mar(bolge)))
                off_kayit.append((sn, bakinma_olc(bolge)))

        # --- 4. YOLCULAR (predict.py) ---
        if global_frame_count % atlama_yolcu == 0:
            sonuc = bulucu(frame, conf=0.05, verbose=False)[0]
            kisiler = []; en_arac = None; ea = 0.0
            for k in sonuc.boxes:
                sid = int(k.cls); g = float(k.conf); kutu = k.xyxy[0].tolist()
                if sid == 0 and g >= 0.05:
                    kisiler.append({"kutu": kutu, "conf": g})
                elif sid in (2, 7) and g > ea:
                    ea = g; en_arac = kutu
            if kisiler and en_arac:
                ax1, ay1, ax2, ay2 = en_arac
                arac_orta = (ax1 + ax2) / 2
                ah = ay2 - ay1
                ic_kisiler = []
                for k in kisiler:
                    kx1, ky1, kx2, ky2 = k["kutu"]
                    ix1, iy1 = max(kx1, ax1), max(ky1, ay1); ix2, iy2 = min(kx2, ax2), min(ky2, ay2)
                    iw, ih = max(0, ix2 - ix1), max(0, iy2 - iy1)
                    alan = (kx2 - kx1) * (ky2 - ky1)
                    oran = (iw * ih) / alan if alan > 0 else 0.0
                    if oran >= 0.15:
                        ic_kisiler.append({"kutu": k["kutu"], "conf": k["conf"], "merkez_x": (kx1 + kx2) / 2, "alt_y": ky2, "alan": alan})
                if ic_kisiler:
                    sofor_adaylari = [b for b in ic_kisiler if b["merkez_x"] > arac_orta]
                    sofor = max(sofor_adaylari, key=lambda b: b["alan"]) if sofor_adaylari else max(ic_kisiler, key=lambda b: b["alan"])
                    kalan = [b for b in ic_kisiler if b is not sofor]
                    arka_sayac = 0
                    for b in kalan:
                        ust_oran = (b["alt_y"] - ay1) / ah if ah > 0 else 1.0
                        kucuk = b["alan"] < sofor["alan"] * 0.6
                        if ust_oran < 0.55 and kucuk:
                            arka_sayac += 1
                            koltuk = f"arka_koltuk_{min(arka_sayac, 2)}"
                        else:
                            koltuk = "on_koltuk"
                        gorulme[koltuk] = gorulme.get(koltuk, 0) + 1
                        if b["conf"] > best_conf.get(koltuk, 0): best_conf[koltuk] = b["conf"]

    cap.release()

    # === POST-PROCESSING (Şoför Eylemleri) ===
    etiket_map = {"sigara": "sigara_icme", "telefon": "telefonla_konusma", "su": "su_icme"}
    kararlar = []
    for ad in ["sigara", "telefon", "su"]:
        for (orta, tepe) in ardisik_seg(yolo_kayit[ad], ARDISIK_GEREK):
            kararlar.append((orta, "sofor_eylemi", etiket_map[ad], tepe))

    kemer_var = set(s for s, g in yolo_kayit["kemer"] if g is not None)
    # Eğer tüm video boyunca kemer en az 3 karede net görünmüşse (false positive değilse),
    # kemer takılmış sayılır ve ihlal verilmez.
    if len(kemer_var) < 3:
        sofor_net = [s for s, var in surucu_var_kayit if var]
        ihlal = [(s, s in kemer_var) for s in sofor_net]
        i = 0; n = len(ihlal); ihlal_zamani = None
        while i < n:
            if not ihlal[i][1]:
                j = i
                while j+1 < n and not ihlal[j+1][1]: j += 1
                if (j-i+1) >= KEMER_GEREK:
                    ihlal_zamani = ihlal[i][0]  # ilk ihlal tespitinin zamanı
                    break
                i = j+1
            else: i += 1

        if ihlal_zamani is not None:
            kararlar.append((ihlal_zamani, "sofor_eylemi", "emniyet_kemeri_ihlali", 0.50))

    for (orta, tepe) in esneme_seg([(s, m) for s, m in mar_kayit if m is not None]):
        kararlar.append((orta, "sofor_eylemi", "esneme", min(0.99, 0.5+tepe/20)))
    for (et, orta, sure) in bakinma_seg([(s, o) for s, o in off_kayit if o is not None], dt):
        kararlar.append((orta, "sofor_eylemi", et, min(0.99, 0.5+sure/10)))

    # Çakışma Önleme
    bakinmalar = [k for k in kararlar if k[2] == "etrafa_bakinma"]
    digerleri = [k for k in kararlar if k[2] in ("sigara_icme", "su_icme")]
    yeni_kararlar = [k for k in kararlar if k[2] != "etrafa_bakinma"]
    for b in bakinmalar:
        cakisiyor = False
        for d in digerleri:
            if abs(b[0] - d[0]) <= 1.5:
                cakisiyor = True; break
        if not cakisiyor: yeni_kararlar.append(b)
    kararlar = yeni_kararlar

    # 3-Saniye Kilit (Cooldown)
    kararlar.sort()
    son_zaman = {}
    for (sn, kat, et, guv) in kararlar:
        if et not in son_zaman or (sn - son_zaman[et]) >= 3.0:
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

    # === POST-PROCESSING (Yolcular) ===
    for koltuk, count in gorulme.items():
        if count >= 1:
            vehicle_events.append(tespit_olustur(0.0, "yolcular", koltuk, best_conf[koltuk]))

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
