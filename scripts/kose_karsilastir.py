#!/usr/bin/env python3
"""Iki ASIC kosumunun dokuz kose metriklerini yan yana koyar.

Kullanim:
    python scripts/kose_karsilastir.py REFERANS.json YENI.json

G_saat deneyi icin: C_kapanis referans, G_saat yeni. Bakilan sey
saat skew'inin kuculup kuculmedigi - C olcumu hold ihlallerinin
skew'in artigi oldugunu gosterdi (skew/WNS orani 2,5-291 kat).
"""
import json
import sys


def yukle(p):
    with open(p) as f:
        return json.load(f)


def kose_tablosu(d, onek):
    return {k.split(":")[-1]: v for k, v in d.items()
            if k.startswith(onek) and ":" in k}


def yazdir(baslik, ref, yeni, tersine_iyi=False):
    """tersine_iyi: True ise deger BUYUDUKCE iyi (slack gibi)."""
    print()
    print(baslik)
    print("  %-22s %10s %10s %10s" % ("kose", "referans", "yeni", "fark"))
    print("  " + "-" * 54)
    kotu = iyi = 0
    for kose in sorted(set(ref) | set(yeni)):
        a, b = ref.get(kose), yeni.get(kose)
        if a is None or b is None:
            continue
        fark = b - a
        # Skew ve slack negatifken kotudur; sifira yaklasmak iyidir.
        gelisme = abs(b) < abs(a) if not tersine_iyi else b > a
        isaret = "  IYI" if gelisme and abs(fark) > 1e-6 else (
            " KOTU" if abs(fark) > 1e-6 else "     ")
        if abs(fark) > 1e-6:
            iyi += gelisme
            kotu += not gelisme
        print("  %-22s %10.4f %10.4f %+10.4f%s" % (kose, a, b, fark, isaret))
    print("  -> %d kosede iyilesme, %d kosede kotulesme" % (iyi, kotu))


def main():
    if len(sys.argv) != 3:
        print(__doc__)
        return 1
    ref, yeni = yukle(sys.argv[1]), yukle(sys.argv[2])

    yazdir("SAAT SKEW (hold) - ASIL BAKILAN",
           kose_tablosu(ref, "clock__skew__worst_hold__corner"),
           kose_tablosu(yeni, "clock__skew__worst_hold__corner"))

    yazdir("HOLD WNS",
           kose_tablosu(ref, "timing__hold__wns__corner"),
           kose_tablosu(yeni, "timing__hold__wns__corner"))

    yazdir("SETUP WS (buyudukce iyi)",
           kose_tablosu(ref, "timing__setup__ws__corner"),
           kose_tablosu(yeni, "timing__setup__ws__corner"), tersine_iyi=True)

    print()
    print("HUCRE SAYIMI")
    print("  %-34s %10s %10s" % ("sinif", "referans", "yeni"))
    print("  " + "-" * 56)
    for k in ["design__instance__count__class:clock_buffer",
              "design__instance__count__class:clock_inverter",
              "design__instance__count__class:timing_repair_buffer",
              "design__instance__count__hold_buffer",
              "design__instance__count__setup_buffer",
              "design__max_slew_violation__count",
              "design__max_cap_violation__count",
              "design__max_fanout_violation__count"]:
        a, b = ref.get(k), yeni.get(k)
        if a is None and b is None:
            continue
        ad = k.split(":")[-1] if ":" in k else k.replace(
            "design__instance__count__", "").replace("design__", "")
        print("  %-34s %10s %10s" % (ad, a, b))
    return 0


if __name__ == "__main__":
    sys.exit(main())
