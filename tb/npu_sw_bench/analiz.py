#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Yazilim gerceklemesinin tam cikarim maliyetini iki olcumden cikarir.

NEDEN IKI OLCUM

Tam cikarim ~64 milyon cevrimdir; RTL simulasyonunda saatler surer. Bunun
yerine kucuk bir alt kume olculur. Ancak DUZ PIKSEL ORANI ILE OLCEKLEME
YANLIS SONUC VERIR:

  Olculen ilk N piksel tamamen t=0 bolgesindedir. Orada cekirdegin 10
  satirindan yalnizca 6'si gecerlidir (ti = 2t-4+kh, 0 <= ti <= 48).
  f=0 ve f=1 sutunlarinda da 8 kolondan 5 ve 7'si gecerlidir. Yani
  olculen pikseller ic bolgedekilerden cok daha ucuzdur.

MODEL

  cevrim = a * tap + b * piksel

    a : tap (bir MAC + iki TCM bayt okumasi) basina maliyet
    b : piksel basina sabit maliyet (requantization, ReLU, 4 FC MAC,
        dongu yonetimi)

Iki bilinmeyen, iki olcum -> kapali cozum.

KULLANIM

  1) Iki kosum yap ve cevrim sayilarini not et:
         xvlog ... -d BENCH_N25 ; xelab ; xsim
         xvlog ... -d BENCH_N50 ; xelab ; xsim
  2) Sayilari asagidaki OLCUMLER tablosuna yaz
  3) python tb/npu_sw_bench/analiz.py
"""

# (N_OUT, olculen cevrim)  -  tb_npu_sw_bench.sv ciktisindan
OLCUMLER = [
    (25, 252625),
    (50, 542273),
]

DONANIM_CEVRIM = 72583      # tb_npu_audio, cikarim basina
SAAT_HZ        = 50_000_000


def gecerli_kh(t):
    """t cikis satiri icin gecerli cekirdek satiri sayisi (SAME padding)."""
    return sum(1 for k in range(10) if 0 <= 2 * t - 4 + k <= 48)


def gecerli_kw(f):
    """f cikis sutunu icin gecerli cekirdek sutunu sayisi."""
    return sum(1 for k in range(8) if 0 <= 2 * f - 3 + k <= 39)


def tap_onek(n):
    """Ilk n cikis pikselinin toplam tap sayisi."""
    sayi = 0
    toplam = 0
    for t in range(25):
        for f in range(20):
            for _d in range(8):
                if sayi >= n:
                    return toplam
                toplam += gecerli_kh(t) * gecerli_kw(f)
                sayi += 1
    return toplam


TOPLAM_TAP    = 8 * sum(gecerli_kh(t) for t in range(25)) \
                  * sum(gecerli_kw(f) for f in range(20))
TOPLAM_PIKSEL = 4000


def main():
    if len(OLCUMLER) < 2:
        raise SystemExit("en az iki olcum gerekli")

    (n1, c1), (n2, c2) = OLCUMLER[0], OLCUMLER[1]
    t1, t2 = tap_onek(n1), tap_onek(n2)

    # c1 = a*t1 + b*n1 ; c2 = a*t2 + b*n2
    payda = t2 * n1 - t1 * n2
    if payda == 0:
        raise SystemExit("olcumler dogrusal bagimli - farkli N secin")
    a = (c2 * n1 - c1 * n2) / payda
    b = (c1 - a * t1) / n1

    tam = a * TOPLAM_TAP + b * TOPLAM_PIKSEL
    hizlanma = tam / DONANIM_CEVRIM

    print("=" * 64)
    print(" YAZILIM / DONANIM HIZLANMA ANALIZI")
    print("=" * 64)
    print("Olcumler:")
    for n, c in OLCUMLER:
        print("  N=%-4d  tap=%-6d  cevrim=%d" % (n, tap_onek(n), c))
    print()
    print("Cozulen model:  cevrim = a*tap + b*piksel")
    print("  a (tap basina)          : %8.1f cevrim" % a)
    print("  b (piksel basina sabit) : %8.0f cevrim" % b)
    print()
    print("Tam cikarim:")
    print("  gecerli tap             : %8d" % TOPLAM_TAP)
    print("  piksel                  : %8d" % TOPLAM_PIKSEL)
    print("  YAZILIM                 : %,d cevrim".replace(",", "") % int(tam)
          if False else "  YAZILIM                 : %d cevrim = %.2f s @%d MHz"
          % (int(tam), tam / SAAT_HZ, SAAT_HZ // 1_000_000))
    print("  DONANIM (NPU)           : %d cevrim = %.2f ms"
          % (DONANIM_CEVRIM, DONANIM_CEVRIM * 1000.0 / SAAT_HZ))
    print()
    print("  HIZLANMA                : %.0fx" % hizlanma)
    print()
    print("Sartname 4.2.2.1 'islenmis veri/saniye':")
    print("  yazilim : %.2f cikarim/s" % (SAAT_HZ / tam))
    print("  donanim : %.0f cikarim/s" % (SAAT_HZ / DONANIM_CEVRIM))
    print("=" * 64)


if __name__ == "__main__":
    main()
