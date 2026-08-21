#!/usr/bin/env python3
"""
Arkhe SoC - Tam regresyon kosumu

Sartname s.297: "Gerceklestirilen dogrulama calismalarinda, 'regression' ve
'coverage' sonuclarinin raporlanmasi degerlendirme puanini yukseltecektir."

Sartname s.615: Testler manuel inceleme gerektirmeden kendi kendini kontrol
etmelidir. Buradaki tum testler hata durumunda $fatal ile biter; bu betik
de sifir olmayan cikis koduyla doner.

Kullanim:
    python scripts/run_regression.py
    python scripts/run_regression.py --vivado "C:/AMDDesignTools/2025.2/Vivado/bin"

Cikis kodu: 0 = hepsi gecti, 1 = en az bir test basarisiz
"""

import argparse
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
WORK = ROOT / "build" / "regression"
RTL  = ROOT / "rtl"
TB   = ROOT / "tb"

VARSAYILAN_VIVADO = r"C:/AMDDesignTools/2025.2/Vivado/bin"

CEV = RTL / "Cevre_Birimleri"
F1  = CEV / "files_1"
MEM = RTL / "Memory"
NPU = RTL / "npu"

# -----------------------------------------------------------------------------
# Test tanimlari
#
# Her test: ad, ust modul, kaynak dosyalar, gereken .mem dosyalari
# -----------------------------------------------------------------------------
TESTLER = [
    dict(
        ad="uart",
        top="uart_tb",
        kaynak=[F1/"uart_pkg.sv", F1/"uart_tx.sv", F1/"uart_rx.sv",
                F1/"sync_fifo.sv", F1/"uart_peripheral.sv",
                F1/"uart_stream_peripheral.sv", F1/"uart_tb.sv"],
        mem=[],
    ),
    dict(
        ad="i2c",
        top="i2c_peripheral_tb",
        kaynak=[CEV/"i2c_peripheral.sv", CEV/"i2c_peripheral_tb.sv"],
        mem=[],
    ),
    dict(
        ad="qspi",
        top="tb_qspi_mock",
        kaynak=[CEV/"qspi_master.sv", TB/"spi_flash_model.sv",
                CEV/"tb_qspi_mock.sv"],
        mem=["qspi_test_pattern.hex"],
    ),
    dict(
        ad="jtag_debug",
        top="tb_jtag_debug",
        kaynak=[CEV/"jtag_debug.sv", TB/"T3.1_jtag_debug"/"tb_jtag_debug.sv"],
        mem=[],
    ),
    dict(
        ad="npu_blok",
        top="tb_npu_compute_engine",
        # npu_weights_pkg.sv modulden ONCE gelmeli - agirliklar artik
        # RTL'e gomulu, $readmemh ile dosyadan okunmuyor.
        kaynak=[NPU/"npu_weights_pkg.sv", NPU/"npu_compute_engine.sv",
                TB/"tb_npu_compute_engine.sv"],
        mem=[],
    ),
    dict(
        ad="npu_golden",
        top="tb_npu_golden",
        kaynak=[NPU/"npu_weights_pkg.sv", NPU/"npu_compute_engine.sv",
                TB/"npu_golden"/"tb_npu_golden.sv"],
        # Agirliklar gomulu; test_input_pattern.mem testin GIRDISIDIR,
        # agirlik degildir - kopyalanmaya devam ediyor.
        mem=["test_input_pattern.mem"],
    ),
    # -------------------------------------------------------------------------
    # TAM SISTEM TESTI
    #
    # 21 Agustos 2026'da fark edildi: regresyon YALNIZCA blok testlerini
    # kapsiyordu, tb_soc_top hic kosmuyordu. Yani bootloader'in calistigi,
    # QSPI -> I-RAM aktariminin dogrulugu ve uctan uca akis regresyonla
    # dogrulanmiyordu. Blok testleri gectigi icin "dogrulandi" saniliyordu.
    #
    # Kaynak listesi asic/filelist.f'ten okunur (bkz. filelist_rtl).
    # -------------------------------------------------------------------------
    dict(
        ad="sistem",
        top="tb_soc_top",
        kaynak=None,                      # filelist_rtl() ile doldurulur
        ek_kaynak=[TB/"spi_flash_model.sv", TB/"tb_soc_top.sv"],
        mem=["app.hex", "boot.hex"],
        mem_zorunlu=False,                # bulunamazsa test atlanir, cokmez
    ),
]

MEM_KAYNAKLARI = [
    TB,
    ROOT/"vivado"/"vivado_nexys_project"/"Arkhe_SoC_Nexys.ip_user_files"/"mem_init_files",
    TB/"npu_golden",
    NPU,
]


def mem_bul(ad):
    for d in MEM_KAYNAKLARI:
        p = d / ad
        if p.is_file():
            return p
    return None


def komut(args, cwd, log_yolu):
    """Komutu calistir, ciktiyi loga yaz, (rc, cikti) dondur."""
    with open(log_yolu, "w", encoding="utf-8", errors="replace") as fh:
        p = subprocess.run(args, cwd=str(cwd), stdout=subprocess.PIPE,
                           stderr=subprocess.STDOUT, text=True,
                           encoding="utf-8", errors="replace")
        fh.write(p.stdout or "")
    return p.returncode, (p.stdout or "")


