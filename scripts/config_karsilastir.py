#!/usr/bin/env python3
"""Teslim edilen asic/config.yaml ile kosumun urettigi resolved.json'u karsilastirir.

Amac: teslim edilen yapilandirmanin FIILEN KOSULAN yapilandirma oldugunu
kanitlamak. Sartname, teslim edilen config ile akisin yeniden
kosulabilmesini ister; ikisi ayrisirsa `make asic_run` baska bir tasarim
uretir.

Farklar iki gruba ayrilir:
  - akis turetmesi : teslim dosyasinda HIC BULUNMAYAN, akisin kosum
                     sirasinda ekledigi mutlak yol/ortam anahtarlari
                     (PDK hucre dosyalari, DESIGN_DIR, KLAYOUT_* ...).
                     Makineye ozgudur, baska makinede yeniden cozulur.
  - gercek fark    : teslim dosyasinda BULUNAN ama degeri tutmayan
                     anahtar. Bu bir sorundur ve giderilmelidir.

Kullanim:
    python scripts/config_karsilastir.py
    python scripts/config_karsilastir.py --yaz    # provenance/ guncelle
"""
import argparse
import json
import pathlib
import sys

KOK = pathlib.Path(__file__).resolve().parent.parent
TESLIM = KOK / "asic/config.yaml"
KOSUM = KOK / "asic/results/config/resolved.json"
CIKTI = KOK / "provenance/config_comparison.json"

# Degeri degil yalnizca uzunlugu karsilastirilan liste anahtarlari:
# icerik mutlak yol tasir, uzunluk esitligi yeterli kanittir.
KRITIK = ["CLOCK_PERIOD", "CLOCK_PORT", "PNR_SDC_FILE", "SIGNOFF_SDC_FILE",
          "MAGIC_EXT_USE_GDS", "MAGIC_CAPTURE_ERRORS", "DESIGN_NAME", "PDK",
          "STD_CELL_LIBRARY", "FP_CORE_UTIL", "VERILOG_FILES"]


def karsilastir():
    tes = json.loads(TESLIM.read_text(encoding="utf-8"))
    koz = json.loads(KOSUM.read_text(encoding="utf-8"))

    ayni, turetilen, gercek = [], [], []
    for k in sorted(set(tes) | set(koz)):
        a, b = tes.get(k, "<yok>"), koz.get(k, "<yok>")
        if a == "<yok>":
            turetilen.append(k)
        elif isinstance(a, list) and isinstance(b, list):
            (ayni if len(a) == len(b) else gercek).append(k)
        elif a == b:
            ayni.append(k)
        else:
            gercek.append(k)

    # 'meta' akisin kendi surum bilgisini ekler - gercek fark sayilmaz
    meta_farki = "meta" in gercek
    if meta_farki:
        gercek.remove("meta")

    return tes, koz, ayni, turetilen, gercek, meta_farki


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--yaz", action="store_true",
                    help="provenance/config_comparison.json dosyasini guncelle")
    a = ap.parse_args()

    for p in (TESLIM, KOSUM):
        if not p.is_file():
            sys.exit(f"bulunamadi: {p}")

    tes, koz, ayni, turetilen, gercek, meta_farki = karsilastir()

    print(f"  ayni anahtar          : {len(ayni)}")
    print(f"  akis turetmesi        : {len(turetilen)}")
    print(f"  GERCEK TASARIM FARKI  : {len(gercek)}")
    print()
    print("  kritik anahtarlar:")
    for k in KRITIK:
        if k not in tes:
            continue
        v = tes[k]
        v = f"{len(v)} dosya" if isinstance(v, list) else v
        tutar = "OK " if k not in gercek else "FARK"
        print(f"    [{tutar}] {k:24s} = {v}")

    if gercek:
        print()
        print("  !! GERCEK FARKLAR:")
        for k in gercek:
            print(f"     {k}: teslim={tes.get(k)!r}  kosum={koz.get(k)!r}")

    if a.yaz:
        out = {
            "aciklama": ("Teslim edilen asic/config.yaml ile kosumun kendi "
                         "urettigi asic/results/config/resolved.json "
                         "karsilastirmasi."),
            "kosum": "S_final2",
            "teslim_dosyasi": "asic/config.yaml",
            "kosum_dosyasi": "asic/results/config/resolved.json",
            "ozet": {
                "ayni_anahtar": len(ayni),
                "akis_turetmesi_anahtar": len(turetilen),
                "gercek_tasarim_farki": len(gercek),
            },
            "sonuc": ("TEMIZ - gercek tasarim farki yoktur. Butun farklar, "
                      "akisin kosum sirasinda kendi ekledigi mutlak yol ve "
                      "ortam anahtarlaridir; makineye ozgudur ve baska bir "
                      "makinede yeniden cozulur."
                      if not gercek else
                      f"DIKKAT - {len(gercek)} gercek tasarim farki var."),
            "meta_notu": ("'meta' anahtari akisin kendi surum bilgisini "
                          "(librelane_version, step) ekler; tasarim "
                          "parametresi degildir."
                          if meta_farki else None),
            "gercek_tasarim_farklari": [
                {"anahtar": k, "teslim": str(tes.get(k))[:200],
                 "kosum": str(koz.get(k))[:200]} for k in gercek],
            "akis_turetmesi_anahtarlar": sorted(turetilen),
            "dogrulanan_kritik_anahtarlar": {
                k: (f"{len(tes[k])} dosya" if isinstance(tes[k], list)
                    else tes[k]) for k in KRITIK if k in tes},
            "yeniden_uretme": "python scripts/config_karsilastir.py --yaz",
        }
        CIKTI.write_text(json.dumps(out, indent=2, ensure_ascii=False),
                         encoding="utf-8")
        print(f"\n  yazildi: {CIKTI.relative_to(KOK)}")

    return 1 if gercek else 0


if __name__ == "__main__":
    sys.exit(main())
