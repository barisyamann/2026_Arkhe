#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Testlerin GERCEKTEN hata yakaladigini kanitlar (mutasyon testi).

NEDEN VAR
  Regresyonda 28/28 test geciyor. Ama bu tek basina "testler iyi"
  demek DEGILDIR - hicbir sey denetlemeyen bir test de gecer.

  Tek kanit yolu: RTL'e KASITLI hata sokup ilgili testin KIRMIZIYA
  dondugunu gostermek. Donmuyorsa o test o hatayi yakalamiyor demektir
  ve dekoratiftir.

  Sartname EK-3 testlerin "kendi kendini kontrol eden" olmasini
  istiyor. Bu betik o iddiayi OLCER.

NASIL CALISIR
  1. Hedef RTL dosyasini yedekler
  2. Tek satirlik bir mutasyon uygular (gercekci bir hata)
  3. Ilgili testi kosar
  4. Test KALDIYSA  -> [OK]   test bu hatayi yakaliyor
     Test GECTIYSE  -> [HATA] test bu hatayi KACIRIYOR
  5. Dosyayi HER DURUMDA geri yukler

GUVENLIK
  Her mutasyon try/finally icinde; kesinti olsa bile dosya geri
  yuklenir. Calistiktan sonra rtl_manifest ile dogrulanmalidir.

KULLANIM
  python scripts/hata_enjeksiyon.py
  python scripts/hata_enjeksiyon.py --liste
  python scripts/hata_enjeksiyon.py --sadece wstrb_bit
