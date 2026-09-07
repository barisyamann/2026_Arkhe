#!/usr/bin/env python3
# =============================================================================
#  check_teslim.py - Final Ciktilar belgesine gore teslim denetimi
#
#  make asic_verify tarafindan cagrilir.
#
#  Belge (Final Ciktilar 2026) Bolum 5'te ZORUNLU RAPORLARI, Bolum 6'da
#  ZORUNLU CIKTILARI tanimliyor. Bu betik hepsinin varligini denetler ve
#  eksikleri listeler.
#
#  Cikis kodu: 0 tam, 1 eksik var.
# =============================================================================

import hashlib
import io
import os
import sys

ASIC = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# (bagil_yol, zorunlu_mu, aciklama)
# Bolum 6.1 - zorunlu fiziksel tasarim gorunumleri
ZORUNLU_CIKTI = [
    ("results/gds",     True,  "Nihai GDSII                    (Bolum 6.1)"),
    ("results/lef",     True,  "Nihai LEF                      (Bolum 6.1)"),
    ("results/def",     True,  "Nihai DEF                      (Bolum 6.1)"),
    ("results/netlist", True,  "Gate level netlistler          (Bolum 6.2)"),
    ("results/sdc",     True,  "PnR ve signoff SDC             (Bolum 6.2)"),
    ("results/spef",    True,  "Parazitik SPEF                 (Bolum 6.2)"),
    ("results/spice",   True,  "LVS SPICE/CDL netlisti         (Bolum 6.2)"),
    ("results/config",  True,  "resolved.json                  (Bolum 6.2)"),
    ("results/metrics", True,  "metrics.csv / metrics.json     (Bolum 6.2)"),
    # Bolum 6.3 - onerilen
    ("results/odb",     False, "ODB veritabani                 (Bolum 6.3, onerilen)"),
    ("results/sdf",     False, "SDF gecikme dosyasi            (Bolum 6.3, onerilen)"),
    ("results/lib",     False, "Liberty modeli                 (Bolum 6.3, onerilen)"),
    ("results/mag",     False, "Magic layout                   (Bolum 6.3, onerilen)"),
    ("results/images",  False, "Yerlesim goruntusu             (Bolum 6.3, onerilen)"),
    ("checksums",       False, "SHA256SUMS                     (Bolum 6.3, onerilen)"),
]

# Bolum 5 - zorunlu raporlar
ZORUNLU_RAPOR = [
    ("reports/general",   True,  "flow.log, warning.log, error.log  (5.1)"),
    ("reports/lint",      True,  "Verilator lint ciktisi            (5.2)"),
    ("reports/synthesis", True,  "stat.rpt, chk.rpt, latch.rpt      (5.3)"),
    ("reports/routing",   True,  "congestion, wirelength, via       (5.4)"),
    ("reports/timing",    True,  "STAPostPNR corner raporlari       (5.5)"),
    ("reports/drc",       True,  "Magic ve KLayout DRC              (5.6)"),
    ("reports/lvs",       True,  "Netgen LVS                        (5.6)"),
    ("reports/antenna",   True,  "Anten kontrol sonuclari           (5.6)"),
    ("reports/pdn",       True,  "PDN grid-errors                   (5.6)"),
    ("reports/signoff",   True,  "manufacturability, XOR, pinler    (5.6)"),
    ("reports/power",     True,  "corner guc + irdrop.rpt           (5.7)"),
]

# Girdi tarafi - akis kosmadan da bulunmasi gerekenler (Bolum 4, Tablo 8)
ZORUNLU_GIRDI = [
    ("README.md",                    True, "Ana aciklama belgesi (Bolum 9)"),
    ("Makefile",                     True, "asic_run hedefi (Bolum 8)"),
    ("config.yaml",                  True, "LibreLane yapilandirmasi"),
    ("filelist.f",                   True, "RTL kaynak listesi"),
    ("THIRD_PARTY.md",               True, "Ucuncu taraf bilgileri (Bolum 10)"),
    ("licenses",                     True, "Ucuncu taraf lisanslari"),
    ("environment/flake.nix",        True, "Nix ortam tanimi (Bolum 1.4)"),
    ("environment/flake.lock",       True, "Bagimlilik kilidi (Bolum 1.4)"),
    ("environment/versions.txt",     True, "Surum bilgileri (Bolum 1.4)"),
    ("constraints/design.sdc",       True, "Zamanlama kisitlari (Bolum 3.2)"),
    ("macros",                       True, "Fiziksel makro dosyalari (Bolum 3.3)"),
    ("scripts",                      True, "Otomasyon betikleri"),
]

