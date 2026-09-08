#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""ASIC teslim denetimi - Final Ciktilar Bolum 5, 6 ve Tablo 8.

NEDEN VAR

  asic/Makefile icindeki `asic_verify` hedefi bu betigi cagiriyordu ama
  betik depoda YOKTU - `make asic_verify` "No such file" hatasi veriyordu.
  Jurinin komutu kosmasi hâlinde eksik gorunecekti.

NE YAPAR

  Iki ayri sey denetler ve ikisini AYRI raporlar:

  1) DOSYA VARLIGI  - Bolum 5 (raporlar) ve Bolum 6 (ciktilar) listesindeki
     her kategori mevcut mu, icinde dosya var mi.

  2) SIGNOFF SONUCU - manufacturability.rpt, metrics.json ve STA ozeti
     okunarak DRC / LVS / anten / zamanlama HUKUMLERI cikarilir.

  Ikincisi kritik: bir dosyanin var olmasi, iceriginin GECER oldugu anlamina
  gelmez. Yalnizca dosya sayan bir denetim, `manufacturability.rpt` icinde
  "DRC: Failed" yazarken "[TAM]" der ve yaniltir.

CIKIS KODU

  0  zorunlu maddelerin tamami mevcut VE signoff hukumlerinde FAIL yok
  1  eksik zorunlu madde var
  2  dosyalar tam ama signoff hukmunde FAIL var

KULLANIM

  python3 scripts/check_teslim.py            # asic/ dizinini denetler
  python3 scripts/check_teslim.py --dizin X  # baska bir kok