# -----------------------------------------------------------------------------
# Tam sistem testi icin RTL listesi
#
# TEK DOGRULUK KAYNAGI asic/filelist.f'tir. Listeyi elle tekrarlamak yerine
# oradan okuyoruz; boylece ASIC akisi ile regresyon AYNI kaynaklari kullanir
# ve biri degisince digeri geride kalmaz.
#
# filelist.f yollari asic/ dizinine goredir (../rtl/...), burada cozuluyor.
# -----------------------------------------------------------------------------
def filelist_rtl():
    fl = ROOT / "asic" / "filelist.f"
    if not fl.is_file():
        return None
    kaynaklar = []
    for satir in fl.read_text(encoding="utf-8", errors="replace").splitlines():
        satir = satir.split("//")[0].split("#")[0].strip()
        if not satir or satir.startswith("+") or satir.startswith("-"):
            continue
        yol = (ROOT / "asic" / satir).resolve()
        if yol.is_file():
            kaynaklar.append(yol)
    return kaynaklar or None


def test_kos(t, vivado_bin):
    # Kaynak listesi gec baglanan testler (tam sistem) icin
    if t.get("kaynak") is None:
        rtl = filelist_rtl()
        if rtl is None:
            return dict(ad=t["ad"], durum="ATLANDI", denetim=0,
                        not_="asic/filelist.f okunamadi")
        t = dict(t, kaynak=rtl + list(t.get("ek_kaynak", [])))

    d = WORK / t["ad"]
    if d.exists():
        shutil.rmtree(d, ignore_errors=True)
    d.mkdir(parents=True, exist_ok=True)

    for m in t["mem"]:
        kaynak = mem_bul(m)
        if kaynak is None:
            if not t.get("mem_zorunlu", True):
                continue
            return dict(ad=t["ad"], durum="ATLANDI", denetim=0,
                        not_=f"{m} bulunamadi")
        shutil.copy2(kaynak, d / m)

    xvlog = str(Path(vivado_bin) / "xvlog.bat")
    xelab = str(Path(vivado_bin) / "xelab.bat")
    xsim  = str(Path(vivado_bin) / "xsim.bat")

    rc, out = komut([xvlog, "-sv"] + [str(k) for k in t["kaynak"]] +
                    ["-log", "vlog.log"], d, d / "vlog.log")
    if rc != 0:
        return dict(ad=t["ad"], durum="DERLEME HATASI", denetim=0,
                    not_=ilk_hata(out))

    rc, out = komut([xelab, "-debug", "typical", "-timescale", "1ns/1ps",
                     t["top"], "-s", "snap", "-log", "elab.log"],
                    d, d / "elab.log")
    if rc != 0:
        return dict(ad=t["ad"], durum="ELAB HATASI", denetim=0,
                    not_=ilk_hata(out))

    (d / "run.tcl").write_text("run all\nquit\n", encoding="ascii")

    t0 = time.time()
    # xsim'in kendi logu ayri dosyaya; stdout'u sim.log'a aliyoruz.
    # Ikisi ayni dosya olursa her satir IKI KEZ yazilir ve denetim sayilari
    # iki katina cikar - ilk surumde tam olarak bu oldu.
    rc, out = komut([xsim, "snap", "-tclbatch", "run.tcl", "-log", "xsim.log"],
                    d, d / "sim.log")
    sure = time.time() - t0

    metin = (d / "sim.log").read_text(encoding="utf-8", errors="replace")

    # $fatal cagrildi mi?
    fatal = ("Fatal:" in metin) or ("FATAL_ERROR" in metin)

    ok   = len(re.findall(r"\[OK\]|\[PASS\]", metin))
    hata = len(re.findall(r"\[HATA\]|\[FAIL\]", metin))

    # npu_golden farkli bicim kullaniyor: satir basinda "PASS:" / "FAIL:"
    ok   += len(re.findall(r"^PASS:", metin, re.M))
    hata += len(re.findall(r"^FAIL:", metin, re.M))

    if fatal or hata > 0:
        durum = "BASARISIZ"
    elif ok == 0:
        durum = "DENETIM YOK"
    else:
        durum = "GECTI"

    return dict(ad=t["ad"], durum=durum, denetim=ok, hata=hata,
                sure=sure, not_="")


def ilk_hata(cikti):
    for satir in (cikti or "").splitlines():
        if satir.startswith("ERROR"):
            return satir.strip()[:110]
    return "bilinmeyen hata"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--vivado", default=os.environ.get("VIVADO_BIN", VARSAYILAN_VIVADO),
                    help="Vivado bin dizini")
    a = ap.parse_args()

    if not Path(a.vivado, "xvlog.bat").is_file():
        print(f"HATA: Vivado araclari bulunamadi: {a.vivado}")
        print("      --vivado ile yol verin veya VIVADO_BIN ortam degiskenini ayarlayin.")
        return 2

    WORK.mkdir(parents=True, exist_ok=True)
    print("=" * 70)
    print(" ARKHE SoC - BLOK SEVIYESI REGRESYON")
    print("=" * 70)

    sonuclar = []
    for t in TESTLER:
        print(f"  {t['ad']:<12} calisiyor...", end="", flush=True)
        s = test_kos(t, a.vivado)
        sonuclar.append(s)
        if s["durum"] == "GECTI":
            print(f"\r  {t['ad']:<12} GECTI    {s['denetim']:>3} denetim  "
                  f"{s.get('sure',0):5.1f} s")
        else:
            print(f"\r  {t['ad']:<12} {s['durum']}  {s.get('not_','')}")

    print("=" * 70)
    gecen  = sum(1 for s in sonuclar if s["durum"] == "GECTI")
    toplam_denetim = sum(s["denetim"] for s in sonuclar)
    kalan  = [s for s in sonuclar if s["durum"] != "GECTI"]

    print(f" {gecen}/{len(sonuclar)} test gecti, toplam {toplam_denetim} denetim")
    if kalan:
        print(" BASARISIZ:")
        for s in kalan:
            print(f"   - {s['ad']}: {s['durum']} {s.get('not_','')}")
    print("=" * 70)

    return 1 if kalan else 0


if __name__ == "__main__":
    sys.exit(main())
