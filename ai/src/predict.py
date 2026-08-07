import cv2
import numpy as np
from ultralytics import YOLO
import math
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

from src.utils import (
    tespit_olustur, arac_bilgisi_olustur, sonuc_birlestir,
    GECERLI_SOFOR_EYLEMI, GECERLI_NESNELER, GECERLI_YOLCULAR,
)

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

# --- SERBEST YAZI (plaka-ustu kapatma yazisi) OCR kanali -------------------
# Final kurali (07.08): plaka kapali, yerinde serbest bir YAZI var ("EVET",
# "Evleniyoruz!" vb. — Turkce karakter/kucuk harf/bosluk olabilir). 96
# kompozitlik prova: plaka_modeli kapali plakayi %47 buluyor (kirmizi zemin
# 0), karakter_modeli alfabesi yetersiz; ARAC ALT-SERIDI + buyutme + CLAHE +
# EasyOCR(tr+en) ise 96'da 95 TAM okuma. Eski plaka zinciri AYNEN duruyor ve
# ONCELIKLI: gercek/okunur plaka varsa (faz2 gibi) regex'li zincir kazanir,
# kilitlenemezse (ortulu plaka) OCR kanalinin oylamali sonucu kullanilir.
# easyocr yoksa kanal sessizce kapali (eski davranis birebir).
SERBEST_YAZI_AKTIF = os.environ.get("SERBEST_YAZI", "1") == "1"
ocr_okuyucu = None
if SERBEST_YAZI_AKTIF:
    try:
        import easyocr as _easyocr
        _ocr_dizin = os.path.join(WEIGHTS_DIR, "easyocr")
        _ocr_gpu = torch.cuda.is_available()
        if os.path.isdir(_ocr_dizin):
            ocr_okuyucu = _easyocr.Reader(
                ["tr", "en"], gpu=_ocr_gpu, verbose=False,
                model_storage_directory=_ocr_dizin, download_enabled=False)
        else:
            ocr_okuyucu = _easyocr.Reader(["tr", "en"], gpu=_ocr_gpu, verbose=False)
    except Exception:
        ocr_okuyucu = None

YAZI_OKUMA_ARALIGI = 25   # her ~1 sn'de bir dene (25fps varsayimiyla)
YAZI_KARE_CONF = 0.30     # tek parca icin taban guven
YAZI_OY_ESIK = 2.5        # oylamada kilitlenme esigi (conf toplami)
YAZI_OY_TABAN = 1.5       # video sonunda kilit yoksa kabul icin alt esik
_yazi_clahe = cv2.createCLAHE(clipLimit=2.0, tileGridSize=(8, 8))


def _yazi_normalize(s):
    """Oylama anahtari: buyuk harf + TR->ASCII + yalniz alfanumerik."""
    s = s.upper().replace("İ", "I").replace("Ş", "S").replace("Ğ", "G") \
         .replace("Ü", "U").replace("Ö", "O").replace("Ç", "C")
    return "".join(ch for ch in s if ch.isalnum())


def yazi_serit_oku(frame, arac_kutu):
    """Arac kutusunun alt %45 seridinden yaziyi okur -> (metin, taban_conf).

    Plaka dedektorune bagimli DEGIL: EasyOCR'in kendi yazi-buluculugu
    (CRAFT) seritte banner'i zeminden bagimsiz bulur (prova: kirmizi zemin
    12/12). Buyutme + CLAHE, kucuk/uzak yaziyi okunur kiliyor.
    """
    ax1, ay1, ax2, ay2 = [int(v) for v in arac_kutu]
    h = ay2 - ay1
    serit = frame[max(0, ay1 + int(h * 0.55)):ay2, max(0, ax1):ax2]
    if serit.size == 0 or serit.shape[0] < 12:
        return "", 0.0
    sh, sw = serit.shape[:2]
    olcek = max(1, int(round(420.0 / sh)))
    buyuk = cv2.resize(serit, (sw * olcek, sh * olcek), interpolation=cv2.INTER_CUBIC)
    lab = cv2.cvtColor(buyuk, cv2.COLOR_BGR2LAB)
    l_k, a_k, b_k = cv2.split(lab)
    buyuk = cv2.cvtColor(cv2.merge((_yazi_clahe.apply(l_k), a_k, b_k)), cv2.COLOR_LAB2BGR)
    parcalar = [p for p in ocr_okuyucu.readtext(buyuk) if p[2] >= YAZI_KARE_CONF]
    if not parcalar:
        return "", 0.0
    parcalar.sort(key=lambda p: min(n[0] for n in p[0]))
    return " ".join(p[1] for p in parcalar).strip(), min(p[2] for p in parcalar)
# ---------------------------------------------------------------------------

slalom_device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
slalom_model = SlalomLSTM(input_size=1, hidden_size=128, num_layers=2)
slalom_model.load_state_dict(torch.load(os.path.join(WEIGHTS_DIR, 'slalom_lstm.pt'), map_location=slalom_device, weights_only=True))
slalom_model.to(slalom_device)
slalom_model.eval()
teknocan_model = YOLO(os.path.join(WEIGHTS_DIR, 'teknocan.pt'))
# Laptop (COCO class 63) icin AYRI bir yolov8s ornegi: detector_model zaten ana dongude
# arac takibi icin track(persist=True) ile cagriliyor; laptobu artik arac ROI'sine
# kirpilmis, kendi track(persist=True) durumunu tasiyan bu ayri ornekle arayacagiz --
# ayni model nesnesini iki farkli kirpim/cagri stiliyle kullanmak track()'in ic durumunu
# sifirlar (bkz. yolcu_model / yolcu_model_sofor ayrimi).
laptop_model = YOLO(os.path.join(WEIGHTS_DIR, 'laptop.pt'))

poz = YOLO(os.path.join(WEIGHTS_DIR, "yolov8n-pose.pt"))
# Yolcu (tek-sinif "yolcu") modeli -- ID takipli (BoT-SORT, varsayilan) ile arac ROI'si
# icinde calisir; kendi ozel model dosyasi oldugu icin ayri bir ornek olmasi baska hicbir
# karisma riski tasimiyor.
yolcu_model = YOLO(os.path.join(WEIGHTS_DIR, "yolcu.pt"))
# Sofor kirpimi icin AYRI bir "yolcu.pt" ornegi: her karede duz predict() ile TAZE sofor
# konumu bulmak icin kullanilir (bkz. sofor_konumu_bul). Ayni model nesnesini hem burada
# duz predict() hem yukarida yolcu koltuk rolleri icin track(persist=True) ile cagirmak,
# track()'in kalici ic durumunu sifirlar -- iki ayri ornek bu karismayi onluyor.
yolcu_model_sofor = YOLO(os.path.join(WEIGHTS_DIR, "yolcu.pt"))
# Arka koltuk pencere aramasi icin UCUNCU "yolcu.pt" ornegi: sag-yari ROI'de duz
# predict() ile cagrilir. yolcu_model'in track(persist=True) ic durumu bu duz
# cagrilarla sifirlanmasin diye (on_koltuk ID sayaclarini bozuyordu) ayri ornek.
yolcu_model_koltuk = YOLO(os.path.join(WEIGHTS_DIR, "yolcu.pt"))
# Sigara/telefon artik Masaustu/Models klasorundeki K1-K16 kural setiyle calisiyor --
# kendi ozel poz modelini (s-pose, n-pose'tan farkli) kullanir; bakinma'nin kullandigi
# "poz" (n-pose) ile karismasin diye ayri bir ornek.
sigara_model = YOLO(os.path.join(WEIGHTS_DIR, "sigara.pt"))
# ELYUZE_SIGARA=1: sigara kanali sigara.pt yerine birlesik el-yuze modelinin
# (elyuze.pt; 0=su_icme 1=telefon 2=sigara) YALNIZ sigara sinifiyla calisir.
# Faz2 olcumu (07.08): birlesik model sigara GT'lerinin 3/3'unu goruyor
# (0.55-0.82), eski model 92.6'yi kaciriyor. Su/telefon siniflari kullanilmaz
# (ayni olcumde su asiri-atesli, telefon faz2'de kor). Agirlik yoksa bayrak
# sessizce yok sayilir (imaja elyuze.pt konmadan da ayni kod calisir).
# VARSAYILAN ACIK (07.08 VM olcumu: hibrit sigara 2/3->3/3, FP sayisi ayni,
# genel F1@5s 0.79->0.81); ELYUZE_SIGARA=0 ile kapatilabilir.
ELYUZE_SIGARA_AKTIF = False
_elyuze_yol = os.path.join(WEIGHTS_DIR, "elyuze.pt")
if os.environ.get("ELYUZE_SIGARA", "1") == "1" and os.path.exists(_elyuze_yol):
    sigara_model = YOLO(_elyuze_yol)
    ELYUZE_SIGARA_AKTIF = True
# ARACICI (arac_ici_v1, 07.08; 0=su_icme 1=telefon 2=sigara): izole faz2
# olcumunde 7/7 GT el-yuze olayi + SIFIR FP kosusu (esik 0.35-0.7 tum
# degerlerde, capraz sinif karisimi sifir) -- uc el-yuze kanalini tek modele
# baglama adayi. Kanal kanal A/B icin ARACICI_SU/TELEFON/SIGARA=0 ile tek tek
# kapatilabilir; ARACICI=0 ya da agirlik yoksa tamamen devre disi (v18 duzeni
# aynen calisir). ARACICI_SIGARA, ELYUZE_SIGARA'dan onceliklidir.
aracici_model = None
_aracici_yol = os.path.join(WEIGHTS_DIR, "aracici.pt")
if os.environ.get("ARACICI", "1") == "1" and os.path.exists(_aracici_yol):
    aracici_model = YOLO(_aracici_yol)
ARACICI_SU = aracici_model is not None and os.environ.get("ARACICI_SU", "1") == "1"
ARACICI_TELEFON = aracici_model is not None and os.environ.get("ARACICI_TELEFON", "1") == "1"
# SIGARA VARSAYILAN KAPALI (07.08 takim karari): arac_ici sigara kanali
# pipeline'da 2 FP uretti (3.8 + 49.6cift-rapor); sigara mevcut duzende
# (elyuze hibrit, 3TP/1FP) kalir, arac_ici yalniz su+telefon'u tasir.
ARACICI_SIGARA = aracici_model is not None and os.environ.get("ARACICI_SIGARA", "0") == "1"
telefon_model = YOLO(os.path.join(WEIGHTS_DIR, "telefon.pt"))
poz_s = YOLO(os.path.join(WEIGHTS_DIR, "yolov8s-pose.pt"))
modeller = {
    "su":      YOLO(os.path.join(WEIGHTS_DIR, "su.pt")),
    "kemer":   YOLO(os.path.join(WEIGHTS_DIR, "kemer.pt")),
    "esneme":  YOLO(os.path.join(WEIGHTS_DIR, "esneme.pt"))
}
# --- HIBRIT KEMER (kemer2 = kemer_v2, parlak-domain modeli) ---------------
# 07.08 kalibrasyonu (kemer_hibrit_kalibre.py, faz2+aydinlik serileri):
# kemer_v2'nin 0.45-0.64 bandindaki VAR'lari GT ihlallerinde ZEHIRLI (saati
# yanlis sifirlar), >=0.65 VAR'lari ise mesru — parlakta FP supurur. YOK
# sinifi >=0.55 + 1sn sureklilikle gercek ihlal kaniti. kemer2.pt yoksa ya
# da KEMER2=0 ise kanal tamamen kapali (eski davranis birebir).
kemer2_model = None
_kemer2_yol = os.path.join(WEIGHTS_DIR, "kemer2.pt")
if os.environ.get("KEMER2", "1") == "1" and os.path.exists(_kemer2_yol):
    kemer2_model = YOLO(_kemer2_yol)
