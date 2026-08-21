# Karar Gunlugu - Arkhe SoC

21 Agustos 2026 · Takim Arkhe

Bu belge projede alinan tasarim kararlarini, denenip GERI ALINAN
girisimleri ve RTL seviyesinde yapilan degisiklikleri tek yerde toplar.
Her karar icin gerekce ve mumkun oldugunca OLCUM verilmistir.

---

# BOLUM 1 - TASARIM KARARLARI

## 1.1 Komut seti: RV32IMFC -> RV32IMC (FPU = 0)

**OTR'de ne yaziyordu:** Bolum 3.6.2 - *"CV32E40P ... RV32IMFC
eklentilerini desteklemektedir. Floating-Point (F) eklentisi hassasiyet
isteyen matematiksel islemlerde dogrudan ivme katar."*

**Ne yapildi:** Cekirdek `FPU = 0` ile yapilandirildi. Uygulanan komut
seti RV32IMC'dir.

**Gerekce - OLCULDU, tahmin degil:**

| | FPU = 0 | FPU = 1 | Fark |
|---|---|---|---|
| LUT | temel | +2.344 | ek maliyet |
| Flip-flop | temel | +1.048 | ek maliyet |
| FPU hucresi | 0 | 17 | - |

NPU tamamen **tamsayi aritmetigiyle** calisir (INT8 agirliklar, INT32
biriktiriciler, Q0.12 softmax). Kayan nokta hicbir yerde kullanilmiyor.
FPU kaynak yiyor, karsiliginda hicbir sey uretmiyor.

**Kanit:** `evidence/fpga/fpu_karar_olcumu.md`

**Sapma durumu:** OTR gonderilmis belgedir, degistirilemez. Depodaki
butun guncel belgeler RV32IMC olarak duzeltildi ve gerekce baglantisi
eklendi.

---

## 1.2 NPU agirliklari nereye konacak