# README'de bulunmasi zorunlu basliklar (Bolum 9)
README_BASLIK = [
    "Tasarim Ozeti",
    "Arac ve Ortam Bilgileri",
    "Akisin Calistirilmasi",
    "RTL ve Akis Girdileri",
    "SRAM ve Fiziksel Makrolar",
    "Zamanlama Kisitlari ve Istisnalari",
    "Fiziksel Tasarim Yapilandirmasi",
    "Lint Sonuclari ve Istisnalari",
    "Bilinen Sorunlar ve Kabul Edilmis Istisnalar",
    "Guc ve IR-Drop Analizi",
    "Signoff Sonuc Ozeti",
    "Rapor ve Cikti Konumlari",
    "Ucuncu Taraf Bilesenler ve Lisanslar",
]


def dosya_say(bagil):
    yol = os.path.join(ASIC, bagil)
    if os.path.isfile(yol):
        return 1
    if not os.path.isdir(yol):
        return -1
    n = 0
    for kok, _, dosyalar in os.walk(yol):
        n += len([d for d in dosyalar if d != ".gitkeep"])
    return n


def bolum_denetle(baslik, liste):
    eksik_zorunlu = 0
    eksik_onerilen = 0
    print("\n%s" % baslik)
    print("-" * 72)
    for bagil, zorunlu, aciklama in liste:
        n = dosya_say(bagil)
        if n > 0:
            durum = "[OK]  "
            ek = "%d dosya" % n
        elif n == 0:
            durum = "[BOS] " if zorunlu else "[bos] "
            ek = "dizin var, ici bos"
            if zorunlu:
                eksik_zorunlu += 1
            else:
                eksik_onerilen += 1
        else:
            durum = "[YOK] " if zorunlu else "[yok] "
            ek = "dizin yok"
            if zorunlu:
                eksik_zorunlu += 1
            else:
                eksik_onerilen += 1
        print("  %s %-24s %-42s %s" % (durum, bagil, aciklama, ek))
    return eksik_zorunlu, eksik_onerilen


def readme_denetle():
    print("\nREADME BASLIKLARI  (Final Ciktilar Bolum 9)")
    print("-" * 72)
    yol = os.path.join(ASIC, "README.md")
    if not os.path.isfile(yol):
        print("  [YOK]  README.md bulunamadi")
        return len(README_BASLIK)

    # Turkce karakterleri sadelestirerek karsilastir
    cev = {ord(a): b for a, b in zip(u"ıİşŞğĞüÜöÖçÇ", u"iIsSgGuUoOcC")}
    metin = io.open(yol, encoding="utf-8").read().translate(cev).lower()

    eksik = 0
    for b in README_BASLIK:
        if b.translate(cev).lower() in metin:
            print("  [OK]   %s" % b)
        else:
            print("  [YOK]  %s" % b)
            eksik += 1
    return eksik


def main():
    print("=" * 72)
    print(" ARKHE SoC - TESLIM DENETIMI")
    print(" Referans: TEKNOFEST 2026 Cip Tasarimi, Final Istenen Ciktilar")
    print("=" * 72)

    gz, _ = bolum_denetle("AKIS GIRDILERI  (Tablo 8)", ZORUNLU_GIRDI)
    rz, _ = bolum_denetle("ZORUNLU RAPORLAR  (Bolum 5)", ZORUNLU_RAPOR)
    cz, co = bolum_denetle("CIKTILAR  (Bolum 6)", ZORUNLU_CIKTI)
    re = readme_denetle()

    # run/ teslim aninda temiz olmali (Bolum 4)
    print("\nTESLIM HAZIRLIGI")
    print("-" * 72)
    run_n = dosya_say("run")
    if run_n <= 0:
        print("  [OK]   run/ temiz")
    else:
        print("  [!]    run/ icinde %d dosya var - teslimden once"
              " 'make asic_clean' calistirin" % run_n)

    toplam = gz + rz + cz + re
    print("\n" + "=" * 72)
    print(" Eksik zorunlu girdi   : %d" % gz)
    print(" Eksik zorunlu rapor   : %d" % rz)
    print(" Eksik zorunlu cikti   : %d" % cz)
    print(" Eksik README basligi  : %d" % re)
    print(" Eksik onerilen cikti  : %d  (puan kaybi degil)" % co)
    print("=" * 72)

    if toplam == 0:
        print("[TAM] Butun zorunlu maddeler yerinde.")
        return 0
    print("[EKSIK] %d zorunlu madde tamamlanmali." % toplam)
    return 1


if __name__ == "__main__":
    sys.exit(main())
