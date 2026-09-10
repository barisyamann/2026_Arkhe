#!/usr/bin/env python3
"""Sentez/PnR sonrasi kritik yolun SRAM->CPU bypass'ini icerip
icermedigini kontrol eder.

NEDEN VAR
  10 Eylul 2026 denetimi, G_saat kosumunun en kotu setup yolunun
  SRAM makro cikisindan CPU ALU girisine kadar uzandigini gosterdi:

      u_instruction_ram.g_sram[2].u_macro/dout1[17]
        -> SRAM bank secimi ve bypass mux'lari
        -> komut/veri secimi ve islemci mantigi
        -> _186846_/D    (_186846_/Q = u_core.alu_operand_b_ex[1])

  Kok neden: sunucudaki ESKI sram_module.sv makro okumasini dogrudan
  geciriyordu (bypass). Yereldeki duzeltilmis surum ise kayitli veri
  verir; bu yolun KESILMESI beklenir.

  Bu script, duzeltmenin fiziksel tasarimda gercekten ise yarayip
  yaramadigini TAM KOSUM BEKLEMEDEN olcer.

KULLANIM
    python scripts/kritik_yol_kontrol.py <max.rpt yolu>
"""
import re
import sys

# Bypass yolunun imzasi: SRAM makro cikisi ile CPU ic dugumu ayni yolda
MAKRO_DESEN = re.compile(r"u_(instruction|data)_ram\.g_sram\[\d+\]\.u_macro/dout")
CPU_DESEN = re.compile(r"u_core\.|alu_operand|_\d{6}_/D")


def main():
    if len(sys.argv) != 2:
        print(__doc__)
        return 2
    metin = open(sys.argv[1], encoding="utf8", errors="replace").read()

    # Ilk yol blogunu al (en kotu yol)
    bloklar = metin.split("Startpoint:")
    if len(bloklar) < 2:
        print("Rapor beklenen bicimde degil (Startpoint bulunamadi)")
        return 2
    ilk = bloklar[1][:8000]

    makro = MAKRO_DESEN.search(ilk)
    cpu = CPU_DESEN.search(ilk)

    print("EN KOTU SETUP YOLU")
    bas = ilk.split("\n")[0].strip()
    print("  Startpoint: %s" % bas[:90])
    for l in ilk.split("\n"):
        if "Endpoint:" in l:
            print("  %s" % l.strip()[:90])
            break
    m = re.search(r"(-?[\d.]+)\s+slack", ilk)
    if m:
        print("  slack: %s ns" % m.group(1))

    print()
    if makro and cpu:
        print("SONUC: SRAM -> CPU BYPASS YOLU HALA VAR")
        print("  makro cikisi: %s" % makro.group(0))
        print("  CPU dugumu  : %s" % cpu.group(0))
        print("  Duzeltilmis RTL kullanildigindan emin olun")
        print("  (python scripts/rtl_manifest.py dogrula asic/rtl_manifest.txt)")
        return 1
    if makro:
        print("SONUC: yol SRAM'den basliyor ama CPU'ya uzanmiyor")
        print("  Bu BEKLENEN durumdur: okuma kayitli, yol kisaldi.")
        return 0
    print("SONUC: en kotu yol SRAM makrosundan gelmiyor")
    print("  Bypass yolu kesilmis gorunuyor.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