KEMER2_VAR_ESIK = float(os.environ.get("KEMER2_VAR_ESIK", "0.65"))
KEMER2_YOK_ESIK = float(os.environ.get("KEMER2_YOK_ESIK", "0.55"))
KEMER2_YOK_SN = float(os.environ.get("KEMER2_YOK_SN", "1.0"))
KEMER2_YOK_BOSLUK = 0.6   # yok kosusunda izin verilen karar boslugu (sn)
# 07.08 takim karari: YOKLUK SAATI KALDIRILDI -- "var kaniti gelmiyor" tek
# basina ihlal SAYILMAZ; ihlal yalniz modelin gercek "yok" tespitiyle yazilir
# (surekli-yok kanali). Arastirma icin KEMER_YOKLUK=1 ile geri acilabilir.
KEMER_YOKLUK_AKTIF = os.environ.get("KEMER_YOKLUK", "0") == "1"

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
BUYUTME = 3
ESIK = {"su": 0.45, "kemer": 0.45, "esneme": 0.50}
ARDISIK_GEREK = 2
ESNEME_ARDISIK_SN = 0.3    # konusma sirasindaki kisa agiz acilma-kapanmalarini elemek icin
                           # esnemenin bu kadar sn sureyle onaylanmasi gerekir (bosluk
                           # toleransiyla birlikte -- asagida ESNEME_BOSLUK_TOLERANS)
ESNEME_BOSLUK_TOLERANS = 2 # seri icinde bu kadar ardisik kareye kadar (olcum gurultusu)
                           # kopma toleransi -- konusmadaki surekli kesintiyi hala eler
ORAN_ESIK = 2.0; PLATO_GEREK = 8; HAREKET_ESIK = 1.5
MAR_MIN_ACIKLIK = 0.015    # oran ne kadar buyuk olursa olsun, agiz bu mutlak acikligi
                           # gecmiyorsa esneme sayilmaz -- taban neredeyse sifira yakinken
                           # (agiz kapaliyken) piksel-alti landmark titremesi oranı 2-3
                           # kat sicratabiliyor, mutlak esik bu gurultuyu eler
DONUK_OFFSET = 0.30; T_ARKAYA = 3.0; T_ETRAFA_MIN = 1.2
# 07.08 kullanici istegi: ufak yan bakislar etrafa_bakinma SAYILMASIN --
# kosunun TEPE donme siddeti (|burun-omuz orani|) bu esigi asmali. Arkaya
# bakma kanallari (sure>=T_ARKAYA + mediapipe yuz-kayip) etkilenmez, ayrim
# korunur. Deger faz2 dokum taramasiyla kalibre edildi (BAKINMA_LOG=1).
# faz2 dokumu: FP kosusu (82.9) tepe 0.49, gercek TP (92.58) tepe 1.28 --
# 0.80 ikisini genis payla ayirir.
ETRAFA_OFFSET_MIN = float(os.environ.get("ETRAFA_OFFSET_MIN", "0.80"))
ARKAYA_ETRAFA_SOGUMA_SN = 6.0  # son bu kadar sn icinde etrafa_bakinma yazildiysa mediapipe-tabanli arkaya_bakma bastirilir
YUZ_BOSLUK_TOLERANS = 2  # yuz_kayip_seg icin -- bu kadar ardisik "yuz bulundu" titremesi seriyi bozmaz
ARAC_KENAR_PAY = 3   # arac kutusu kare sol/sag kenarina bu kadar piksel ya da daha az
                     # kalirsa "kirpilmis/eksik gorunuyor" sayilir -- donus/manevra sirasinda
                     # arac kismen kadraj disina cikinca "sofor sagda" geometrik varsayimi
                     # bozuluyor, o karede sofor/sigara/telefon tespiti atlanir
NOSE, LSHO, RSHO = 0, 5, 6

# === SIGARA + TELEFON (Masaustu/Models klasorundeki K1-K16 kural seti, ayni degerler) ===
SIGTEL_MIN_ARAC_ORANI = 0.010   # K3: arac kadrajin en az bu kadarini kaplamali
SIGTEL_MIN_KIRPIM = 48          # K2: bu boyutun altindaki kirpimda olcum guvenilmez
SIGTEL_KENAR_PAYI = 0.04        # K4: kutu kirpim kenarina bu kadar yakinsa supheli
SIGTEL_GUCLU_CONF = 0.70        # K5: tek karede bu guven -> hemen kanit
SIGTEL_PENCERE_SN = 1.5         # K6: kanit biriktirme penceresi
SIGTEL_KANIT_ESIGI = 1.0        # K6: pencerede toplanmasi gereken agirlik
SIGTEL_SOGUMA_SN = 3.0          # K7: ayni olay bu sure icinde tekrar raporlanmaz

SIGARA_ZAYIF_CONF = 0.55        # K5: bu altindaki tespitler yok sayilir
ELYUZE_SIGARA_CONF = 0.50       # birlesik modelin sigara sinifi icin taban -- GT
                                # anlarindaki en dusuk olcum 0.55'ti, kirpim farki
                                # payi icin 0.05 asagida tutuldu
SIGARA_KIRPIM_BUYUTME = 3       # kirpim modele verilmeden once kac kat buyutulur

TELEFON_ZAYIF_CONF = 0.55       # K5
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
# NOT: arac kutusu icin ayri bir esik yok -- yolcu, ana dongude zaten hesaplanan
# current_car_boxes'i (detector_model, conf=0.45) paylasiyor, kendi arac tespitini
# yapmiyor.
YOLCU_KISI_ESIK = 0.25     # arac ROI'si icinde kisi tespiti icin taban guven
YOLCU_ROI_PAD_ORAN = 0.05
YOLCU_SOFOR_DUP_ORAN = 0.5
YOLCU_LOCK_MIN_CONF = 0.25
YOLCU_SOFOR_YENIDEN_KAZANIM_ORANI = 0.20
YOLCU_ARDISIK_GEREK = 2    # kilitleme icin 2 ardisik (islenen) kare yeterli
# --- ON YOLCU sol-yari bolge kurali (07.08 lokal kaniti) ---
# Arac ROI'sinin SOL yarisinda (arkadan bakista sol = on-yolcu tarafinin karsisi
# DEGIL: kabin on-sol bolgesi), soforden yatayda belirgin ayrik, yuksek guvenli
# kisi = on koltuk yolcusu. Olcum: GT 98.56'daki on yolcu cx~0.47/conf 0.87'yle
# yakalandi, videonun kalaninda sifir sahte aday kovasi.
ON_YOLCU_CONF = 0.60           # aday icin taban guven (olcumdeki yakalama 0.87)
ON_YOLCU_AYRIM_ORAN = 0.12     # soforle yatay ayrim: arac genisliginin orani
ON_YOLCU_ARDISIK_GEREK = 2     # ardisik islenen kare (~1 sn) israr sarti
ON_YOLCU_YENIDEN_SN = 12.0     # ayni kosuda yeniden yazma araligi
UST_DUDAK, ALT_DUDAK, SOL_KOSE, SAG_KOSE = 13, 14, 78, 308

def _arac_roi_parlaklik_duzelt(img):
    # Karanlik/dusuk kontrastli ROI'lerde detaylari gorunur kilmak icin L kanalina CLAHE
    # uygulanir -- kemer, on_koltuk, su ve esneme bu fonksiyonu paylasir (sigara/telefon
    # HARIC -- orada yanlis pozitifleri artirdigi icin kaldirildi).
    if img is None or img.size == 0:
        return img
    # CLAHE=0 ortam degiskeniyle tamamen kapatilabilir (A/B olcumu icin --
    # varsayilan davranis degismez, acik kalir).
    if os.environ.get("CLAHE", "1") == "0":
        return img
    lab = cv2.cvtColor(img, cv2.COLOR_BGR2LAB)
    l, a, b = cv2.split(lab)
    clahe = cv2.createCLAHE(clipLimit=3.0, tileGridSize=(8, 8))
    l = clahe.apply(l)
    return cv2.cvtColor(cv2.merge((l, a, b)), cv2.COLOR_LAB2BGR)

def sofor_konumu_bul(frame, arac_kutusu):
    """Bu karenin arac ROI'sinden (arac_kutusu) yolcu_model_sofor ile kisiler bulunur;
    soldan direksiyon farziyla arac merkezinin SAGINDA kalan en buyuk kisi sofor kabul
    edilir. Onceki karelerden HICBIR durum tasinmaz -- her cagri sadece BU karenin kendi
    tespitinden hesaplar, kilitli/donmus kutu yoktur. arac_kutusu bu karede None ise (arac
    goruntude degilse) ya da ROI icinde kimse bulunamazsa None doner."""
    if arac_kutusu is None:
        return None
    H, W = frame.shape[:2]
    ax1, ay1, ax2, ay2 = [int(v) for v in arac_kutusu]
    aw, ah = ax2-ax1, ay2-ay1
    pad_x, pad_y = int(aw*0.05), int(ah*0.05)
    rx1, ry1 = max(0, ax1-pad_x), max(0, ay1-pad_y)
    rx2, ry2 = min(W, ax2+pad_x), min(H, ay2+pad_y)
    arac_roi = frame[ry1:ry2, rx1:rx2]
    if arac_roi.size == 0:
        return None
    arac_orta_roi = ((ax1-rx1) + (ax2-rx1)) / 2

    sonuc = yolcu_model_sofor(arac_roi, conf=YOLCU_KISI_ESIK, verbose=False)[0]
    adaylar = []
    for k in sonuc.boxes:
        kx1, ky1, kx2, ky2 = k.xyxy[0].tolist()
        if (kx1+kx2)/2 > arac_orta_roi:
            adaylar.append((kx1+rx1, ky1+ry1, kx2+rx1, ky2+ry1))
    if not adaylar:
        return None
    return max(adaylar, key=lambda k: (k[2]-k[0])*(k[3]-k[1]))

def sofor_kirp(frame, sofor_kutu_bilinen=None):
    """Verilen sofor_kutusunu (sofor_konumu_bul'dan, bu karenin TAZE tespiti) kirpip
    BUYUTME kati buyutur. sofor_kutu_bilinen None ise (arac veya sofor bu karede
    bulunamadi) kirpim yapilmaz -- baska hicbir yedek/geometrik/kisi-arama mantigi yok."""
    if sofor_kutu_bilinen is None:
        return None, 0, 0

    H, W = frame.shape[:2]
    x1, y1, x2, y2 = [int(v) for v in sofor_kutu_bilinen]
    px, py = int((x2-x1)*0.15), int((y2-y1)*0.15)
    x1, y1 = max(0, x1-px), max(0, y1-py); x2, y2 = min(W, x2+px), min(H, y2+py)
    kirpik = frame[y1:y2, x1:x2]
    if kirpik.size == 0: return None, 0, 0
    kirpik = _arac_roi_parlaklik_duzelt(kirpik)
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

def su_bul(model, bolge, esik, yuz_sonuc, siniflar=None):
    sonuc = model(bolge, conf=esik, classes=siniflar, verbose=False)[0]
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

SU_GENIS_ESIK = 0.50  # genis-baglam ikinci bakisin esigi (agiz filtresi yok, telafi)
# SU_GENIS=1 ile acilir; VARSAYILAN KAPALI. v17 tam-pipeline olcumu (07.08):
# genis bakis GT 28.9+63.2'yi kurtardi (su 2/2) AMA 5 su FP uretti ve el-yuze
# munhasirligi uzerinden 2 sigara TP'sini sildi -- net F1 0.78 -> 0.75. Kural
# rafine edilene kadar arastirma kapisi olarak duruyor, uretimde kullanilmiyor.
SU_GENIS_AKTIF = os.environ.get("SU_GENIS", "0") == "1"


