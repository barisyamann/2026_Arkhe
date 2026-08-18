# G07 - Lint Taramasi ve AXI4-Lite WSTRB Uyumlulugu

Tarih: 18 Agustos 2026

## Yontem

Ayri bir lint araci (Verilator vb.) kurulu degildi. Vivado'nun sentez
logu (nexys_top.vds / synth_1 runme.log) zaten ucretsiz ve elde
mevcuttu; kendi modullerimizi ucuncu parti CV32E40P cekirdeginden
ayiklayarak tarandi.

## Latch

    grep -ic "latch" runme.log  -> 0

Sifir. En sinsi hata sinifi zaten temiz.

## Elenen iki yanlis pozitif

Ilk taramada iki "bulgu" gorundu, ikisi de incelemede duzeltilecek bir
sey olmadigi ortaya cikti:

1. "Olu yazmaclar" (sum_exp_reg, nudge_reg, r64_reg, x_centered_reg,
   quant_fc_reg vb., [Synth 8-6014]) - bunlar aslinda always_ff
   icinde bloklayici atamayla kullanilan blok-yerel gecici
   degiskenler (orn. npu_compute_engine.sv:330-333). Vivado once
   sirali eleman saniyor, sonra kaldiriyor - dogru davranis.

2. "Surucusuz net" (p_0_out, [Synth 8-3848], npu_compute_engine icinde
   3 kez) - ayni gecici degiskenlerin optimizasyon artigi. Python ile
   modul govdesi taranarak dogrulandi: bildirilip HIC atanmayan tek
   sinyaller $readmemh ile yuklenen ROM dizileri (dw_weights,
   fc_weights, softmax_exp_lut vb.) - beklenen davranis.

## Duzeltilen kucuk bulgu

jtag_debug.sv: bus_rdata_result, kullanildigi TAP blogundan SONRA
bildiriliyordu ([Synth 8-6901]). Bildirim yukari, ilk kullanimdan
once tasindi.

## Ana bulgu - WSTRB tamamen goz ardi ediliyordu

Sentez logu 100 adet [Synth 8-7129] uyarisi verdi: DOKUZ cevre
biriminin hepsinde wstrb portu "unconnected or has no load".

    timer_peripheral    50
    i2c_peripheral       20
    jtag_debug            8
    uart_stream_peripheral 4
    uart_peripheral        4
    qspi_master            4
    npu_csr                 4
    dma_controller          4
    gpio_peripheral         2

AXI4-Lite'ta wstrb, hangi baytlarin yazmaya dahil oldugunu belirtir.
Yok sayilinca sb/sh ile bir yazmaca bayt yazmak DAIMA tum 32-bit
kelimeyi eziyordu. Yazilimimiz hep kelime erisimi yaptigi icin bu
bugune kadar hic tetiklenmedi, ama AXI4-Lite ihlaliydi ve jüri
denemesinde (ornegin bir yazmaca sb ile deneme) yanlis sonuc verirdi.

### Zincir dogrulamasi (duzeltmeye baslamadan once)

    CPU obi_be_i -> obi_to_axi_simple (be_d <= obi_be_i)
      -> axil_wstrb_o -> ara baglanti (27 referans) -> cevre birimi
      portlari (s_axi_wstrb / s_axil_wstrb)

Zincir uctan uca saglamdi; sorun yalnizca cevre birimlerinin degeri
KULLANMAMASIYDI. Boylece duzeltme cevre birimi seviyesinde kalabildi,
kopru veya ara baglantiya dokunmaya gerek kalmadi.

### Uygulanan desen

Her birimde bayt maskesi turetildi:

    wr_mask = {{8{wstrb[3]}}, {8{wstrb[2]}}, {8{wstrb[1]}}, {8{wstrb[0]}}};
    wr_data = wdata & wr_mask;

Yazma turune gore dogru ifade:

    duz yazma : (eski & ~wr_mask) | wr_data
    SET       : eski |  wr_data
    CLEAR     : eski & ~wr_data
    TOGGLE    : eski ^  wr_data
    W1C durum : eski & ~wr_data

qspi_master, dma_controller, npu_csr: veriyi tek noktada mandallayan
ortak desen (w_data_lat) kullaniyordu; strobe de ayni noktada
mandallanip kullanim yerinde uygulandi.

i2c_peripheral: yazmaclarda karsilastirma (clamp) ve bit bazli mantik
oldugu icin maske yerine "birlesik deger" (wr_val fonksiyonu) tercih
edildi - kodun geri kalani degismeden calisiyor.

### Yol boyunca cikan iki kendi hatam

  - i2c_peripheral'da cfg_wr sinyalini bildirmeden kullanmistim.
  - Fonksiyon cagrisinin sonucunu indekslemeye calistim
    (wr_val(...)[6:0]) - SystemVerilog'da gecersiz. reg_adr icin adres
    baytini dogrudan strobe ile gecitleyerek cozuldu (bit 0'da).

Ikisi de derleme/elaborasyon asamasinda, simulasyona gitmeden once
Python ile kaynak taranarak yakalandi.

## Dogrulama

Yazilimda degisiklik yapilmadi. Sistem testi ayni app.hex ile tekrar
kosuldu:

    Onceki (R8 kosumu) : 61.078150 ms, 0 hata, 1:04
    WSTRB sonrasi       : 61.078150 ms, 0 hata, 1:04  (BIREBIR AYNI)

Zamanlamalarin nanosaniyeye kadar ozdes cikmasi beklenen sonuctu:
yazilim hep kelime erisimi yapiyor (wstrb = 4'hF), maske tum bitleri
gecirir, davranis degismez. Fark cikmasi bir maskeleme hatasina
isaret ederdi.

## Kapanan

  Lint: latch = 0 (dogrulandi)
  Lint: surucusuz net / olu yazmac iddialari incelendi, kusur yok
  jtag_debug bildirim sirasi duzeltildi
  WSTRB - 9/9 cevre biriminde AXI4-Lite uyumlulugu saglandi

## Acik kalan

  QSPI saat/kenar anomalisi - dalga formuyla incelenecek
  Tri-state ayrimi
  B2 kalani - TCM Port B salt-okunur + SRAM makrosu
