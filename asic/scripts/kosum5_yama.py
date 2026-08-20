#!/usr/bin/env python3
"""
kosum5_yama.py - 5. (son) kosum icin config.yaml yamasi

YALNIZCA 4. KOSUM DRT-1231 ILE DUSERSE UYGULANIR.

4. kosum su iki degisikligi tasiyordu:
    PDN_MACRO_CONNECTIONS      makro guc baglantisi  (KANITLANDI: 46 eslesme)
    FP_MACRO_*_HALO: 25        makro kenar payi      (sinavi 44. adimda)

Halo yetmezse sorunun kokune inilir: diyot yerlestirmesi.

    3. kosumdaki hata zinciri
      1. Ana yonlendirme BASARILI bitti - 63 turda 55.347 -> 23 ihlal
      2. Anten denetimi 282 ag + 343 pin ihlali buldu
      3. Onarim 586 DIYOT ekledi
      4. Bir diyot makro kenarina dusunce pin erisimi kapandi:
         [ERROR DRT-1231] Pin u_data_ram.g_sram[3].u_macro/addr1[7]
                          does not have access point

Bu yama diyot yerlestirmesini TAMAMEN devreden cikarir.

    GRT_ANTENNA_REPAIR_JUMPER_ONLY: true

Anten ihlalleri diyot yerine METAL ATLAMA TELI (jumper) ile giderilir.
Atlama teli yeni hucre yerlestirmez - yalnizca mevcut agi ust katmana
tasir. Yerlesim kalabaligi olusmaz, dolayisiyla makro pini kapanamaz.

Maliyeti yonlendirme kaynagidir; bizde bol:
    global yonlendirme kullanimi %14,4, overflow 0

Halo da 25 -> 30 um cikarilir. Son kosum oldugu icin iki onlem birden
alinir; hangisinin ise yaradigini ayirt etmek teslim tarihinden sonraki
bir merak konusudur.

Kullanim (WSL, asic/ dizininden):

    python3 scripts/kosum5_yama.py
    rm -rf run/arkhe
    make asic_run
"""

import io
import os
import sys

ASIC = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CONFIG = os.path.join(ASIC, "config.yaml")

YAMA = """
# -----------------------------------------------------------------------------
# ANTEN ONARIMI - YALNIZCA ATLAMA TELI  (5. kosumda eklendi)
#
# 3. kosum su hatayla dustu:
#     [ERROR DRT-1231] Pin u_data_ram.g_sram[3].u_macro/addr1[7]
#                      does not have access point
#
# Kok neden: anten onarimi 586 diyot ekledi, biri makro kenarina dusup
# pin erisimini kapatti. 4. kosumda halo 25 um'ye cikarildi; yetmedi.
#
# Bu ayar diyot yerlestirmesini tamamen devreden cikarir. Anten ihlalleri
# metal atlama teliyle giderilir - yeni hucre yerlesmez, yerlesim
# kalabaligi olusmaz, makro pini kapanamaz.
#
# Maliyet yonlendirme kaynagidir. Bizde bol: global yonlendirme kullanimi
# %14,4, overflow 0.
# -----------------------------------------------------------------------------
GRT_ANTENNA_REPAIR_JUMPER_ONLY: true
"""


def main():
    s = io.open(CONFIG, encoding="utf-8").read()

    if "GRT_ANTENNA_REPAIR_JUMPER_ONLY" in s:
        print("Yama zaten uygulanmis. Bir sey yapilmadi.")
        return 0

    if "FP_MACRO_HORIZONTAL_HALO: 25" not in s:
        print("HATA: config.yaml beklenen 4. kosum halinde degil.")
        print("      'FP_MACRO_HORIZONTAL_HALO: 25' bulunamadi.")
        return 1

    # Halo 25 -> 30
    s = s.replace("FP_MACRO_HORIZONTAL_HALO: 25", "FP_MACRO_HORIZONTAL_HALO: 30")
    s = s.replace("FP_MACRO_VERTICAL_HALO: 25", "FP_MACRO_VERTICAL_HALO: 30")
    s = s.replace("PDN_HORIZONTAL_HALO: 25", "PDN_HORIZONTAL_HALO: 30")
    s = s.replace("PDN_VERTICAL_HALO: 25", "PDN_VERTICAL_HALO: 30")

    s = s.rstrip("\n") + "\n" + YAMA

    io.open(CONFIG, "w", encoding="utf-8", newline="\n").write(s)

    print("5. kosum yamasi uygulandi:")
    print("  halo                           25 -> 30 um")
    print("  GRT_ANTENNA_REPAIR_JUMPER_ONLY true (diyot yerlestirmesi kapali)")
    print()
    print("Simdi:  rm -rf run/arkhe && make asic_run")
    return 0


if __name__ == "__main__":
    sys.exit(main())
