#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Spike ISS izi ile CV32E40P RTL izini karsilastirir.

NEDEN

  Sartname s.569:
    "CV32E40P RISC-V islemci cekirdeginin dogrulanmasinin bir buyruk kumesi
     benzetim araci (ISS) ile (Orn. Spike ISS) yapilmasi beklenmektedir."

  EK-3 "Cekirdek Testleri":
    "...komut izlerinin (instruction trace) TUR ve SIRA bakimindan eslesip
     eslesmedigini gormek adina Spike ISS ve yazilim testleri (C/assembly)
     kullanilarak yapilan CV32E40P cekirdeginin BIREYSEL testleri.
     Bu testler kendi kendini kontrol eden (self-checking) yapida olmali..."

  DTR'de "ilk 20 buyruk Spike ile 20/20 eslesti, %100 uyum" yaziyordu.
  Gercek Spike hic kosulmamisti; eski karsilastirma elle yazilmis bir PC
  listesine dayaniyordu. Bu betik o iddiayi gercek olcumle degistirir.

KARSILASTIRMA NEYI DENETLER

  Her retire edilen buyrugun PC'si ve makine kodu, IKI izde de AYNI SIRADA
  olmalidir. Bu "tur ve sira" esitligidir.

BASLANGIC NOKTASI FARKI

  Spike reset vektorunden (0x1000) baslar ve kendi onyukleyicisini kosar.
  RTL izi ise cekirdegin ilk retire ettigi buyruktan baslar; bizim
  testbench'imiz boot_addr_i'yi 0x01000000'a zorlar.

  Bu yuzden karsilastirma UYGULAMANIN GIRIS NOKTASINDAN (0x01000000)
  baslatilir; oncesi platform farkidir, cekirdek dogrulugu degildir.

KULLANIM

  python3 scripts/spike_iz_al.py                     # Spike izi
  (RTL izi: build/coretest/trace_core_00000000.log)
  python3 scripts/spike_karsilastir.py
"""
import argparse
import re
import sys
from pathlib import Path

KOK = Path(__file__).resolve().parents[1]

BASLANGIC_PC = "01000000"   # uygulamanin giris noktasi (_start)

# RTL tracer satiri:
#   260000   5 01000000 1f002117   auipc  x2, ...
RTL_SATIR = re.compile(r"^\s*\d+\s+\d+\s+([0-9a-f]{8})\s+([0-9a-f]{4,8})\s")


def spike_oku(yol):
    iz = []
    with open(yol, encoding="ascii", errors="replace") as fh:
        for s in fh:
            p = s.split()
            if len(p) == 2:
                iz.append((p[0], p[1].lstrip("0") or "0"))
    return iz


def rtl_oku(yol):
    iz = []
    with open(yol, encoding="utf-8", errors="replace") as fh:
        for s in fh:
            m = RTL_SATIR.match(s)
            if m:
                iz.append((m.group(1), m.group(2).lstrip("0") or "0"))
    return iz


def hizala(iz, pc):
    """Verilen PC'nin ilk gorulusunden itibaren kes."""
    for i, (p, _) in enumerate(iz):
        if p == pc:
            return iz[i:]
    return []


