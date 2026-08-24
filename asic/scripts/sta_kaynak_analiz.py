#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Setup ihlallerini KAYNAK bloga gore siniflandirir (netlist eslemeli).

NEDEN AYRI BIR BETIK

  max.rpt icinde normal flip-flop'lar sentezlenmis adla gorunur (_121995_),
  yalnizca SRAM makrolari hiyerarsik adini korur (u_data_ram.g_sram[0]).

  Bu yuzden ham metne bakarak siniflandirmak YANILTICIDIR: makro
  kaynakli yollar dogru sinifllanir ama butun flip-flop kaynakli yollar
  "diger" kovasina duser. Ilk denememde NPU kaynakli yol sayisi 3
  gorundu; oysa baslangic dagiliminda u_npu...t_out 275 ile en buyuk
  ikinci kalemdi.

  Bu betik hem BASLANGIC hem BITIS noktalarini netlist'ten gercek
  adlarina cevirip oyle siniflandirir.

KULLANIM

  python3 asic/scripts/sta_kaynak_analiz.py <run_dizini> [kose]
"""
import collections
import re
import sys
from pathlib import Path


def netlist_haritasi(netlist):
    harita = {}
    son = None
    hucre = re.compile(r"^\s*sky130_\S+\s+(\S+)\s*\(")
    q = re.compile(r"\.Q\(\s*\\?([^)]*?)\s*\)")
    with open(netlist, errors="replace") as fh:
        for satir in fh:
            m = hucre.match(satir)
            if m:
                son = m.group(1)
            g = q.search(satir)
            if g and son:
                harita[son] = g.group(1).strip()
                son = None
    return harita


def blok(ad):
    """Hiyerarsik adi ust duzey bloga indirger."""
    ad = re.sub(r"\[.*", "", ad).strip()
    if ad.startswith("u_core"):
        return "CV32E40P cekirdegi"
    if ad.startswith("u_npu.u_npu_sram"):
        return "NPU TCM SRAM makrosu"
    if ad.startswith("u_npu"):
        return "NPU (mantik)"
    if ad.startswith("u_data_ram"):
        return "D-RAM SRAM makrosu"
    if ad.startswith("u_instruction_ram"):
        return "I-RAM SRAM makrosu"
    if ad.startswith("u_uart"):
        return "UART"
    if ad.startswith("u_dma"):
        return "DMA"
    if ad.startswith("u_qspi"):
        return "QSPI"
    parca = ad.split(".")
    return parca[0] if parca else ad


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    run = Path(sys.argv[1])
    kose = sys.argv[2] if len(sys.argv) > 2 else "nom_ss_100C_1v60"

    sta = list(run.glob("*-openroad-stapostpnr"))
    rapor = sta[0] / kose / "max.rpt"
    netlist = list(run.glob("*-openroad-cts/*.nl.v")) or list(run.glob("*/*.nl.v"))

    harita = netlist_haritasi(netlist[0])

    bas = collections.Counter()
    bas_kotu = {}
    bit = collections.Counter()
    bit_kotu = {}
    ciftler = collections.Counter()

    sp = ep = None
    sp_re = re.compile(r"^\s*Startpoint:\s*(\S+)")
    ep_re = re.compile(r"^\s*Endpoint:\s*(\S+)")
    sl_re = re.compile(r"^\s*(-?\d+\.\d+)\s+slack \(VIOLATED\)")

    with open(rapor, errors="replace") as fh:
        for satir in fh:
            m = sp_re.match(satir)
            if m:
                sp = m.group(1)
                continue
            m = ep_re.match(satir)
            if m:
                ep = m.group(1)
                continue
            s = sl_re.match(satir)
            if s and sp and ep:
                v = float(s.group(1))
                b1 = blok(harita.get(sp, sp))
                b2 = blok(harita.get(ep, ep))
                bas[b1] += 1
                bit[b2] += 1
                ciftler[(b1, b2)] += 1
                if b1 not in bas_kotu or v < bas_kotu[b1]:
                    bas_kotu[b1] = v
                if b2 not in bit_kotu or v < bit_kotu[b2]:
                    bit_kotu[b2] = v

    print("kose : %s" % kose)
    print("rapor: %s" % rapor.name)
    print()
    print("=" * 72)
    print("IHLALLERIN KAYNAK BLOGU (baslangic)")
    print("=" * 72)
    print("%-30s %7s %12s" % ("blok", "ihlal", "en kotu"))
    print("-" * 72)
    for b, n in bas.most_common():
        print("%-30s %7d %9.2f ns" % (b, n, bas_kotu[b]))
    print()
    print("=" * 72)
    print("IHLALLERIN VARIS BLOGU (bitis)")
    print("=" * 72)
    print("%-30s %7s %12s" % ("blok", "ihlal", "en kotu"))
    print("-" * 72)
    for b, n in bit.most_common():
        print("%-30s %7d %9.2f ns" % (b, n, bit_kotu[b]))
    print()
    print("=" * 72)
    print("EN SIK YOL CIFTLERI  (baslangic -> bitis)")
    print("=" * 72)
    for (a, b), n in ciftler.most_common(10):
        print("%-30s -> %-28s %5d" % (a[:30], b[:28], n))


if __name__ == "__main__":
    main()
