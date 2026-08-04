"""Incremental (streaming) dedektörlerin, FTR'deki batch mantığıyla AYNI sonucu
ürettiğini kanıtlayan testler — plan "Doğrulama Planı" son maddesi.

Refactor'ın davranışı bozmadığının kanıtı budur: aynı girdi dizisi hem referans
batch fonksiyonundan hem streaming dedektöründen geçirilir, çıktılar karşılaştırılır.
Rastgele üretilmiş yüzlerce senaryo ile denenir (sabit tohum → tekrarlanabilir).
"""

import random

import numpy as np
import pytest

from app.services.vehicle_ai.streaming.event_gate import EventGate
from app.services.vehicle_ai.streaming.events import DetectedEvent
from app.services.vehicle_ai.streaming.run_detectors import (
    ConsecutiveRunDetector,
    HeadTurnDetector,
    SeatbeltDetector,
    YawnDetector,
)
from tests import reference_batch as ref

TOLERANS = 1e-9


def _stream(detector, samples, value_getter):
    """Örnekleri sırayla dedektöre verip toplanan olayları döndürür."""
    events = []
    for sn, value in samples:
        ev = detector.observe(sn, value_getter(value))
        if ev is not None:
            events.append(ev)
    ev = detector.finalize()
    if ev is not None:
        events.append(ev)
    return events


@pytest.mark.parametrize("seed", range(40))
def test_ardisik_seg_esdegerligi(seed):
    rng = random.Random(seed)
    n = rng.randint(1, 120)
    samples = [
        (round(i * 0.25, 2), rng.choice([None, round(rng.uniform(0.45, 0.99), 3)]))
        for i in range(n)
    ]
    gerek = rng.randint(1, 4)

    beklenen = ref.ardisik_seg(samples, gerek)
    detector = ConsecutiveRunDetector("sofor_eylemi", "telefonla_konusma", gerek)
    alinan = _stream(detector, samples, lambda v: v)

    assert len(alinan) == len(beklenen)
    for got, (zaman, tepe) in zip(alinan, beklenen):
        assert got.zaman_saniye == pytest.approx(zaman, abs=TOLERANS)
        assert got.confidence_score == pytest.approx(tepe, abs=TOLERANS)
        assert got.etiket == "telefonla_konusma"


@pytest.mark.parametrize("seed", range(40))
def test_esneme_seg_esdegerligi(seed):
    """Batch, MAR tabanını tüm videonun medyanından hesaplar. Streaming'de bu
    mümkün olmadığı için `fixed_baseline` ile aynı taban verilir; bu koşulda
    çıktıların birebir aynı olması beklenir."""
    rng = random.Random(seed)
    n = rng.randint(1, 150)
    # Zaman zaman uzun "ağız açık" platoları oluşacak şekilde üret
    samples = []
    i = 0
    while len(samples) < n:
        if rng.random() < 0.25:
            plato = rng.randint(1, 14)
            for _ in range(plato):
                samples.append((round(i * 0.25, 2), round(rng.uniform(0.20, 0.40), 4)))
                i += 1
        else:
            samples.append((round(i * 0.25, 2), round(rng.uniform(0.05, 0.12), 4)))
            i += 1
    samples = samples[:n]

    taban = float(np.median([m for _, m in samples]))
    beklenen = ref.esneme_seg(samples)

    detector = YawnDetector(
        oran_esik=ref.ORAN_ESIK,
        plato_gerek=ref.PLATO_GEREK,
        hareket_esik=ref.HAREKET_ESIK,
        baseline_min_ornek=0,
        fixed_baseline=taban,
    )
    alinan = _stream(detector, samples, lambda v: v)

    assert len(alinan) == len(beklenen)
    for got, (zaman, tepe) in zip(alinan, beklenen):
        assert got.zaman_saniye == pytest.approx(zaman, abs=TOLERANS)
        assert got.confidence_score == pytest.approx(min(0.99, 0.5 + tepe / 20), abs=TOLERANS)
        assert got.etiket == "esneme"


@pytest.mark.parametrize("seed", range(40))
def test_bakinma_seg_esdegerligi(seed):
    rng = random.Random(seed)
    n = rng.randint(1, 150)
    dt = 0.25
    samples = []
    i = 0
    while len(samples) < n:
        # Bazen uzun süreli aynı yöne bakma blokları üret
        if rng.random() < 0.3:
            uzunluk = rng.randint(1, 25)
            deger = rng.uniform(0.30, 0.9) * rng.choice([-1, 1])
            for _ in range(uzunluk):
                samples.append((round(i * dt, 2), round(deger + rng.uniform(-0.02, 0.02), 4)))
                i += 1
        else:
            samples.append((round(i * dt, 2), round(rng.uniform(-0.29, 0.29), 4)))
            i += 1
    samples = samples[:n]

    beklenen = ref.bakinma_seg(samples, dt)
    detector = HeadTurnDetector(
        donuk_offset=ref.DONUK_OFFSET,
        t_arkaya=ref.T_ARKAYA,
        t_etrafa_min=ref.T_ETRAFA_MIN,
        ornekleme_araligi=dt,
    )
    alinan = _stream(detector, samples, lambda v: v)

    assert len(alinan) == len(beklenen)
    for got, (etiket, orta, sure) in zip(alinan, beklenen):
        assert got.etiket == etiket
        assert got.zaman_saniye == pytest.approx(orta, abs=TOLERANS)
        assert got.confidence_score == pytest.approx(min(0.99, 0.5 + sure / 10), abs=TOLERANS)