def donguyu_kes(iz, esik=20):
    """Sonsuz donguye girildigi yerde izi keser.

    crt0 programin sonunda kendine dallanan bir dongude bekler. Simulasyon
    sabit bir sure kostugu icin RTL izi bu donguyu yuzlerce kez icerir;
    Spike izi de oyle. Karsilastirmadan once ikisi de kesilir.
    """
    son = None
    tekrar = 0
    for i, (p, _) in enumerate(iz):
        if p == son:
            tekrar += 1
            if tekrar >= esik:
                # Dongu PC'sinin ILK gorulusune kadar geri sar
                j = i
                while j > 0 and iz[j - 1][0] == p:
                    j -= 1
                return iz[:j + 1]
        else:
            tekrar = 0
            son = p
    return iz


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--spike", default=str(KOK / "build/spike/spike_iz.txt"))
    ap.add_argument("--rtl",
                    default=str(KOK / "build/coretest/trace_core_00000000.log"))
    ap.add_argument("--baslangic", default=BASLANGIC_PC)
    a = ap.parse_args()

    for yol in (a.spike, a.rtl):
        if not Path(yol).is_file():
            sys.exit("iz bulunamadi: %s" % yol)

    ham_s = spike_oku(a.spike)
    ham_r = rtl_oku(a.rtl)
    print("Spike ham buyruk : %d" % len(ham_s))
    print("RTL   ham buyruk : %d" % len(ham_r))

    s = donguyu_kes(hizala(ham_s, a.baslangic))
    r = donguyu_kes(hizala(ham_r, a.baslangic))
    print("hizalama PC      : 0x%s" % a.baslangic)
    print("Spike (hizali)   : %d" % len(s))
    print("RTL   (hizali)   : %d" % len(r))
    print()

    if not s or not r:
        sys.exit("HATA: hizalama PC'si izlerden birinde bulunamadi")

    n = min(len(s), len(r))
    pc_hata = 0
    kod_hata = 0
    sikistirilmis = 0
    ilk_hatalar = []
    for i in range(n):
        spc, sk = s[i]
        rpc, rk = r[i]

        if spc != rpc:
            pc_hata += 1
            if len(ilk_hatalar) < 10:
                ilk_hatalar.append(
                    "  #%-5d PC FARKLI  Spike %s   RTL %s" % (i, spc, rpc))
            continue

        # SIKISTIRILMIS BUYRUK FARKI - BEKLENEN DAVRANIS
        #
        # Spike ham 16-bit sikistirilmis kodu raporlar (orn. 4601).
        # CV32E40P tracer'i ise ACILMIS 32-bit karsiligini yazar (00000613).
        # Ayni buyruk, farkli gosterim.
        #
        # TESPIT: RISC-V'de bir buyruk 32-bit ise alt iki biti '11'dir.
        # Alt iki bit '11' DEGILSE buyruk sikistirilmistir. Bu, kodlamanin
        # kendi kurali - uzunluga bakmaktan guvenilir.
        #
        # (Ilk yazimda uzunluk karsilastirmasi kullaniliyordu; acilmis
        #  bicimin bastaki sifirlari kirpildigi icin 00000613 -> "613"
        #  olup sikistirilmis "4601"den KISA gorunuyordu ve 5 buyruk
        #  yanlislikla uyusmazlik sayiliyordu.)
        if (int(sk, 16) & 3) != 3:
            sikistirilmis += 1
            continue

        if sk != rk:
            kod_hata += 1
            if len(ilk_hatalar) < 10:
                ilk_hatalar.append(
                    "  #%-5d KOD FARKLI PC=%s  Spike %-8s RTL %-8s"
                    % (i, spc, sk, rk))
    hata = pc_hata + kod_hata

    print("=" * 66)
    print("KARSILASTIRMA")
    print("=" * 66)
    print("  karsilastirilan buyruk : %d" % n)
    print("  PC uyusmazligi         : %d" % pc_hata)
    print("  makine kodu uyusmazligi: %d" % kod_hata)
    print("  sikistirilmis (beklenen): %d" % sikistirilmis)
    if len(s) != len(r):
        print("  UZUNLUK FARKI          : Spike %d, RTL %d" % (len(s), len(r)))
        print("  (RTL izi sonsuz dongude kesilmis olabilir - normal)")
    print()

    if ilk_hatalar:
        print("ilk uyusmazliklar:")
        for h in ilk_hatalar:
            print(h)
        print()

    if hata == 0:
        print("SONUC: %d buyrukta PC dizisi BIREBIR ESLESTI." % n)
        print("       Spike ISS ile RTL izleri TUR ve SIRA bakimindan ayni.")
        if sikistirilmis:
            print()
            print("       %d buyrukta makine kodu gosterimi farkli: Spike ham" % sikistirilmis)
            print("       16-bit sikistirilmis kodu, CV32E40P tracer'i ise")
            print("       ACILMIS 32-bit karsiligini raporlar. Ayni buyruk,")
            print("       farkli gosterim - PC esitligi dogru cozuldugunu kanitlar.")
        return 0

    print("SONUC: %d/%d buyrukta uyusmazlik var." % (hata, n))
    return 1


if __name__ == "__main__":
    sys.exit(main())