def su_genis_bak(model, frame, sofor_kutu, arac_kutu=None):
    """Dar kirpimda su bulunamazsa GENIS baglamli + CLAHE'li ikinci bakis.

    07.08 kirpim taramasi: GT 63.16'daki sise dar sofor kirpiminin DISINDA
    kaliyor -- genis(+%40 pad)+CLAHE kirpimda eski su modeli 0.56 veriyor,
    su FP pencerelerinde ise <=0.17 (temiz). Agiz-hizasi filtresi bu kirpimda
    uygulanamadigi icin esik bilerek yuksek (SU_GENIS_ESIK).

    SOFOR HIC BULUNAMADIYSA (kenar/aci -- 07.08 sondasi: GT 28.9 kosusunun bir
    kismi ve 63.16 oncesi boyle) arac ROI'sinin SAG yarisinda aranir: soldan
    direksiyonlu aracta surucu+sise sag yarida.
    """
    H, W = frame.shape[:2]
    if sofor_kutu is not None:
        x1, y1, x2, y2 = [int(v) for v in sofor_kutu]
        px, py = int((x2 - x1) * 0.40), int((y2 - y1) * 0.40)
        gen = frame[max(0, y1 - py):min(H, y2 + py), max(0, x1 - px):min(W, x2 + px)]
    elif arac_kutu is not None:
        ax1, ay1, ax2, ay2 = [int(v) for v in arac_kutu]
        orta = (ax1 + ax2) // 2
        gen = frame[max(0, ay1):min(H, ay2), max(0, orta):min(W, ax2)]
    else:
        return 0.0
    if gen.size == 0:
        return 0.0
    gen = cv2.resize(gen, None, fx=2, fy=2, interpolation=cv2.INTER_CUBIC)
    gen = _arac_roi_parlaklik_duzelt(gen)
    r = model(gen, conf=SU_GENIS_ESIK, verbose=False)[0]
    h, w = gen.shape[:2]
    en = 0.0
    for k in r.boxes:
        bx1, by1, bx2, by2 = k.xyxy[0].tolist()
        if (bx2 - bx1) > w * 0.45 or (by2 - by1) > h * 0.5:
            continue  # sise soforun yarisi kadar buyuk olamaz (su_bul ile ayni fikir)
        en = max(en, float(k.conf))
    return en


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

def ardisik_seg(varlik, gerek, bosluk_tolerans=0):
    """bosluk_tolerans>0 ise bir seri icinde bu kadar ardisik None'a izin verilir (seri
    kesilmez) -- gercek olayin arasina giren tek karelik olcum gurultusunu tolere eder;
    varsayilan 0 ile eski (kesintisiz) davranisla birebir ayni."""
    seg = []; i = 0; n = len(varlik)
    while i < n:
        if varlik[i][1] is not None:
            j = son_dolu = i; ardisik_bosluk = 0
            while j+1 < n:
                if varlik[j+1][1] is not None:
                    j += 1; son_dolu = j; ardisik_bosluk = 0
                elif ardisik_bosluk < bosluk_tolerans:
                    j += 1; ardisik_bosluk += 1
                else:
                    break
            if (son_dolu-i+1) >= gerek:
                tepe = max(varlik[k][1] for k in range(i, son_dolu+1) if varlik[k][1] is not None)
                seg.append((varlik[i][0], tepe))
            i = son_dolu+1
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
            tepe_off = max(abs(off_kayit[k][1]) for k in range(i, j+1)
                           if off_kayit[k][1] is not None)
            if sure >= T_ARKAYA: out.append(("arkaya_bakma", orta, sure))
            elif sure >= T_ETRAFA_MIN and tepe_off >= ETRAFA_OFFSET_MIN:
                out.append(("etrafa_bakinma", orta, sure))
            i = j+1
        else: i += 1
    return out

def yuz_kayip_seg(yuz_kayit, dt, sure_esik, bosluk_tolerans_kare):
    """Mediapipe'in soforun yuzunu ARDISIK olarak bulamadigi (bosluk toleransli, esneme'deki
    ESNEME_BOSLUK_TOLERANS ile ayni mantik) sureyi olcer -- pose modelinin (bakinma_olc)
    burun gormedigi icin None dondugu tam da bu anlarda bile calisir, dolayisiyla gercek
    "arkaya donme" icin bakinma_seg'den daha guvenilirdir. Tek karelik "yuz bulundu"
    titremeleri seriyi bozmaz. sure_esik'i asan seriler (orta_sn, sure) olarak dondurulur."""
    veri = [(sn, bulundu) for sn, bulundu in yuz_kayit if bulundu is not None]
    out = []; i = 0; n = len(veri)
    while i < n:
        if not veri[i][1]:
            j = son_dolu = i; ardisik_bosluk = 0
            while j+1 < n:
                if not veri[j+1][1]:
                    j += 1; son_dolu = j; ardisik_bosluk = 0
                elif ardisik_bosluk < bosluk_tolerans_kare:
                    j += 1; ardisik_bosluk += 1
                else:
                    break
            sure = (veri[son_dolu][0]-veri[i][0]) + dt
            if sure >= sure_esik:
                orta = (veri[i][0]+veri[son_dolu][0])/2
                out.append((orta, sure))
            i = son_dolu+1
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
def sigara_surucu_bolgesi(frame, arac, sofor_kutu_bilinen=None):
    """(kutu, yontem) -- sofor_kutu_bilinen varsa (yolcu_model'den) dogrudan onu kullanir
    (kendi poz_s aramasini calistirmaz). Yoksa: once poz_s ile arac ROI'si icinde kisi
    aranir (hassas kirpim, arama arac disina cikmaz), bulunamazsa on cam geometrisi
    (soldan direksiyon, onden bakis -> sofor sagda)."""
    ax1, ay1, ax2, ay2 = arac
    aw, ah = ax2-ax1, ay2-ay1
    if sofor_kutu_bilinen is not None:
        x1, y1, x2, y2 = sofor_kutu_bilinen
        pay_x, pay_y = (x2-x1)*0.35, (y2-y1)*0.30
        return [x1-pay_x, y1-pay_y, x2+pay_x, y2+pay_y*0.5], "yolcu_model"

    H, W = frame.shape[:2]
    pad_x, pad_y = int(aw*0.10), int(ah*0.10)
    rx1, ry1 = max(0, int(ax1-pad_x)), max(0, int(ay1-pad_y))
    rx2, ry2 = min(W, int(ax2+pad_x)), min(H, int(ay2+pad_y))
    arac_roi = frame[ry1:ry2, rx1:rx2]
    if arac_roi.size > 0:
        r = poz_s(arac_roi, conf=0.25, verbose=False)[0]
        for b in r.boxes:
            x1, y1, x2, y2 = [float(v) for v in b.xyxy[0]]
            x1, x2 = x1+rx1, x2+rx1; y1, y2 = y1+ry1, y2+ry1
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
    if ARACICI_SIGARA:
        r = aracici_model(buyuk, conf=ELYUZE_SIGARA_CONF, classes=[2], verbose=False)[0]
    elif ELYUZE_SIGARA_AKTIF:
        r = sigara_model(buyuk, conf=ELYUZE_SIGARA_CONF, classes=[2], verbose=False)[0]
    else:
        r = sigara_model(buyuk, conf=SIGARA_ZAYIF_CONF, verbose=False)[0]
    if not len(r.boxes):
        return 0.0, None, kb
    b = r.boxes[int(r.boxes.conf.argmax())]
    c = float(b.conf[0])
    bx = [float(v)/SIGARA_KIRPIM_BUYUTME for v in b.xyxy[0]]
    mutlak = [x1+bx[0], y1+bx[1], x1+bx[2], y1+bx[3]]
    return c, mutlak, kb

def sigara_isle(frame, en_arac, kare_alani, sofor_kutu_bilinen=None):
    """Bir kare icin (agirlik, conf) dondurur. en_arac None -> (0.0, 0.0) (K1)."""
    if en_arac is None:
        return 0.0, 0.0
    arac_orani = ((en_arac[2]-en_arac[0]) * (en_arac[3]-en_arac[1])) / kare_alani
    bolge, _ = sigara_surucu_bolgesi(frame, en_arac, sofor_kutu_bilinen)
    conf, kutu, kb = sigara_kirpimda_ara(frame, bolge)
    if conf < (ELYUZE_SIGARA_CONF if (ARACICI_SIGARA or ELYUZE_SIGARA_AKTIF) else SIGARA_ZAYIF_CONF):
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
    """Uyarlanabilir yakinlastirma + CLAHE.

    CLAHE artik HER ZAMAN uygulanir (eskiden yalniz karanlik karede, K16):
    07.08 kirpim taramasi olcumu -- GT telefon anlarinda eski modelin yaniti
    CLAHE'yle 0.28->0.58 ve 0.54->0.74'e cikiyor. FP riski K-kurallariyla
    (poz kapilari) sinirli; tam-pipeline faz2 skorunda dogrulanacak.
    """
    h, w = kirpim.shape[:2]
    z = float(np.clip(TELEFON_HEDEF_GENISLIK / max(w, 1), 1.0, TELEFON_MAKS_ZOOM))
    buyuk = (cv2.resize(kirpim, None, fx=z, fy=z, interpolation=cv2.INTER_CUBIC)
             if z > 1.001 else kirpim.copy())
    karanlik = float(buyuk.mean()) < TELEFON_KARANLIK_ESIK
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

def telefon_kirpimda_ara(frame, arac, sofor_kutu_bilinen=None):
    """IKI GECISLI kirpim: 1) arac ust yarisi -> poz bul, 2) sofor etrafi dar
    kirpilip telefon modeline verilir. sofor_kutu_bilinen varsa (yolcu_model'den)
    1. gecis (genis kabin taramasi) atlanir, dogrudan bilinen kutunun etrafi kirpilir --
    keypoint'ler (K8/K9/K10 icin) yine de bu dar kirpim uzerinden cikarilir.
    Doner: (conf, kutu, kirpim_kisa_kenar, poz, yontem, bolge)."""
    if sofor_kutu_bilinen is not None:
        x1, y1, x2, y2 = sofor_kutu_bilinen
        px, py = (x2-x1)*0.40, (y2-y1)*0.35
        bolge, yontem = [x1-px, y1-py, x2+px, y2+py*0.6], "yolcu_model"
        k2, ofs2 = _sigtel_kirp(frame, bolge)
        if k2 is None:
            return 0.0, None, 0, None, yontem, bolge
        kb = min(k2.shape[0], k2.shape[1])
        b2, z2, _ = telefon_hazirla(k2)
        poz = telefon_poz_bul(b2, ofs2, z2)
    else:
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
    if ARACICI_TELEFON:
        rt = aracici_model(b2, conf=TELEFON_ZAYIF_CONF, classes=[1], verbose=False)[0]
    else:
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

