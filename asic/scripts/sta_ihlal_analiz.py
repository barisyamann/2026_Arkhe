#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""ASIC STA setup ihlallerini bitis yazmaclarina gore siniflandirir.

NEDEN

  LibreLane'in max.rpt dosyasi ihlalleri sentezlenmis net adlariyla
  (_124166_ gibi) raporluyor. Bu adlardan tasarimin NERESINDE sorun
  oldugu anlasilmiyor.

  Bu betik netlist'ten "ornek adi -> Q sinyali" haritasini cikarip
  her ihlali GERCEK yazmac adina baglar. Boylece "ihlaller CPU'da mi
  NPU'da mi" sorusu tahminle degil sayiyla cevaplanir.

KULLANIM

  python3 asic/scripts/sta_ihlal_analiz.py <run_dizini> [kose]

  ornek:
    python3 asic/scripts/sta_ihlal_analiz.py asic/run/sta2 nom_ss_100C_1v60
"""
import collections
import re
import sys
from pathlib import Path


def netlist_haritasi(netlist):
    """ornek adi -> surdugu Q sinyali"""
    harita = {}
    son_ornek = None
    hucre_re = re.compile(r"^\s*sky130_\S+\s+(\S+)\s*\(")
    q_re = re.compile(r"\.Q\(\s*\\?([^)]*?)\s*\)")
    with open(netlist, errors="replace") as fh:
        for satir in fh:
            m = hucre_re.match(satir)
            if m:
                son_ornek = m.group(1)
            q = q_re.search(satir)
            if q and son_ornek:
                harita[son_ornek] = q.group(1).strip()
                son_ornek = None
    return harita


def ihlal_bitisleri(rapor):
    """bitis noktasi -> ihlal sayisi, ve en kotu slack"""
    bitisler = collections.Counter()
    en_kotu = {}
    ep = None
    ep_re = re.compile(r"^\s*Endpoint:\s*(\S+)")
    slack_re = re.compile(r"^\s*(-?\d+\.\d+)\s+slack \(VIOLATED\)")
    with open(rapor, errors="replace") as fh:
        for satir in fh:
            m = ep_re.match(satir)
            if m:
                ep = m.group(1)
                continue
            s = slack_re.match(satir)
            if s and ep:
                bitisler[ep] += 1
                v = float(s.group(1))
                if ep not in en_kotu or v < en_kotu[ep]:
                    en_kotu[ep] = v
    return bitisler, en_kotu


def baslangic_dagilimi(rapor, harita):
    """ihlal eden yollarin BASLANGIC noktalarini da siniflandirir"""
    sayac = collections.Counter()
    sp = None
    sp_re = re.compile(r"^\s*Startpoint:\s*(\S+)")
    with open(rapor, errors="replace") as fh:
        for satir in fh:
            m = sp_re.match(satir)
            if m:
                sp = m.group(1)
                continue
            if "slack (VIOLATED)" in satir and sp:
                ad = harita.get(sp, sp)
                sayac[modul_yolu(ad)] += 1
    return sayac


def modul_yolu(ad, derinlik=3):
    """u_soc.u_npu.u_npu_engine.conv_acc[3] -> u_npu.u_npu_engine.conv_acc"""
    ad = re.sub(r"\[.*", "", ad).strip()
    parcalar = ad.split(".")
    if len(parcalar) <= derinlik:
        return ad
    return ".".join(parcalar[:derinlik])


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    run = Path(sys.argv[1])
    kose = sys.argv[2] if len(sys.argv) > 2 else "nom_ss_100C_1v60"

    sta = list(run.glob("*-openroad-stapostpnr"))
    if not sta:
        sys.exit("STA adimi bulunamadi: %s" % run)
    rapor = sta[0] / kose / "max.rpt"
    if not rapor.is_file():
        sys.exit("rapor yok: %s" % rapor)

    netlist = list(run.glob("*-openroad-cts/*.nl.v"))
    if not netlist:
        netlist = list(run.glob("*/*.nl.v"))
    if not netlist:
        sys.exit("netlist bulunamadi")

    print("kose    : %s" % kose)
    print("rapor   : %s" % rapor)
    print("netlist : %s" % netlist[0].name)
    print()

    harita = netlist_haritasi(netlist[0])
    print("netlist yazmac sayisi : %d" % len(harita))

    bitisler, en_kotu = ihlal_bitisleri(rapor)
    print("raporlanan ihlal      : %d" % sum(bitisler.values()))
    print("farkli bitis noktasi  : %d" % len(bitisler))
    print()

    # Bitis noktalarini modul yoluna gore topla
    modul = collections.Counter()
    modul_slack = {}
    eslesmeyen = 0
    for ep, n in bitisler.items():
        ad = harita.get(ep)
        if ad is None:
            eslesmeyen += 1
            yol = "(netlist'te bulunamadi)"
        else:
            yol = modul_yolu(ad)
        modul[yol] += n
        s = en_kotu[ep]
        if yol not in modul_slack or s < modul_slack[yol]:
            modul_slack[yol] = s

    print("=" * 78)
    print("IHLALLERIN BITIS NOKTALARI (modul yoluna gore)")
    print("=" * 78)
    print("%-52s %6s %10s" % ("modul", "ihlal", "en kotu"))
    print("-" * 78)
    toplam = sum(modul.values())
    for yol, n in modul.most_common(20):
        print("%-52s %6d %9.2f ns" % (yol[:52], n, modul_slack[yol]))
    print("-" * 78)
    print("%-52s %6d" % ("TOPLAM", toplam))
    if eslesmeyen:
        print("(netlist'te eslesmeyen bitis noktasi: %d)" % eslesmeyen)
    print()

    print("=" * 78)
    print("IHLAL EDEN YOLLARIN BASLANGIC NOKTALARI")
    print("=" * 78)
    bas = baslangic_dagilimi(rapor, harita)
    for yol, n in bas.most_common(12):
        print("%-60s %6d" % (yol[:60], n))


if __name__ == "__main__":
    main()
