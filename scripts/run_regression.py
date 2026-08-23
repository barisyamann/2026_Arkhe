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
    # -------------------------------------------------------------------------
    # GPIO BLOK TESTI
    #
    # 22 Agustos 2026'da eklendi. GPIO'nun HIC blok testi yoktu; sistem testi
    # yalnizca cikis yazmacini kullaniyordu. Kesme mekanizmasinin dort modu -
    # yukselen kenar, dusen kenar, seviye-yuksek, seviye-dusuk - hicbir testte
    # calismamisti.
    # -------------------------------------------------------------------------
    # -------------------------------------------------------------------------
    # DMA BLOK TESTI
    #
    # 22 Agustos 2026'da eklendi. DMA'nin HIC blok testi yoktu; yalnizca
    # sistem testinde dolayli calisiyordu (%41,1 statement).
    #
    # EN ONEMLI KISIM: testbench'teki bellek modeli AW ve W'yi KASITLI
    # OLARAK farkli cevrimlerde kabul eder. Bu, veriyolu incelemesindeki
    # bulgu V1'in duzeltmesini dogrular. Duzeltme geri alinip kosuldugunda
    # test 20 hatayla duser ve AW islem sayisi 8 yerine 1 cikar.
    # -------------------------------------------------------------------------
    dict(
        ad="dma",
        top="tb_dma_controller",
        kaynak=[CEV/"dma_controller.sv", TB/"dma"/"tb_dma_controller.sv"],
        mem=[],
    ),
    dict(
        ad="gpio",
        top="tb_gpio_peripheral",
        kaynak=[CEV/"gpio_peripheral.sv", TB/"gpio"/"tb_gpio_peripheral.sv"],
        mem=[],
    ),
    dict(
        ad="qspi",
        top="tb_qspi_mock",
        kaynak=[CEV/"qspi_master.sv", TB/"spi_flash_model.sv",
                CEV/"tb_qspi_mock.sv"],
        mem=["qspi_test_pattern.hex"],
    ),
    # -------------------------------------------------------------------------
    # TIMER BLOK TESTI
    #
    # 22 Agustos 2026 dogrulama denetiminde cikti: Timer, 23 RTL modulu
    # icinde HICBIR denetimi olmayan tek moduldu. Sistem testi onu hic
    # kullanmiyor, npu_hizlanma yalnizca ALET olarak kullaniyordu.
    #
    # Sartname EK-2'nin sekiz yazmacini da kapsar: prescaler orani, yukari
    # ve asagi sayma, auto-reload, event uretimi, kesme, TIM_CLR davranisi
    # ve salt-okunur yazmaclarin yazmaya direnci.
    # -------------------------------------------------------------------------
    dict(
        ad="timer",
        top="tb_timer_peripheral",
        kaynak=[CEV/"timer_peripheral.sv", TB/"timer"/"tb_timer_peripheral.sv"],
        mem=[],
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
        mem=["fc_weights_packed32.mem"],
    ),
    dict(
        ad="npu_golden",
        top="tb_npu_golden",
        kaynak=[NPU/"npu_weights_pkg.sv", NPU/"npu_compute_engine.sv",
                TB/"npu_golden"/"tb_npu_golden.sv"],
        # Agirliklar gomulu; test_input_pattern.mem testin GIRDISIDIR,
        # agirlik degildir - kopyalanmaya devam ediyor.
        mem=["test_input_pattern.mem", "fc_weights_packed32.mem"],
    ),
    # -------------------------------------------------------------------------
    # NPU COK-VEKTORLU DOGRULUK TESTI
    #
    # Sartname EK-1 hizlandiricinin yazilim modeliyle %10 pencerede uyumlu
    # olmasini ister. npu_golden TEK vektor kosuyordu ve yalnizca NO sinifini
    # uyariyordu; SILENCE / UNKNOWN / YES dallari hic calismiyordu.
    #
    # Bu test dort sinifi da kapsayan vektorlerle kosar ve RTL ciktisini
    # yazilim referans modeliyle BIREBIR karsilastirir.
    #
    # Vektorler uretilmistir: python tb/npu_audio/gen_vectors.py
    # -------------------------------------------------------------------------
    dict(
        ad="npu_dogruluk",
        top="tb_npu_audio",
        kaynak=[NPU/"npu_weights_pkg.sv", NPU/"npu_compute_engine.sv",
                TB/"npu_audio"/"tb_npu_audio.sv"],
        mem=["vectors.mem", "fc_weights_packed32.mem"],
    ),
    # -------------------------------------------------------------------------
    # YAZILIM / DONANIM HIZLANMA OLCUMU
    #
    # Sartname EK-1: "YZ hizlandiricisi ... RISC-V cekirdegi uzerinde calisan
    # yazilim gerceklemesine kiyasla HIZLANMA elde etmelidir."
    # Bolum 4.2.2.1: performans "veri/saat dongusu bazinda" olculmelidir.
    #
    # CPU, ayni modeli C ile kosar (agirliklar TCM'de - 16 kB FC agirligi
    # 8 kB D-RAM'e sigmaz). Test, yazilimin donanimdan en az 100x yavas
    # oldugunu dogrular. Kesin oran icin: python tb/npu_sw_bench/analiz.py
    # -------------------------------------------------------------------------
    dict(
        ad="npu_hizlanma",
        top="tb_npu_sw_bench",
        kaynak=None,
        ek_kaynak=[TB/"npu_sw_bench"/"tb_npu_sw_bench.sv"],
        tanim=["BENCH_N50"],
        mem=["tcm_image.mem", "bench_50.hex"],
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
        # axil_protocol_checker asic/filelist.f'te YOKTUR - yalnizca SVA
        # denetleyicisidir, sentezlenmez. tb_soc_top onu bind ile
        # bagliyor, bu yuzden simulasyon kaynagi olarak eklenmeli.
        ek_kaynak=[MEM/"axil_protocol_checker.sv",
                   TB/"spi_flash_model.sv", TB/"tb_soc_top.sv"],
        mem=["app.hex", "boot.hex", "flash.hex", "fc_weights_packed32.mem"],
        mem_zorunlu=False,                # bulunamazsa test atlanir, cokmez
    ),
    # -------------------------------------------------------------------------
    # GERCEK IKI ASAMALI BOOT TESTI
    #
    # Sartname Bolum 5.2 (odul icin asgari basari kriteri):
    #   "En azindan bir adet self-checking test ile BOOT AKISI, bir cevre
    #    birimi programlamasi ve cevre birimi calismasinin dogrulanmasi."
    #
    # Yukaridaki 'sistem' testi HIZLI ACILIS kullanir: I-RAM dogrudan
    # doldurulur ve cekirdegin boot_addr_i girisi zorlanir. Yani yukleyici,
    # QSPI okumasi ve shadowing zinciri HIC KOSMUYOR. Blok testleri gectigi
    # icin "boot dogrulandi" saniliyordu.
    #
    # Bu test -d REAL_BOOT ile gercek zinciri kosar:
    #   Boot ROM -> QSPI Master -> flash -> I-RAM -> jalr -> uygulama
    # -------------------------------------------------------------------------
    dict(
        ad="sistem_gercek_boot",
        top="tb_soc_top",
        kaynak=None,
        ek_kaynak=[MEM/"axil_protocol_checker.sv",
                   TB/"spi_flash_model.sv", TB/"tb_soc_top.sv"],
        tanim=["REAL_BOOT"],
        mem=["app.hex", "boot.hex", "flash.hex", "fc_weights_packed32.mem"],
        mem_zorunlu=False,
    ),
]

