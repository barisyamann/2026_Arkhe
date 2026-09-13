# Ucuncu inceleme raporunun dogrulanmasi (10 Eylul 2026)

Raporun butun somut iddialari kendi olcumlerimizle sinandi.
**Uc ana teknik iddiasinin ucu de DOGRU cikti.** En agir bulgu, tum
ASIC kosumlarinin ESKI RTL ile yapilmis olmasidir.

## DOGRULANDI 1: KOSUMLAR YANLIS RTL ILE YAPILMIS  (en kritik)

filelist.f'teki 57 dosya, satir sonlari LF'ye normalize edilerek
SHA-256 ile karsilastirildi:

    toplam: 57   FARKLI: 2   YOK: 0
      FARK: rtl/Memory/sram_module.sv
      FARK: rtl/npu/npu_tcm_sram.sv

Raporun soyledigi iki dosyanin AYNISI. Kritik fark:

    YEREL  (satir 285):  assign ram_rdata = rdata_hold;
    SUNUCU (satir 258):  assign ram_rdata = rd_en_q ? dout_r[rsel_q]
                                                    : rdata_hold;

Sunucudaki surum SRAM cikisini DOGRUDAN gecirir (bypass); yereldeki
duzeltilmis surum ise kayitli veri verir. Sunucu dosyasinin tarihi
**22 Agustos 2026**. Yani yereldeki duzeltme sunucuya hic tasinmamis.

SONUC: A_yeniRTL, C_kapanis, D_hold, E_dengeli ve G_saat kosumlarinin
HEPSI eski RTL ile yapilmistir. G'nin en kotu setup yolunun SRAM
cikisindan CPU ALU girisine kadar uzanmasi bununla birebir tutarli.

npu_tcm_sram.sv farki ise yalnizca YORUM. Dogrulandi: yorum ve bos
satirlar cikarilinca iki dosyanin md5'i ayni (1eacea39...). Yereldeki
"bypass kaldirildi" yorumu YANILTICI - kod hala bypass yapiyor.
Rapor bu ayrimda da hakli.

## DOGRULANDI 2: SRAM YAZMA VERISI KAYBI

Kod zinciri okundu:

    satir 148:  assign wr_en = aw_active && w_active && !s_axil_bvalid;
    satir 68:   if (s_axil_wvalid && s_axil_wready) begin
                    w_active      <= 1'b1;
                    s_axil_wready <= 1'b0;     // WREADY DUSUYOR
                end
    satir 224:  .wmask0 (s_axil_wstrb),   // CANLI sinyal
    satir 226:  .din0   (s_axil_wdata),   // CANLI sinyal
    satir 297:  if (s_axil_wstrb[0]) ram[waddr][7:0] <= s_axil_wdata[7:0];

W el sikismasinda yalnizca `w_active` bayragi kuruluyor; WDATA ve
WSTRB HICBIR YERE KAYDEDILMIYOR. AW daha gec gelirse `wr_en` sonraki
cevrimde yukselir ve o anda master, WREADY dustugu icin AXI'ye gore
veriyi degistirmekte SERBESTTIR. Fiziksel yazma o an canli sinyali
orneklediginden yanlis veri yazilir.

Duzeltme: W el sikismasinda WDATA/WSTRB kaydedilmeli, fiziksel
yazmada bu kayitlar kullanilmali. AW/W bagimsiz gelis sirasi
korunmali.

