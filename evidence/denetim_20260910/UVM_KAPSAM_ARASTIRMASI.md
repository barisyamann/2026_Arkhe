# UVM dogrulamada daha ne yapilabilir - arastirma
# (12 Eylul 2026)

Kullanici istegi: "UVM dogrulamada testlerde daha ne yapilabilir
iyice arastir bakalim."

# 1. MEVCUT YAPININ ENVANTERI (olculdu)

`tb/uvm/axil_uvm_pkg.sv` icinde hangi UVM bileseni VAR, hangisi YOK:

| Bilesen | Durum |
|---|---|
| uvm_monitor | VAR |
| uvm_scoreboard | VAR |
| uvm_agent | VAR |
| uvm_env | VAR |
| uvm_test | VAR |
| covergroup | VAR (11 Eylul'de eklendi) |
| **uvm_sequencer** | **YOK** |
| **uvm_driver** | **YOK** |
| **uvm_sequence** | **YOK** (yalniz kelime geciyor) |
| uvm_subscriber | YOK |

Yani agent tamamen **PASIF**: izliyor, kendi trafigi URETMIYOR.

# 2. BULGU 1: KAPSAM OLCULUYOR AMA GORULMUYORDU

11 Eylul'de covergroup eklenmisti; orneklenip sample ediliyordu
ama **sonucu hicbir yere yazilmiyordu**.

Sebep olculdu: testbench `$finish` ile biter ve UVM'nin
`report_phase`'i HIC CALISMAZ. Ozet `axil_ozet_yaz()` adli statik
fonksiyondan gelir; o da covergroup ORNEGINE erisemez.

## Cozum

Kapsam degerleri statik degiskenlere kopyalanip ozet yaziciya
baglandi:

    static real kapsam_tur, kapsam_bolge, kapsam_strb,
                kapsam_yanit, kapsam_toplam;

`write()` her islemde tazeler; `axil_ozet_yaz()` okur.

# 3. BULGU 2: ADRES BINLERI YANLIS HEDEFE GOREYDI

Ilk olcum:

    tur %100,0   bolge %8,3   strb %33,3   yanit %33,3   TOPLAM %35,4

**%8,3 yaniltici bir sayiydi.** Sebep olculdu: covergroup 12 SoC
bolgesi (bootrom, gpio, uart, i2c...) tanimliyordu, ama agent SoC
yoluna DEGIL, NPU motorunun kendi AXI arayuzune baglidir:

    tb_soc_top.sv:1617
        assign npu_eng_if.awaddr = uut.u_npu.eng_awaddr;

Motor yalnizca KENDI TCM'ine erisir (0x0 - 0x76bc). Diger 11
bolgeyi gormesi **MUMKUN DEGILDIR**. Onlari bin olarak saymak,
ulasilamayan bir hedefe gore kapsam raporlamaktir.

## Cozum

Binler TCM ic yerlesimine gore yeniden tanimlandi:

    tcm_girdi    0x00000-0x007A8   girdi tensoru (490 kelime)
    tcm_serbest  0x007AC-0x037FC   serbest alan
    tcm_agirlik  0x03800-0x0767C   FC agirliklari (4000 kelime)
    tcm_cikis    0x076B0-0x076BC   cikis (4 kelime)

Yeni olcum:

    tur %100,0   bolge %75,0   strb %33,3   yanit %33,3   TOPLAM %52,1

Bolge %8,3 -> **%75,0**. Artik gercek bir bilgi veriyor: dort TCM
bolgesinden ucu goruldu, biri gorulmedi (buyuk olasilikla
`tcm_serbest` - sartname geregi bos duran %40'lik alan).

# 4. KALAN EKSIKLER VE DEGERLENDIRME

## 4.1 strb %33,3 ve yanit %33,3 - BEKLENEN

Bu iki deger DUSUK ama **hedef degil**:

  - strb: motor TCM'e her zaman tam kelime yazar; bayt/yarim
    yazma bu yolda OLUSMAZ. (Kismi yazma ayri bir testle
    kapsandi: `tb_wstrb_kismi_yazma`, 11 denetim.)
  - yanit: slave `npu_tcm_axi_slave`'dir ve adres her zaman TCM
    icindedir; SLVERR/DECERR uretilmesi beklenmez. Binler yine
    de TUTULUYOR - gorulurlerse bu bir UYARIDIR.

Bu binleri silmek kapsami %100 gosterirdi ama bilgi kaybederdi.
Tutulup gerekcesi yazildi.

## 4.2 Aktif agent (sequencer + driver) - YAPILMADI

Sartname EK-3 "UVM-tabanli olasi scoreboarding faaliyetleri"
diyor; scoreboard VAR ve calisiyor. Aktif surucu ZORUNLU degil.

Yapilsaydi ne kazandirirdi:
  - rastgele/kisitli AXI trafigi uretilebilirdi
  - SLVERR/DECERR yollari zorlanabilirdi
  - kismi yazma desenleri bu arayuzde de gorulebilirdi

Neden yapilmadi:
  - Agent motorun IC arayuzune baglidir; oraya trafik enjekte
    etmek motorun kendi akisiyla CAKISIR ve gercek olmayan bir
    senaryo uretir.
  - Aktif surucu gereken yer SoC ana yoludur; orada zaten
    `interconnect_adres` testi 13 slave'i sinir adreslerinden
    dogruluyor (13 denetim) ve DECERR yollarini kapsiyor.
  - Yani aktif agent'in kazandiracagi seylerin cogu BASKA
    testlerle zaten kapsandi.

## 4.3 Yapilabilecekler (oncelik sirasi)

| Is | Kazanc | Maliyet |
|---|---|---|
| SoC ana yoluna IKINCI pasif agent | 12 bolgenin gercek kapsami | dusuk |
| Aktif agent (SoC yoluna) | rastgele trafik, DECERR zorlamasi | orta |
| npu_accelerator motor dali | kalan bilinen acik | orta |

En yuksek getirili: **SoC ana yoluna ikinci pasif agent**. Mevcut
altyapi aynen kullanilir, yalniz baglanti noktasi eklenir ve 12
bolgelik covergroup ORADA anlamli olur.

# 5. SONUC

Bu arastirma iki gercek sorun buldu ve duzeltti:

  1. Kapsam olculuyor ama raporlanmiyordu -> baglandi
  2. Adres binleri ulasilamayan hedefe goreydi (%8,3 yaniltici)
     -> baglanti noktasina gore duzeltildi (%75,0)

UVM testi: 35 denetim, 162.064 islem, 32/32 regresyon.

Kalan eksikler OLCULDU ve gerekceleri yazildi; hicbiri sartname
zorunlulugu degildir.