"""
import argparse
import io
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

KOK = Path(__file__).resolve().parents[1]

# -----------------------------------------------------------------------
#  MUTASYONLAR
#
#  Her kayit GERCEKCI bir hatayi temsil eder - yani gercekten yapilmis
#  veya yapilabilecek bir yanlis. Rastgele karakter degisimi degil.
# -----------------------------------------------------------------------
MUTASYONLAR = [
    dict(
        ad="wstrb_bit",
        aciklama="WSTRB bit 1 YANLIS dilime baglaniyor ([15:8] yerine [7:0])",
        dosya="rtl/Memory/sram_module.sv",
        eski="                if (w_strb_reg[1]) ram[waddr][15:8]  <= w_data_reg[15:8];",
        yeni="                if (w_strb_reg[1]) ram[waddr][7:0]   <= w_data_reg[7:0];",
        test="wstrb_kismi_yazma",
        neden="12 Eylul 2026'da yazilan kismi yazma testinin gercekten "
              "bayt eslemesini denetledigini kanitlar.",
    ),
    dict(
        ad="sram_w_yakalama",
        aciklama="W verisi el sikismada YAKALANMIYOR (canli sinyal kullaniliyor)",
        dosya="rtl/Memory/sram_module.sv",
        eski="                w_data_reg    <= s_axil_wdata;   // el sikismasinda YAKALA",
        yeni="                w_data_reg    <= 32'h0;          // MUTASYON",
        test="sram_w_yakalama",
        neden="10 Eylul 2026'da duzeltilen GERCEK hatanin testi. "
              "Bu mutasyon o hatayi geri getirir.",
    ),
    dict(
        ad="qspi_presc_bit",
        aciklama="QSPI prescaler 7 bit yerine 6 bit (presc=63'te sarma)",
        dosya="rtl/Cevre_Birimleri/qspi_master.sv",
        eski="logic [6:0]  sck_tam_periyot;",
        yeni="logic [5:0]  sck_tam_periyot;   // MUTASYON",
        test="qspi_sck_olcum",
        neden="10 Eylul 2026'da duzeltilen 6->7 bit hatasi. Ilk kosumda "
              "tb_qspi_presc_sinir KACIRMISTI (DUT ornekleMIYOR); "
              "12 Eylul'de gercek DUT'u olcen tb_qspi_sck_olcum yazildi.",
    ),
    dict(
        ad="i2c_bolen",
        aciklama="I2C bolen 1 eksik (SCL frekansi kayar)",
        dosya="rtl/Cevre_Birimleri/i2c_peripheral.sv",
        eski="    localparam int PERIYOT     = SYS_CLK_FREQ / I2C_FREQ;        // 125 @ 50 MHz",
        yeni="    localparam int PERIYOT     = SYS_CLK_FREQ / I2C_FREQ - 1;    // MUTASYON",
        test="i2c_scl_periyot",
        neden="Ilk kosumda i2c blok testi KACIRMISTI - yazmac/ACK akisini "
              "dogruluyor ama SCL FREKANSINI olcmuyordu. 12 Eylul'de "
              "uretilen dalgayi olcen tb_i2c_scl_periyot yazildi.",
    ),
    dict(
        ad="i2c_saat_germe",
        aciklama="I2C saat germe devre disi (slave SCL'i tutsa master farketmez)",
        dosya="rtl/Cevre_Birimleri/i2c_peripheral.sv",
        eski="""    assign germe_dur = i2c_active && !scl_oe &&
                       (birakma_yasi == 2'd2) && !scl_hat;""",
        yeni="    assign germe_dur = 1'b0;  // MUTASYON",
        test="i2c_saat_germe",
        neden="Bu mutasyon testin ILK yazimini da yakaladi. Test once `scl` "
              "TELINI olcuyordu ve germe kapaliyken bile 1240->6240 ns uzama "
              "gorup GECIYORDU - cunku teli 5 us boyunca testbench'in kendisi "
              "cekiyordu, totolojik olcum. Test DUT'un IC ceyrek sayacini "
              "surekli izleyecek sekilde duzeltildi: duzeltilmis RTL'de 0 "
              "hareket, mutasyonlu RTL'de 248/250 hareket olculuyor.",
    ),
    dict(
        ad="jtag_yanit_kodu",
        aciklama="JTAG AXI yanit kodu denetimi kapali (DECERR gecerli sanilir)",
        dosya="rtl/Cevre_Birimleri/jtag_debug.sv",
        eski="bus_hata         <= (m_axi_rresp != 2'b00);",
        yeni="bus_hata         <= 1'b0;  // MUTASYON",
        test="jtag_yanit_kodu",
        neden="m_axi_rresp/bresp 12 Eylul'e kadar HIC okunmuyordu. JTAG "
              "interconnect uzerinden tum slave'lere eristigi icin tanimsiz "
              "adres DECERR + 0xDEADBEEF dondurur ve bu cop veri GECERLI "
              "sanilirdi. Mutasyonda test 9 -> 7 denetime duser ve KALIR.",
    ),
    dict(
        ad="sram_rdata_bit",
        aciklama="SRAM okuma verisi bit0 sifirlanir (kayitli okuma yolu bozulur)",
        dosya="rtl/Memory/sram_module.sv",
        eski="    assign s_axil_rdata = ram_rdata;",
        yeni="    assign s_axil_rdata = {ram_rdata[31:1], 1'b0};  // MUTASYON",
        test="sram_registered",
        neden="tb_sram_registered.sv 13 Eylul 2026'ya kadar YAZILMIS ama "
              "regresyonda KAYITLI DEGILDI - her kosumda atlaniyordu. "
              "sram_module teslim edilen tasarimin parcasidir (filelist.f "
              "satir 23; soc_top ve npu_tcm_sram kullanir). Regresyona "
              "eklendi ve bu mutasyonla hata yakaladigi kanitlandi.",
    ),
    dict(
        ad="npu_hakem_motor_dali",
        aciklama="NPU hakemi motor dalini yok sayar (TCM yazma yolu CPU'ya sabitlenir)",
        dosya="rtl/npu/npu_accelerator.sv",
        eski="    assign tcm_we_a    = eng_wr_req ? axi_ram_we_a    : ram_we_a;",
        yeni="    assign tcm_we_a    = ram_we_a;  // MUTASYON",
        test="npu_accelerator",
        neden="A1 (13 Eylul 2026): Kapsam analizi npu_accelerator'un "
              "hakemlik mantiginda MOTOR dalinin hicbir testte "
              "uyarilmadigini gostermisti - eng_wr_req hic 1 olmuyordu. "
              "Test NPU'yu CSR'dan baslatip (weights_ready + start) tam "
              "cikarim kosturur; motor sonucu TCM'e yazarken hakem "
              "gozlemlenir. ILK denemede sayaclar dal secimini olcuyordu "
              "ve bu mutasyonu KACIRDI; gozlemciye VERI YOLU denetimi "
              "eklendi (tcm_* sinyalleri dogru kaynagi tasiyor mu). "
              "Artik mutasyon 4 cevrimde yakalaniyor.",
    ),
    dict(
        ad="interconnect_sinir",
        aciklama="Timer bolgesinin UST siniri bir eksik (0x40010FFF -> 0x40010FFE)",
        dosya="rtl/Memory/axi_lite_interconnect.sv",
        eski="        if (addr >= 32'h4001_0000 && addr <= 32'h4001_0FFF) return 4;  // Timer",
        yeni="        if (addr >= 32'h4001_0000 && addr <= 32'h4001_0FFE) return 4;  // MUTASYON",
        test="interconnect_adres",
        neden="Interconnect 616 satirla en buyuk test edilmemis moduldu. "
              "Sinir adresi hatasi sistem testinde gorunmezdi cunku sistem "
              "testi yalnizca fiilen kullanilan adresleri dokunur.",
    ),
]


