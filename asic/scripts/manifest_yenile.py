#!/usr/bin/env python3
"""provenance/package_files.json manifestini mevcut dosyalardan yeniden uretir.

NEDEN VAR
  Teslim paketi K_diyot kosumuna gecirildi (11 Eylul 2026). Onceki
  manifest d45_anten2 kosumunun dosyalarina aitti; GDS, DEF, netlist,
  SPEF ve timing raporlari degistigi icin 629 hash uyusmazligi
  veriyordu.

  Bu script manifesti YENIDEN URETIR: dosya listesi korunur, boyut ve
  SHA-256 degerleri mevcut icerikten hesaplanir.

NE YAPMAZ
  Yeni dosya EKLEMEZ, dosya SILMEZ. Yalnizca listedeki dosyalarin
  hash/boyut bilgisini tazeler. Listede olup diskte olmayan dosya
  varsa uyarir ve cikis kodu 1 verir - sessizce gecmez.

KULLANIM
    python3 scripts/manifest_yenile.py            # onizleme
    python3 scripts/manifest_yenile.py --yaz      # dosyayi guncelle
"""
import hashlib
import json
import pathlib
import sys

KOK = pathlib.Path(__file__).resolve().parents[2]
MANIFEST = KOK / "provenance" / "package_files.json"


def hashle(yol):
    h = hashlib.sha256()
    with yol.open("rb") as f:
        for blok in iter(lambda: f.read(4 * 1024 * 1024), b""):
            h.update(blok)
    return h.hexdigest()


def main():
    yaz = "--yaz" in sys.argv
    eski = json.loads(MANIFEST.read_text())

    yeni = {}
    eksik = []
    degisen = 0

    # Bu kosumda URETILMEYEN dosyalar manifestten DUSURULUR.
    # Sessizce atlanmaz - asagida ayrica raporlanir.
    #
    #   S_hold2 (13 Eylul 2026) SPICE cikarimini LEF/DEF gorunumunden
    #   yapar (MAGIC_EXT_USE_GDS=false) ve LVS'i o netlist uzerinde
    #   kosar -> "Circuits match uniquely".
    #
    #   Onceki K_diyot kosusunda ise GDS tabanli ek bir cikarim ve ona
    #   dayali ek bir LVS calismasi vardi. S_hold2'de bu EK calisma
    #   TEKRARLANMADI, dolayisiyla su dosyalar uretilmez:
    #       results/spice/soc_top_gds.spice
    #       reports/lvs_gds/*         (ek GDS-LVS raporlari)
    #   Bu, standart akisin istedigi LVS'nin eksik oldugu anlamina
    #   GELMEZ; yalnizca GDS ici transistor duzeyinde EK bir dogrulama
    #   iddia edilmedigini belirtir. Ayrinti: asic/README.md §12.
    #
    #   *.mcs : FPGA flash imajlari; buyuk binary olduklari icin
    #       depoda tutulmuyor, ASIC teslimiyle ilgisiz.
    DUSUR = (

        # S_final2 (13 Eylul 2026): SPICE artik GDS'ten cikariliyor
        # (MAGIC_EXT_USE_GDS=true) ve adi soc_top.spice'dir.
        # Eski LEF/DEF tabanli ad artik uretilmez.
        "asic/results/spice/soc_top_lef_def.spice",
        "asic/reports/lvs_gds/env.tcl",
        "asic/reports/lvs_gds/extract.log",
        "asic/reports/lvs_gds/lvs.netgen.json",
        "asic/reports/lvs_gds/lvs.netgen.rpt",
        "asic/reports/lvs_gds/lvs_script.lvs",
        "asic/reports/lvs_gds/netgen.log",
        "asic/reports/lvs_gds/netgen_env.tcl",
        "asic/reports/lvs_gds/run.py",
        "asic/reports/lvs_gds/status.json",
        # Eski d45_anten2 GitHub Release kaydi - bu teslimde harici
        # arsiv YOK, tum ciktilar depo icinde (asic/README.md 12.1).
        "provenance/release_assets.json",
        "d45_anten2-delivery.tar.gz.sha256",
        "fpga/JURI_FPGA_TESTI/arkhe_jury.mcs",
        "fpga/nexys_demo_20260908/firmware/build/arkhe_demo_flash.mcs",
    )
    dusurulen = []

    for rel, bilgi in sorted(eski.items()):
        f = KOK / rel
        if not f.is_file():
            # Eski manifestte bazi Turkce adlar CIFT KODLANMIS:
            # 'ç' UTF-8 baytlari (0xC3 0xA7) iki ayri karakter olarak
            # yazilmis. Diskteki ad dogru; manifest bozuk. Cozup dene.
            try:
                duz = rel.encode("latin-1").decode("utf-8")
                if (KOK / duz).is_file():
                    rel = duz
                    f = KOK / rel
            except (UnicodeEncodeError, UnicodeDecodeError):
                pass
        if not f.is_file():
            if rel in DUSUR:
                dusurulen.append(rel)
            else:
                eksik.append(rel)
            continue
        b = f.stat().st_size
        h = hashle(f)
        yeni[rel] = {"bytes": b, "sha256": h}
        if b != bilgi.get("bytes") or h != bilgi.get("sha256"):
            degisen += 1

    print("manifest girdisi : %d" % len(eski))
    print("guncellenen      : %d" % degisen)
    print("manifestten dusen: %d" % len(dusurulen))
    for r in dusurulen:
        print("    -", r)
    print("diskte YOK       : %d" % len(eksik))
    for r in eksik[:10]:
        print("   ", r)
    if len(eksik) > 10:
        print("    ... (%d tane daha)" % (len(eksik) - 10))

    if eksik:
        print()
        print("HATA: listedeki bazi dosyalar diskte yok.")
        print("Manifest YAZILMADI - once eksikler giderilmeli.")
        return 1

    if yaz:
        MANIFEST.write_text(json.dumps(yeni, indent=1, sort_keys=True) + "\n")
        print()
        print("YAZILDI: %s" % MANIFEST)
    else:
        print()
        print("(onizleme - yazmak icin --yaz ekleyin)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
