# "Ayni hata baska yerde de var mi?" taramasi (10 Eylul 2026)

Denetim `sram_module.sv`'de W kanali veri kaybini buldu. Ayni KALIP
butun AXI slave'lerinde arandi. **Iki modulde daha AYNI HATA bulundu
ve olcumle kanitlandi.**

## YONTEM

RTL'de 13 gercek AXI slave modulu var. Her biri iki soruyla incelendi:
  1) READY sinyalleri BAGIMSIZ mi yukseliyor?
  2) Fiziksel yazma CANLI wdata'yi mi ornekliyor?

Ikisi de "evet" ise hata vardir: W once gelirse el sikismasi biter,
WREADY duser ve master AXI'ye gore WDATA'yi degistirmekte serbesttir;
AW gec gelince yanlis veri yazilir.

## SONUC TABLOSU

| Modul                     | READY kalibi          | WDATA | Durum |
|---------------------------|-----------------------|-------|-------|
| sram_module.sv            | bagimsiz, gecikmeli   | kayit | DUZELTILDI |
| **uart_peripheral.sv**    | bagimsiz, gecikmeli   | canli | **HATA - DUZELTILDI** |
| **uart_stream_periph.sv** | bagimsiz, gecikmeli   | canli | **HATA - DUZELTILDI** |
| dma_controller.sv         | -                     | kayit | guvenli (w_data_lat) |
| jtag_debug.sv             | -                     | kayit | guvenli (csr_w_data_lat) |
| npu_csr.sv                | -                     | kayit | guvenli (w_data_lat) |
| qspi_master.sv            | -                     | kayit | guvenli (w_data_lat) |
| gpio_peripheral.sv        | AW&W birlikte sart    | canli | guvenli |
| timer_peripheral.sv       | AW&W birlikte sart    | canli | guvenli |
| i2c_peripheral.sv         | axi_wr_en (birlikte)  | canli | guvenli |
| npu_tcm_axi_slave.sv      | sabit 1, ayni cevrim  | canli | guvenli |
| npu_accelerator.sv        | yalnizca yonlendirici | -     | ilgisiz |
| obi_to_axi_simple.sv      | master tarafi         | -     | ilgisiz |

GPIO/Timer/I2C guvenli cunku READY'leri ancak AW ve W'nin IKISI BIRDEN
hazirken yukseliyor:

    assign s_axil_awready = ~bvalid && s_axil_awvalid && s_axil_wvalid;
    assign s_axil_wready  = ~bvalid && s_axil_awvalid && s_axil_wvalid;

Bu tasarimda el sikismalari ayni cevrimde olur; "W bekler, veri
degisir" durumu YAPISAL OLARAK dogamaz.

npu_tcm_axi_slave guvenli cunku yazma kosulu:

    wire yazma_kabul = s_axi_awvalid && s_axi_awready &&
                       s_axi_wvalid  && s_axi_wready;

yani yazma her iki el sikismasinin AYNI ANDA oldugu cevrimde yapilir.

## OLCUMLE KANIT

Tahminle degil, sonda ile dogrulandi. uart_peripheral'a CPB yazmacina
0x000000AB yazildi (W once), sonra WDATA 0xFFFFFFFF'e bozuldu, sonra
AW gonderildi:

    DUZELTME ONCESI:
      reg_cpb_r = 0xffffffff
      SONUC: HATA - canli WDATA kullanilmis

    DUZELTME SONRASI:
      reg_cpb_r = 0x000000ab
      SONUC: DOGRU - veri kaydediliyor

uart_stream_peripheral icin de ayni sonda, ayni sonuc.

## YAPILAN DEGISIKLIK

Her iki modulde:

    logic [AXI_DATA_W-1:0] w_data_r;
    logic [3:0]            w_strb_r;

    // el sikismasinda yakala
    if (s_axil_wvalid && s_axil_wready) begin
        w_active_r <= 1'b1;
        w_data_r   <= s_axil_wdata;
        w_strb_r   <= s_axil_wstrb;
        s_axil_wready <= 1'b0;
    end

wr_data/wr_mask ve yazma blogundaki tum dogrudan kullanimlar
(TDR, CFG bitleri, FIFO_CLR) kayitli sinyallere cevrildi.
Reset'e de eklendi.

## DERS

Bu tarama, tek bir hatanin AYNI KALIPLA baska yerlerde tekrarlanmis
olabilecegini gosteriyor. Bir hata bulundugunda "baska nerede ayni
sey var?" diye sormak, tek tek hata avlamaktan daha verimli.

Uc modulun hepsi ayni gecmisten geliyor gorunuyor: adres kaydediliyor
(aw_addr_r) ama veri kaydedilmiyor - ayni ASIMETRI.
