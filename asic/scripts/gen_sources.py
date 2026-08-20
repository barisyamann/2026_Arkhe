#!/usr/bin/env python3
"""
gen_sources.py - filelist.f -> config.yaml VERILOG_FILES donusumu

Final ciktilar belgesi (Bolum 4):

  "LibreLane yapilandirmasinda kullanilan RTL kaynaklari ile asic/filelist.f
   icerigi birbiriyle uyumlu olmalidir. Gerekli donusum veya yapilandirma
   islemleri asic/Makefile ya da asic/scripts/ altindaki betiklerle
   yapilmalidir."

LibreLane bir dosya-listesi dosyasini dogrudan kabul etmiyor; yalnizca
VERILOG_FILES adinda bir liste bekliyor. Bu betik filelist.f'i okuyup
config.yaml icindeki isaretlenmis blogu yeniden uretir.

TEK DOGRULUK KAYNAGI filelist.f'tir. config.yaml icindeki liste her zaman
ondan turetilir; elle duzenlenmemelidir.

Kullanim:
    python3 scripts/gen_sources.py           # config.yaml'i guncelle
    python3 scripts/gen_sources.py --check   # yalnizca tutarliligi denetle
"""

import os
import re
import sys

ASIC     = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FILELIST = os.path.join(ASIC, "filelist.f")
CONFIG   = os.path.join(ASIC, "config.yaml")

BAS = "# >>> URETILEN BLOK - gen_sources.py ile uretilir, ELLE DUZENLEMEYIN >>>"
SON = "# <<< URETILEN BLOK SONU <<<"


def filelist_oku():
    kaynaklar = []
    with open(FILELIST, encoding="utf-8") as fh:
        for satir in fh:
            s = satir.strip()
            if s and not s.startswith("#") and not s.startswith("//"):
                kaynaklar.append(s)
    return kaynaklar


def blok_uret(kaynaklar):
    satirlar = [BAS,
                "# Kaynak: filelist.f  (%d dosya)" % len(kaynaklar),
                "VERILOG_FILES:"]
    satirlar += ["  - %s" % k for k in kaynaklar]
    satirlar.append(SON)
    return "\n".join(satirlar)


def config_bloktan_oku(icerik):
    """config.yaml icindeki uretilen bloktan kaynak listesini cikarir."""
    m = re.search(re.escape(BAS) + r"(.*?)" + re.escape(SON), icerik, re.S)
    if not m:
        return None
    return re.findall(r"^\s*-\s*(\S+)\s*$", m.group(1), re.M)


def main():
    denetim = "--check" in sys.argv

    if not os.path.isfile(FILELIST):
        print("HATA: filelist.f bulunamadi")
        return 1
    if not os.path.isfile(CONFIG):
        print("HATA: config.yaml bulunamadi")
        return 1

    kaynaklar = filelist_oku()
    icerik = open(CONFIG, encoding="utf-8").read()
    mevcut = config_bloktan_oku(icerik)

    if denetim:
        if mevcut is None:
            print("  UYARI: config.yaml'da uretilen blok yok")
            print("         'make sources' calistirin")
            return 1
        if mevcut != kaynaklar:
            print("  IHLAL: config.yaml ile filelist.f AYRISMIS")
            eksik = [k for k in kaynaklar if k not in mevcut]
            fazla = [k for k in mevcut if k not in kaynaklar]
            for e in eksik:
                print("    filelist'te var, config'de yok : %s" % e)
            for f in fazla:
                print("    config'de var, filelist'te yok : %s" % f)
            if not eksik and not fazla:
                print("    (yalnizca sira farkli)")
            print("  Duzeltmek icin: make sources")
            return 1
        print("kaynak tutarliligi TEMIZ (%d dosya)" % len(kaynaklar))
        return 0

    # --- Uretim ---
    yeni_blok = blok_uret(kaynaklar)

    if mevcut is None:
        # Blok yoksa dosyanin sonuna ekle
        icerik = icerik.rstrip() + "\n\n" + yeni_blok + "\n"
        print("config.yaml'a uretilen blok EKLENDI")
    else:
        icerik = re.sub(re.escape(BAS) + r".*?" + re.escape(SON),
                        yeni_blok.replace("\\", "\\\\"), icerik, flags=re.S)
        print("config.yaml'daki uretilen blok GUNCELLENDI")

    open(CONFIG, "w", encoding="utf-8", newline="\n").write(icerik)
    print("  %d kaynak yazildi" % len(kaynaklar))
    return 0


if __name__ == "__main__":
    sys.exit(main())
