#!/usr/bin/env python3
"""provenance/signoff_metrics.json dosyasini guncel kosumdan yeniden uretir.

NEDEN VAR
  13 Eylul 2026 dis incelemesi, bu dosyanin hala ONCEKI kosumun
  (d45_anten2) metriklerini tasidigini tespit etti. 68 anahtarin
  31'i gercek degerden farkliydi:

      anten diyotu      6380  ->  2233
      toplam guc     121,8 mW -> 105,7 mW
      max slew         19.341 ->  16.030
      max cap           1.888 ->   1.952
      max fanout           11 ->      81
      lint warning        818 ->     813

  asic/README bu dosyayi "makine tarafindan secilmis guncel metrikler"
  diye tanimladigi icin celiski dogrudan teslim riskiydi.

NE YAPAR
  asic/results/metrics/metrics.json icinden ayni anahtar kumesini okur
  ve provenance dosyasini tazeler. Anahtar listesi korunur; yalnizca
  degerler guncellenir. Kaynakta artik bulunmayan anahtarlar (orn.
  daha az yonlendirme iterasyonu gerektigi icin dusen
  route__drc_errors__iter:N) DUSURULUR ve raporlanir.

KULLANIM
    python scripts/signoff_metrics_yenile.py          # onizleme
    python scripts/signoff_metrics_yenile.py --yaz    # dosyayi guncelle
"""
import argparse
import json
import pathlib
import sys

KOK = pathlib.Path(__file__).resolve().parent.parent
HEDEF = KOK / "provenance/signoff_metrics.json"
KAYNAK = KOK / "asic/results/metrics/metrics.json"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--yaz", action="store_true")
    a = ap.parse_args()

    for p in (HEDEF, KAYNAK):
        if not p.is_file():
            sys.exit(f"bulunamadi: {p}")

    eski = json.loads(HEDEF.read_text(encoding="utf-8"))
    kaynak = json.loads(KAYNAK.read_text(encoding="utf-8"))

    yeni, degisen, dusen = {}, [], []
    for k in eski:
        if k in kaynak:
            yeni[k] = kaynak[k]
            if str(eski[k]) != str(kaynak[k]):
                degisen.append((k, eski[k], kaynak[k]))
        else:
            dusen.append(k)

    print(f"  anahtar        : {len(eski)}")
    print(f"  guncellenen    : {len(degisen)}")
    print(f"  kaynakta YOK   : {len(dusen)}")
    if dusen:
        for k in dusen:
            print(f"    dusuruldu: {k}")
    if degisen:
        print("\n  degisen degerler:")
        for k, e, y in degisen:
            print(f"    {k[:48]:50s} {str(e)[:12]:14s} -> {y}")

    if a.yaz:
        HEDEF.write_text(json.dumps(yeni, indent=1, ensure_ascii=False) + "\n",
                         encoding="utf-8")
        print(f"\n  YAZILDI: {HEDEF.relative_to(KOK)}")
    else:
        print("\n  (onizleme - yazmak icin --yaz ekleyin)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
