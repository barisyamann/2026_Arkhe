#!/usr/bin/env python3
"""
collect_outputs.py - LibreLane ciktilarini sartnamenin istedigi agaca tasir

Kullanim:
    python3 scripts/collect_outputs.py run/<tag>

LibreLane kendi run dizinine adim adim ciktilar birakir. Final ciktilar
belgesi (Tablo 8) bunlarin asic/results/ ve asic/reports/ altinda belirli
bir duzende bulunmasini istiyor. Bu betik esleme islemini yapar.

Kopyalama YAPAR, tasima yapmaz: run/ dizini "gecici calisma alani" olarak
kalir ve yeniden uretilebilir.
"""

import os
import shutil
import sys

ASIC = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# LibreLane cikti uzantisi -> hedef dizin
# Ayni uzanti birden fazla adimda uretilebilir; en SON uretilen alinir.
SONUC_ESLEME = {
    ".def":  "results/def",
    ".gds":  "results/gds",
    ".lef":  "results/lef",
    ".odb":  "results/odb",
    ".sdc":  "results/sdc",
    ".sdf":  "results/sdf",
    ".spef": "results/spef",
    ".spice": "results/spice",
    ".lib":  "results/lib",
    ".mag":  "results/mag",
}

# Rapor adinda gecen anahtar -> hedef dizin
RAPOR_ESLEME = [
    ("drc",        "reports/drc"),
    ("lvs",        "reports/lvs"),
    ("antenna",    "reports/antenna"),
    ("pdn",        "reports/pdn"),
    ("grid-errors", "reports/pdn"),
    ("congestion", "reports/routing"),
    ("routing",    "reports/routing"),
    ("wirelength", "reports/routing"),
    ("via",        "reports/routing"),
    ("power",      "reports/power"),
    ("ir_drop",    "reports/power"),
    ("irdrop",     "reports/power"),
    ("sta",        "reports/timing"),
    ("timing",     "reports/timing"),
    ("slack",      "reports/timing"),
    ("wns",        "reports/timing"),
    ("tns",        "reports/timing"),
    ("synth",      "reports/synthesis"),
    ("stat",       "reports/synthesis"),
    ("area",       "reports/synthesis"),
    ("lint",       "reports/lint"),
    ("signoff",    "reports/signoff"),
    ("xor",        "reports/signoff"),
    ("unconnected", "reports/signoff"),
    ("manufactur", "reports/signoff"),
]


def hedef_dizin(yol):
    ad = os.path.basename(yol).lower()
    kok, uzanti = os.path.splitext(ad)

    # netlist'ler ayri: .nl.v, .pnl.v vb.
    if ad.endswith(".v") or ad.endswith(".nl.v") or ad.endswith(".pnl.v"):
        return "results/netlist"

    if uzanti in SONUC_ESLEME:
        return SONUC_ESLEME[uzanti]

    if uzanti in (".rpt", ".log", ".txt", ".json", ".csv"):
        for anahtar, hedef in RAPOR_ESLEME:
            if anahtar in ad:
                return hedef
        if ad in ("resolved.json",):
            return "config"
        if ad.startswith("metrics"):
            return "metrics"
        return "reports/general"

    if uzanti in (".png", ".jpg", ".svg", ".pdf"):
        return "results/images"

    return None


def main():
    if len(sys.argv) < 2:
        print("kullanim: collect_outputs.py run/<tag>")
        return 2

    run_dir = sys.argv[1]
    if not os.path.isabs(run_dir):
        run_dir = os.path.join(ASIC, run_dir)

    if not os.path.isdir(run_dir):
        print("HATA: run dizini bulunamadi: %s" % run_dir)
        print("      Once 'make asic_run' veya 'make synth' kosun.")
        return 1

    # Ayni ada sahip birden fazla dosya olabilir (her adimda bir tane).
    # En son degistirileni alalim.
    adaylar = {}
    for kok, _, dosyalar in os.walk(run_dir):
        for d in dosyalar:
            tam = os.path.join(kok, d)
            hedef = hedef_dizin(tam)
            if hedef is None:
                continue
            anahtar = (hedef, d)
            try:
                mt = os.path.getmtime(tam)
            except OSError:
                continue
            if anahtar not in adaylar or mt > adaylar[anahtar][1]:
                adaylar[anahtar] = (tam, mt)

    sayac = {}
    for (hedef, ad), (kaynak, _) in sorted(adaylar.items()):
        hedef_tam = os.path.join(ASIC, hedef)
        os.makedirs(hedef_tam, exist_ok=True)
        shutil.copy2(kaynak, os.path.join(hedef_tam, ad))
        sayac[hedef] = sayac.get(hedef, 0) + 1

    if not sayac:
        print("UYARI: kopyalanacak cikti bulunamadi (%s)" % run_dir)
        return 1

    print("Cikti toplama tamamlandi:")
    for hedef in sorted(sayac):
        print("  %-22s %3d dosya" % (hedef, sayac[hedef]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
