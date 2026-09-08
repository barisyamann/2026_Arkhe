# TEKNOFEST final demosu - ARKHE FPGA tarafi

8 Eylul 2026. Bu klasor, yarisma paketiyle gelen `demo_harness.py` araciyla
kartin ucdan uca kosulmasi icin gereken takim tarafi dosyalarini icerir.

## Donanim baglantisi

Demo araci IKI AYRI seri port ister. Nexys A7 uzerinde tek USB-UART koprusu
vardir, bu yuzden ikinci port harici bir 3,3 V UART-TTL modulu ile Pmod JB
uzerinden verilir.

| Islev | Yol | Baud |
|---|---|---|
| Core UART (sonuc) | kart ustu USB-UART koprusu (C4/D4) | 115200 |
| UART-stream (vektor) | Pmod JB, harici UART-TTL modulu | 1 Mbps |

Pmod JB kablolama (ust sira):

    JB1 (D14) <- modulun TX'i   (FPGA girisi)
    JB2 (F16) -> modulun RX'i   (FPGA cikisi)
    JB5/JB6   <- GND

DIKKAT: modul 3,3 V kipinde olmalidir. 5 V seviye FPGA bankasini bozar.

## Kart imaji

Demo gunu karta DEMO_MODE ile derlenmis imaj yuklenir:

    python sw_nexys/scripts/build.py          # app_demo.hex uretir
    python sw_nexys/scripts/gen_flash_image.py # flash_demo.hex uretir

`flash_demo.bin` Vivado'da `write_cfgmem` ile bitstream'e eklenir ve QSPI
flash'a yazilir. Yazma bittikten sonra kartta PROG dugmesine basilir.

DEMO_MODE'un normal imajdan iki farki vardir:

1. Cikarimlar arasi 3 saniyelik bekleme yoktur. Demo araci vektorleri arka
   arkaya gonderir; bekleme aracin zaman asimina dusmesine yol acardi.

2. `UART_RDR` bayt yolu dogrulama blogu atlanir. O blok cerceve basina 1960
   DEGIL 1964 bayt tuketir; demo araci tam 1960 bayt gonderdigi icin fazladan
   istenen 4 bayt bir SONRAKI cercevenin basindan karsilanir ve o cerceve 4
   bayt kaymis islenirdi. Normal kart imaji ve simulasyon imaji blogu hala
   kosar, dolayisiyla kapsama kaybi yoktur.

## Kosum

    python demo_harness.py validate -c arkhe_icd.json
    python demo_harness.py run -c arkhe_icd.json --manifest public_dataset/manifest.csv -n 0

## Olculen sonuclar (8 Eylul 2026, 17:31)

`sonuclar/` altindaki dosyalar bu kosumun ham ciktilaridir.

| Metrik | Deger |
|---|---|
| Gonderilen ornek | 156 |
| Golden referansi olan | 156 |
| **Golden ile uyum** | **100,00 % (156/156)** |
| Uyusmazlik | 0 |
| Zaman asimi | 0 |
| Gecikme (medyan / p95 / maks) | 7,74 / 8,78 / 21,58 ms |
| Olculen hizlanma | 183,3x |
| Saglamlik senaryolari | 9/10 (+1 opsiyonel atlandi) |

Uyum matrisi tamamen kosegendir: silence 6, unknown 16, yes 50, no 84;
kosegen disi hucre yoktur. Donanim dogrulugu ve golden model dogrulugu
%72,44 ile ayni; fark 0,00 puandir. Bu oran veri setinin zorlugudur ve
puanlamada kullanilmaz.

## Bilinen sinirlama

`back_to_back` senaryosu tam sirada kosuldugunda 5 cerceveden 4'une yanit
verir. Tek basina kosuldugunda uc bagimsiz tekrarda 5/5 gecmistir; fark,
kendinden onceki senaryodan devreden gecis etkisidir.

Kok nedeni `uart_stream_peripheral.sv` icindeki toplayici sayacinin
(`pack_cnt_r`) yalnizca reset ve tam kelime okumasi ile sifirlanmasi,
`UARTS_FIFO_CLR` ile sifirlanmamasidir. Bu tespit 8 Eylul 2026'da yapilmistir.
Duzeltmesi hazirdir ancak d45_anten2 ASIC teslimi yamasiz RTL'e SHA-256 ile
bagli oldugu icin bu teslime dahil EDILMEMISTIR; ayri bir fiziksel kosumla
birlikte girecektir.

## Simulator beyani

Fonksiyonel dogrulama Vivado xsim 2025.2 (`xvlog`/`xelab`/`xsim`) ile
yapilmistir; DSim kullanilmamistir.