## DOGRULANDI 3: QSPI PRESCALER TASMASI (P=63)

    satir 372:  logic [5:0] sck_tam_periyot;          // 6 BIT
    satir 436:  assign sck_tam_periyot = presc_sifir ? 6'd1
                                       : (ccr_prescaler + 6'd1);
    satir 437:  assign sck_half_period = (sck_tam_periyot >> 1);

Aritmetik olarak dogrulandi:

    presc=62 -> tam_periyot=63  yarim=31   (calisir)
    presc=63 -> tam_periyot= 0  yarim= 0   <-- TASMA

63+1 = 64, alti bitte 0'a sariyor. Yarim periyot 0 olunca SCK kenari
hic uretilmez. Raporun "P=63 -> 0 kenar" bulgusu dogru.

Duzeltme: tam periyot hesabi 7 bit yapilmali, sayac karsilastirmalari
genislik bakimindan tutarli hale getirilmeli.

## KAPSAMA UYARISI HAKLI

21/21 regresyon ve 52/52 islevsel bin bu iki sinir durumunu
KAPSAMIYOR. Islevsel kapsamanin %100 olmasi, tanimlanan noktalarin
kapsandigi anlamina gelir; tum RTL durumlarinin dogrulandigi anlamina
GELMEZ. Bu iki hata icin ayrica test yazilmali.

## G_saat SONUCLARININ DEGERI

G kosumu gecersiz degil ama SINIRLI: eski RTL ile yapildigi icin
"teslim adayi" olamaz. Yine de sunlari OLCTU:

  - -repair_clock_nets gercekten uygulandi (log ile dogrulandi)
  - D_hold'u olduren adim 44 asildi (tikaniklik 0/0/0)
  - E_dengeli'yi olduren adim 43 asildi
  - Yonlendirme DRC 0, anten 0/0
  - Hold 9 kosenin 3'unde temiz (C'de 1'di)
  - ANCAK setup uc ss kosesinde ihlalli (en kotu -5,842 ns)

Setup ihlalinin buyuk kismi zaten eski RTL'deki SRAM bypass yolundan
geliyor olabilir - rapor bu yolu birebir gosteriyor:
    u_instruction_ram.g_sram[2].u_macro/dout1[17] -> ... -> _186846_/D
    (_186846_/Q = u_core.alu_operand_b_ex[1])

Yani duzeltilmis RTL ile bu yol kisalacagi icin setup tablosu
tamamen degisebilir. Eski netlist uzerinden frekans tahmini yapmak
yaniltici olur.

## SIRADAKI ADIMLAR (raporun sirasi benimsendi)

1. Yerel RTL'yi sunucuya tasi; hash manifesti ile dogrula.
2. Iki islevsel hatayi kapat (SRAM WDATA/WSTRB yakalama, QSPI 7 bit).
   Her ikisi icin regresyon testi yaz.
3. SDC/saat hedefini tekile: PnR ve signoff ayni periyot.
4. Once sentez + kisa yerlesim/CTS ile SRAM->ALU yolunun kisaldigini
   NETLIST uzerinden dogrula; ancak sonra tam kosum.

---

# YAPILAN DUZELTMELER (10 Eylul 2026)

## 1) sram_module.sv - W kanali veri yakalama

Eklenen kayitlar:

    logic [AXI_DATA_W-1:0] w_data_reg;
    logic [3:0]            w_strb_reg;

El sikismasinda yakalanir:

    if (s_axil_wvalid && s_axil_wready) begin
        w_active   <= 1'b1;
        w_data_reg <= s_axil_wdata;   // YENI
        w_strb_reg <= s_axil_wstrb;   // YENI
        s_axil_wready <= 1'b0;
    end

Fiziksel yazma artik kayitlari kullanir (hem makro hem cikarimsal yol):

    .wmask0 (w_strb_reg),  .din0 (w_data_reg)
    if (w_strb_reg[0]) ram[waddr][7:0] <= w_data_reg[7:0];  ...

Adres tarafinda bu zaten dogru yapiliyordu (aw_addr_reg); veri
tarafindaki eksiklik bir ASIMETRIYDI.

## 2) qspi_master.sv - prescaler tasmasi

Genislikler alti bitten YEDI bite cikarildi:

    logic [6:0] sck_cnt;
    logic [6:0] sck_tam_periyot;
    logic [6:0] sck_half_period;

    assign sck_tam_periyot = presc_sifir ? 7'd1
                                         : ({1'b0, ccr_prescaler} + 7'd1);

Sayac karsilastirma/artirmalari da yedi bite uyumlandi (7'd1). Dosyada
hicbir alti bitlik kalinti kalmadi (grep ile dogrulandi).

## TESTLER

Iki yeni testbench yazildi ve regresyona eklendi:

    tb/tb_sram_w_yakalama.sv     4 denetim
    tb/tb_qspi_presc_sinir.sv  127 denetim

### Sahte pozitif olmadigi KANITLANDI

tb_sram_w_yakalama, duzeltme GECICI OLARAK GERI ALINARAK sinandi:

    duzeltme geri alinmis RTL:
      [HATA] el sikismasindaki veri yazildi - beklenen 0x12345678,
             gelen 0xxxxxxxxx
      SRAM W YAKALAMA TESTI BASARISIZ - 1 hata

    duzeltilmis RTL:
      [OK] el sikismasindaki veri yazildi = 0x12345678
      SRAM W YAKALAMA TESTI GECTI - 4 denetim, 0 hata

Yani test gercekten hatayi yakaliyor; sadece "gecen bir test" degil.

Not: testbench yazarken el sikismasi zamanlamasinda uc kez yanlis
kenar kullanip kilitlenme yasadim. RTL'in READY'yi bir cevrim
gecikmeli yukseltip el sikismasi posedge'inde dusurdugu, ayri bir
sonda ile OLCULEREK bulundu; VALID, READY'nin goruldugu negedge'i
TAKIP EDEN negedge'e kadar yuksek tutulmalidir.

## KAYNAK ESITLIGI ARTIK KANITLANIYOR

scripts/rtl_manifest.py eklendi:

    python scripts/rtl_manifest.py uret > asic/rtl_manifest.txt
    python scripts/rtl_manifest.py dogrula asic/rtl_manifest.txt

Duzeltilmis RTL sunucuya tasindi (eski dosyalar
~/sram_module.sv.eski_20260910 ve ~/qspi_master.sv.eski_20260910
olarak yedeklendi) ve dogrulandi:

    toplam 57 dosya
    SONUC: TUM DOSYALAR ESLESIYOR

Bundan sonra hicbir ASIC kosumu bu dogrulama gecmeden
baslatilmamalidir.
