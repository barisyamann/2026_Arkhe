#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
NPU cok-vektorlu dogruluk testi icin girdi vektorleri ve beklenen ciktilar uretir.

Sartname EK-1:
    "Yarismacilar, YZ hizlandiricisini kullanarak, yazilim ile gerceklenen
     modelin dogrulugunu (accuracy) %10'luk bir pencere dahilinde
     yakalamalidir."

Yontem: AYNI 1960 INT8 girdi hem yazilim referans modeline hem RTL'e verilir.
Dort sinifi da uyaran vektorler aranir, boylece test yalnizca tek bir kod
yolunu degil karar mekanizmasinin tamamini kapsar.

Ciktilar:
    vectors.mem            - tum vektorler ard arda (her biri 490 x 32-bit word)
    vectors_expected.svh   - testbench'in okudugu beklenen deger tablolari
    vectors_meta.json      - insan tarafindan okunabilir ozet
"""
import json
import sys
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from npu_ref_model import NpuReferansModel, SINIF_ADLARI, GIRIS_UZUNLUK  # noqa: E402

TOHUM = 20260831          # teslim tarihi - tekrarlanabilirlik icin sabit
ARAMA_BUTCESI = 4000


def aday_uret(rng, k):
    """Cesitli istatistiklerde aday girdi vektorleri uretir.

    Tek bir dagilimdan cekmek karar sinirlarinin cogunu hic uyarmaz; bu yuzden
    farkli ortalama/varyans/yapi kombinasyonlari denenir.
    """
    tur = k % 5
    if tur == 0:                                    # duzgun dagilim
        v = rng.integers(-128, 128, GIRIS_UZUNLUK)
    elif tur == 1:                                  # dusuk enerji (sessizlige yakin)
        v = rng.integers(-128, -90, GIRIS_UZUNLUK)
    elif tur == 2:                                  # yuksek enerji
        v = rng.integers(60, 128, GIRIS_UZUNLUK)
    elif tur == 3:                                  # zaman ekseninde bantli yapi
        v = np.full(GIRIS_UZUNLUK, -128, dtype=np.int64)
        t0 = int(rng.integers(0, 40))
        gen = int(rng.integers(3, 12))
        for t in range(t0, min(49, t0 + gen)):
            f0 = int(rng.integers(0, 30))
            v[t * 40 + f0: t * 40 + min(40, f0 + 10)] = rng.integers(0, 128, 
                                                                     min(40, f0 + 10) - f0)
    else:                                           # gauss
        v = np.clip(rng.normal(rng.integers(-100, 60), rng.integers(10, 70),
                               GIRIS_UZUNLUK), -128, 127).astype(np.int64)
    return [int(x) for x in v]


def paketle(qin):
    """1960 INT8 -> 490 adet 32-bit little-endian word (TCM duzeni)."""
    words = []
    for i in range(0, GIRIS_UZUNLUK, 4):
        w = 0
        for b in range(4):
            w |= (qin[i + b] & 0xFF) << (8 * b)
        words.append(w)
    assert len(words) == 490
    return words


def main():
    model = NpuReferansModel()
    rng = np.random.default_rng(TOHUM)

    bulunan = {}          # sinif -> (qin, sonuc)
    denenen = 0
    for k in range(ARAMA_BUTCESI):
        if len(bulunan) == 4:
            break
        qin = aday_uret(rng, k)
        r = model.infer(qin)
        denenen += 1
        c = r["sinif"]
        if c not in bulunan:
            bulunan[c] = (qin, r)
            print("  sinif %d (%-7s) bulundu  -  %d aday denendi"
                  % (c, SINIF_ADLARI[c], denenen))

    if not bulunan:
        sys.exit("Hicbir vektor bulunamadi")

    # Deterministik golden vektorunu de ekle: RTL ile zaten dogrulanmis referans
    golden = [((i * 37 + 13) % 256) - 128 for i in range(GIRIS_UZUNLUK)]
    liste = [(golden, model.infer(golden), "deterministik_golden")]
    for c in sorted(bulunan):
        qin, r = bulunan[c]
        liste.append((qin, r, "rastgele_sinif%d_%s" % (c, SINIF_ADLARI[c].lower())))

    # -------------------------------------------------------------------------
    # GERCEK SES VEKTORLERI  (Sartname EK-3)
    #
    #   "Referans ses verilerini (ornekler TFLite Micro deposunda bulunabilir
    #    ve 1000 milisaniyelik mono kanalli WAV dosyalari da test verisine
    #    donusturulebilir) bellekten hizlandirici cekirdegine suren ve
    #    ciktilari kontrol eden ... testler."
    #
    # WAV -> 1960 INT8 donusumu micro_frontend.py ile yapilir. Yalnizca
    # AYIRT EDICI klipler alinir: yes ve no, modelin yuksek guvenle dogru
    # siniflandirdigi orneklerdir.
    #
    # silence_1000ms.wav BILEREK DISARIDA BIRAKILDI: bu modelde tamamen
    # doygun bir girdi dort sinifa da esit olasilik verir (probs =
    # [1024,1024,1024,1024]) ve sonuc argmax'in beraberlik cozumune kalir.
    # Bu modelin bir ozelligidir, tasarimin degil; regresyona kirilgan bir
    # denetim koymanin anlami yok. Bulgu evidence/npu/ altinda kayitli.
    # -------------------------------------------------------------------------
    try:
        from micro_frontend import wav_to_features
        td = HERE / "testdata"
        for wav_ad, beklenen in [("yes_1000ms.wav", "YES"), ("no_1000ms.wav", "NO")]:
            p = td / wav_ad
            if not p.exists():
                print("  UYARI: %s yok, atlaniyor" % wav_ad)
                continue
            qin = wav_to_features(p)
            r = model.infer(qin)
            durum = "OK" if r["sinif_adi"] == beklenen else "SAPMA"
            print("  ses %-20s -> %-8s (beklenen %-8s) %s"
                  % (wav_ad, r["sinif_adi"], beklenen, durum))
            if r["sinif_adi"] != beklenen:
                print("     regresyona EKLENMEDI - once on isleme incelenmeli")
                continue
            liste.append((qin, r, "ses_%s" % wav_ad.replace("_1000ms.wav", "")))
    except ImportError as e:
        print("  UYARI: micro_frontend yuklenemedi (%s) - ses vektorleri atlandi" % e)

    # --- vectors.mem ---
    satirlar = []
    for qin, _, _ in liste:
        satirlar += ["%08x" % w for w in paketle(qin)]
    (HERE / "vectors.mem").write_text("\n".join(satirlar) + "\n")

    # --- vectors_expected.svh ---
    n = len(liste)
    L = []
    L.append("// OTOMATIK URETILDI - gen_vectors.py  (tohum=%d)" % TOHUM)
    L.append("// Elle duzenlemeyin. Yeniden uretmek icin:")
    L.append("//     python tb/npu_audio/gen_vectors.py")
    L.append("localparam int VEKTOR_SAYISI = %d;" % n)
    L.append("localparam int VEKTOR_WORD   = 490;")
    L.append("")
    L.append("localparam logic [1:0] BEKLENEN_SINIF [0:%d] = '{%s};"
             % (n - 1, ", ".join("2'd%d" % r["sinif"] for _, r, _ in liste)))
    for i in range(4):
        L.append("localparam int BEKLENEN_LOGIT%d [0:%d] = '{%s};"
                 % (i, n - 1, ", ".join("%d" % r["logits"][i] for _, r, _ in liste)))
    for i in range(4):
        L.append("localparam int BEKLENEN_PROB%d [0:%d] = '{%s};"
                 % (i, n - 1, ", ".join("%d" % r["probs"][i] for _, r, _ in liste)))
    L.append("")
    L.append("// Vektor adlari (raporlama icin)")
    for i, (_, _, ad2) in enumerate(liste):
        L.append('// [%d] %s' % (i, ad2))
    (HERE / "vectors_expected.svh").write_text("\n".join(L) + "\n")

    # --- meta ---
    meta = dict(
        tohum=TOHUM, aday_denenen=denenen, vektor_sayisi=n,
        aciklama="Ayni girdi hem yazilim referans modeline hem RTL'e verilir; "
                 "siniflandirma ve softmax olasiliklari birebir esitlenmelidir.",
        vektorler=[dict(ad=ad, sinif=r["sinif"], sinif_adi=r["sinif_adi"],
                        logits=r["logits"], probs=r["probs"])
                   for _, r, ad in liste])
    (HERE / "vectors_meta.json").write_text(json.dumps(meta, indent=2, ensure_ascii=False))

    print()
    print("%d vektor yazildi:" % n)
    for _, r, ad in liste:
        print("   %-34s -> %d (%s)  probs=%s" % (ad, r["sinif"], r["sinif_adi"], r["probs"]))
    kapsanan = sorted(set(r["sinif"] for _, r, _ in liste))
    print("\nKapsanan siniflar: %s" % kapsanan)


if __name__ == "__main__":
    main()