def test_bakinma_gorunmeyen_ornekleri_blogu_kesmez():
    """Sürücünün görünmediği (offset None) örnekler diziye hiç eklenmez —
    orijinal kodda da `if o is not None` ile filtreleniyordu."""
    dt = 0.25
    gecerli = [(0.0, 0.5), (0.25, 0.5), (0.5, 0.5), (0.75, 0.5), (1.0, 0.5), (1.25, 0.5)]
    beklenen = ref.bakinma_seg(gecerli, dt)

    detector = HeadTurnDetector(ref.DONUK_OFFSET, ref.T_ARKAYA, ref.T_ETRAFA_MIN, dt)
    events = []
    for sn, val in [(0.0, 0.5), (0.1, None), (0.25, 0.5), (0.3, None), (0.5, 0.5),
                    (0.75, 0.5), (1.0, 0.5), (1.25, 0.5)]:
        ev = detector.observe(sn, val)
        if ev:
            events.append(ev)
    ev = detector.finalize()
    if ev:
        events.append(ev)

    assert len(events) == len(beklenen) == 1
    assert events[0].etiket == beklenen[0][0]


@pytest.mark.parametrize("seed", range(30))
def test_kemer_ihlali_esdegerligi(seed):
    rng = random.Random(seed)
    n = rng.randint(1, 100)
    kemer_gerek = 10
    fail_safe = 3

    surucu_var_kayit = []
    kemer_kayit = []
    for i in range(n):
        sn = round(i * 0.25, 2)
        sofor_var = rng.random() < 0.85
        surucu_var_kayit.append((sn, sofor_var))
        kemer = round(rng.uniform(0.5, 0.9), 3) if (sofor_var and rng.random() < 0.15) else None
        kemer_kayit.append((sn, kemer))

    beklenen_zaman = ref.kemer_ihlali(kemer_kayit, surucu_var_kayit, kemer_gerek, fail_safe)

    detector = SeatbeltDetector(kemer_gerek=kemer_gerek, fail_safe_gorulme=fail_safe)
    olay = None
    for (sn, sofor_var), (_, kemer) in zip(surucu_var_kayit, kemer_kayit):
        ev = detector.observe(sn, sofor_var, kemer)
        if ev is not None and olay is None:
            olay = ev

    # Nihai çıktı kuralı: kemer video boyunca yeterince görüldüyse ihlal geçersizdir.
    nihai = None if (olay is None or detector.suppressed) else olay

    if beklenen_zaman is None:
        assert nihai is None
    else:
        assert nihai is not None
        assert nihai.zaman_saniye == pytest.approx(beklenen_zaman, abs=TOLERANS)
        assert nihai.confidence_score == pytest.approx(0.50, abs=TOLERANS)


@pytest.mark.parametrize("seed", range(40))
def test_event_gate_esdegerligi(seed):
    """Çakışma önleme + cooldown + etiket başına max adet filtrelerinin,
    batch versiyonuyla aynı olay kümesini ürettiğini doğrular."""
    rng = random.Random(seed)
    etiketler = ["sigara_icme", "su_icme", "telefonla_konusma", "etrafa_bakinma", "esneme"]
    n = rng.randint(1, 30)

    kararlar = []
    for _ in range(n):
        kararlar.append(
            (
                round(rng.uniform(0, 60), 2),
                "sofor_eylemi",
                rng.choice(etiketler),
                round(rng.uniform(0.5, 0.99), 3),
            )
        )

    beklenen = ref.cakisma_ve_cooldown(list(kararlar), cooldown=3.0, marj=1.5, max_olay=1)

    gate = EventGate(cooldown_saniye=3.0, cakisma_marji_saniye=1.5, etiket_basina_max_olay=1)
    for zaman, kategori, etiket, guven in kararlar:
        gate.submit(DetectedEvent(zaman, kategori, etiket, guven))
    alinan = gate.flush()

    assert len(alinan) == len(beklenen)
    for got, (zaman, kategori, etiket, guven) in zip(alinan, beklenen):
        assert got.zaman_saniye == pytest.approx(zaman, abs=TOLERANS)
        assert got.etiket == etiket
        assert got.confidence_score == pytest.approx(guven, abs=TOLERANS)


def test_event_gate_cakisan_bakinmayi_bekletir_ve_bastirir():
    """Canlı akışta `etrafa_bakinma`, çakışma penceresi dolana kadar yayınlanmaz;
    o pencerede sigara içme gelirse hiç yayınlanmaz."""
    gate = EventGate(cooldown_saniye=3.0, cakisma_marji_saniye=1.5, etiket_basina_max_olay=1)
    gate.submit(DetectedEvent(10.0, "sofor_eylemi", "etrafa_bakinma", 0.7))

    # Pencere dolmadan yayınlanmamalı
    assert gate.drain(simdiki_zaman=10.5) == []

    # Pencere içinde çakışan olay geldi → bakınma bastırılır
    gate.submit(DetectedEvent(11.0, "sofor_eylemi", "sigara_icme", 0.8))
    yayinlananlar = gate.drain(simdiki_zaman=13.0)

    assert [e.etiket for e in yayinlananlar] == ["sigara_icme"]


def test_event_gate_cakismayan_bakinmayi_yayinlar():
    gate = EventGate(cooldown_saniye=3.0, cakisma_marji_saniye=1.5, etiket_basina_max_olay=1)
    gate.submit(DetectedEvent(10.0, "sofor_eylemi", "etrafa_bakinma", 0.7))
    yayinlananlar = gate.drain(simdiki_zaman=13.0)
    assert [e.etiket for e in yayinlananlar] == ["etrafa_bakinma"]