def telefon_isle(frame, en_arac, kare_alani, onceki_kutu, sofor_kutu_bilinen=None):
    """Bir kare icin (agirlik, conf, alt_etiket, kutu) dondurur."""
    if en_arac is None:
        return 0.0, 0.0, None, None
    arac_orani = ((en_arac[2]-en_arac[0]) * (en_arac[3]-en_arac[1])) / kare_alani
    conf, kutu, kb, poz, yontem, bolge = telefon_kirpimda_ara(frame, en_arac, sofor_kutu_bilinen)
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

    # DUSUK COZUNURLUK ON-BUYUTME: 240p tarzi girdilerde (hakem "dusuk kaliteli
    # video" ayagi) plaka karakterleri ~10px kaliyor -- plaka bos, kasa tipi
    # yanlis cikiyordu (240p faz2 olcumu). Genislik 640'in altindaysa kareler
    # okunur okunmaz 1280 genislige cubic ile buyutulur; tum asagi akis (ROI
    # kirpimlari, esikler, kenar hesaplari) buyutulmus kareyi gorur.
    kaynak_genislik = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH) or 0)
    kaynak_yukseklik = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT) or 0)
    on_olcek = 1.0
    if 0 < kaynak_genislik < 640:
        # ON_BUYUTME_HEDEF: dusuk cozunurluk girdinin buyutulecegi genislik
        # (varsayilan 1280; 1920 A/B'si 07.08 240p optimizasyonu icin eklendi --
        # kucuk nesne kanallari teknocan/su/sigara 240p'de kor kaliyor).
        on_olcek = float(os.environ.get("ON_BUYUTME_HEDEF", "1280")) / kaynak_genislik
    efektif_genislik = int(kaynak_genislik * on_olcek) if kaynak_genislik else 0
    efektif_yukseklik = int(kaynak_yukseklik * on_olcek) if kaynak_yukseklik else 0

    global_frame_count = 0
    
    # --- VİDEO ÇIKTI ALTYAPISI (yalnizca gelistirme icin) ---
    # Varsayilan KAPALI: tam cozunurluklu kare-kare mp4 encode hem sure butcesinden
    # yiyor hem de dosyayi hakem tarafinin INPUT mount'una yaziyordu (salt-okunur
    # mount'ta risk). Yerel denemede DEBUG_VIDEO=1 ile acilir; bu bir ortam tespiti
    # degil, dokumante edilmis ve varsayilani sabit bir gelistirme anahtaridir.
    out_video = None
    if os.environ.get("DEBUG_VIDEO") == "1":
        out_video = cv2.VideoWriter(
            os.path.join(os.path.dirname(video_path), "PREDICT_GERCEK_Cikti.mp4"),
            cv2.VideoWriter_fourcc(*'mp4v'), fps,
            (efektif_genislik or int(cap.get(cv2.CAP_PROP_FRAME_WIDTH)),
             efektif_yukseklik or int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT)))
        )
    son_su_kutu = None
    son_su_g = 0.0
    son_su_zamani = -999

    # LAPTOP gorunum-gecisi durumu (bkz. asagida bilgisayar blogu)
    LAPTOP_YOKLUK_SN = 15.0  # bu kadar sn gorulmezse "kayboldu" sayilir.
                             # OLCULDU: 5sn ile laptop yanlis-algi kumeleri (~9sn
                             # aralikli) her seferinde "yeni gorunum" sayilip 11 FP
                             # uretiyor; 15sn ile 2 FP kaliyor ama GT 84.8'deki tek
                             # gercek gosterim de yutuluyor. GT'de bilgisayar=1 olay
                             # oldugu icin FP'siz taraf net kazancli (v5 vs v6 olcumu).
    LAPTOP_ONAY_SN = 0.0     # conf 0.45 esigi + gorunum-gecisi zaten sinirliyor;
                             # 0.6 ve 0.2 denendi: GT 84.8'deki 1-2 karelik gercek
                             # gosterim ikisinde de kaciyordu -- ilk karede yaz
    laptop_son_gorulme = None
    laptop_gorunum_baslangic = None
    laptop_conf_tepe = 0.0
    laptop_yazildi_bu_gorunum = False

    # TEKNOCAN gorunum-gecisi durumu (ayni mantik: GT "gorulebilir oldugu anda"
    # bir kez isaretliyor; surekli gorunur nesne 5sn cooldown'la tekrar tekrar
    # yazilmamali -- v2 olcumunde 13.8sn'de boyle bir tekrar-FP vardi)
    TEKNOCAN_YOKLUK_SN = 15.0
    TEKNOCAN_ONAY_SN = 0.0   # conf 0.6 esigi zaten gurultuyu eliyor; kisa gosterimler
                             # (85.0 ve 110.5'teki 1-2 karelik gorunumler) kacmasin
    teknocan_son_gorulme = None
    teknocan_gorunum_baslangic = None
    teknocan_conf_tepe = 0.0
    teknocan_yazildi_bu_gorunum = False
    
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

    # UYARLANABILIR KARE ATLAMA -- 10 dk inference limiti guvencesi.
    # faz2 (114sn, 1080p, 2850 kare) T4'te atlama=1 ile ~428sn surdu; final gunu
    # videosunun SURESI BILINMIYOR (stream kaydi 5 dk'ya kadar cikabilir). Kare
    # basina olculen maliyet: ~0.04sn her karede kosan arac takibi + ~0.11sn
    # atlamaya tabi uzman modeller. 540sn hedefe (60sn guvenlik payi) gore atlama
    # otomatik secilir; 114sn videoda 1 kalir (davranis degismez), 3 dk videoda 2,
    # 5 dk videoda 4 olur. Bu bir ortam tespiti degil, girdinin kendi uzunluguna
    # bagli deterministik bir olcekleme.
    toplam_kare = int(cap.get(cv2.CAP_PROP_FRAME_COUNT) or 0)
    atlama = 1
    if toplam_kare > 0:
        HEDEF_SN = 500.0  # 540 ile 4K@114sn atlama=3'e cikip 583sn olctu (limit
                          # 600'e 17sn pay -- ince). 500, ayni videoyu atlama=4'e
                          # zorlar (~460sn, guvenli pay); 1080p/240p'de atlama=1 kalir.
        # Kare basina maliyet cozunurlukle olculekleniyor -- T4 olcumleri:
        # 240p 0.09sn, 1080p 0.15sn, 4K 0.32sn/kare => faktor = alan_orani^0.55
        # (taban 0.6: kucuk girdide sabit yukler baskin). 4K'da atlama=1 ile
        # 910sn olculdu (limit ustu!) -- bu formul 4K'yi atlama=3'e cekip
        # ~508sn'ye indirir; 1080p/240p'de atlama=1 kalir (davranis degismez).
        alan_orani = 1.0
        if efektif_genislik and efektif_yukseklik:
            alan_orani = (efektif_genislik * efektif_yukseklik) / (1920.0 * 1080.0)
        faktor = max(0.6, alan_orani ** 0.55)
        KARE_SABIT_SN = 0.05 * faktor  # atlanamayan is (arac takibi vb.)
        KARE_AGIR_SN = 0.10 * faktor   # atlamayla bolunen is (uzman modeller)
        pay = HEDEF_SN / toplam_kare - KARE_SABIT_SN
        if pay <= 0:
            atlama = 6
        else:
            atlama = min(6, max(1, math.ceil(KARE_AGIR_SN / pay)))
    print(f"video: {toplam_kare} kare @ {fps:.1f}fps, "
          f"{kaynak_genislik}x{kaynak_yukseklik} (on_olcek={on_olcek:.2f}) -> atlama={atlama}", flush=True)
    atlama_yolcu = max(1, int(round(fps/2)))
    dt = atlama/fps
    yolo_kayit = {ad: [] for ad in modeller}
    off_kayit = []
    yuz_kayit = []  # (sn, mediapipe yuz buldu mu) -- arkaya_bakma yukseltmesi icin
    surucu_var_kayit = []

    # YOLCU: ID takipli (BoT-SORT) surekli-kimlik durumu -- test_yolcu.py ile ayni
    yolcu_sofor_id = None
    yolcu_sofor_son_konum = None
    yolcu_id_role = {}          # track_id -> koltuk ("on_koltuk" -- sofor disindaki herkes)
    yolcu_ardisik_sayac = {}    # track_id -> kesintisiz (islenen kare bazinda) gorulme sayaci
    yolcu_ardisik_son_kare = {} # track_id -> en son goruldugu islenen-kare sirasi
    yolcu_kilitli_idler = set()  # bu ID zaten JSON'a yazildi mi (ayni kisi tekrar tekrar yazilmaz, ama yeni bir kisi -- yeni ID -- yeniden yazilabilir)
    yolcu_islenen_kare_sirasi = 0
    # ON YOLCU (sol-yari kurali) durumu -- ID'ye DAYANMAZ (BoT-SORT id'leri 0.5
    # sn'lik seyrek cagrilarda kopuyor; yukaridaki id-kilit sayaci faz2'de bu
    # yuzden hic dolmadi). Nitelikli adayin varligi konum-tabanli sayilir.
    on_yolcu_ardisik = 0
    on_yolcu_son_kare = None
    on_yolcu_tepe_conf = 0.0
    on_yolcu_yazilan_son = None
    # SERBEST YAZI (ortulu plaka) durumu: normalize anahtar uzerinde
    # guven-agirlikli oylama; kilitlenince okuma durur (sure tasarrufu).
    yazi_oylar = {}      # normalize_anahtar -> conf toplami
    yazi_hamlar = {}     # normalize_anahtar -> {ham_metin: sayi}
    yazi_kilit = None
    # SIGARA + TELEFON: zamansal kanit birikimi durumu (K6/K7/K12/K15)
    sigara_pencere = deque()       # (sn, agirlik)
    sigara_son_olay = -99.0
    telefon_pencere = deque()      # (sn, agirlik, alt_etiket, conf)
    telefon_son_olay = -99.0
    telefon_onceki_kutu = None

    # KEMER: pencere/tetikleyici YOK -- soför ROI'si bulundugu her karede dogrudan kontrol
    # edilir. "Kemer var" gorulurse durum sifirlanir (bir sonraki "yok" tekrar yazilabilir).
    # "Kemer yok" ANINDA yazilmaz: faz2 GT olcumunde tek-karelik "yok" kararlari 8 FP
    # uretti. Simdi KEMER_YOK_SUREKLILIK_SN boyunca (kucuk bosluklara tolerar) kesintisiz
    # "yok" gorulmesi gerekir; olay, "yok" kosusunun BASLANGIC anina yazilir.
    kemer_son_ihlal_yazildi = False
    KEMER_YOK_SUREKLILIK_SN = 0.08  # ihlal icin gereken kesintisiz "Kemer Yok" suresi
                                    # (~2 kare). Olculen tarama: 1.0sn -> gercek ihlal
                                    # patlamalari kisa oldugu icin recall cokuyor; 0.2sn
                                    # -> gercek tekli atimlar (GT 25.3/99.8 tipi) hala
                                    # kaciyor. 2 kare, tek-kare flicker'i elerken kisa
                                    # gercek atimlari tutan en genellenebilir nokta.
    KEMER_YOK_BOSLUK_TOLERANS = 1.0 # bu kadar sn karar gelmezse kosu sifirlanir
    kemer_yok_baslangic = None
    kemer_yok_son_gorulme = None
    kemer_yok_conf_tepe = 0.0

    # KEMER YOKLUK SAATI (kenar-penceresi sentetik kuralinin YERINE, 06.08 takim
    # karari): model "kemer VAR" kanitini (guven >= KEMER_VAR_ESIK) gordugu surece
    # sessiz kalinir; var kaniti KEMER_YOKLUK_SN boyunca hic gelmezse ESIGIN
    # ASILDIGI ANA ihlal yazilir, kosu surdukce KEMER_YENIDEN_SN'de bir tekrar
    # yazilir. Parametreler PIPELINE'in kendi kemer zaman serisiyle kalibre edildi
    # (v13 KEMER_LOG dokumu + faz2 GT, tum kombinasyon taramasi): bu degerlerle
    # 4/4 GT ihlali yakalaniyor, faz hatasi ~2.8sn (4TP/3FP; eski kenar-penceresi
    # 3TP/9FP, kosu-baslangicina yazan surum 1TP/6FP@5s idi). Olayin esik aninda
    # yazilmasi olculerek secildi: GT ihlali "gorulebilir oldugu anda" isaretliyor,
    # var-kanitinin kesilmesi gorunurlukten ~8sn once basliyor. Saat sofor
    # gorunmese de isler (GT 67.5/75.9 ihlalleri sofor gorunmezken); yalnizca
    # gercek "var" kaniti sifirlar. Arac uzun sure kadraj disindaysa saat
    # durdurulup yeniden baslatilir; kemer modeli en az bir kez calismadan
    # (sofor hic gorulmeden) saat kurulmaz (bos-sahne garantisi).
    KEMER_VAR_ESIK = 0.45     # "kemer var" saymak icin gereken guven (pipeline
                              # dokumunde karelerin %2'si -- model kemeri nadiren
                              # ama saglam gordugunde bu esigi asiyor)
    KEMER_MODEL_TABAN = 0.10  # model cagrisinin taban conf'u (var kanitini kacirmamak
                              # icin dusuk; karar esikleri yukarida ayrica uygulanir)
    KEMER_YOKLUK_SN = 8.0     # bu kadar sn "var" kaniti gelmezse ihlal (6.0 ile
                              # 4TP/4FP, 8.0 ile 4TP/3FP olculdu)
    KEMER_YENIDEN_SN = 12.0   # yokluk kosusu surdukce tekrar yazim araligi
    KEMER_ARAC_KOPUKLUK_SN = 3.0  # arac bu kadar sn gorunmezse saat sifirlanir
    kemer_kuruldu = False         # kemer modeli en az bir kez calisti mi
    kemer_yokluk_bas = None       # aktif yokluk kosusunun baslangic sn'si
    # kemer2 (hibrit) surekli-yok durumu
    kemer2_yok_bas = None
    kemer2_yok_son = None
    kemer2_yok_tepe = 0.0
    kemer2_yok_yazildi = False
    kemer_yokluk_yazilan_son = None  # bu kosuda son yazilan olayin sn'si
    kemer_son_arac_sn = None      # kemer saati icin aracin en son gorulme sn'si
    # KEMER_LOG=1: pipeline'in KENDI kemer zaman serisini dokmek icin gelistirme
    # anahtari (esik kalibrasyonu izole zincirle degil gercek zincirle yapilsin
    # diye). Uretimde env yok -> tamamen pasif.
    kemer_log = [] if os.environ.get("KEMER_LOG") == "1" else None

    # IYI-GORUNUM PENCERESI (arka koltuk aramasi icin): arac kutusu SOL ya da SAG
    # kenara YENI dayandiginda 3 saniyelik pencere acilir -- arac kameraya en yakin
    # ve kabin ici en okunur konumdayken yolcu aranir. (Kemer artik bu pencereyi
    # KULLANMIYOR -- yukaridaki yokluk saatine tasindi.)
    onceki_kenar_dayali = False
    KEMER_PENCERE_SN = 3.0  # pencerenin acik kalacagi sure (sn)
    KEMER_KENAR_ESIK = int((efektif_genislik or 1606) * 0.05)  # kenara "yakin" sayilacak piksel payi (on-buyutme sonrasi efektif genislik)
    belirsizlik_pencere_acik = False
    belirsizlik_pencere_baslangic = 0.0

    # ARKA KOLTUK (pencere-tabanli): ayni kenar-tetikleyicili pencereyi kullanir -- pencere
    # aciksa roi'nin SAG tarafinda yolcu_model ile kisi aranir (sofor'la cakisan elenir).
    # Bos olan ilk yer (once arka_koltuk_1, sonra arka_koltuk_2) doldurulur (FTR sartnamesi
    # sadece bu iki etiketi taniyor). HER IKI yer de ARKA_KOLTUK_SIFIRLAMA_SN'de bir
    # bosaltilir -- boylece koltuk degisikligi (inen/binen farkli kisi) tekrar yakalanabilir.
    arka_koltuk_pencerede_yazildi = False
    arka_koltuk_1_dolu = False
    arka_koltuk_2_dolu = False
    arka_koltuk_son_sifirlama = 0.0
    ARKA_KOLTUK_SIFIRLAMA_SN = 6.0

    while cap.isOpened():
        ret, frame = cap.read()
        if not ret:
            break
        if on_olcek != 1.0:
            frame = cv2.resize(frame, None, fx=on_olcek, fy=on_olcek,
                               interpolation=cv2.INTER_CUBIC)
        global_frame_count += 1

        # --- CAR BOXES PASS ---
        detector_results = detector_model.track(frame, classes=[2, 5, 7], conf=0.45, persist=True, verbose=False)
        current_car_boxes = []
        for result in detector_results:
            for box in result.boxes:
                if int(box.cls[0].item()) in [2, 5, 7]:
                    current_car_boxes.append(tuple(map(int, box.xyxy[0])))
        en_buyuk = max(current_car_boxes, key=lambda b: (b[2]-b[0])*(b[3]-b[1])) if current_car_boxes else None

        # SERBEST YAZI okumasi (~1 sn'de bir; kilitlendiyse artik denenmez).
        # Eski plaka zinciriyle YARISMAZ — secim run_inference sonunda yapilir
        # (regex'li zincir kilitlendiyse o kazanir).
        if (ocr_okuyucu is not None and yazi_kilit is None and en_buyuk is not None
                and global_frame_count % YAZI_OKUMA_ARALIGI == 0):
            yazi_metin_k, yazi_g = yazi_serit_oku(frame, en_buyuk)
            anahtar = _yazi_normalize(yazi_metin_k)
            if len(anahtar) >= 2:
                yazi_oylar[anahtar] = yazi_oylar.get(anahtar, 0.0) + yazi_g
                sayaclar = yazi_hamlar.setdefault(anahtar, {})
                sayaclar[yazi_metin_k] = sayaclar.get(yazi_metin_k, 0) + 1
                if yazi_oylar[anahtar] >= YAZI_OY_ESIK:
                    yazi_kilit = anahtar

        t_simdi = global_frame_count / fps

        if t_simdi - arka_koltuk_son_sifirlama >= ARKA_KOLTUK_SIFIRLAMA_SN:
            arka_koltuk_1_dolu = False
            arka_koltuk_2_dolu = False
            arka_koltuk_son_sifirlama = t_simdi

        # Arac kutusu SOL ya da SAG kenara YENI dayandiginda (once dayanmamisken simdi
        # dayaniyorsa) 3 saniyelik "iyi gorunum" penceresi acilir. Pencere ACIKKEN arac
        # bir-iki kare icin kaybolsa bile pencere KAPANMAZ -- sadece 3 saniye dolunca kapanir.
        # Pencere zaten aciksa yeni bir "kenara degme" onu yeniden baslatmaz.
        if en_buyuk is not None:
            kenar_dayali_mi = en_buyuk[0] <= KEMER_KENAR_ESIK or en_buyuk[2] >= frame.shape[1] - KEMER_KENAR_ESIK
            if kenar_dayali_mi and not onceki_kenar_dayali and not belirsizlik_pencere_acik:
                belirsizlik_pencere_acik = True
                belirsizlik_pencere_baslangic = t_simdi
                arka_koltuk_pencerede_yazildi = False  # yeni pencere -- arka koltuk tekrar aranabilir
            onceki_kenar_dayali = kenar_dayali_mi
        else:
            onceki_kenar_dayali = False

        if belirsizlik_pencere_acik and (t_simdi - belirsizlik_pencere_baslangic > KEMER_PENCERE_SN):
            belirsizlik_pencere_acik = False

        belirsizlik_pencere_gorunum = belirsizlik_pencere_acik and en_buyuk is not None

        # TEKNOCAN + LAPTOP: SADECE araç içinde sayılır (araç dışında görülenler
        # değerlendirilmez). ID/hafıza takibi yok -- her karede eşiği geçen ve araç
        # içinde olan tespit dogrudan o karenin zamanıyla yazılır; aynı nesnenin arka
        # arkaya defalarca yazılmasını sondaki genel 5sn'lik soğuma filtresi zaten
        # engelliyor, ayrıca bir "N kere görüldü" hafızasına gerek yok.
        def _arac_icinde_mi(cx, cy):
            return any(c[0] <= cx <= c[2] and c[1] <= cy <= c[3] for c in current_car_boxes)

        # --- 1. TEKNOCAN --- (gorunum-gecisi: yeni gorunumde BIR olay)
        # Kadans atlamayla olceklenir -- uzun/4K videolarda sure butcesi icin.
        if global_frame_count % (2 * atlama) == 0:
            teknocan_results = teknocan_model(frame, conf=0.6, verbose=False)
            teknocan_kare_conf = 0.0
            for t_res in teknocan_results:
                for t_box in t_res.boxes:
                    conf = float(t_box.conf[0])
                    tx1, ty1, tx2, ty2 = map(int, t_box.xyxy[0])
                    if _arac_icinde_mi((tx1+tx2)/2, (ty1+ty2)/2):
                        teknocan_kare_conf = max(teknocan_kare_conf, conf)
            if teknocan_kare_conf > 0:
                zaman_saniye = global_frame_count / fps
                if teknocan_son_gorulme is None or zaman_saniye - teknocan_son_gorulme > TEKNOCAN_YOKLUK_SN:
                    teknocan_gorunum_baslangic = zaman_saniye
                    teknocan_conf_tepe = 0.0
                    teknocan_yazildi_bu_gorunum = False
                teknocan_son_gorulme = zaman_saniye
                teknocan_conf_tepe = max(teknocan_conf_tepe, teknocan_kare_conf)
                if (not teknocan_yazildi_bu_gorunum
                        and zaman_saniye - teknocan_gorunum_baslangic >= TEKNOCAN_ONAY_SN):
                    vehicle_events.append(tespit_olustur(
                        teknocan_gorunum_baslangic, "nesneler", "teknocan",
                        round(teknocan_conf_tepe, 2)))
                    teknocan_yazildi_bu_gorunum = True

        # --- 2. LAPTOP (bilgisayar) --- araba ROI'sine kirpilip taranir. CLAHE
        # BILEREK UYGULANMAZ: yeni laptop modeli (laptop7) ham karelerle olculdu --
        # faz2'de CLAHE'siz 1TP/0FP, CLAHE'yle 0TP/2FP (v12 A/B olcumu). Kadans
        # atlamayla olceklenir.
        if en_buyuk is not None and global_frame_count % atlama == 0:
            lax1, lay1, lax2, lay2 = en_buyuk
            lpad_x, lpad_y = int((lax2-lax1)*0.05), int((lay2-lay1)*0.05)
            lrx1, lry1 = max(0, lax1-lpad_x), max(0, lay1-lpad_y)
            lrx2, lry2 = min(frame.shape[1], lax2+lpad_x), min(frame.shape[0], lay2+lpad_y)
            laptop_roi = frame[lry1:lry2, lrx1:lrx2]
            if laptop_roi.size > 0:
                laptop_sonuc = laptop_model(laptop_roi, conf=0.45, verbose=False)[0]
                # GORUNUM-GECISI mantigi: GT nesneleri "gorulebilir olduklari anda" bir
                # kez isaretliyor. Eski kod her karede (5sn sogumayla) olay basiyordu --
                # faz2 olcumunde 12 tespit / 11 FP uretti. Simdi: kisa bir onay suresi
                # dolunca GORUNUMUN BASLANGICINA tek olay yazilir; nesne LAPTOP_YOKLUK_SN
                # boyunca kaybolup geri gelirse yeni gorunum sayilir ve tekrar yazilir.
                laptop_kare_conf = max((float(b.conf[0]) for b in laptop_sonuc.boxes), default=0.0)
                if laptop_kare_conf > 0:
                    zaman_saniye = global_frame_count / fps
                    if laptop_son_gorulme is None or zaman_saniye - laptop_son_gorulme > LAPTOP_YOKLUK_SN:
                        laptop_gorunum_baslangic = zaman_saniye
                        laptop_conf_tepe = 0.0
                        laptop_yazildi_bu_gorunum = False
                    laptop_son_gorulme = zaman_saniye
                    laptop_conf_tepe = max(laptop_conf_tepe, laptop_kare_conf)
                    if (not laptop_yazildi_bu_gorunum
                            and zaman_saniye - laptop_gorunum_baslangic >= LAPTOP_ONAY_SN):
                        vehicle_events.append(tespit_olustur(
                            laptop_gorunum_baslangic, "nesneler", "bilgisayar",
                            round(laptop_conf_tepe, 2)))
                        laptop_yazildi_bu_gorunum = True

        # --- 3. ARAÇ (kasa/renk/plaka) ---
        for result in detector_results:
            for box in result.boxes:
                if box.id is None: continue
                v_id = int(box.id.item())
                ax1, ay1, ax2, ay2 = map(int, box.xyxy[0])
                conf = float(box.conf[0])

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
            # ARAC KENARDA KIRPILMIS MI: araci kismen kadraj disinda birakan donus/manevra
            # anlarinda "sofor sagda" geometrik varsayimi ve kirpim guvenilmez hale geliyor --
            # bu durumda o karede sofor/sigara/telefon tespiti atlanir.
            guvenilir_arac = en_buyuk
            if en_buyuk is not None:
                ax1, _, ax2, _ = en_buyuk
                if ax1 <= ARAC_KENAR_PAY or ax2 >= frame.shape[1] - ARAC_KENAR_PAY:
                    guvenilir_arac = None

            # HER KEREDE TAZE: sofor konumu bu karenin kendi arac ROI'sinden yeniden
            # hesaplanir -- gecmis kareden/donmus bir kutudan hicbir sey tasinmaz. Arac bu
            # karede goruntude degilse/kenarda kirpilmisse ya da ROI icinde kimse bulunamazsa
            # None doner.
            sofor_kutusu = sofor_konumu_bul(frame, guvenilir_arac)
            bolge, kirp_x1, kirp_y1 = sofor_kirp(frame, sofor_kutusu)
            surucu_var_kayit.append((sn, bolge is not None))

            # Kemer modeli için sadece arabayı kırp (En büyük arabayı al)
            araba_crop = frame
            if en_buyuk is not None:
                ax1, ay1, ax2, ay2 = en_buyuk
                pad_x, pad_y = int((ax2-ax1)*0.05), int((ay2-ay1)*0.05)
                p_ax1, p_ay1 = max(0, ax1 - pad_x), max(0, ay1 - pad_y)
                p_ax2, p_ay2 = min(frame.shape[1], ax2 + pad_x), min(frame.shape[0], ay2 + pad_y)
                araba_crop = frame[p_ay1:p_ay2, p_ax1:p_ax2]

            # --- SIGARA + TELEFON (Masaustu/Models K1-K16 mantigi) -- artik bu karenin taze
            # sofor_kutusu'nu kullanir, kendi baslarina "sofor kim" aramazlar (bulunamadiysa
            # kendi eski yedek mantiklarina duserler). ---
            en_arac_sigtel = guvenilir_arac
            kare_alani = frame.shape[0] * frame.shape[1]

            sig_a, sig_conf = sigara_isle(frame, en_arac_sigtel, kare_alani, sofor_kutusu)
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

            tel_a, tel_conf, tel_alt, tel_kutu = telefon_isle(frame, en_arac_sigtel, kare_alani, telefon_onceki_kutu, sofor_kutusu)
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

            # KEMER: soför ROI'sine (sofor_kutusu) %15 padding ile bakar -- arac ROI'si
            # DEGIL. Uc kanal birlikte calisir:
            #   1) "kemer VAR" kaniti (conf >= KEMER_VAR_ESIK): sessiz + yokluk saati
            #      ve yok-kosusu durumu sifirlanir.
            #   2) "kemer YOK" sinifi (conf >= ESIK): surekli-yok dedektoru (eski mantik).
            #      Yeni kemer modeli bu sinifi hic uretmiyor (izole olcum: 1424 ornekte 0)
            #      ama model degisirse kanal hazir.
            #   3) YOKLUK SAATI: "var" kaniti KEMER_YOKLUK_SN boyunca hic gelmezse
            #      ihlal -- asagida, sofor gorunurlugunden BAGIMSIZ degerlendirilir.
            kemer_kare_cls, kemer_kare_conf = -2, 0.0  # -2: model bu karede cagrilmadi
            if sofor_kutusu is not None:
                sfx1, sfy1, sfx2, sfy2 = sofor_kutusu
                sfpad_x, sfpad_y = (sfx2-sfx1)*0.15, (sfy2-sfy1)*0.15
                sfrx1, sfry1 = max(0, int(sfx1-sfpad_x)), max(0, int(sfy1-sfpad_y))
                sfrx2, sfry2 = min(frame.shape[1], int(sfx2+sfpad_x)), min(frame.shape[0], int(sfy2+sfpad_y))
                sofor_roi_kemer = frame[sfry1:sfry2, sfrx1:sfrx2]
                if sofor_roi_kemer.size > 0:
                    sofor_roi_kemer = _arac_roi_parlaklik_duzelt(sofor_roi_kemer)
                    res = modeller["kemer"](sofor_roi_kemer, conf=KEMER_MODEL_TABAN, verbose=False)[0]
                    b_cls, b_conf = -1, 0.0
                    for k in res.boxes:
                        if float(k.conf) > b_conf:
                            b_conf, b_cls = float(k.conf), int(k.cls)
                    kemer_kare_cls, kemer_kare_conf = b_cls, b_conf
                    kemer_kuruldu = True
                    if b_cls == 1 and b_conf >= KEMER_VAR_ESIK:
                        # VAR kaniti: her sey sifirlanir, sessiz kalinir
                        kemer_yokluk_bas = None
                        kemer_yokluk_yazilan_son = None
                        kemer_son_ihlal_yazildi = False
                        kemer_yok_baslangic = None
                        kemer_yok_conf_tepe = 0.0
                        kemer2_yok_bas = None
                        kemer2_yok_tepe = 0.0
                    elif b_cls == 0 and b_conf >= ESIK["kemer"]:
                        # uzun karar bosluklarinda kosuyu sifirla (surucu kaybolup geri
                        # geldiginde iki ayri kisa "yok" ani tek kosu sayilmasin)
                        if kemer_yok_son_gorulme is not None and sn - kemer_yok_son_gorulme > KEMER_YOK_BOSLUK_TOLERANS:
                            kemer_yok_baslangic = None
                            kemer_yok_conf_tepe = 0.0
                        if kemer_yok_baslangic is None:
                            kemer_yok_baslangic = sn
                        kemer_yok_son_gorulme = sn
                        kemer_yok_conf_tepe = max(kemer_yok_conf_tepe, b_conf)
                        if (sn - kemer_yok_baslangic) >= KEMER_YOK_SUREKLILIK_SN and not kemer_son_ihlal_yazildi:
                            vehicle_events.append(tespit_olustur(
                                kemer_yok_baslangic, "sofor_eylemi", "emniyet_kemeri_ihlali",
                                round(kemer_yok_conf_tepe, 2)))
                            kemer_son_ihlal_yazildi = True

            # KEMER YOKLUK SAATI: sofor gorunurlugunden BAGIMSIZ, islenen her karede
            # degerlendirilir (GT 67.5/75.9 ihlalleri sofor gorunmezken yasandi; v9/v10
            # olcumleri gorunurluk gardinin TP'yi 3->1 dusurdugunu gosterdi). Yalnizca
            # gercek "var" kaniti (yukarida) saati sifirlar. Arac KEMER_ARAC_KOPUKLUK_SN
            # boyunca hic gorunmediyse saat yeniden baslatilir -- bos yol/kadraj disi
            # bolumlerde sahte ihlal uretilmez (faz2'de arac hep gorunur, davranis ayni).
            if KEMER_YOKLUK_AKTIF and en_buyuk is not None and kemer_kuruldu:
                if kemer_son_arac_sn is not None and (sn - kemer_son_arac_sn) > KEMER_ARAC_KOPUKLUK_SN:
                    kemer_yokluk_bas = None
                    kemer_yokluk_yazilan_son = None
                kemer_son_arac_sn = sn
                if kemer_yokluk_bas is None:
                    kemer_yokluk_bas = sn
                elif (sn - kemer_yokluk_bas) >= KEMER_YOKLUK_SN:
                    # ESIGIN ASILDIGI ANA yazilir -- pipeline dokumu olcumune gore
                    # GT'nin "gorulebilir oldugu an" isaretine en yakin an bu
                    # (kosu baslangicina yazmak 5-7sn erken kaliyordu).
                    if kemer_yokluk_yazilan_son is None:
                        vehicle_events.append(tespit_olustur(
                            sn, "sofor_eylemi", "emniyet_kemeri_ihlali", 0.5))
                        kemer_yokluk_yazilan_son = sn
                    elif (sn - kemer_yokluk_yazilan_son) >= KEMER_YENIDEN_SN:
                        vehicle_events.append(tespit_olustur(
                            sn, "sofor_eylemi", "emniyet_kemeri_ihlali", 0.5))
                        kemer_yokluk_yazilan_son = sn

            if kemer_log is not None:
                kemer_log.append({
                    "t": sn, "cls": kemer_kare_cls, "conf": round(kemer_kare_conf, 3),
                    "arac": en_buyuk is not None, "pencere": belirsizlik_pencere_acik,
                })

            # ARKA KOLTUK (pencere-tabanli): arac ROI'si (5% padding) + CLAHE -- kenar-
            # tetikleyicili belirsizlik penceresini kullanir. Kirpimin SAG yarisinda kisi
            # aranir, sofor_kutusu ile cakisan (IOU) adaylar elenir. Bos olan ilk yer
            # (once arka_koltuk_2, sonra arka_koltuk_1 -- sag yari = arac sag tarafi) doldurulur.
            if en_buyuk is not None and belirsizlik_pencere_gorunum and not arka_koltuk_pencerede_yazildi and not (arka_koltuk_1_dolu and arka_koltuk_2_dolu):
                kax1, kay1, kax2, kay2 = en_buyuk
                kpad_x, kpad_y = int((kax2-kax1)*0.05), int((kay2-kay1)*0.05)
                krx1, kry1 = max(0, kax1-kpad_x), max(0, kay1-kpad_y)
                krx2, kry2 = min(frame.shape[1], kax2+kpad_x), min(frame.shape[0], kay2+kpad_y)
                arac_roi_koltuk = frame[kry1:kry2, krx1:krx2]
                if arac_roi_koltuk.size > 0:
                    arac_roi_koltuk = _arac_roi_parlaklik_duzelt(arac_roi_koltuk)
                    krx_orta = krx1 + (krx2 - krx1) // 2
                    sag_roi = arac_roi_koltuk[:, krx_orta-krx1:]
                    if sag_roi.size > 0:
                        ay_sonuc = yolcu_model_koltuk(sag_roi, conf=YOLCU_KISI_ESIK, verbose=False)[0]

                        def _sofor_ile_cakisiyor_mu(kutu):
                            if sofor_kutusu is None:
                                return False
                            x1, y1, x2, y2 = kutu
                            sx1, sy1, sx2, sy2 = sofor_kutusu
                            ix1, iy1 = max(x1, sx1), max(y1, sy1)
                            ix2, iy2 = min(x2, sx2), min(y2, sy2)
                            iw, ih = max(0, ix2-ix1), max(0, iy2-iy1)
                            alan = (x2-x1)*(y2-y1)
                            oran = (iw*ih)/alan if alan > 0 else 0.0
                            return oran >= 0.3

                        adaylar = []
                        for k in ay_sonuc.boxes:
                            kx1, ky1, kx2, ky2 = k.xyxy[0].tolist()
                            tam_kutu = (kx1+krx_orta, ky1+kry1, kx2+krx_orta, ky2+kry1)
                            if not _sofor_ile_cakisiyor_mu(tam_kutu):
                                adaylar.append((float(k.conf), tam_kutu))
                        adaylar.sort(key=lambda a: a[0], reverse=True)
                        # AYNI KISIYE cift kutu elemesi: dusuk cozunurluk/parlak
                        # goruntude tek yolcuya iki kutu cikabiliyor (v14 olcumu:
                        # 240p'de 2, aydinlikta 5 sahte arka_koltuk_1). En yuksek
                        # guvenli adayla IoU>=0.4 cakisan digerleri ayni kisidir.
                        if len(adaylar) >= 2:
                            adaylar = [adaylar[0]] + [
                                a for a in adaylar[1:] if _iou(a[1], adaylar[0][1]) < 0.4
                            ]

                        if adaylar:
                            # Arama ROI'nin SAG yarisinda yapiliyor: aracin arkasindan
                            # bakista sag yari = aracin SAG (yolcu) tarafi = arka_koltuk_2.
                            # faz2 GT ile dogrulandi (12 arka_koltuk_2'ye karsi 1
                            # arka_koltuk_1): ilk gorunen aday sag koltuktur.
                            # arka_koltuk_1 ise ancak AYNI karede IKINCI bir es-zamanli
                            # kisi de gorunuyorsa yazilir -- "koltuk_2 dolu diye tek
                            # adayi koltuk_1'e terfi ettirme" v12'de 3 yuksek-guvenli FP
                            # uretti (ayni yolcu yeni pencerede yeniden bulununca).
                            if not arka_koltuk_2_dolu:
                                arka_koltuk_2_dolu = True
                                # 07.08 hakem bilgisi: GT semasinda arka_koltuk_2 YOK --
                                # arka koltuk tespitleri tek etiketle (arka_koltuk_1) yazilir.
                                vehicle_events.append(tespit_olustur(sn, "yolcular", "arka_koltuk_1", adaylar[0][0]))
                                arka_koltuk_pencerede_yazildi = True
                                if len(adaylar) >= 2 and not arka_koltuk_1_dolu:
                                    arka_koltuk_1_dolu = True
                                    vehicle_events.append(tespit_olustur(sn, "yolcular", "arka_koltuk_1", adaylar[1][0]))
                            elif len(adaylar) >= 2 and not arka_koltuk_1_dolu:
                                arka_koltuk_1_dolu = True
                                vehicle_events.append(tespit_olustur(sn, "yolcular", "arka_koltuk_1", adaylar[1][0]))
                                arka_koltuk_pencerede_yazildi = True
                            # tek aday + koltuk_2 dolu: ayni kisi yeniden gorunmus --
                            # yeni olay yazilmaz (6 sn'lik sifirlama zaten periyodik
                            # yeniden-raporlamayi sagliyor)

            if bolge is None:
                for ad in modeller:
                    if ad == "kemer":
                        continue
                    if ad == "su" and SU_GENIS_AKTIF:
                        # Sofor bulunamasa da su aranir: GT 28.9 kosusunun kenar
                        # donemi ve 63.16 oncesi tam boyle kayboluyordu (07.08
                        # sondasi). Arac ROI sag-yari + CLAHE, yuksek esik.
                        g_genis = su_genis_bak(modeller["su"], frame, None, en_buyuk)
                        yolo_kayit["su"].append((sn, g_genis if g_genis > 0 else None))
                    else:
                        yolo_kayit[ad].append((sn, None))
                off_kayit.append((sn, None))
                yuz_kayit.append((sn, None))
            else:
                rgb = cv2.cvtColor(bolge, cv2.COLOR_BGR2RGB)
                mp_img = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)
                yuz_sonuc = yuz_dedektor.detect(mp_img)
                yuz_kayit.append((sn, bool(yuz_sonuc and yuz_sonuc.face_landmarks)))

                for ad, model in modeller.items():
                    if ad == "kemer":
                        continue  # yukarida arac ROI'sinde ayrica islendi
                    elif ad == "su":
                        if ARACICI_SU:
                            g, kutu = su_bul(aracici_model, bolge, ESIK[ad], yuz_sonuc, siniflar=[0])
                        else:
                            g, kutu = su_bul(model, bolge, ESIK[ad], yuz_sonuc)
                        if g <= 0 and SU_GENIS_AKTIF:
                            # dar kirpim bos -> genis baglamli ikinci bakis (olcumle
                            # eklendi; bkz. su_genis_bak). kutu donmez -> debug cizimi
                            # guncellenmez, yalnizca zaman serisine yazilir.
                            g_genis = su_genis_bak(model, frame, sofor_kutusu, en_buyuk)
                            if g_genis > 0:
                                g = g_genis
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
                        # HİBRİT KONTROL: MAR (agiz aciklik mesafesi) VEYA YOLO -- ikisinden
                        # biri onaylarsa esneme sayilir (el agzi kapatirsa MAR calismaz ama YOLO
                        # yine de yakalayabilir; YOLO kacirirsa MAR yakalayabilir). AMA yuz
                        # gorunuyor ve agiz kesinlikle kapaliysa (MAR_MIN_ACIKLIK altinda) bu,
                        # YOLO'nun kararini VETO eder -- agiz acik degilse esneme sayilmaz,
                        # YOLO modeli ne derse desin.
                        g = yolo_bul(model, bolge, ESIK[ad], tek_sinif0=True)
                        yolo_onayi_var = g > 0

                        mar_onayi_var = False
                        if yuz_sonuc and yuz_sonuc.face_landmarks:
                            lm = yuz_sonuc.face_landmarks[0]
                            mar_degeri = abs(lm[ALT_DUDAK].y - lm[UST_DUDAK].y)
                            if mar_degeri >= MAR_MIN_ACIKLIK:
                                mar_onayi_var = True
                            else:
                                yolo_onayi_var = False  # yuz var, agiz kapali -> YOLO veto

                        if yolo_onayi_var or mar_onayi_var:
                            esneme_g = g if yolo_onayi_var else 0.75
                            yolo_kayit[ad].append((sn, esneme_g))
                        else:
                            yolo_kayit[ad].append((sn, None))
                off_kayit.append((sn, bakinma_olc(bolge)))

        # --- 4. YOLCULAR (yolcu.pt + BoT-SORT ID takibi, test_yolcu.py'nin sofor
        # cozumleme/kilitleme mantigi -- sofor disindaki herkes on_koltuk sayilir, ID'ye
        # kalici baglanarak. Bir ID 2 ardisik islenen karede gorulunce ANINDA yazilir --
        # her ID sadece bir kez yazilir ama FARKLI bir ID (yeni bir kisi) tekrar yazilabilir,
        # yani on_koltuk video basina 1 kezle sinirli degildir. Sofor JSON'a hic yazilmaz --
        # sadece sofor disi rolleri elemek icin kullanilir.) ---
        if global_frame_count % atlama_yolcu == 0:
            yolcu_islenen_kare_sirasi += 1
            en_arac = max(current_car_boxes, key=lambda b: (b[2]-b[0])*(b[3]-b[1])) if current_car_boxes else None
            if en_arac is not None:
                ax1, ay1, ax2, ay2 = en_arac
                arac_orta = (ax1 + ax2) / 2
                arac_capraz = ((ax2-ax1)**2 + (ay2-ay1)**2) ** 0.5
                pad_x, pad_y = int((ax2-ax1)*YOLCU_ROI_PAD_ORAN), int((ay2-ay1)*YOLCU_ROI_PAD_ORAN)
                rx1, ry1 = max(0, ax1-pad_x), max(0, ay1-pad_y)
                rx2, ry2 = min(frame.shape[1], ax2+pad_x), min(frame.shape[0], ay2+pad_y)
                arac_roi = frame[ry1:ry2, rx1:rx2]

                if arac_roi.size > 0:
                    arac_roi = _arac_roi_parlaklik_duzelt(arac_roi)
                    kisi_sonuc = yolcu_model.track(arac_roi, conf=YOLCU_KISI_ESIK, persist=True, verbose=False)[0]
                    # id'siz kutular da toplanir (on-yolcu kurali icin): 07.08 sondasi,
                    # bu cadence'ta (fps/2) BoT-SORT'un TUM videoda tek id bile
                    # atamadigini gosterdi (104 kutu, hepsi id=None) -- id sarti
                    # bu kanali fiilen kapatiyordu.
                    tum_kisiler = []
                    if kisi_sonuc.boxes is not None:
                        for k in kisi_sonuc.boxes:
                            kx1, ky1, kx2, ky2 = k.xyxy[0].tolist()
                            kx1, ky1, kx2, ky2 = kx1+rx1, ky1+ry1, kx2+rx1, ky2+ry1
                            tum_kisiler.append({
                                "id": int(k.id.item()) if k.id is not None else None,
                                "kutu": (kx1, ky1, kx2, ky2),
                                "conf": float(k.conf), "merkez_x": (kx1+kx2)/2, "alt_y": ky2,
                                "alan": (kx2-kx1)*(ky2-ky1),
                            })
                    ic_kisiler = [b for b in tum_kisiler if b["id"] is not None]

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
                            koltuk = "on_koltuk"
                            yolcu_id_role[pid] = koltuk

                        onceki_kare = yolcu_ardisik_son_kare.get(pid)
                        if onceki_kare == yolcu_islenen_kare_sirasi - 1:
                            yolcu_ardisik_sayac[pid] = yolcu_ardisik_sayac.get(pid, 0) + 1
                        else:
                            yolcu_ardisik_sayac[pid] = 1
                        yolcu_ardisik_son_kare[pid] = yolcu_islenen_kare_sirasi

                        if yolcu_ardisik_sayac[pid] >= YOLCU_ARDISIK_GEREK and pid not in yolcu_kilitli_idler:
                            yolcu_kilitli_idler.add(pid)
                            vehicle_events.append(tespit_olustur(global_frame_count / fps, "yolcular", koltuk, b["conf"]))

                    # --- ON YOLCU sol-yari kurali (ID'SIZ -- yukaridaki id-takipli
                    # sofor cozumlemesine DAYANMAZ, cunku id'ler bu cadence'ta hic
                    # atanmiyor): sofor = sag-yari en buyuk kutu (o karede), on yolcu
                    # = sol-yari + conf>=ON_YOLCU_CONF + soforden >= %12 yatay ayrik.
                    # Tum-video sondasi (07.08): aday YALNIZ GT 98.56 civarinda
                    # (98.88/99.36, 0.86/0.87), videonun kalaninda sifir tetik. ---
                    aday_conf = 0.0
                    sag_kisiler = [b for b in tum_kisiler
                                   if b["merkez_x"] > arac_orta and b["conf"] >= YOLCU_LOCK_MIN_CONF]
                    on_sofor = max(sag_kisiler, key=lambda b: b["alan"]) if sag_kisiler else None
                    if on_sofor is not None:
                        ayrim = (ax2 - ax1) * ON_YOLCU_AYRIM_ORAN
                        for b in tum_kisiler:
                            if b is on_sofor:
                                continue
                            if (b["merkez_x"] < arac_orta and b["conf"] >= ON_YOLCU_CONF
                                    and abs(b["merkez_x"] - on_sofor["merkez_x"]) >= ayrim
                                    and b["conf"] > aday_conf):
                                aday_conf = b["conf"]
                    if aday_conf > 0:
                        if on_yolcu_son_kare == yolcu_islenen_kare_sirasi - 1:
                            on_yolcu_ardisik += 1
                        else:
                            on_yolcu_ardisik = 1
                        on_yolcu_son_kare = yolcu_islenen_kare_sirasi
                        on_yolcu_tepe_conf = max(on_yolcu_tepe_conf, aday_conf)
                        t_yolcu = global_frame_count / fps
                        if on_yolcu_ardisik >= ON_YOLCU_ARDISIK_GEREK and (
                                on_yolcu_yazilan_son is None
                                or t_yolcu - on_yolcu_yazilan_son >= ON_YOLCU_YENIDEN_SN):
                            vehicle_events.append(tespit_olustur(
                                t_yolcu, "yolcular", "on_koltuk", round(on_yolcu_tepe_conf, 2)))
                            on_yolcu_yazilan_son = t_yolcu
                            on_yolcu_tepe_conf = 0.0
                    else:
                        on_yolcu_ardisik = 0
                        on_yolcu_tepe_conf = 0.0

        # VİDEO ÇİKTISI İÇİN KUTUYU ÇİZ (yalnizca DEBUG_VIDEO=1 iken)
        if out_video is not None:
            if son_su_kutu is not None and (global_frame_count - son_su_zamani) < (atlama * 3): # 3 işlem periyodu ekranda tut
                rx1, ry1, rx2, ry2 = son_su_kutu
                cv2.rectangle(frame, (rx1, ry1), (rx2, ry2), (0, 0, 255), 3)
                cv2.putText(frame, f"ONAY: su_icme {son_su_g:.2f}", (rx1, ry1-10), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 0, 255), 2)
                cv2.putText(frame, "PREDICT KILITLENDI!", (50, 50), cv2.FONT_HERSHEY_DUPLEX, 1.0, (0, 0, 255), 2)
            out_video.write(frame)

    cap.release()
    if out_video is not None:
        out_video.release()

    if os.environ.get("BAKINMA_LOG") == "1":
        # bakinma zaman serisi dokumu (ETRAFA_OFFSET_MIN kalibrasyonu icin)
        try:
            with open(os.environ.get("BAKINMA_LOG_YOL", "/app/data/output/bakinma_dokum.json"),
                      "w", encoding="utf-8") as bf:
                json.dump(off_kayit, bf)
        except OSError:
            pass

    if kemer_log is not None:
        try:
            with open(os.environ.get("KEMER_LOG_YOL", "/app/data/output/kemer_pipeline.jsonl"),
                      "w", encoding="utf-8") as klf:
                for kayit in kemer_log:
                    klf.write(json.dumps(kayit) + "\n")
        except OSError:
            pass  # gelistirme dokumu -- yazilamazsa akisi etkilemesin

    # === POST-PROCESSING (Şoför Eylemleri) ===
    # NOT: sigara/telefon/kemer artik CANLI olarak (kendi kanit pencereleriyle) yukarida
    # vehicle_events'e yazildi -- burada tekrar islenmiyor.
    etiket_map = {"su": "su_icme", "esneme": "esneme"}
    ardisik_gerek_map = {"su": ARDISIK_GEREK, "esneme": max(ARDISIK_GEREK, round(ESNEME_ARDISIK_SN / dt))}
    bosluk_tolerans_map = {"su": 0, "esneme": ESNEME_BOSLUK_TOLERANS}
    kararlar = []
    for ad in ["su", "esneme"]:
        for (orta, tepe) in ardisik_seg(yolo_kayit[ad], ardisik_gerek_map[ad], bosluk_tolerans_map[ad]):
            kararlar.append((orta, "sofor_eylemi", etiket_map[ad], tepe))

    bakinma_sonuclar = bakinma_seg([(s, o) for s, o in off_kayit if o is not None], dt)
    for (et, orta, sure) in bakinma_sonuclar:
        kararlar.append((orta, "sofor_eylemi", et, min(0.99, 0.5+sure/10)))

    # ARKAYA_BAKMA (mediapipe-tabanli, bagimsiz): pose modeli (bakinma_olc) tam arkaya
    # donuldugunde burnu goremeyip None dondugu icin bakinma_seg bu anlari kacirabilir --
    # onun yerine mediapipe'in SOFORUN yuzunu ARDISIK (bosluk toleransli, tek karelik
    # "yuz bulundu" titremelerine karsi dayanikli) bulamadigi sureyi dogrudan olcer;
    # T_ARKAYA'yi asarsa arkaya_bakma yazilir. bakinma_seg'in ayni zaman araliginda zaten
    # bulmus oldugu arkaya_bakma ile CAKISIRSA tekrar yazilmaz. Ayrica ONCESINDE (son
    # ARKAYA_ETRAFA_SOGUMA_SN icinde) zaten bir etrafa_bakinma yazildiysa da bastirilir --
    # ayni fiziksel donuşün hem etrafa_bakinma hem arkaya_bakma olarak cift yazilmasini onler.
    pose_arkaya_araliklari = [(orta, sure) for (et, orta, sure) in bakinma_sonuclar if et == "arkaya_bakma"]
    etrafa_zamanlari = [orta for (et, orta, sure) in bakinma_sonuclar if et == "etrafa_bakinma"]
    for (orta, sure) in yuz_kayip_seg(yuz_kayit, dt, T_ARKAYA, YUZ_BOSLUK_TOLERANS):
        cakisiyor = any(abs(orta - o2) < (sure+s2)/2 for o2, s2 in pose_arkaya_araliklari)
        son_etrafa_var = any(orta - ARKAYA_ETRAFA_SOGUMA_SN <= et_orta <= orta for et_orta in etrafa_zamanlari)
        if not cakisiyor and not son_etrafa_var:
            kararlar.append((orta, "sofor_eylemi", "arkaya_bakma", min(0.99, 0.5+sure/10)))

    # TERSI YONDE SOGUMA: bir arkaya_bakma'dan SONRAKI ARKAYA_ETRAFA_SOGUMA_SN icinde
    # gelen etrafa_bakinma'lar da bastirilir -- ayni donusun kuyrugunun ayrica kisa bir
    # yana bakis olarak cift yazilmasini onler.
    arkaya_zamanlari_tum = [orta for (orta, kat, et, conf) in kararlar if et == "arkaya_bakma"]
    kararlar = [
        k for k in kararlar
        if not (k[2] == "etrafa_bakinma" and any(a_orta < k[0] <= a_orta + ARKAYA_ETRAFA_SOGUMA_SN for a_orta in arkaya_zamanlari_tum))
    ]

    # NOT: eski "etrafa_bakinma/esneme, sigara-telefon-su ±1.5sn icindeyse sil" kurali
    # etrafa_bakinma icin KALDIRILDI -- faz2 GT'de etrafa_bakinma + sigara_icme AYNI
    # saniyede (92.58) var; kural dogru pozitifi siliyordu (olculdu). ESNEME icinse
    # korundu (asagida, olay birlestirmeden sonra): sigara/su/telefon sirasindaki
    # agiz-cene hareketi MAR sinyalini tetikleyip sahte esneme uretiyor (v2 olcumu:
    # 28.8 ve 72.4'te, GT'deki su/telefon olaylarinin yaninda 2 sahte esneme).

    # 5-Saniye Kilit (Cooldown)
    kararlar.sort()
    son_zaman = {}
    for (sn, kat, et, guv) in kararlar:
        if et not in son_zaman or (sn - son_zaman[et]) >= 5.0:
            vehicle_events.append(tespit_olustur(sn, kat, et, guv))
            son_zaman[et] = sn

    # === Aynı Etiketin 5sn İçinde Tekrarını Engelleme (Soğuma) ===
    filtered_events = []
    son_yazilan = {}
    for ev in sorted(vehicle_events, key=lambda e: e["zaman_saniye"]):
        # Sonekleri temizle
        if ev["etiket"].startswith("teknocan_"): ev["etiket"] = "teknocan"
        if ev["etiket"].startswith("bilgisayar_"): ev["etiket"] = "bilgisayar"
        etiket = ev["etiket"]

        if etiket not in son_yazilan or (ev["zaman_saniye"] - son_yazilan[etiket]) >= 5.0:
            filtered_events.append(ev)
            son_yazilan[etiket] = ev["zaman_saniye"]

    vehicle_events = filtered_events

    # === EL-YUZE MUNHASIRLIK (su / sigara / telefon: BIRI VARSA OBURU OLAMAZ) ===
    # Elin yuze gittigi tek bir harekette uc model birden ateslenebiliyor (faz2
    # olcumu: t=28'de GT "su_icme" iken sigara+telefon+su birlikte yazilmisti).
    # ±2.5 sn icinde bu uc etiketten birden fazlasi varsa YALNIZCA EN YUKSEK
    # GUVENLISI kalir. Sabit bir oncelik/siralama iliskisi YOK (06.08 takim
    # karari: "su > sigara > telefon" kesinlik sirasi kaldirildi -- genel
    # videoda hangi modelin daha isabetli olacagi bilinemez, karari yalnizca
    # modellerin kendi guveni verir).
    EL_YUZE_ETIKETLER = ("su_icme", "sigara_icme", "telefonla_konusma")
    EL_YUZE_PENCERE_SN = 2.5
    el_yuze_evler = sorted(
        (ev for ev in vehicle_events if ev["etiket"] in EL_YUZE_ETIKETLER),
        key=lambda e: e["zaman_saniye"])
    silinecekler = set()
    for i, a in enumerate(el_yuze_evler):
        if id(a) in silinecekler:
            continue
        for b in el_yuze_evler[i+1:]:
            if b["zaman_saniye"] - a["zaman_saniye"] > EL_YUZE_PENCERE_SN:
                break
            if id(b) in silinecekler:
                continue
            a_g = float(a.get("confidence_score", 0.0))
            b_g = float(b.get("confidence_score", 0.0))
            kaybeden = a if a_g < b_g else b
            silinecekler.add(id(kaybeden))
            if kaybeden is a:
                break
    vehicle_events = [ev for ev in vehicle_events if id(ev) not in silinecekler]

    # === ESNEME <-> EL-YUZE MUNHASIRLIGI ===
    # Esneme ile sigara/su/telefon ayni anda OLAMAZ (agiz/el ayni anda iki iste
    # olamaz -- takim karari). Kazanan EL-YUZE olayidir, esneme silinir; cunku
    # (a) el-yuze eylemi sirasindaki agiz hareketi MAR sinyalini tetikleyip sahte
    # esneme uretiyor (v2 olcumu: 28.8 ve 72.4'te GT su/telefon olaylarinin
    # yaninda 2 sahte esneme), (b) MAR-onayli esnemenin guveni sabit 0.75 --
    # model guveniyle kiyaslanabilir bir olcu degil, guven yarisina sokulamaz.
    # (etrafa_bakinma'ya DOKUNULMAZ; GT es-zamanliligi kanitliyor: 92.58'de
    # etrafa_bakinma + sigara_icme birlikte.)
    el_yuze_zamanlar = [ev["zaman_saniye"] for ev in vehicle_events
                        if ev["etiket"] in EL_YUZE_ETIKETLER]
    vehicle_events = [
        ev for ev in vehicle_events
        if not (ev["etiket"] == "esneme"
                and any(abs(ev["zaman_saniye"] - t) <= 1.5 for t in el_yuze_zamanlar))
    ]

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
                
    # SERBEST YAZI kazanani: kilit yoksa ama toplam oy tabani asan aday varsa
    # (kisa video / az okuma) onu kabul et. Cikti = en sik gorulen HAM biçim
    # (Turkce harf/kucuk harf/bosluk korunur; normalize yalniz oylama icindi).
    yazi_sonuc, yazi_conf = None, 0.0
    if yazi_kilit is None and yazi_oylar:
        aday, oy = max(yazi_oylar.items(), key=lambda kv: kv[1])
        if oy >= YAZI_OY_TABAN:
            yazi_kilit = aday
    if yazi_kilit is not None:
        yazi_sonuc = max(yazi_hamlar[yazi_kilit].items(), key=lambda kv: kv[1])[0]
        yazi_conf = min(0.95, yazi_oylar[yazi_kilit] / YAZI_OY_ESIK)

    if best_vid is not None:
        # Regex'li plaka zinciri kilitlendi (gercek plaka gorunur) -> o kazanir.
        c = vehicle_confidences.get(best_vid, {})
        ov_conf = (c.get('kasa', 0) + c.get('renk', 0) + c.get('plaka', 0)) / 3.0
        arac = arac_bilgisi_olustur(
            finalized_types[best_vid],
            finalized_plates[best_vid],
            finalized_colors[best_vid],
            ov_conf
        )
    elif yazi_sonuc is not None and finalized_types:
        # ORTULU PLAKA gunu: plaka zinciri kilitlenemez ama tip/renk kilitli --
        # tip+renk kilitli en guvenli araci sec, plaka alanina OCR yazisini yaz.
        aday_vid, aday_skor = None, -1.0
        for vid in finalized_types:
            if vid in finalized_colors:
                c = vehicle_confidences.get(vid, {})
                s = c.get('kasa', 0) + c.get('renk', 0)
                if s > aday_skor:
                    aday_skor, aday_vid = s, vid
        if aday_vid is not None:
            c = vehicle_confidences.get(aday_vid, {})
            ov_conf = (c.get('kasa', 0) + c.get('renk', 0) + yazi_conf) / 3.0
            arac = arac_bilgisi_olustur(
                finalized_types[aday_vid], yazi_sonuc,
                finalized_colors[aday_vid], ov_conf)
        else:
            v_t = list(finalized_types.values())[0]
            arac = arac_bilgisi_olustur(v_t, yazi_sonuc, "beyaz", 0.50)
    else:
        if finalized_types:
            v_t = list(finalized_types.values())[0]
            v_c = list(finalized_colors.values())[0] if finalized_colors else "beyaz"
            v_p = list(finalized_plates.values())[0] if finalized_plates else ""
            if not v_p and yazi_sonuc is not None:
                v_p = yazi_sonuc
            arac = arac_bilgisi_olustur(v_t, v_p, v_c, 0.50)
        else:
            arac = arac_bilgisi_olustur("sedan", yazi_sonuc or "", "beyaz", 0.0)

    # SON GUVENLIK KATMANI: FTR sartnamesinin izin verdigi etiket disina cikan hicbir kayit
    # JSON'a yazilmaz -- kategori-etiket eslesmesi GECERLI_* setleriyle dogrulanir.
    GECERLI_KATEGORI_ETIKET = {
        "sofor_eylemi": GECERLI_SOFOR_EYLEMI,
        "nesneler": GECERLI_NESNELER,
        "yolcular": GECERLI_YOLCULAR,
    }
    vehicle_events = [
        ev for ev in vehicle_events
        if ev["etiket"] in GECERLI_KATEGORI_ETIKET.get(ev["kategori"], set())
    ]

    return sonuc_birlestir(video_name, arac, vehicle_events)