def testi_kos(ad, py):
    """Tek testi kosar; (gecti_mi, ozet) dondurur."""
    komut = [py, str(KOK / "scripts" / "run_regression.py"), "--test", ad]
    p = subprocess.run(komut, cwd=str(KOK), capture_output=True, text=True,
                       timeout=1800)
    cikti = p.stdout + p.stderr
    gecti = "1/1 test gecti" in cikti
    ozet = ""
    for satir in cikti.splitlines():
        if ad in satir and ("GECTI" in satir or "BASARISIZ" in satir
                            or "DENETIM YOK" in satir or "KALDI" in satir):
            ozet = satir.strip()
            break
    return gecti, ozet


def mutasyon_uygula(m):
    """Mutasyonu uygular; yedek dosya yolunu dondurur."""
    hedef = KOK / m["dosya"]
    icerik = io.open(hedef, encoding="utf-8").read()
    if m["eski"] not in icerik:
        return None, "hedef satir bulunamadi"
    yedek = Path(tempfile.gettempdir()) / (hedef.name + ".hata_enjeksiyon_yedek")
    shutil.copy2(hedef, yedek)
    io.open(hedef, "w", encoding="utf-8", newline="\n").write(
        icerik.replace(m["eski"], m["yeni"], 1))
    return yedek, None


def geri_yukle(m, yedek):
    if yedek and yedek.is_file():
        shutil.copy2(yedek, KOK / m["dosya"])
        yedek.unlink()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--liste", action="store_true", help="mutasyonlari listele")
    ap.add_argument("--sadece", help="yalniz bu mutasyonu kos")
    ap.add_argument("--python", default=sys.executable)
    a = ap.parse_args()

    if a.liste:
        for m in MUTASYONLAR:
            print("%-18s %s" % (m["ad"], m["aciklama"]))
            print("%-18s test: %s" % ("", m["test"]))
        return 0

    secili = [m for m in MUTASYONLAR
              if not a.sadece or m["ad"] == a.sadece]
    if not secili:
        sys.exit("bilinmeyen mutasyon: %s" % a.sadece)

    print("=" * 70)
    print(" HATA ENJEKSIYONU - testler gercekten hata yakaliyor mu?")
    print("=" * 70)
    print()

    yakalanan = 0
    kacirilan = 0
    atlanan = 0

    for m in secili:
        print("-" * 70)
        print("MUTASYON : %s" % m["ad"])
        print("  hata   : %s" % m["aciklama"])
        print("  dosya  : %s" % m["dosya"])
        print("  test   : %s" % m["test"])
        print("  neden  : %s" % m["neden"])

        yedek, hata = mutasyon_uygula(m)
        if hata:
            print("  SONUC  : ATLANDI (%s)" % hata)
            atlanan += 1
            continue

        try:
            gecti, ozet = testi_kos(m["test"], a.python)
            print("  cikti  : %s" % (ozet or "(ozet yok)"))
            if gecti:
                print("  SONUC  : [HATA] test bu hatayi KACIRDI")
                kacirilan += 1
            else:
                print("  SONUC  : [OK] test hatayi YAKALADI")
                yakalanan += 1
        finally:
            geri_yukle(m, yedek)
            print("  (RTL geri yuklendi)")
        print()

    print("=" * 70)
    print(" OZET")
    print("=" * 70)
    print("  yakalanan : %d" % yakalanan)
    print("  KACIRILAN : %d" % kacirilan)
    print("  atlanan   : %d" % atlanan)
    print()
    if kacirilan:
        print("  UYARI: %d mutasyon yakalanmadi. Ilgili testler o hatayi" % kacirilan)
        print("         denetlemiyor demektir.")
    else:
        print("  Tum mutasyonlar yakalandi - testler ilgili hatalari")
        print("  gercekten denetliyor.")
    print()
    print("  DIKKAT: Bu betik RTL'i gecici olarak degistirir ve geri yukler.")
    print("  Kosumdan sonra dogrulayin:")
    print("    python scripts/rtl_manifest.py dogrula rtl_manifest.txt")
    return 1 if kacirilan else 0


if __name__ == "__main__":
    sys.exit(main())