17,7 kB tablo (`fc_weights` tek basina %86'si). Uc secenek degerlendirildi.

### Secenek A - hepsini mantik olarak sentezle
### Secenek B - QSPI flash'tan SRAM'e yukle
### Secenek C - melez (fc_weights SRAM'e, kalani mantik)

**Once tahmin edildi:**

    fc_weights 14 bit adres, yuksek entropili INT8 veri
    Shannon tabani : 2^14/14 x 8 = ~9.400 kapi
    Mux agaci      : ~131.000 mux, optimizasyonla 65-90 bin hucre
    Beklenen       : 40.000 - 90.000 hucre

Bu aralik karar vermeye yetmiyordu, **olculdu.**

**Olcum sonucu:**

| | Iceriksiz | Tablolar gomulu | Fark |
|---|---|---|---|
| Standart hucre | 47.926 | 87.850 | **+39.924** |
| Cip alani | 0,631 mm2 | 1,028 mm2 | +%63 |

Gercek deger **39.924** - tahmin araliginin ALT SINIRINDA. Yosys
`memory_bmux2rom` ile 259.143 donusum yapip verimli ROM kodlamasi uretti,
saf coklayici agaci kurmadi.

**Alan hesabi:**

    Die (ust pay 500 um)     16,28 mm2
    Makrolar (23 x 0,285)   - 6,55 mm2
                            ----------
    Standart hucreye kalan    9,73 mm2
    Kullanilan                ~1,3 mm2  ->  %13 doluluk

**KARAR: Secenek A - mantik olarak birakildi.**

B ve C secenekleri +8/+9 makro, die %20-37 buyume, bootloader eklentisi
ve yeni bir SRAM blogu gerektiriyordu. Alan sigdigi icin hicbiri gerekli
olmadi. **Yaklasik bir gunluk is tasarrufu.**

**Onemli not:** Agirliklarin 1 kB'lik boot ROM'a konmasi teklif edildi ve
MUMKUN OLMADIGI icin reddedildi - 17,7 kB, boot ROM'un 17,7 katidir.

**Kanit:** `evidence/asic/READMEMH_BULGUSU.md`

---

## 1.3 ROM tablolarinin RTL bicimi

Tablolari gomerken iki bicim denendi.

**Bicim 1 - unpacked localparam dizisi:**

    localparam logic signed [7:0] FC_WEIGHTS [0:15999] = '{...};

**Bicim 2 - parcali packed vektor + erisim fonksiyonu:**

    localparam logic [32767:0] FC_WEIGHTS_DUZ0 = 32768'h...;
    function automatic logic signed [7:0] fc_weights(input logic [13:0] i);

**Olcum - ayni tablo, iki bicim, ayni arac:**

| Arac | unpacked | parcali packed |
|---|---|---|
| Verilator lint | 0,4 sn | temiz |
| Yosys sentez | 20:32 | 42:42 |
| **Vivado xelab** | **240 sn'de BITMEDI** | **2,5 sn** |
| Yosys hucre sayisi | 87.850 | **109.963** |

**Sebep:** unpacked dizi elaboratore gore **16.000 ayri nesnedir**;
Vivado her biri icin sembol tablosu girisi ve tip analizi yapar.
Verilator ve Yosys ic temsilde hemen duzlestirdigi icin etkilenmez.

**Parcalama neden gerekli:** Verilator sayi sabitlerinde **65.536 bit**
sinirina sahip. Olculdu: 65.536 tamam, 98.304 *"Width of number exceeds
implementation limit"*. `fc_weights` 128.000 bit oldugu icin 4 parcaya
bolundu.

**KARAR: Bicim 2.** Maliyeti +%25 hucre ve +%108 sentez suresi; alternatif
Vivado'nun hic calismamasiydi ve FPGA akisina ihtiyacimiz var.

**REDDEDILEN alternatif:** `ifdef` ile araca gore bicim secmek. Tam olarak
kurtulmaya calistigimiz araclar-arasi ayrisma budur.

---

## 1.4 Bellek: cikarimsal dizi -> SRAM makrosu

**Sorun:** Butun bellekler cikarimsal dizi (`logic [31:0] ram [...]`)
olarak yazilmisti. FPGA'de Vivado bunlari Block RAM'e esliyor. ASIC'te
boyle bir esleme yok - her bit bir flip-flop olur.

**Olcum:**

    SRAM makrosu ONCESI : ~391.000 flip-flop, sentez 1 saatte bitmedi
    SRAM makrosu SONRASI:   10.908 flip-flop

**KARAR:** 23 adet `sky130_sram_2kbyte_1rw1r_32x512_8`.

    NPU TCM  30 kB -> 15 makro
    I-RAM     8 kB ->  4 makro
    D-RAM     8 kB ->  4 makro

RTL cift gerceklemeli yazildi: `USE_SRAM_MACRO` tanimliyken makro,
tanimsizken cikarimsal dizi (FPGA icin). Regresyon iki kipte de kosar.

---

## 1.5 Dogrulama: tam UVM yerine hedefli dogrulama

**OTR bolum 3.9 zaten bunu secmisti:**

> *"Proje takvimi goz onune alinarak tam tesekkullu UVM yerine, AXI veri
> yollarinin guvenilirligini saglamak icin Hedefli Dogrulama yaklasimi
> izlenecektir."*

Vaat edilen dort maddenin dordu de karsilandi: AXI SVA denetleyicisi,
assertion'lar, kendi kendini kontrol eden testbench'ler, kapsama
metrikleri.

**Sapma yok** - planlanmis bir tercih.

---

# BOLUM 2 - DENENIP GERI ALINAN KARARLAR

Bu bolum onemli: yanlis cikan hipotezler de kayda gecmelidir.

## 2.1 R10 - OBI->AXI koprusunde cevrim kazanimi (IKI KEZ GERI ALINDI)

**Hipotez:** Kopru her islemde `ST_IDLE`'a ugruyor; bu cevrim bosa
gidiyor. Atlanirsa islem basina bir cevrim kazanilir.

**1. deneme:** Calisti ama zamanlama bozuldu - WNS 2,147 -> 0,529 ns.
Geri alindi.

**2. deneme:** **Islevsel olarak YANLIS cikti.** CV32E40P yanit beklerken
`req`'i yuksek tutabiliyor, ustelik eski adresle. Kod ayni islemi ikinci
kez baslatiyordu. Simulasyon 10 hata verdi, UART hic cikti uretmedi.

**Ogrenilen:** `ST_IDLE`'daki cevrim bosa gitmiyor - CPU'nun `req`/`addr`
guncellemesi icin gereken ayrim noktasi.

**Durum:** R10 bilerek ACIK birakildi (denetimde "Risk", engelleyici degil).

## 2.2 Kanal genisligi - YANLIS HIPOTEZ

Uc kosum boyunca makrolar arasi kanal genisletildi:

| Kosum | Kanal | Die | Sonuc |
|---|---|---|---|
| 1 | 100 um | 11,67 mm2 | global yonlendirme bitmedi |
| 2 | 150 um | 13,07 mm2 | 57 dk sonra hala kosuyordu |
| 3 | 200 um | 15,33 mm2 | gecti (4:36, 0 overflow) |

**Ama asil darbogaz kanal degildi.** 4. kosumda makro HALOSU 10 -> 25 um
yapilinca:

    3. kosum (halo 10): 63 tur -> 23 ihlal, 1 sa 10 dk
    4. kosum (halo 25): 12 tur ->  0 IHLAL, 1 dk 35 sn

Global yonlendirme de 4:36 -> 1:30 hizlandi.

**Ogrenilen:** Sikisiklik makrolar ARASINDA degil, makro PINLERININ
CEVRESINDEydi. Sikisiklik raporu bunu zaten soyluyordu - kullanim yalnizca
%14,4'tu, yani yer boldu - ama yanlis yere bakildi.

## 2.3 Anten onarimi: yalnizca atlama teli - ISE YARAMADI

**Hipotez:** Anten onarimi diyot yerlestiriyor, diyotlar makro pinini
kapatiyor. `GRT_ANTENNA_REPAIR_JUMPER_ONLY: true` ile diyot yerine metal
atlama teli kullanilirsa yerlesim kalabaligi olusmaz.

**Sonuc:** Ayar uygulandi (adimin `config.json`'unda `true` gorunuyor)
ama **OpenROAD yine diyot koydu - hem de 1813 tane** (onceki kosumda 545).
Log: `Unable to repair antennas on net with diodes`.

**Ogrenilen:** Atlama teli yetmeyince arac diyota dusuyor; ayar mutlak
degil. Ayrica: bir ayarin davranisini DOGRULAMADAN ona bir kosum
yatirilmamali.

## 2.4 Spike ISS karsilastirmasi - GERI CEKILDI

`compare_trace.py` *"referans model ile %100 uyumludur"* ciktisi
uretiyordu. Denetimde ortaya cikti ki **Spike hicbir zaman kurulmadi**;
"referans model" dedigi sey koda elle yazilmis 20 adreslik sabit bir
diziydi. Ustelik dizi guncel bootloader'a uymuyordu - `0x08` ve `0x0a`
adreslerindeki RV32C sikistirilmis buyruklari atliyordu.

Betik kaldirildi. Yerine `trace_check.py` yazildi: referansi
`bootloader.elf`'in objdump ciktisindan uretir.

**Kanit:** `evidence/TAAHHUT_DENETIMI.md` bolum 1

---

# BOLUM 3 - RTL SEVIYESINDE YAPILAN DEGISIKLIKLER

## 3.1 GERCEK HATALAR (islevsel kusur, duzeltildi)

### (a) QSPI adres fazi 3 bayt yerine 1 bayt gonderiyordu

`rtl/Cevre_Birimleri/qspi_master.sv` - sayac karsilastirmasi bir kaymisti:

    - if (addr_byte_cnt == 3'd1)      // YANLIS
    + if (addr_byte_cnt == 3'd0)      // dogru

Aylardir kodda duruyordu. FPGA'de gorunmuyordu cunku varsayilan
simulasyon hizli boot kullaniyor ve QSPI yolu hic uyarilmiyordu.

### (b) UART_RDR bayt okuma kaymasi

`uart_stream_peripheral.sv` - FIFO cikisi KAYITLI oldugu icin her okuma
bir onceki bayti donduruyordu. Iki fazli okumaya cevrildi; bos FIFO'da
bloklamayacak sekilde.

### (c) Paketleyici bayt caliyordu

Ayni dosya - paketleyici, CPU'nun okumak istedigi baytlari FIFO'dan
onceden cekiyordu. `pack_arm` eklendi: yalnizca RDR32 okumasi beklerken
veri cekiyor.

### (d) Timer TIM_CLR / TIM_EVC SLVERR donduruyordu

`timer_peripheral.sv` - iki yazmac yazma cozucusunde eksikti. Bu hatayi
**yeni eklenen veri yolu hata kesmesi mekanizmasi yakaladi** - yani R8
eklenir eklenmez gercek bir hata buldu.

### (e) boot_rom AXI protokol ihlali

`soc_top.sv` - okuma kanalinda `RVALID`, `RREADY` gelene kadar
tutulmuyordu. AXI4-Lite ihlali.

### (f) i2c_peripheral: `sda_oe`/`scl_oe` iki kez bildirilmis

Hem port hem ic sinyal olarak. Proje derlemesinde uyari, tek basina
derlemede HATA.

### (g) TCM okuma verisi tutulmuyordu

`npu_tcm_sram.sv` - cikarimsal surumde `rdata` bir KAYITTI ve degerini
korurdu. Makro surumu kombinasyonel birakilmisti; `en` dustugu anda veri
kayboluyordu. AXI `rready` gecikmesi -> yonetici cop okuyor -> bootloader
I-RAM'i geri okuyamiyor -> CPU hic baslamiyor (8 hata).

Tutma mantigi eklendi:

    always_ff @(posedge clk) begin
        if (en_a_q) rdata_a_hold <= (inr_a_q ? dout_a[sel_a_q] : 32'h0);
    end
    assign rdata_a = en_a_q ? (...) : rdata_a_hold;

### (h) ROM icerikleri sentezde siliniyordu

`boot_rom.sv` ve `npu_compute_engine.sv` - alti `$readmemh` cagrisi
CIPLAK dosya adi kullaniyordu. LibreLane her adimi kendi dizininde
kosturdugu icin dosyalar bulunamiyor, tablolar tanimsiz (X) kaliyor,
Yosys de siliyordu.

**ASIC netlist'inde ne bootloader ne NPU agirliklari vardi.**

Cozum: degerler RTL'e gomuldu (`scripts/gen_rom_paketleri.py`).

## 3.2 ARAC UYUMSUZLUKLARI (Vivado kabul ediyordu, digerleri etmiyordu)

| # | Sorun | Reddeden |
|---|---|---|
| 1 | Bozuk `ifdef` - backtick'ten sonra bosluk | Verilator |
| 2 | `sum_exp`'te bloklayan/bloklamayan atama karisimi | slang |
| 3 | Makro guc pinleri sabite bagli (elektriksel kisa) | Verilator |
| 4 | `localparam` unpacked dizi (16.000 giris) | **Vivado** |

4 numarali ilginc: yon degistirdi. Ilk uc maddede Vivado sessizce kabul
ediyordu; dorduncude reddeden Vivado oldu.

## 3.3 BASARIM IYILESTIRMELERI

### R4 - NPU hizlandirmasi: 13,7x

**Asama 1 - kanal paylasimi (6,5x):** Girdi adresi yalnizca
(t_out, f_out, kh, kw)'ya baglidir; `d_out` adrese GIRMEZ. Yani sekiz
kanalin hepsi ayni girdi piksellerini okuyor, ayni 10x8 pencere sekiz kez
taraniyordu. Pencere bir kez okunup sekiz paralel biriktiriciye dagitildi.

**Asama 2 - okuma boru hatti (13,7x toplam):** TCM okuma cikisi
kayitlidir. Eski FSM bunu READ_REQ -> READ_WAIT -> MAC seklinde uc cevrime
yayiyordu. Iki asamali boru hattina cevrildi: `kh/kw` adresi verilen tap,
`mac_kh/kw` verisi hazir olan tap.

| | Once | Sonra |
|---|---|---|
| Cikarim | 19,84 ms | **1,45 ms** |
| Cevrim | 992.083 | **72.583** |
| DSP | 9 | **9** (degismedi) |

Sekiz paralel carpici LUT'a eslendi, DSP artmadi.

**Aritmetik degistirilmedi** - yalnizca cevrimlere yayildi. Sonuclar
bit-birebir ayni.

### Diger

- **FC boru hatti ayrimi:** requantization yolu 4 asamaya bolundu,
  sonuclar ayni, zamanlama kapandi.
- **WSTRB uyumlulugu:** 9 cevre biriminin hepsinde AXI4-Lite bayt
  maskeleme dogru gerceklendi (+585 LUT, neredeyse tamami maskeleme
  mantigi).
- **Tri-state ayrimi (G07):** `soc_top`'ta sifir `inout`, sifir `'z`.
  Tri-state yalnizca pad ring'de (`nexys_top.sv`).

## 3.4 ISLEVSEL EKLEMELER

### G05 - NPU kesme zinciri

Yoklama dongusu kaldirildi, sartname s.16'nin istedigi kesme mimarisi
kuruldu:

    NPU done -> npu_csr irq_o -> irq_vector[22] -> CV32E40P irq_i
      -> mtvec (0x01000200) -> trap_handler -> mret

`mtvec` 256 bayt hizali olmali (CV32E40P adresin yalnizca [31:8]
bitlerini saklar).

### G06 - UART-stream -> DMA -> hizlandirici bellegi

Sartname EK-1 s.21: *"UART-stream cevresel birimi cikarim yapilacak
veriyi iletecek ve bu veri istenilen hizlandirici bellek adresine
yazilacaktir."*

Onceden girdi tensorunu CPU bir dongude TCM'e yaziyordu. Artik:

    UART2 RX (1 Mbps) -> stream FIFO -> UARTS_RDR32
      -> DMA (SRC_FIXED) -> TCM 0x2001_0000 -> NPU

CPU yalnizca yazmaclari kuruyor ve `wfi` ile uyuyor.

### R8 - veri yolu hata kesmesi

`jtag_debug.sv` icinde hata yakalama yazmaclari:

    0x4008_0014  FAULT_ST    [0] hata, [1] instr kopru, [2] data kopru
    0x4008_0018  FAULT_ADDR
    0x4008_001C  FAULT_CLR

Ilk hata kazanir; hata, ayni cevrimde gelen temizleme isteginden
onceliklidir. Kaynak bir DARBE oldugu icin sonsuz kesme dongusu
yapisal olarak imkansiz.

**Not:** Bu mekanizma icin once "yalnizca gozlemlenebilir olsun, kesme
uretmesin" onerisi yapildi; kaptan itiraz etti ve HAKLI cikti - kesme
gerceklendi ve hemen (d) maddesindeki timer hatasini buldu.

---

# BOLUM 4 - FIZIKSEL TASARIM KARARLARI

| Parametre | Gecmis | Son | Gerekce |
|---|---|---|---|
| Kanal genisligi | 100 -> 150 -> 200 um | **200 um** | Yanlis hipotez; asil sorun halo idi |
| Makro halosu | 10 -> 25 -> 30 um | **30 um** | ASIL COZUM - yonlendirme 63 tur/23 ihlal -> 12 tur/0 ihlal |
| Ust kenar payi | 250 um | **500 um** | Uc kosum da UST SIRA makrolarinda dustu |
| Makro guc baglantisi | yok | `PDN_MACRO_CONNECTIONS` | 23 makronun gucu bagli degildi, LVS gecmezdi |
| Anten onarimi | varsayilan | atlama teli (ise yaramadi) | Bkz. 2.3 |
| Izgara | 4 sutun | **4 sutun** | 5 ve 6 sutun denendi, ikisi de daha buyuk (22,9 ve 23,8 mm2) |

**Dosya sistemi:** Akis `/mnt/c` uzerinden kosuyordu; WSL'in kendi diskine
tasindiginda ayni adima varis suresi 50 dk -> 19 dk (yaklasik 3x).

---

# BOLUM 5 - OZET SAYILAR

| Metrik | Deger |
|---|---|
| Standart hucre | 109.963 |
| Flip-flop | 11.586 |
| SRAM makrosu | 23 (46 kB) |
| Die | 3832,40 x 4249,24 um = 16,28 mm2 |
| Guc | 107,9 mW |
| NPU cikarim | 1,45 ms (13,7x hizlanma) |
| FPGA (eski olcum) | 18.587 LUT, +1,811 ns WNS, 137 mW |
| Regresyon | 6/6 test, 55 denetim |
| Lint | 0 hata |