MEM_KAYNAKLARI = [
    ROOT/"weights",
    ROOT/"sw_nexys"/"build",
    TB,
    ROOT/"vivado"/"vivado_nexys_project"/"Arkhe_SoC_Nexys.ip_user_files"/"mem_init_files",
    TB/"npu_golden",
    TB/"npu_audio",
    TB/"npu_sw_bench",
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


def test_kos(t, vivado_bin, kapsam=False):
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

    tanim_arg = []
    for tn in t.get("tanim", []):
        tanim_arg += ["-d", tn]

    rc, out = komut([xvlog, "-sv"] + tanim_arg + [str(k) for k in t["kaynak"]] +
                    ["-log", "vlog.log"], d, d / "vlog.log")
    if rc != 0:
        return dict(ad=t["ad"], durum="DERLEME HATASI", denetim=0,
                    not_=ilk_hata(out))

    # ---------------------------------------------------------------------
    # KOD KAPSAMA (Sartname EK-3)
    #
    #   "Code Coverage ... Opsiyonel***" ve
    #   "***Opsiyonel: Dogrulama aktivitelerinden TAM PUAN alimini
    #    saglayacak unsurlar."
    #
    # sbct = (s)tatement (b)ranch (c)ondition (t)oggle
    # Her testin veritabani ayri isimle yazilir; sonunda xcrg ile
    # birlestirilip tek rapor uretilir.
    # ---------------------------------------------------------------------
    kapsam_arg = []
    if kapsam:
        # Yol POSIX bicimde verilmeli. Windows'ta str(Path) ters bolu
        # uretir ve xelab uretilen C dosyasini derleyemez:
        #     ERROR: [XSIM 43-3409] Failed to compile generated C file
        # Bayraklarin kendisi sorunsuz; yalnizca ayrac sorunuydu.
        kapsam_arg = ["--cc_type", "sbct",
                      "--cov_db_dir", (WORK / "covdb").as_posix(),
                      "--cov_db_name", t["ad"]]

    rc, out = komut([xelab, "-debug", "typical", "-timescale", "1ns/1ps"] +
                    kapsam_arg +
                    [t["top"], "-s", "snap", "-log", "elab.log"],
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


def _kapsam_ozet(rapor_dizini):
    """xcrg dashboard.html icinden ozet skorlari cikarir."""
    dash = Path(rapor_dizini) / "codeCoverageReport" / "dashboard.html"
    if not dash.is_file():
        return None
    metin = dash.read_text(encoding="utf-8", errors="replace")
    duz = re.sub(r"<[^>]+>", " ", metin)
    duz = re.sub(r"\s+", " ", duz)
    m = re.search(r"Total Files Total Modules Total Instances "
                  r"Statement Coverage Score Branch Coverage Score "
                  r"Condition Coverage Score Toggle Coverage Score "
                  r"([\d.]+) ([\d.]+) ([\d.]+) "
                  r"([\d.]+) ([\d.]+) ([\d.]+) ([\d.]+)", duz)
    if not m:
        return None
    g = m.groups()
    return dict(dosya=int(float(g[0])), modul=int(float(g[1])),
                ornek=int(float(g[2])),
                statement=float(g[3]), branch=float(g[4]),
                condition=float(g[5]), toggle=float(g[6]),
                dashboard=dash)


def _xcrg(vivado_bin, args, log_adi):
    xcrg = str(Path(vivado_bin) / "xcrg.bat")
    rc, _ = komut([xcrg] + args + ["-log", (WORK / log_adi).as_posix()],
                  WORK, WORK / (log_adi + ".stdout"))
    return rc


def kapsam_raporu(vivado_bin):
    """Kod kapsama raporlarini uretir.

    IKI AYRI RAPOR uretilir, cunku xcrg ayni modulun FARKLI PARAMETRELERLE
    elaborate edilmis surumlerini birlestiremiyor:

        CCI-MERGE10 : ... as toggle coverage info are different
        CCI-MERGE2  : Cannot merge module i2c_peripheral(SYS_CLK_FREQ=50000000)

    Blok testleri modulleri kendi test kosullarinda, sistem testi ise SoC
    icindeki gercek parametrelerle elaborate ediyor. Zorla birlestirmek
    sistem seviyesi modullerin RAPORDAN DUSMESINE yol aciyordu - ilk
    kosumda soc_top, interconnect ve arbiter'lar hic gorunmedi.

      evidence/coverage         blok testlerinin birlesigi
      evidence/coverage_sistem  tam SoC (sistem_gercek_boot kosumu)

    Sartname EK-3, Code Coverage'i "Opsiyonel***" isaretler; dipnot
    "***Opsiyonel: Dogrulama aktivitelerinden TAM PUAN alimini saglayacak
    unsurlar" der.
    """
    covdb = WORK / "covdb"
    if not covdb.is_dir():
        print(" Kapsama veritabani bulunamadi - kapsama atlandi.")
        return None

    sonuc = {}

    # --- 1) Blok testlerinin birlesigi ---
    blok = ROOT / "evidence" / "coverage"
    shutil.rmtree(blok, ignore_errors=True)
    blok.mkdir(parents=True, exist_ok=True)
    _xcrg(vivado_bin, ["-cov_db_dir", covdb.as_posix(),
                       "-merge_dir", covdb.as_posix(),
                       "-merge_db_name", "birlesik",
                       "-report_dir", blok.as_posix(),
                       "-report_format", "html"], "xcrg_blok.log")
    o = _kapsam_ozet(blok)
    if o:
        sonuc["Blok testleri (birlesik)"] = o

    # --- 2) Tam SoC: sistem testi tek basina ---
    sis_db = covdb / "xsim.codeCov" / "sistem_gercek_boot"
    if sis_db.is_dir():
        sis = ROOT / "evidence" / "coverage_sistem"
        shutil.rmtree(sis, ignore_errors=True)
        sis.mkdir(parents=True, exist_ok=True)
        _xcrg(vivado_bin, ["-cov_db_dir", covdb.as_posix(),
                           "-cov_db_name", "sistem_gercek_boot",
                           "-report_dir", sis.as_posix(),
                           "-report_format", "html"], "xcrg_sistem.log")
        o = _kapsam_ozet(sis)
        if o:
            sonuc["Tam SoC (sistem_gercek_boot)"] = o

    return sonuc or None


def ilk_hata(cikti):
    for satir in (cikti or "").splitlines():
        if satir.startswith("ERROR"):
            return satir.strip()[:110]
    return "bilinmeyen hata"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--vivado", default=os.environ.get("VIVADO_BIN", VARSAYILAN_VIVADO),
                    help="Vivado bin dizini")
    ap.add_argument("--coverage", action="store_true",
                    help="Kod kapsama (statement/branch/condition/toggle) topla")
    a = ap.parse_args()

    if a.coverage:
        shutil.rmtree(WORK / "covdb", ignore_errors=True)

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
        s = test_kos(t, a.vivado, a.coverage)
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

    if a.coverage:
        print(" Kapsama raporlari uretiliyor...")
        k = kapsam_raporu(a.vivado)
        if k:
            print("=" * 70)
            print(" KOD KAPSAMA")
            for ad, o in k.items():
                print("")
                print(f" {ad}")
                print(f"   {o['dosya']} dosya, {o['modul']} modul, {o['ornek']} ornek")
                print(f"   Statement %{o['statement']:.2f}   Branch    %{o['branch']:.2f}")
                print(f"   Condition %{o['condition']:.2f}   Toggle    %{o['toggle']:.2f}")
                print(f"   {o['dashboard']}")
            print("=" * 70)
        else:
            print(" Kapsama raporu uretilemedi - build/regression/xcrg_*.log")

    return 1 if kalan else 0


if __name__ == "__main__":
    sys.exit(main())
