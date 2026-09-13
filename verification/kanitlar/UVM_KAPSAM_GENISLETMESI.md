# UVM ve protokol dogrulama kapsaminin genisletilmesi
# (12 Eylul 2026)

Kullanici istegi: "UVM'nin capini daha da arttir, testlerin capini hem
calisiyor mu hem de protokol dogru mu diye daha da arttir."

# 1. ONCEKI DURUM

UVM agent PASIF bir monitor + scoreboard yapisiydi:

    tb/uvm/axil_if.sv         sanal arayuz
    tb/uvm/axil_uvm_pkg.sv    825 satir

Denetledigi protokol kurallari:
  - VALID kararliligi (AR/AW/W/R/B): READY gelmeden VALID dusmemeli
  - El sikismadan once bilgi sinyalleri degismemeli
  - El sikisan cevrimde X/Z olmamali
  - Yanit kodu gecerli olmali
  - Adres 4 bayta hizali olmali
  - WSTRB == 0 olmamali

Fonksiyonel kapsam: **YOKTU** (covergroup sayisi 0).

# 2. EKLENEN PROTOKOL DENETIMLERI

## 2.1 Reset sirasinda VALID  (ARM IHI0022 A3.1.2)

    if (!vif.rst_n) begin
        if (vif.arvalid || vif.awvalid || vif.wvalid) begin
            rst_valid_hata++;
            `uvm_error(... "reset aktifken VALID yuksek" ...)
        end
        ...
    end

NE YAKALAR: Sentez sonrasi netlistte reset agi eksikse veya bir
yazmac reset'siz kalmissa, reset aktifken kanal VALID'i yuksek kalir.
Islem duzeyi denetim bunu GORMEZ cunku el sikisma hic tamamlanmaz.

## 2.2 EXOKAY yasagi  (ARM IHI0022 A3.4.4)

AXI4-Lite'ta ozel erisim (exclusive access) YOKTUR; RRESP/BRESP
degeri 2'b01 YASAKTIR.

    if (it.yanit == 2'b01) begin
        exokay_hata++;
        `uvm_error(... "AXI4-Lite'ta EXOKAY (2'b01) yasaktir" ...)
    end

