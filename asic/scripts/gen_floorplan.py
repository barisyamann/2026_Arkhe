#!/usr/bin/env python3
# =============================================================================
#  gen_floorplan.py - Makro izgarasini ve DIE_AREA'yi hesaplar, config.yaml'a yazar
#
#  NEDEN BETIK
#    Bes ASIC kosumu boyunca izgara elle hesaplandi ve her seferinde kanal,
#    kenar payi, satir/sutun sayisi degistirildi. Elle hesap hem yavas hem
#    hataya acik. Bu betik gecmisi de tasiyor: hangi ayarin hangi sonucu
#    verdigi asagida kayitli.
#
#  KOSUM GECMISI
#    | # | kanal | kenar | die (mm2) | global yonl. | detayli yonl.       |
#    |---|-------|-------|-----------|--------------|---------------------|
#    | 1 | 100   | 200   | 11,67     | bitmedi      | -                   |
#    | 2 | 150   | 200   | 13,07     | 57 dk bitmedi| -                   |
#    | 3 | 200   | 250   | 15,33     | 4:36 temiz   | 63 turda 23 ihlal   |
#    | 4 | 200   | 250   | 15,33     | 1:30 temiz   | 12 turda 0 IHLAL    |
#    | 5 | 200   | 250   | 15,33     | temiz        | 0 ihlal             |
#
#    4. kosumda halo 10 -> 25 um yapildi ve detayli yonlendirme SIFIR ihlale
#    dustu. Darbogaz kanallar degil, MAKRO PINLERININ CEVRESIYDI.
#
#  UST KENAR PAYI - 3, 4 ve 5. kosumun dustugu yer
#    Uc kosum da ayni hatayla dustu:
#        [DRT-1231] Pin u_data_ram.g_sram[N].u_macro/... does not have
#                   access point
#    Ucunde de dusen makro EN UST SIRADAYDI (y = 3332,7). O sirada makronun
#    ustunde die kenarina kadar yalnizca 250 um vardi. Anten onariminin
#    yerlestirdigi diyotlar orayi doldurunca pin erisimi kapandi.
#
#    Bu yuzden ust kenar payi AYRI parametredir ve digerlerinden buyuk
#    tutulur.
#
#  KULLANIM
#      python3 scripts/gen_floorplan.py                 varsayilanla yaz
#      python3 scripts/gen_floorplan.py --ust 500       ust payi 500 um
#      python3 scripts/gen_floorplan.py --agirlik-sram 8   +8 makro ekle
#      python3 scripts/gen_floorplan.py --goster        yazmadan hesapla
# =============================================================================

import argparse
import io
import os
import re
import sys

ASIC = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CONFIG = os.path.join(ASIC, "config.yaml")

# sky130_sram_2kbyte_1rw1r_32x512_8 fiziksel boyutu
MAKRO_G = 683.10
MAKRO_Y = 416.54
MAKRO_ALAN = MAKRO_G * MAKRO_Y / 1e6      # mm2

BASLA = "    instances:"


def makro_adlari(agirlik_sram):
    """Yerlestirilecek makro ornek adlari, RTL hiyerarsisine gore."""
    adlar = []
    adlar += ["u_npu.u_npu_sram.g_sram[%d].u_macro" % i for i in range(15)]
    adlar += ["u_instruction_ram.g_sram[%d].u_macro" % i for i in range(4)]
    adlar += ["u_data_ram.g_sram[%d].u_macro" % i for i in range(4)]
    # fc_weights SRAM'e tasinirsa eklenecek makrolar
    adlar += ["u_npu.u_npu_wsram.g_sram[%d].u_macro" % i
              for i in range(agirlik_sram)]
    return adlar


def hesapla(kanal, kenar, ust, kol, adet):
    satir = (adet + kol - 1) // kol
    hx = MAKRO_G + kanal
    hy = MAKRO_Y + kanal
    die_g = kenar + (kol - 1) * hx + MAKRO_G + kenar
    die_y = kenar + (satir - 1) * hy + MAKRO_Y + ust
    return satir, hx, hy, die_g, die_y


def main():
    a = argparse.ArgumentParser()
    a.add_argument("--kanal", type=float, default=200.0,
                   help="makrolar arasi kanal genisligi (um)")
    a.add_argument("--kenar", type=float, default=250.0,
                   help="sol/sag/alt kenar payi (um)")
    a.add_argument("--ust", type=float, default=500.0,
                   help="UST kenar payi (um) - 3/4/5. kosum burada dustu")
    a.add_argument("--kol", type=int, default=4, help="sutun sayisi")
    a.add_argument("--agirlik-sram", type=int, default=0,
                   help="fc_weights icin eklenecek makro sayisi")
    a.add_argument("--goster", action="store_true",
                   help="config.yaml'a yazma, yalnizca hesapla")
    k = a.parse_args()

    adlar = makro_adlari(k.agirlik_sram)
    adet = len(adlar)
    satir, hx, hy, die_g, die_y = hesapla(k.kanal, k.kenar, k.ust, k.kol, adet)

    alan = die_g * die_y / 1e6
    doluluk = 100.0 * adet * MAKRO_ALAN / alan

    print("=" * 68)
    print(" MAKRO IZGARASI")
    print("=" * 68)
    print("  makro           : %d adet (%d temel + %d agirlik SRAM)"
          % (adet, adet - k.agirlik_sram, k.agirlik_sram))
    print("  izgara          : %d sutun x %d satir" % (k.kol, satir))
    print("  kanal           : %.0f um" % k.kanal)
    print("  kenar payi      : %.0f um (sol/sag/alt)" % k.kenar)
    print("  UST kenar payi  : %.0f um" % k.ust)
    print("  adim            : %.2f x %.2f um" % (hx, hy))
    print("  die             : %.2f x %.2f um = %.2f mm2" % (die_g, die_y, alan))
    print("  makro doluluk   : %%%.1f" % doluluk)

    # En ust siradaki makronun ustunde kalan bosluk - kritik olcu
    ust_y = k.kenar + (satir - 1) * hy + MAKRO_Y
    print("  ust sira ustu   : %.0f um bosluk" % (die_y - ust_y))

    if k.goster:
        return 0

    satirlar = []
    for n, ad in enumerate(adlar):
        r, c = divmod(n, k.kol)
        satirlar.append(
            "      '%s':\n        location: [%.2f, %.2f]\n        orientation: N"
            % (ad, k.kenar + c * hx, k.kenar + r * hy))

    s = io.open(CONFIG, encoding="utf-8").read()
    i = s.find(BASLA + "\n")
    if i < 0:
        print("HATA: config.yaml icinde 'instances:' bulunamadi")
        return 1
    j = s.find("\n# ", i)
    if j < 0:
        print("HATA: instances blokunun sonu bulunamadi")
        return 1

    s = s[:i] + BASLA + "\n" + "\n".join(satirlar) + "\n" + s[j:]
    s = re.sub(r"DIE_AREA: \[0, 0, [\d.]+, [\d.]+\]",
               "DIE_AREA: [0, 0, %.2f, %.2f]" % (die_g, die_y), s)

    io.open(CONFIG, "w", encoding="utf-8", newline="\n").write(s)
    print("\nconfig.yaml guncellendi: %d makro, DIE_AREA %.2f x %.2f"
          % (adet, die_g, die_y))
    return 0


if __name__ == "__main__":
    sys.exit(main())
