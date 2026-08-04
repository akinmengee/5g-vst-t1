"""FTR'de teslim edilen `predict.py`'deki zamansal post-processing fonksiyonlarının
birebir kopyası — testlerde "doğru cevap" referansı olarak kullanılır.

`_ftr_reference/predict.py` import edilemiyor (modül import anında tüm YOLO
modellerini yüklüyor), bu yüzden sadece saf/modelden bağımsız fonksiyonlar
buraya kopyalandı. **Bu dosyayı değiştirmeyin** — streaming implementasyonunun
karşılaştırıldığı referanstır.
"""

import numpy as np

ORAN_ESIK = 2.0
PLATO_GEREK = 8
HAREKET_ESIK = 1.5
DONUK_OFFSET = 0.30
T_ARKAYA = 4.0
T_ETRAFA_MIN = 1.2


def ardisik_seg(varlik, gerek):
    seg = []
    i = 0
    n = len(varlik)
    while i < n:
        if varlik[i][1] is not None:
            j = i
            while j + 1 < n and varlik[j + 1][1] is not None:
                j += 1
            if (j - i + 1) >= gerek:
                tepe = max(varlik[k][1] for k in range(i, j + 1))
                seg.append(((varlik[i][0] + varlik[j][0]) / 2, tepe))
            i = j + 1
        else:
            i += 1
    return seg


def esneme_seg(mar_kayit):
    if not mar_kayit:
        return []
    marlar = [m for _, m in mar_kayit]
    taban = float(np.median(marlar))
    oranlar = [(m / taban if taban > 1e-6 else 0) for _, m in mar_kayit]
    acik = set(i for i, o in enumerate(oranlar) if o >= ORAN_ESIK)
    out = []
    i = 0
    n = len(mar_kayit)
    while i < n:
        if i in acik:
            j = i
            while j + 1 < n and (j + 1) in acik:
                j += 1
            if (j - i + 1) >= PLATO_GEREK:
                tepe = max(oranlar[i : j + 1])
                giris = oranlar[i - 1] if i > 0 else oranlar[i]
                cikis = oranlar[j + 1] if j + 1 < n else oranlar[j]
                if tepe - min(giris, cikis) >= HAREKET_ESIK:
                    out.append(((mar_kayit[i][0] + mar_kayit[j][0]) / 2, tepe))
            i = j + 1
        else:
            i += 1
    return out


def bakinma_seg(off_kayit, dt):
    durum = [
        (sn, ("L" if o < 0 else "R") if (o is not None and abs(o) >= DONUK_OFFSET) else None)
        for sn, o in off_kayit
    ]
    out = []
    i = 0
    n = len(durum)
    while i < n:
        if durum[i][1] is not None:
            j = i
            yon = durum[i][1]
            while j + 1 < n and durum[j + 1][1] == yon:
                j += 1
            sure = (durum[j][0] - durum[i][0]) + dt
            orta = (durum[i][0] + durum[j][0]) / 2
            if sure >= T_ARKAYA:
                out.append(("arkaya_bakma", orta, sure))
            elif sure >= T_ETRAFA_MIN:
                out.append(("etrafa_bakinma", orta, sure))
            i = j + 1
        else:
            i += 1
    return out


def kemer_ihlali(yolo_kemer_kayit, surucu_var_kayit, kemer_gerek=10, fail_safe=3):
    """`predict.py`'deki kemer post-processing bloğunun birebir karşılığı."""
    kemer_var = set(s for s, g in yolo_kemer_kayit if g is not None)
    if len(kemer_var) >= fail_safe:
        return None

    sofor_net = [s for s, var in surucu_var_kayit if var]
    ihlal = [(s, s in kemer_var) for s in sofor_net]
    i = 0
    n = len(ihlal)
    while i < n:
        if not ihlal[i][1]:
            j = i
            while j + 1 < n and not ihlal[j + 1][1]:
                j += 1
            if (j - i + 1) >= kemer_gerek:
                return ihlal[i][0]
            i = j + 1
        else:
            i += 1
    return None


def cakisma_ve_cooldown(kararlar, cooldown=3.0, marj=1.5, max_olay=1):
    """`predict.py`'deki çakışma önleme + cooldown + max-adet filtrelerinin birleşimi.

    kararlar: [(zaman, kategori, etiket, guven), ...]
    """
    bakinmalar = [k for k in kararlar if k[2] == "etrafa_bakinma"]
    digerleri = [k for k in kararlar if k[2] in ("sigara_icme", "su_icme")]
    yeni_kararlar = [k for k in kararlar if k[2] != "etrafa_bakinma"]
    for b in bakinmalar:
        cakisiyor = False
        for d in digerleri:
            if abs(b[0] - d[0]) <= marj:
                cakisiyor = True
                break
        if not cakisiyor:
            yeni_kararlar.append(b)
    kararlar = yeni_kararlar

    kararlar.sort()
    son_zaman = {}
    events = []
    for sn, kat, et, guv in kararlar:
        if et not in son_zaman or (sn - son_zaman[et]) >= cooldown:
            events.append((sn, kat, et, guv))
            son_zaman[et] = sn

    filtered = []
    seen = {}
    for ev in events:
        et = ev[2]
        seen[et] = seen.get(et, 0) + 1
        if seen[et] <= max_olay:
            filtered.append(ev)
    return filtered
