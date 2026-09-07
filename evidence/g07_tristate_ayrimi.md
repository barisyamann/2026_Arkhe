# G07 - Tri-state Ayrimi (ASIC sinir temizligi)

Tarih: 18 Agustos 2026

## Neden

ASIC akisinda ucdurumlu (tri-state) surucu yalnizca PAD HALKASINDA
bulunabilir. Sentez araclari modul icindeki 'z surumunu standart hucre
kutuphanesine esleyemez. LibreLane'in sertlestirecegi modul soc_top
oldugu icin cift yonlu pinlerin o sinirin DISINDA kalmasi gerekiyordu.

Onceki durumda alti adet inout portu vardi:

    soc_top: i2c_sda, i2c_scl, qspi_io0, qspi_io1, qspi_io2, qspi_io3

## Yapilan

Sinir soc_top'ta cizildi. Arayuz cikis / cikis-etkin / giris uclusune
ayrildi:

| Modul            | Eski                  | Yeni                                     |
|------------------|-----------------------|------------------------------------------|
| qspi_master      | inout qspi_io0..3     | qspi_io_o/_oe/_i  ([3:0])                |
| i2c_peripheral   | inout sda, scl        | sda_o/_oe/_i, scl_o/_oe/_i               |
| soc_top          | 6 x inout             | ayrik ucluler                            |

### QSPI - hat basina cikis etkin

Eski kodda her hattin kendi kosulu vardi:

    assign qspi_io0 = io_oe ? io_out[0] : 1'bz;
    assign qspi_io1 = (io_oe && ccr_data_mode[1]) ? io_out[1] : 1'bz;
    assign qspi_io2 = (io_oe && ccr_data_mode == 2'b11) ? io_out[2] : 1'bz;
    assign qspi_io3 = (io_oe && ccr_data_mode == 2'b11) ? io_out[3] : 1'bz;

Bu kosullar qspi_io_oe'ye birebir tasindi:

    assign qspi_io_oe[0] = io_oe;
    assign qspi_io_oe[1] = io_oe && ccr_data_mode[1];
    assign qspi_io_oe[2] = io_oe && (ccr_data_mode == 2'b11);
    assign qspi_io_oe[3] = io_oe && (ccr_data_mode == 2'b11);

Yani tek hatli modda yalnizca io0, ikili modda io0-io1, dortlu modda
dordu birden surulur - eski davranisin aynisi.

### I2C - acik drenaj

I2C hatti asla yukari SURULMEZ; ya asagi cekilir ya birakilir ve harici
pull-up yukari ceker. Bu yuzden:

    assign sda_o = 1'b0;    // cikis degeri daima 0
    assign scl_o = 1'b0;
    // tum bilgi *_oe'dedir

## Ucdurumlu surucu nereye gitti

Gercek 'z surumu artik iki yerde:

  - FPGA  : nexys_top (generate dongusuyle 4 QSPI hatti + 2 I2C hatti)
  - Sim   : tb_soc_top

ASIC akisinda bu katmanin yerini pad halkasi alacak. soc_top her uc
ortamda da AYNI kaliyor - tasarimin tasinabilirligi bu sekilde saglandi.

## Yol boyunca cikan hata

Derleme tek bir hatayla dondu:

    ERROR: [VRFC 10-2989] 'sda' is not declared
           i2c_peripheral.sv:192

I2C hattin durumunu geri okur (arbitrasyon ve ACK algilama icin):

    assign sda_in = sda;

Cikis tarafini ayirirken bu OKUMA yolunu guncellemeyi atlamistim.
sda_in = sda_i yapildi.

QSPI'da ayni hata yapilmadi cunku orada okuma yolu tek satirdi ve
degisiklikle ayni ekrandaydi (assign io_in = qspi_io_i). I2C'de geri
okuma dosyanin baska bir bolumundeydi.

## Dogrulama

    Onceki kosum : 61.078150 ms, 0 hata
    Bu kosum     : 61.078150 ms, 0 hata   (BIREBIR AYNI)

Degisiklik saf yeniden kablolamadir; mantik degismedi ve zamanlamalarin
nanosaniyeye kadar ozdes kalmasi bunu dogruluyor.

Yapisal kontrol:

    soc_top ve altindaki tum RTL'de:  0 adet inout,  0 adet 'z

## Kapanan

  Tri-state ayrimi - soc_top ASIC'e hazir sinir
  RTL SEVIYESI TAMAMLANDI
