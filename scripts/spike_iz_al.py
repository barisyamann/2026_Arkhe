#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Spike ISS izini alir ve normalize eder.

NEDEN

  Sartname s.569:
    "CV32E40P RISC-V islemci cekirdeginin dogrulanmasinin bir buyruk kumesi
     benzetim araci (ISS) ile (Orn. Spike ISS) yapilmasi beklenmektedir."

  EK-3 "Cekirdek Testleri":
    "...komut izlerinin (instruction trace) TUR ve SIRA bakimindan eslesip
     eslesmedigini gormek adina Spike ISS ve yazilim testleri kullanilarak..."

  DTR'de "ilk 20 buyruk Spike ile 20/20 eslesti, %100 uyum" yaziyordu ama
  gercek Spike hic kosulmamisti. Bu betik o eksigi kapatir.

DIKKAT - IKI TUZAK

  1) Spike izi STDERR'e yazar, stdout'a degil. '2>/dev/null' kullanmak izi
     tamamen kaybettirir (bu hata bir kez yapildi).

  2) crt0 sonsuz donguyle biter; Spike o donguyu milyonlarca kez kosar.
     Iz, program akisinin BITTIGI yerde kesilmelidir. Burada bitis, ayni
     PC'nin ust uste tekrarlanmasiyla tespit edilir.

CIKTI

  Normalize edilmis iz: her satir "PC BUYRUK"
  Ornek:  01000000 1f002117
"""
import argparse
import re
import subprocess
import sys
from pathlib import Path

KOK = Path(__file__).resolve().parents[1]

# "core   0: 0x01000000 (0x1f002117) auipc   sp, 0x1f002"
SATIR = re.compile(r"^core\s+\d+:\s+0x([0-9a-f]{8})\s+\(0x([0-9a-f]+)\)")


def spike_kos(elf, isa, sure):
    """Spike'i kosar, ham iz satirlarini dondurur (stderr'den)."""
    komut = [
        "spike",
        "--isa=" + isa,
        "-m0x1000000:0x100000,0x20000000:0x10000",
        "--log-commits",
        "-l",
        str(elf),
    ]
    try:
        p = subprocess.run(komut, stdout=subprocess.DEVNULL,
                           stderr=subprocess.PIPE, timeout=sure)
        ham = p.stderr
    except subprocess.TimeoutExpired as e:
        # Zaman asimi BEKLENEN durumdur: crt0 sonsuz donguyle biter.
        ham = e.stderr or b""
    return ham.decode("utf-8", errors="replace").splitlines()


def iz_normalize(satirlar, dongu_esigi=50):
    """Ham Spike ciktisini (PC, buyruk) listesine cevirir.

    Program akisinin bittigi yer, AYNI PC'nin ust uste tekrarlanmasiyla
    bulunur (crt0'in sonsuz dongusu). O noktada kesilir.
    """
    iz = []
    son_pc = None
    tekrar = 0
    for s in satirlar:
        m = SATIR.match(s)
        if not m:
            continue
        pc, buyruk = m.group(1), m.group(2)
        if pc == son_pc:
            tekrar += 1
            if tekrar >= dongu_esigi:
                # Sonsuz donguye girildi - tekrarlari at ve bitir
                while iz and iz[-1][0] == pc:
                    iz.pop()
                return iz, True
        else:
            tekrar = 0
            son_pc = pc
        iz.append((pc, buyruk))
    return iz, False


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("elf", nargs="?",
                    default=str(KOK / "sw_nexys/build/core_test/core_test.elf"))
    ap.add_argument("--isa", default="rv32imc_zicsr")
    ap.add_argument("--sure", type=int, default=45)
    ap.add_argument("-o", "--cikti",
                    default=str(KOK / "build/spike/spike_iz.txt"))
    a = ap.parse_args()

    elf = Path(a.elf)
    if not elf.is_file():
        sys.exit("ELF bulunamadi: %s\n(once: python sw_nexys/scripts/build.py)" % elf)

    print("Spike kosuluyor : %s" % elf.name)
    satirlar = spike_kos(elf, a.isa, a.sure)
    print("ham iz satiri   : %d" % len(satirlar))

    iz, dongu = iz_normalize(satirlar)
    print("buyruk sayisi   : %d" % len(iz))
    print("dongude bitti   : %s" % ("evet" if dongu else "HAYIR - zaman asimi?"))

    cikti = Path(a.cikti)
    cikti.parent.mkdir(parents=True, exist_ok=True)
    with open(cikti, "w", encoding="ascii") as fh:
        for pc, buyruk in iz:
            fh.write("%s %s\n" % (pc, buyruk))
    print("yazildi         : %s" % cikti)

    if iz:
        print()
        print("ilk 5 buyruk:")
        for pc, b in iz[:5]:
            print("  %s  %s" % (pc, b))
        print("son 3 buyruk:")
        for pc, b in iz[-3:]:
            print("  %s  %s" % (pc, b))


if __name__ == "__main__":
    main()