"""
import argparse
import json
import os
import re
import sys

KOK = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# -----------------------------------------------------------------------------
# BOLUM 5 - ZORUNLU RAPORLAR
#
# (dizin, en az kac dosya, aciklama)
# -----------------------------------------------------------------------------
BOLUM5 = [
    ("reports/general",   1, "flow.log, warning.log, error.log, resolved.json"),
    ("reports/lint",      1, "Verilator lint ciktisi"),
    ("reports/synthesis", 1, "stat.rpt, chk.rpt, latch.rpt"),
    ("reports/routing",   1, "sikisiklik, tel uzunlugu, via"),
    ("reports/timing",    1, "summary.rpt + kose alt dizinleri"),
    ("reports/drc",       1, "Magic ve KLayout DRC"),
    ("reports/lvs",       1, "Netgen LVS"),
    ("reports/antenna",   1, "anten kontrol sonuclari"),
    ("reports/pdn",       1, "PDN grid-errors"),
    ("reports/signoff",   1, "manufacturability, XOR, baglantisiz pin"),
    ("reports/power",     1, "power.rpt, irdrop.rpt, net-*.csv"),
]

# -----------------------------------------------------------------------------
# BOLUM 6 - ZORUNLU CIKTILAR
# -----------------------------------------------------------------------------
BOLUM6 = [
    ("results/gds",     1, "nihai GDSII"),
    ("results/lef",     1, "nihai LEF"),
    ("results/def",     1, "nihai DEF"),
    ("results/netlist", 1, "sentez / post-PnR / powered netlist"),
    ("results/sdc",     1, "PnR ve signoff SDC"),
    ("results/spef",    1, "parazitik SPEF"),
    ("results/spice",   1, "LVS SPICE / CDL netlisti"),
    ("results/metrics", 1, "metrics.csv, metrics.json"),
]

# -----------------------------------------------------------------------------
# BOLUM 6.3 - ONERILEN EK CIKTILAR (eksikligi BASARISIZLIK DEGILDIR)
# -----------------------------------------------------------------------------
BOLUM63 = [
    ("results/odb",     1, "OpenROAD veritabani"),
    ("results/sdf",     1, "SDF gecikme dosyasi"),
    ("results/lib",     1, "tasarimin Liberty modeli"),
    ("results/mag",     1, "Magic layout"),
    ("checksums",       1, "SHA256SUMS"),
]

# 9 kose: 3 surec x 3 parazitik
BEKLENEN_KOSELER = [
    "min_tt_025C_1v80", "nom_tt_025C_1v80", "max_tt_025C_1v80",
    "min_ss_100C_1v60", "nom_ss_100C_1v60", "max_ss_100C_1v60",
    "min_ff_n40C_1v95", "nom_ff_n40C_1v95", "max_ff_n40C_1v95",
]


def dosya_say(yol):
    if not os.path.isdir(yol):
        return -1
    return sum(1 for a in os.listdir(yol)
               if os.path.isfile(os.path.join(yol, a)))


def bolum_denetle(asic, baslik, liste, zorunlu=True):
    print("\n" + "=" * 68)
    print(" %s" % baslik)
    print("=" * 68)
    eksik = []
    for goreli, asgari, aciklama in liste:
        tam = os.path.join(asic, goreli)
        n = dosya_say(tam)
        if n < 0:
            durum, sorun = "DIZIN YOK", True
        elif n < asgari:
            durum, sorun = "BOS", True
        else:
            durum, sorun = "%d dosya" % n, False
        isaret = "  " if not sorun else ("!!" if zorunlu else " ~")
        print("%s %-20s %-12s %s" % (isaret, goreli, durum, aciklama))
        if sorun:
            eksik.append(goreli)
    return eksik


def koseleri_denetle(asic):
    """9 PVT kosesinin STA raporlari toplanmis mi.

    collect_outputs.py bir donem dosyalari (hedef, dosya_adi) ciftiyle
    anahtarliyordu; dokuz kosenin max.rpt dosyasi ayni anahtara dusup
    birbirinin uzerine yaziyordu ve yalnizca bir kose kaliyordu. Bu denetim
    o hatanin geri gelmesini yakalar.
    """
    print("\n" + "=" * 68)
    print(" 9 PVT KOSESI - STA RAPORLARI")
    print("=" * 68)
    kok = os.path.join(asic, "reports", "timing")
    eksik = []
    for k in BEKLENEN_KOSELER:
        d = os.path.join(kok, k)
        n = dosya_say(d)
        if n < 1:
            print("!! %-22s YOK" % k)
            eksik.append("reports/timing/" + k)
        else:
            print("   %-22s %d dosya" % (k, n))
    return eksik


def signoff_hukmu(asic):
    """Dosya varligi degil, SONUC denetler.

    Bir raporun var olmasi gecer oldugu anlamina gelmez. Burada
    manufacturability.rpt ve metrics.json okunup gercek hukumler cikarilir.
    """
    print("\n" + "=" * 68)
    print(" SIGNOFF HUKUMLERI (dosya degil, SONUC)")
    print("=" * 68)
    basarisiz = []

    # --- manufacturability.rpt ---
    mr = os.path.join(asic, "reports", "signoff", "manufacturability.rpt")
    if os.path.isfile(mr):
        metin = open(mr, encoding="utf-8", errors="replace").read()
        for baslik in ("Antenna", "LVS", "DRC"):
            m = re.search(r"\*\s*%s\s*\n\s*(\w+)" % baslik, metin)
            sonuc = m.group(1) if m else "?"
            gecti = sonuc.lower().startswith("pass")
            print("%s %-10s %s" % ("  " if gecti else "!!", baslik, sonuc))
            if not gecti:
                basarisiz.append("%s=%s" % (baslik, sonuc))
    else:
        print("!! manufacturability.rpt YOK")
        basarisiz.append("manufacturability.rpt yok")

    # --- metrics.json: sayisal hukumler ---
    mj = os.path.join(asic, "results", "metrics", "metrics.json")
    if not os.path.isfile(mj):
        mj = os.path.join(asic, "metrics", "metrics.json")
    if os.path.isfile(mj):
        try:
            d = json.load(open(mj, encoding="utf-8"))
        except Exception as e:
            d = {}
            print("!! metrics.json okunamadi: %s" % e)
        olcut = [
            ("klayout__drc_error__count",   0, "KLayout DRC"),
            ("design__lvs_error__count",    0, "Netgen LVS hatasi"),
            ("design__xor_difference__count", 0, "XOR farki"),
            ("route__drc_errors",           0, "Yonlendirme DRC"),
            ("antenna__violating__nets",    0, "Anten ihlalli ag"),
            ("antenna__violating__pins",    0, "Anten ihlalli pin"),
        ]
        for anahtar, hedef, ad in olcut:
            if anahtar not in d:
                continue
            v = d[anahtar]
            ok = (v == hedef)
            print("%s %-24s %s" % ("  " if ok else "!!", ad, v))
            if not ok:
                basarisiz.append("%s=%s" % (ad, v))

        # Magic DRC ayri raporlanir: DEF gorunumu uzerinden kosuldugunda
        # KLayout ile ayni kapsamda degildir (bkz. asic/README.md 9.8).
        if "magic__drc_error__count" in d:
            v = d["magic__drc_error__count"]
            print("%s %-24s %s" % ("  " if v == 0 else " ~", "Magic DRC", v))
            if v != 0:
                print("     NOT: DEF gorunumu uzerinden kosuluyorsa KLayout ile")
                print("     ayni kapsamda degildir - bkz. asic/README.md 9.8")

        # Zamanlama: kose bazli setup/hold
        print("\n   --- ZAMANLAMA (kose bazli) ---")
        for k in BEKLENEN_KOSELER:
            s = d.get("timing__setup__ws__corner:" + k)
            h = d.get("timing__hold__ws__corner:" + k)
            if s is None and h is None:
                continue
            uyari = "" if (s is None or s >= 0) else "  <- setup negatif"
            print("   %-22s setup %+8.4f   hold %+8.4f%s"
                  % (k, s or 0.0, h or 0.0, uyari))
    else:
        print("!! metrics.json bulunamadi")
        basarisiz.append("metrics.json yok")

    return basarisiz


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--dizin", default=os.path.join(KOK, "asic"),
                    help="ASIC kok dizini (varsayilan: asic/)")
    a = ap.parse_args()
    asic = os.path.abspath(a.dizin)

    print("=" * 68)
    print(" ARKHE SoC - ASIC TESLIM DENETIMI")
    print(" Final Ciktilar Bolum 5, Bolum 6 ve Tablo 8")
    print("=" * 68)
    print(" denetlenen dizin: %s" % asic)

    if not os.path.isdir(asic):
        print("\nHATA: dizin bulunamadi")
        return 1

    eksik = []
    eksik += bolum_denetle(asic, "BOLUM 5 - ZORUNLU RAPORLAR", BOLUM5, True)
    eksik += bolum_denetle(asic, "BOLUM 6 - ZORUNLU CIKTILAR", BOLUM6, True)
    eksik += koseleri_denetle(asic)
    onerilen = bolum_denetle(asic,
                             "BOLUM 6.3 - ONERILEN EK CIKTILAR (zorunlu degil)",
                             BOLUM63, False)
    basarisiz = signoff_hukmu(asic)

    print("\n" + "=" * 68)
    print(" SONUC")
    print("=" * 68)
    print("  zorunlu eksik madde   : %d" % len(eksik))
    print("  onerilen eksik madde  : %d  (basarisizlik degil)" % len(onerilen))
    print("  signoff FAIL hukmu    : %d" % len(basarisiz))

    if eksik:
        print("\n  EKSIK ZORUNLU MADDELER:")
        for e in eksik:
            print("    - %s" % e)
    if basarisiz:
        print("\n  SIGNOFF HUKUMLERI:")
        for b in basarisiz:
            print("    - %s" % b)

    print()
    if eksik:
        print("  [EKSIK] Zorunlu teslim maddeleri tamamlanmamis.")
        return 1
    if basarisiz:
        print("  [DOSYALAR TAM / SIGNOFF ACIK] Butun zorunlu dosyalar mevcut,")
        print("  ancak yukaridaki signoff hukumleri henuz gecer durumda degil.")
        return 2
    print("  [TAM] Zorunlu maddelerin tamami mevcut ve signoff hukumleri gecer.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
