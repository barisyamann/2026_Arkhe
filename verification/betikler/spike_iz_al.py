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

# 12 Eylul 2026: YAZMAC DUZEYI KARSILASTIRMA
#
# --log-commits ile Spike her buyruktan SONRA bir "commit" satiri yazar:
#   "core   0: 3 0x01000000 (0x1f002117) x2  0x20002000"
#                ^ ayricalik      yazilan yazmac ve DEGERI
#
# Onceki surum bu satiri yok sayiyordu; yalniz PC ve makine kodu
# karsilastiriliyordu. Yani cekirdegin dogru SIRAYLA dogru BUYRUKLARI
# kostugu dogrulaniyor, ama SONUCLARI dogru hesaplayip hesaplamadigi
# DOGRULANMIYORDU. Bir ALU hatasi (ornegin add yerine sub) bu
# karsilastirmadan GECERDI.
COMMIT = re.compile(
    r"^core\s+\d+:\s+\d+\s+0x([0-9a-f]{8})\s+\(0x[0-9a-f]+\)"
    r"(?:\s+x\s*(\d+)\s+0x([0-9a-f]+))?")


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
    """Ham Spike ciktisini (PC, buyruk, yazmac, deger) listesine cevirir.

    Program akisinin bittigi yer, AYNI PC'nin ust uste tekrarlanmasiyla
    bulunur (crt0'in sonsuz dongusu). O noktada kesilir.

    12 Eylul 2026: YAZMAC DEGERI de toplanir.

      Spike --log-commits her buyruk icin IKI satir yazar:
        1) "core 0: 0x01000000 (0x1f002117) auipc sp, 0x1f002"   <- SATIR
        2) "core 0: 3 0x01000000 (0x1f002117) x2  0x20002000"    <- COMMIT

      Ikinci satir buyrugun YAZDIGI yazmaci ve DEGERINI verir. Yazmaca
      yazmayan buyruklarda (store, branch) bu alan yoktur; o kayitlarda
      yazmac/deger None kalir.

      Onceki surum commit satirini yok sayiyordu. Yani cekirdegin dogru
      sirayla dogru buyruklari kostugu dogrulaniyor, SONUCLARI dogru
      hesaplayip hesaplamadigi DOGRULANMIYORDU.
    """
    iz = []
    son_pc = None
    tekrar = 0
    bekleyen = None      # (pc, buyruk) - commit satirini bekliyor

    def ekle(kayit):
        """Kaydi ize koyar; sonsuz dongu tespitini uygular.

        Donus: True ise dongu bulundu ve iz kesilmeli.
        """
        nonlocal son_pc, tekrar
        pc = kayit[0]
        if pc == son_pc:
            tekrar += 1
            if tekrar >= dongu_esigi:
                while iz and iz[-1][0] == pc:
                    iz.pop()
                return True
        else:
            tekrar = 0
            son_pc = pc
        iz.append(kayit)
        return False

    for s in satirlar:
        mc = COMMIT.match(s)
        if mc and mc.group(2) is not None:
            # Commit satiri: yazmac yazmasi var
            pc = mc.group(1)
            if bekleyen and bekleyen[0] == pc:
                kayit = (pc, bekleyen[1],
                         mc.group(2), mc.group(3).lstrip("0") or "0")
                bekleyen = None
                if ekle(kayit):
                    return iz, True
            continue

        m = SATIR.match(s)
        if not m:
            continue
        # Yeni buyruk satiri geldi. Onceki buyruk commit'siz kaldiysa
        # (store/branch gibi yazmaca yazmayanlar) onu simdi ekle.
        if bekleyen:
            if ekle((bekleyen[0], bekleyen[1], None, None)):
                return iz, True
        bekleyen = (m.group(1), m.group(2))

    if bekleyen:
        ekle((bekleyen[0], bekleyen[1], None, None))
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

    # Cikti bicimi (12 Eylul 2026'da genisletildi):
    #   "PC BUYRUK"                 -> yazmaca yazmayan buyruk
    #   "PC BUYRUK xN DEGER"        -> yazmac yazmasi olan buyruk
    # Eski okuyucular ilk iki alani aynen okur; ek alanlar geriye
    # donuk uyumludur.
    yazmacli = sum(1 for k in iz if k[2] is not None)
    cikti = Path(a.cikti)
    cikti.parent.mkdir(parents=True, exist_ok=True)
    with open(cikti, "w", encoding="ascii") as fh:
        for pc, buyruk, yz, dg in iz:
            if yz is None:
                fh.write("%s %s\n" % (pc, buyruk))
            else:
                fh.write("%s %s x%s %s\n" % (pc, buyruk, yz, dg))
    print("yazildi         : %s" % cikti)
    print("yazmac yazmasi  : %d / %d buyruk" % (yazmacli, len(iz)))

    if iz:
        print()
        print("ilk 5 buyruk:")
        for pc, b, yz, dg in iz[:5]:
            ek = ("  x%s=%s" % (yz, dg)) if yz is not None else ""
            print("  %s  %s%s" % (pc, b, ek))
        print("son 3 buyruk:")
        for pc, b, yz, dg in iz[-3:]:
            ek = ("  x%s=%s" % (yz, dg)) if yz is not None else ""
            print("  %s  %s%s" % (pc, b, ek))


if __name__ == "__main__":
    main()
