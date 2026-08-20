#!/usr/bin/env python3
"""
check_filelist.py - filelist.f ve config.yaml tutarlilik denetimi

Final ciktilar belgesi (Bolum 4) iki sart koyuyor:

  1. "asic/filelist.f icerisindeki dosya yollari goreli olmali ve ASIC akisi
      asic/ dizininden baslatildiginda dogru sekilde cozumlenebilmelidir."

  2. "LibreLane yapilandirmasinda kullanilan RTL kaynaklari ile
      asic/filelist.f icerigi birbiriyle uyumlu olmalidir. ASIC akisinda
      kullanilan ancak dosya listesinde bulunmayan RTL kaynaklari kabul
      edilmez."

Ayrica sunlari denetler:
  - asic/ altinda RTL kaynagi, testbench veya FPGA'e ozgu dosya BULUNMAMALI
  - listede testbench / FPGA ust modulu olmamali

Cikis kodu: 0 = temiz, 1 = en az bir ihlal
"""

import os
import re
import sys

ASIC = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

FILELIST = os.path.join(ASIC, "filelist.f")
CONFIG   = os.path.join(ASIC, "config.yaml")

# asic/ altinda bulunmamasi gereken uzantilar (sartname: RTL ve testbench
# asic/ altinda tutulmaz). Makro Verilog modelleri istisnadir - onlar
# macros/<ad>/verilog/ altinda durur ve fiziksel makronun parcasidir.
YASAK_UZANTI = (".sv", ".v", ".vhd", ".vhdl")
# asic/ altinda RTL aranirken ATLANACAK dizinler.
#
#   macros/   saticidan gelen makro modelleri - bizim RTL'imiz degil
#   results/  AKIS CIKTISI. results/netlist/soc_top.nl.v bir gate-level
#             netlist'tir, RTL kaynagi degildir; ustelik sartname onu tam
#             da orada istiyor. Denetime dahil edilirse teslim edilecek
#             dosyayi ihlal sayar.
#   run/      gecici calisma alani (asagida ayrica ele aliniyor)
ISTISNA_DIZIN = ("macros", "results")

# Listede olmamasi gerekenler
TESTBENCH_DESEN = re.compile(r"(^|/)(tb_|.*_tb\.)", re.I)
FPGA_DESEN      = re.compile(r"(nexys_top|_fpga|xilinx)", re.I)


def filelist_oku():
    if not os.path.isfile(FILELIST):
        print("HATA: filelist.f bulunamadi: %s" % FILELIST)
        sys.exit(1)
    kaynaklar = []
    with open(FILELIST, encoding="utf-8") as fh:
        for satir in fh:
            s = satir.strip()
            if not s or s.startswith("#") or s.startswith("//"):
                continue
            kaynaklar.append(s)
    return kaynaklar


def main():
    hata = []
    uyari = []

    kaynaklar = filelist_oku()
    print("filelist.f  : %d kaynak" % len(kaynaklar))

    # --- 1) Yollar goreli mi ve cozumleniyor mu -----------------------------
    for p in kaynaklar:
        if os.path.isabs(p) or re.match(r"^[A-Za-z]:", p):
            hata.append("MUTLAK YOL: %s" % p)
            continue
        tam = os.path.normpath(os.path.join(ASIC, p))
        if not os.path.isfile(tam):
            hata.append("COZUMLENMEYEN: %s" % p)

    # --- 2) Listede testbench / FPGA dosyasi var mi -------------------------
    for p in kaynaklar:
        if TESTBENCH_DESEN.search(p):
            hata.append("LISTEDE TESTBENCH: %s" % p)
        if FPGA_DESEN.search(p):
            hata.append("LISTEDE FPGA'E OZGU DOSYA: %s" % p)

    # --- 3) Tekrar eden kaynak ----------------------------------------------
    gorulen = {}
    for p in kaynaklar:
        ad = os.path.basename(p)
        if ad in gorulen and gorulen[ad] != p:
            hata.append("AYNI MODUL IKI YOLDAN: %s / %s" % (gorulen[ad], p))
        gorulen[ad] = p

    # --- 4) asic/ altinda RTL var mi ----------------------------------------
    for kok, dizinler, dosyalar in os.walk(ASIC):
        bagil_kok = os.path.relpath(kok, ASIC)
        ilk = bagil_kok.split(os.sep)[0]
        if ilk in ISTISNA_DIZIN or ilk == "run":
            dizinler[:] = []
            continue
        for d in dosyalar:
            if d.lower().endswith(YASAK_UZANTI):
                hata.append("asic/ ALTINDA RTL: %s" %
                            os.path.join(bagil_kok, d).replace("\\", "/"))

    # --- 5) config.yaml filelist.f'i gosteriyor mu --------------------------
    if os.path.isfile(CONFIG):
        icerik = open(CONFIG, encoding="utf-8").read()
        if "filelist.f" not in icerik:
            uyari.append("config.yaml filelist.f'e referans vermiyor - "
                         "iki kaynak listesi ayrisabilir")
        # config icinde dogrudan .sv sayilmasi (filelist disi kaynak)
        dogrudan = re.findall(r"^\s*-\s*(\S+\.sv)\s*$", icerik, re.M)
        for d in dogrudan:
            if d not in kaynaklar:
                hata.append("config.yaml'da filelist DISI kaynak: %s" % d)
    else:
        uyari.append("config.yaml bulunamadi")

    # --- Sonuc ---------------------------------------------------------------
    for u in uyari:
        print("  UYARI : %s" % u)

    if hata:
        print("\n  %d IHLAL:" % len(hata))
        for h in hata:
            print("    - %s" % h)
        print("\nfilelist denetimi BASARISIZ")
        return 1

    print("filelist denetimi TEMIZ")
    return 0


if __name__ == "__main__":
    sys.exit(main())
