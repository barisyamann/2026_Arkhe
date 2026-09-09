#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Kod kapsama raporunu modul gruplarina ayirip analiz eder.

NEDEN VAR

  xcrg'nin urettigi tek bir genel skor UC FARKLI SEYI karistiriyor:

    1. Bizim yazdigimiz RTL          - asil olculmesi gereken
    2. CV32E40P cekirdegi            - ucuncu taraf, PULP tarafindan
                                       dogrulanmis, bizim test kapsamimiz
                                       disinda
    3. SystemVerilog paketleri       - yalnizca tip/sabit tanimi icerir,
                                       CALISTIRILABILIR KOD YOKTUR; metrik
                                       bunlari %0 sayarak ortalamayi
                                       haksiz yere dusuruyor

  9 Eylul 2026 olcumu: genel skor %62,47 statement gorunuyordu. Gruplara
  ayrilinca BIZIM RTL'in %79,8 oldugu ortaya cikti - yani genel rakam kendi
  tasarimimizin kalitesini gizliyordu.

  Bu betik dislama yapmaz, veriyi DEGISTIRMEZ; yalnizca ayni raporu
  gruplayarak okur. Ham xcrg ciktisi oldugu gibi durur.

KULLANIM

  python scripts/kapsam_analiz.py [rapor_dizini]

  Varsayilan: evidence/coverage_sistem/codeCoverageReport
"""
import io
import re
import sys
from pathlib import Path

KOK = Path(__file__).resolve().parents[1]
VARSAYILAN = KOK / "evidence" / "coverage_sistem" / "codeCoverageReport"


def modulleri_oku(rapor_dizini):
    """modules.html icinden (ad, statement, branch) uclulerini cikarir."""
    yol = Path(rapor_dizini) / "modules.html"
    if not yol.is_file():
        sys.exit("modules.html bulunamadi: %s" % yol)

    ham = io.open(yol, encoding="utf-8", errors="replace").read()
    satirlar = re.findall(r"<tr[^>]*>(.*?)</tr>", ham, re.S)

    moduller = []
    for s in satirlar:
        hucre = [re.sub(r"<[^>]+>", "", h).strip()
                 for h in re.findall(r"<td[^>]*>(.*?)</td>", s, re.S)]
        # Bicim: sira | modul | ornek sayisi | ornek yolu | stmt | branch | cond
        if len(hucre) >= 6 and hucre[0].isdigit():
            try:
                moduller.append((hucre[1], float(hucre[4]), float(hucre[5])))
            except (ValueError, IndexError):
                continue
    return moduller


def grupla(moduller):
    """Modulleri kaynak grubuna ayirir."""
    bizim, cpu, paket, tb = [], [], [], []
    for ad, st, br in moduller:
        if ad.startswith("cv32e40p"):
            cpu.append((ad, st, br))
        elif ad.endswith("_pkg") or ad.endswith("_pck"):
            paket.append((ad, st, br))
        elif ad.startswith("tb_") or "spi_flash_model" in ad:
            tb.append((ad, st, br))
        else:
            bizim.append((ad, st, br))
    return bizim, cpu, paket, tb


def ortalama(liste, indis):
    if not liste:
        return 0.0
    return sum(x[indis] for x in liste) / len(liste)


def main():
    dizin = sys.argv[1] if len(sys.argv) > 1 else str(VARSAYILAN)
    moduller = modulleri_oku(dizin)
    bizim, cpu, paket, tb = grupla(moduller)

    print("=" * 68)
    print(" KOD KAPSAMA - KAYNAK GRUBUNA GORE")
    print("=" * 68)
    print(" Rapor: %s" % dizin)
    print(" Cozumlenen modul: %d" % len(moduller))
    print()
    print(" %-34s %6s %9s %9s" % ("grup", "modul", "statement", "branch"))
    print(" " + "-" * 62)
    for ad, liste in [("BIZIM RTL", bizim),
                      ("CV32E40P (ucuncu taraf)", cpu),
                      ("Testbench / model", tb),
                      ("Paketler (kod yok)", paket)]:
        if liste:
            print(" %-34s %6d %8.1f%% %8.1f%%"
                  % (ad, len(liste), ortalama(liste, 1), ortalama(liste, 2)))
    print()

    print(" BIZIM RTL - en dusuk 10 modul (test eklemek icin oncelik sirasi)")
    print(" " + "-" * 62)
    for ad, st, br in sorted(bizim, key=lambda x: x[1])[:10]:
        print("   %-38s stmt %5.1f%%  branch %5.1f%%" % (ad[:38], st, br))
    print()

    print(" NOT")
    print("   Paket modulleri yalnizca tip/sabit tanimi icerir; icinde")
    print("   calistirilabilir kod yoktur. Kapsama metrigi bunlari %0")
    print("   sayar ve genel ortalamayi haksiz yere dusurur.")
    print("   CV32E40P ucuncu taraf bir cekirdektir ve PULP tarafindan")
    print("   ayrica dogrulanmistir; bizim test kapsamimizin hedefi degildir.")
    print("=" * 68)


if __name__ == "__main__":
    main()
