# -*- coding: utf-8 -*-
"""flash.hex - QSPI flash imajini uretir (uygulama + NPU FC agirliklari).

NEDEN (23 Agustos 2026)

  FC agirliklari artik kombinasyonel ROM'da degil NPU TCM/SRAM'inde.
  SRAM ucucudur: uretilmis cipte guc verildiginde TCM bostur. Agirliklarin
  KALICI kaynagi flash olmali, yukleyici acilista TCM'e kopyalamalidir.

  Bu betik ikisini tek bir flash imajinda birlestirir.

FLASH YERLESIMI (APP_FLASH_OFS = 0x800000'e gore bagil)

  0x0000 .. 0x1FFF   uygulama         8 kB ayrildi
  0x2000 .. 0x5FFF   FC agirliklari  16 kB (4000 x 32-bit)

  Toplam 24 kB = 6144 x 32-bit kelime.

  Mutlak flash adresleri:
      0x800000  uygulama
      0x802000  FC agirliklari

  Bu ofsetler sw_nexys/src/bootloader.S icindeki APP_FLASH_OFS ve
  WEIGHT_FLASH_OFS ile AYNI olmalidir. Biri degisirse digeri de.
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

APP_HEX     = ROOT / "sw_nexys" / "build" / "app.hex"
WEIGHTS_HEX = ROOT / "weights" / "fc_weights_packed32.mem"
DEST        = ROOT / "sw_nexys" / "build" / "flash.hex"

APP_WORDS     = 2048      # 8 kB
WEIGHT_WORDS  = 4000      # 16 kB
TOTAL_WORDS   = APP_WORDS + WEIGHT_WORDS


def oku(yol):
    if not yol.is_file():
        sys.exit("HATA: bulunamadi: %s" % yol)
    return [x.strip() for x in yol.read_text().split() if x.strip()]


def uret(app_yolu, dest, etiket):
    app = oku(app_yolu)
    agirlik = oku(WEIGHTS_HEX)
    if len(app) > APP_WORDS:
        sys.exit("HATA: %s %d kelime, ayrilan alan %d kelime."
                 % (etiket, len(app), APP_WORDS))
    if len(agirlik) != WEIGHT_WORDS:
        sys.exit("HATA: agirlik dosyasi %d kelime, beklenen %d."
                 % (len(agirlik), WEIGHT_WORDS))
    imaj = app + ["00000000"] * (APP_WORDS - len(app)) + agirlik
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_text("\n".join(imaj) + "\n", encoding="ascii")
    print("%-10s uygulama %4d kelime  toplam %d kelime -> %s"
          % (etiket, len(app), len(imaj), dest.name))


def main():
    # FPGA imaji - gercek uygulama (cikarimlar arasi 3 s bekleme)
    uret(APP_HEX, DEST, "flash")

    # Simulasyon imaji - ARKHE_SIM ile derlenmis uygulama (bekleme 2 ms).
    # REUSE testi (global reset olmadan iki cikarim) bunu kullanir; 3 saniye
    # simulasyonda ~3,5 saat surerdi.
    app_sim = APP_HEX.parent / "app_sim.hex"
    if app_sim.is_file():
        uret(app_sim, DEST.parent / "flash_sim.hex", "flash_sim")
    else:
        print("UYARI: app_sim.hex yok, flash_sim.hex uretilmedi")
    return

    app = oku(APP_HEX)
    agirlik = oku(WEIGHTS_HEX)

    if len(app) > APP_WORDS:
        sys.exit("HATA: uygulama %d kelime, ayrilan alan %d kelime. "
                 "bootloader.S icindeki WEIGHT_FLASH_OFS buyutulmeli."
                 % (len(app), APP_WORDS))

    if len(agirlik) != WEIGHT_WORDS:
        sys.exit("HATA: agirlik dosyasi %d kelime, beklenen %d."
                 % (len(agirlik), WEIGHT_WORDS))

    imaj = app + ["00000000"] * (APP_WORDS - len(app)) + agirlik
    assert len(imaj) == TOTAL_WORDS

    DEST.parent.mkdir(parents=True, exist_ok=True)
    DEST.write_text("\n".join(imaj) + "\n", encoding="ascii")

    print("uygulama : %5d kelime  (%5d bos ile dolduruldu)"
          % (len(app), APP_WORDS - len(app)))
    print("agirlik  : %5d kelime  -> flash 0x802000" % len(agirlik))
    print("toplam   : %5d kelime  = %d kB" % (TOTAL_WORDS, TOTAL_WORDS * 4 // 1024))
    print("yazildi  : %s" % DEST)


if __name__ == "__main__":
    main()
