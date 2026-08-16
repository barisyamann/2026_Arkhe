# FPU Yapilandirma Karari - Olcum Raporu

Tarih   : 16 Agustos 2026
Arac    : Vivado 2025.2, xc7a100tcsg324-1
Yontem  : Ayni RTL, yalnizca soc_top.sv icindeki .FPU() parametresi
          degistirilerek iki ayri SENTEZ kosumu

## Olculen degerler (sentez sonrasi)

| Yapilandirma | LUT    | FF    | DSP | FPU hucresi |
|--------------|--------|-------|-----|-------------|
| FPU = 0      | 18.906 | 5.255 | 9   | -           |
| FPU = 1      | 21.250 | 6.303 | -   | 17          |
| Fark         | +2.344 | +1.048|     |             |

## Yorum

CV32E40P'de FPU=1 parametresi cekirdege kayan nokta buyruk cozme
mantigi ve APU (koprosesor) arayuzu ekler. Asil hesaplama birimi
olan FPnew, cekirdegin ICINDE degildir; ayri bir modul olarak
(cv32e40p_fp_wrapper.sv) APU arayuzune baglanmalidir.

soc_top.sv icinde bu baglanti yapilmadigindan FPU=1 yapilandirmasi:
  - 2.344 LUT ve 1.048 FF maliyet getirmekte,
  - sentezlenen tasarimda FPU'ya ait yalnizca 17 hucre birakmakta,
  - kayan nokta yetenegi kazandirmamaktadir.

Bir F buyrugu yurutuldugunde cekirdek, gelmeyecek bir APU cevabini
bekleyecektir.

## Karar

Sistem yazilimi (sw_nexys/src/main.c) ve INT8 yapay zeka
hizlandiricisi kayan nokta islemi icermedigi icin cekirdek
FPU = 0 ile yapilandirilmistir. Mimari RV32IMC'dir.

Bu karar zamanlama analiziyle de desteklenmektedir: mevcut
tasarimda CPU zaten ikinci en kritik yol uzerindedir
(slack +2,348 ns) ve WNS +1,649 ns ile sinirdadir.

DTR'de RV32IMFC belirtilmisti; sapma bu olcume dayanmaktadir.
