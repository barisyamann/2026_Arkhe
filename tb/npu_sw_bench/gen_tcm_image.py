#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Yazilim kiyaslamasi icin NPU TCM on-yukleme imaji uretir.

NEDEN GEREKLI

Sartname EK-1:
    "YZ hizlandiricisi modeli gerceklemeli ve RISC-V cekirdegi uzerinde
     calisan yazilim gerceklemesine kiyasla HIZLANMA elde etmelidir."

Bolum 4.2.2.1:
    "YZ hizlandiricilarin performanslari, testler kapsaminda veri/saat
     dongusu bazinda ve sentezlenmis frekansta islenmis veri/saniye
     bazinda test edilmeli ve degerlendirilmelidir."

Yani hizlanma ORANI icin CPU uzerindeki yazilim gerceklemesinin cevrim
sayisi olculmelidir. Ancak FC agirliklari 16 kB'dir ve D-RAM yalnizca
8 kB'dir - yazilim modeli agirliklari D-RAM'e sigdiramaz.

Cozum: agirliklar 30 kB'lik NPU TCM'ine yerlestirilir; CPU oraya AXI
uzerinden erisir. Bu, bu SoC uzerinde gercekci TEK yazilim senaryosudur -
16 kB agirlik baska hicbir yere sigmaz.

TCM YERLESIMI  (32-bit word ofsetleri)

    0      giris        490 word   (1960 INT8)
    512    dw_weights   160 word   (640 INT8)
    704    dw_bias        8 word   (8 INT32)
    768    fc_weights  4000 word   (16000 INT8)
    4768   fc_bias        4 word   (4 INT32)
    4800   softmax LUT  256 word   (256 x 13 bit)

    Toplam 5056 word kullanilir; TCM 7680 word'dur.

Bu ofsetler npu_sw_bench.c icindeki tanimlarla AYNI olmak zorundadir.
"""
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
W = ROOT / "weights"

TCM_WORDS = 7680

OFS_GIRIS   = 0
OFS_DW_W    = 512
OFS_DW_B    = 704
OFS_FC_W    = 768
OFS_FC_B    = 4768
OFS_LUT     = 4800


def oku_hex(path):
    return [int(x, 16) for x in Path(path).read_text().split()]


def paketle_i8(bayt_listesi):
    """INT8 dizisini 4'erli little-endian 32-bit word'lere paketler."""
    words = []
    for i in range(0, len(bayt_listesi), 4):
        w = 0
        for b in range(4):
            if i + b < len(bayt_listesi):
                w |= (bayt_listesi[i + b] & 0xFF) << (8 * b)
        words.append(w)
    return words


def main():
    tcm = [0] * TCM_WORDS

    def yerlestir(ofs, words, ad):
        if ofs + len(words) > TCM_WORDS:
            sys.exit("TCM tasti: %s" % ad)
        tcm[ofs:ofs + len(words)] = words
        print("  %-14s ofs=%-5d %5d word" % (ad, ofs, len(words)))

    # Girdi: npu_audio'nun ilk vektoru - deterministik golden ile ayni
    giris = [((i * 37 + 13) % 256) - 128 for i in range(1960)]
    yerlestir(OFS_GIRIS, paketle_i8(giris), "giris")

    yerlestir(OFS_DW_W, paketle_i8(oku_hex(W / "dw_weights.mem")), "dw_weights")
    yerlestir(OFS_DW_B, oku_hex(W / "dw_bias.mem"), "dw_bias")
    yerlestir(OFS_FC_W, paketle_i8(oku_hex(W / "fc_weights.mem")), "fc_weights")
    yerlestir(OFS_FC_B, oku_hex(W / "fc_bias.mem"), "fc_bias")
    yerlestir(OFS_LUT, oku_hex(W / "softmax_exp_lut.mem"), "softmax_lut")

    hedef = HERE / "tcm_image.mem"
    hedef.write_text("\n".join("%08x" % w for w in tcm) + "\n")
    print("\nYazildi: %s  (%d word)" % (hedef.name, TCM_WORDS))


if __name__ == "__main__":
    main()
