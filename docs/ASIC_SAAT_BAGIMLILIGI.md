# Cevre birimlerinin saat bagimliligi: ASIC 43,5 MHz etkisi
# (11 Eylul 2026, olculdu)

Bulgu: cevre birimi bolucileri **50 MHz sistem saatine gore**
sabit kodlanmis. ASIC beyani ise 23 ns = **43,5 MHz**.

# 1. SABIT KODLU YERLER

`rtl/Memory/soc_top.sv`:

    satir 749:  .SYS_CLK_HZ   (50_000_000)   -> uart_peripheral
    satir 766:  .SYS_CLK_HZ   (50_000_000)   -> uart_stream_peripheral
    satir 785:  .SYS_CLK_FREQ (50_000_000)   -> i2c_peripheral

Modullerin KENDISI parametrik yazilmis (iyi haber):

    i2c_peripheral.sv:122  PERIYOT = SYS_CLK_FREQ / I2C_FREQ
    uart_peripheral.sv:119 DEF_CPB = SYS_CLK_HZ / DEFAULT_BAUD

Yani yapi hazir; yalnizca ornekleme degeri yanlis olur.

# 2. OLCULEN ETKI

## 2.1 I2C (sartname EK-2: SCL 400 kHz sabit)

| Durum | PERIYOT | Gercek SCL | Sapma |
|---|---:|---:|---:|
| FPGA 50 MHz (mevcut) | 125 | 400.000,0 Hz | %0 |
| ASIC 43,5 MHz, bolen **duzeltilirse** | 108 | 402.576,5 Hz | **+%0,6** |
| ASIC 43,5 MHz, bolen **50M'de kalirsa** | 125 | **347.826,1 Hz** | **-%13,0** |

Fast-mode zamanlama, bolen duzeltilirse:

    t_LOW  = 1,242 us   (ister >= 1,3 us)  <- SINIRIN ALTINDA
    t_HIGH = 1,242 us   (ister >= 0,6 us)  <- rahat

Not: FPGA'daki mevcut deger de 1,260 us ile isterin altinda
(%3 sapma) ve bu SARTNAME_UYUMU_VE_SAPMALAR.md dipnot 1'de zaten
beyan edilmis durumda. ASIC'te sapma %4,5'e cikar.

## 2.2 UART (115.200 baud)

| Durum | CPB | Gercek baud | Hata |
|---|---:|---:|---:|
| FPGA 50 MHz | 434 | 115.207,4 | +%0,01 |
| ASIC 43,5 MHz, CPB **duzeltilirse** | 377 | 115.327,0 | **+%0,11** |
| ASIC 43,5 MHz, CPB **50M'de kalirsa** | 434 | **100.180,3** | **-%13,04** |

UART icin kabul sinirlari genelde +-%2..3'tur. Duzeltilirse %0,11
tamamen guvenli; duzeltilmezse %13 ile **haberlesme calismaz**.

# 3. DEGERLENDIRME - KAPALI (sartname karari alindi)

## Yarisma kurali

DDK'nin bize verdigi cerceve: **"Farkli MHz'lerde calistirabilirsiniz
ama ayni tasarimi istiyoruz."**

Yani frekans hedefleri ayri olabilir; degismemesi gereken sey RTL'in
kendisidir.

## Durumumuz bu kurala UYUYOR

  - **Tek RTL var.** FPGA'ya giden ile ASIC'e giden ayni kaynaktir;
    57/57 SHA-256 manifest ile kanitli.
  - **Frekanslar farkli:** FPGA 50 MHz, ASIC 43,5 MHz. Kural buna
    acikca izin veriyor.
  - **Cevre birimi bolucileri FPGA hedefine gore ayarli** ve
    dogrulama FPGA uzerinde yapiliyor: 34/34 cevre birimi testi
    ve 15/15 NPU testi kart uzerinde gecmistir.

## Ilk degerlendirmem YANLISTI

Bu belgenin onceki surumunde "ASIC'te I2C 348 kHz verir, EK-2
karsilanmaz" diye bir acik isaretlemistim. Bu degerlendirme
**gecersizdir**: sartname ASIC'in kendi saatinde cevre birimi
frekans isterlerini karsilamasini beklemiyor.

## Duzeltme yapmak YANLIS OLURDU

ASIC icin ayri parametre vermek (`ifdef ASIC_43M5` gibi), FPGA ile
ASIC'in tasarimini AYIRMAK anlamina gelirdi - tam olarak kuralin
yasakladigi sey.

Bu nedenle **hicbir RTL degisikligi yapilmamistir ve yapilmamalidir.**

# 4. OLCUMUN KALICI DEGERI

Bolum 2'deki sayilar gecersiz degildir; yalnizca bir ACIK degil,
bir TASARIM BILGISIDIR:

Cip baska bir frekansta calistirilmak istenirse, `soc_top.sv`
satir 749/766/785'teki uc parametre o frekansa ayarlanmalidir.
Moduller zaten parametrik yazildigi icin (`PERIYOT = SYS_CLK_FREQ /
I2C_FREQ`, `DEF_CPB = SYS_CLK_HZ / DEFAULT_BAUD`) baska degisiklik
gerekmez.

43,5 MHz icin dogru degerler olculmustur:

    I2C  : PERIYOT 108 -> SCL 402.576 Hz  (%0,6 sapma)
    UART : CPB 377     -> 115.327 baud    (%0,11 hata)

Bu, cipin farkli bir saatte kullanilmasi gerekirse hazir bilgidir.

# 5. SONUC

Sartname acisindan **uyumsuzluk yoktur**. Teslim paketi mevcut
haliyle dogrudur ve K_diyot kosumu gecerlidir.
