#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
asic/checksums/SHA256SUMS uretir.

Final Ciktilar Bolum 6.3, "Onerilen Ek Ciktilar":

    SHA256SUMS   Teslim edilen dosyalarin SHA-256 ozet degerleri

Bicim standart sha256sum ciktisidir; dogrulamak icin:

    cd asic && sha256sum -c checksums/SHA256SUMS

Kapsam: asic/results/ ve asic/reports/ altindaki TUM dosyalar. Yollar
asic/ dizinine goredir, boylece deponun nereye klonlandigi onemli olmaz.

Bu betik akis tamamlanmadan da calisir; henuz uretilmemis ciktilar icin
yalnizca uyari basar ve sifir olmayan kod DONMEZ (Makefile'da collect
hedefinin sonunda cagriliyor).
"""
import hashlib
import os
import sys
from datetime import datetime, timezone

HERE = os.path.dirname(os.path.abspath(__file__))
ASIC = os.path.dirname(HERE)

# Ozeti alinacak agaclar (asic/ dizinine gore)
KAPSAM = ["results", "reports"]

# Uretilmis ozet dosyasinin kendisi kapsam disi kalmali
HARIC_DOSYA = {"SHA256SUMS"}

BLOK = 1 << 20      # 1 MiB - 330 MB'lik GDS'i belleğe almadan okur


def sha256(yol):
    h = hashlib.sha256()
    with open(yol, "rb") as fh:
        while True:
            parca = fh.read(BLOK)
            if not parca:
                break
            h.update(parca)
    return h.hexdigest()


def main():
    kayitlar = []
    toplam_bayt = 0

    for kok in KAPSAM:
        tam_kok = os.path.join(ASIC, kok)
        if not os.path.isdir(tam_kok):
            continue
        for dizin, _alt, dosyalar in os.walk(tam_kok):
            for ad in sorted(dosyalar):
                if ad in HARIC_DOSYA or ad == ".gitkeep":
                    continue
                tam = os.path.join(dizin, ad)
                if not os.path.isfile(tam):
                    continue
                # Yol ayraci her platformda '/' olsun - sha256sum uyumu
                goreli = os.path.relpath(tam, ASIC).replace(os.sep, "/")
                try:
                    ozet = sha256(tam)
                except OSError as e:
                    print("UYARI: okunamadi %s (%s)" % (goreli, e))
                    continue
                kayitlar.append((goreli, ozet))
                toplam_bayt += os.path.getsize(tam)

    hedef_dizin = os.path.join(ASIC, "checksums")
    os.makedirs(hedef_dizin, exist_ok=True)
    hedef = os.path.join(hedef_dizin, "SHA256SUMS")

    if not kayitlar:
        print("UYARI: results/ ve reports/ altinda dosya yok.")
        print("       ASIC akisi henuz kosmamis olabilir; once 'make asic_run',")
        print("       sonra 'make collect' calistirin.")
        return 0

    kayitlar.sort()

    with open(hedef, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("# Arkhe SoC - teslim edilen ASIC ciktilarinin SHA-256 ozetleri\n")
        fh.write("# Uretildi: %s\n" % datetime.now(timezone.utc)
                 .strftime("%Y-%m-%d %H:%M:%S UTC"))
        fh.write("# Uretici : asic/scripts/gen_checksums.py\n")
        fh.write("# Dogrula : cd asic && sha256sum -c checksums/SHA256SUMS\n")
        fh.write("#\n")
        fh.write("# Yollar asic/ dizinine goredir.\n")
        for goreli, ozet in kayitlar:
            fh.write("%s  %s\n" % (ozet, goreli))

    mb = toplam_bayt / (1024.0 * 1024.0)
    print("SHA256SUMS uretildi: %d dosya, %.1f MB" % (len(kayitlar), mb))
    print("  %s" % os.path.relpath(hedef, ASIC).replace(os.sep, "/"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