Ayrica covergroup'ta `illegal_bins exokay = {2'b01}` ile simulator
seviyesinde de yakalanir.

NE YAKALAR: Tam AXI4 slave'i yanlislikla AXI4-Lite baglantisina
konursa veya yanit kodlamasi bozulursa.

## 2.3 Yazma genisligi dagilimi

    tam_kelime_yazma   strb == 4'b1111
    bayt_yazma         strb'de tek bit
    yarim_yazma        strb == 0011 veya 1100

Bu bir HATA denetimi degil, KAPSAM olcumudur: kismi yazmalarin
gercekten test edilip edilmedigini raporlar. Bolum 4'te bu olcum
gercek bir acik buldu.

# 3. EKLENEN FONKSIYONEL KAPSAM

Daha once hic covergroup yoktu. Eklenen:

    covergroup islem_kapsami;
        tur_cp      : okuma / yazma
        bolge_cp    : 12 adres bolgesi (bootrom, iram, dram, npu_mem,
                      gpio, uart1, uart2, i2c, qspi, timer, npu_csr, dma)
        strb_cp     : tam_kelime / tek_bayt / yarim / diger
        yanit_cp    : okay / slverr / decerr
                      + illegal_bins exokay = {2'b01}
        tur_x_bolge : cross  (her bolgeye hem okuma hem yazma yapildi mi)
        tur_x_strb  : cross  (yazmalarda hangi strb desenleri gorundu)
    endgroup

Her islem `write()` icinde ornekleniyor.

# 4. KAPSAM OLCUMU GERCEK BIR ACIK BULDU

UVM kosumu sunu raporladi:

    [OK] yazmalar tek genislikte (tam=16 bayt=0 yarim=0)

**162.064 AXI isleminde TEK BIR kismi yazma yok.**

Yani `rtl/Memory/sram_module.sv:319-322` HIC dogrulanmamisti:

    if (w_strb_reg[0]) ram[waddr][7:0]   <= w_data_reg[7:0];
    if (w_strb_reg[1]) ram[waddr][15:8]  <= w_data_reg[15:8];
    if (w_strb_reg[2]) ram[waddr][23:16] <= w_data_reg[23:16];
    if (w_strb_reg[3]) ram[waddr][31:24] <= w_data_reg[31:24];

Bir strb biti YANLIS dilime bagli olsaydi (ornegin [1] -> [7:0]),
mevcut 26 testin HICBIRI yakalamazdi. Cunku hepsi tam kelime yaziyor
ve tam kelimede dort dilim de yazildigi icin eslesme hatasi
gorunmuyor.

## Yazilan test: tb_wstrb_kismi_yazma  (11 denetim)

| # | Senaryo | Dogrulanan |
|---|---|---|
| 1 | strb=0001/0010/0100/1000 | her bayt seridi DOGRU dilime yaziyor |
| 2 | yazilmayan baytlar | KORUNUYOR (asil risk) |
| 3 | strb=0011 / 1100 | yarim kelime yazma |
| 4 | strb=0000 | hicbir sey degismiyor |
| 5 | birikimli | 4 ayri bayt yazmasi -> 0xEFBEADDE |
| 6 | komsu adres | kismi yazma yan adresi bozmuyor |

Sonuc: **11/11 gecti.** Bayt-secmeli yazma mantigi DOGRU.

## Test yazarken yapilan hata ve duzeltmesi

Ilk surum 500 us gozcu suresinde asili kaldi. Sebep: posedge tabanli
el sikisma beklemesi. RTL READY'yi bir cevrim GEC yukseltir ve el
sikisma posedge'inde dusurur; VALID takip eden negedge'e kadar
yuksek kalmalidir.

Calisan referans `tb_sram_w_yakalama.sv`'deki kalip uyarlandi:

    @(negedge clk); <sinyal sur>; valid = 1;
    @(negedge clk);
    while (!ready && g < 40) begin @(negedge clk); g++; end
    @(negedge clk);
    valid = 0;

Bu kalip daha once de ogrenilmisti; belgelenmedigi icin tekrar
kesfedilmesi gerekti. Artik iki testte birden kayitli.

# 5. SONUC

## UVM testi

    once : 32 denetim
    sonra: 35 denetim   (+3 yeni protokol denetimi)

    162.064 AXI4-Lite islemi yakalandi
    [OK] reset aktifken hicbir kanalda VALID yuksek degildi
    [OK] EXOKAY (2'b01) yaniti yok - AXI4-Lite yanit kumesi dogru
    [OK] yazma genisligi raporlandi

## Regresyon

    once : 26/26 test, 602 denetim
    sonra: 28/28 test, 625 denetim

Eklenen iki test:
    i2c_scl_frekans      9 denetim  (ASIC 43,2 MHz -> SCL tam 400 kHz)
    wstrb_kismi_yazma   11 denetim  (bayt-secmeli yazma)

## Dosyalar

    tb/uvm/axil_uvm_pkg.sv        genisletildi
    tb/tb_wstrb_kismi_yazma.sv    YENI
    tb/tb_i2c_scl_frekans.sv      YENI (11 Eylul)
    scripts/run_regression.py     iki test kaydedildi

# 6. DURUST DEGERLENDIRME

Eklenen denetimler kosumda HATA BULMADI - hepsi [OK] dondu. Bu,
tasarimin bu kurallara zaten uydugunu gosterir.

Asil kazanc kapsamdadir: artik bu kurallar SUREKLI denetleniyor.
Bir sonraki RTL degisikligi reset agini bozarsa veya yanit
kodlamasini degistirirse, regresyon bunu yakalar.

Ve kapsam olcumu bir bosluk BULDU: kismi yazma hic test edilmemisti.
O bosluk artik kapali.
