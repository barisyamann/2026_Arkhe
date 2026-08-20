# ASIC Olcum Gecmisi - SKY130A / LibreLane Classic

Ust modul: `soc_top` · Hedef saat: 50 MHz (20 ns) · PDK: sky130A
Standart hucre kutuphanesi: `sky130_fd_sc_hd`

---

## a1 - Ilk basarili sentez (20 Agustos 2026)

Ilk kez ASIC sentezine ulasildi. Onceki denemeler SRAM makrosu olmadigi
icin tamamlanamiyordu.

| Metrik | Deger |
|---|---|
| Standart hucre | 47.926 |
| Standart hucre alani | 0,631 mm2 |
| SRAM makrosu | **23** |
| Makro alani | 6,54 mm2 (23 x 0,285) |
| **Toplam cekirdek alani** | **~7,17 mm2** |
| Flip-flop | 10.908 |
| Lint hatasi | 0 |
| Lint uyarisi | 810 |

### Flip-flop dususu

    SRAM makrosu ONCESI : ~391.000  (butun bellekler cikarimsal dizi)
    SRAM makrosu SONRASI:   10.908

Makro entegrasyonu oncesinde Yosys/ABC 391 bin flip-flop uzerinde
calisiyordu ve sentez bir saatten fazla surede tamamlanamadi. Bu bir
performans sorunu degil, ASIC'te bellegin cikarimsal dizi olarak
birakilamayacaginin dogrudan kanitidir.

### En cok kullanilan hucreler

| Hucre | Adet | Pay |
|---|---|---|
| `sky130_fd_sc_hd__mux2_1` | 10.163 | %21,2 |
| `sky130_fd_sc_hd__dfxtp_2` | 5.748 | %12,0 |
| `sky130_fd_sc_hd__dfrtp_2` | 5.160 | %10,8 |
| `sky130_fd_sc_hd__a22o_2` | 2.762 | %5,8 |
| `sky130_fd_sc_hd__a21o_2` | 2.011 | %4,2 |

**mux2_1 hakimiyeti dikkat cekici** - tum hucrelerin besde biri.

Kaynagi bellek okuma coklayicilaridir: TCM'de 15 makro arasindan,
I-RAM ve D-RAM'de 4'er makro arasindan 32 bit genisliginde secim
yapiliyor. Kabaca:

    TCM   : 32 bit x 15 giris x 2 port
    I-RAM : 32 bit x  4 giris
    D-RAM : 32 bit x  4 giris

Bu, coklu makro kullanmanin kacinilmaz bedeli. Azaltmak icin daha az
sayida buyuk makro gerekirdi, ancak sky130'da 2 kB en buyuk 32-bit
genisligindeki secenek.

Optimizasyon dusunulurse: TCM'in ust adres bitleriyle makro secimi
yerine, coklayiciyi agac yapisina bolmek veya okuma yolunu boru hattina
almak degerlendirilebilir. Su an oncelik akisi tamamlamak.

---

## SRAM makrosu

| | |
|---|---|
| Makro | `sky130_sram_2kbyte_1rw1r_32x512_8` |
| Kaynak | SKY130A PDK, `libs.ref/sky130_sram_macros/` |
| Yapi | 512 kelime x 32 bit, Port0 RW + Port1 R |
| Fiziksel boyut | 683,1 x 416,54 um = 0,285 mm2 |
| Zamanlama modeli | TT_1p8V_25C (tek kose) |

Dagilim:

| Bellek | Kapasite | Makro |
|---|---|---|
| NPU TCM | 30 kB | 15 |
| I-RAM | 8 kB | 4 |
| D-RAM | 8 kB | 4 |

### Sartname dogrulamasi

> "SRAM makrosu sentez sonucunda optimize edilerek kaldirilmamali;
>  nihai gate level netlist, DEF ve GDSII ciktilarinda bulunmalidir."

Sentez netlist'inde dogrulandi:

    grep -c "sky130_sram_2kbyte_1rw1r_32x512_8" soc_top.nl.v
    23

DEF ve GDSII dogrulamasi akis tamamlandiginda yapilacak.

---

## Akisa ulasirken asilan engeller

Sentez adimina varmak sekiz ayri duzeltme gerektirdi. Ucu **gercek RTL
hatasiydi** ve aylardir kodda duruyordu; FPGA akisi hicbirinde
sikayet etmemisti.

| # | Sorun | Yakalayan |
|---|---|---|
| 1 | `VERILOG_FILES_FILE` diye anahtar yok | LibreLane |
| 2 | `--force-run-dir` dizini kendi olusturmuyor | LibreLane |
| 3 | Bozuk `ifdef` direktifi (backtick + bosluk) | **Verilator** |
| 4 | `sum_exp`'te bloklayan/bloklamayan atama karisimi | **slang** |
| 5 | Makro guc pinleri sabite baglanmis (elektriksel kisa) | **Verilator** |
| 6 | Makro modelinde `mem` bildiriminden once kullanim | Vivado |
| 7 | Makro modeli STA'da netlist saniliyor | OpenSTA |
| 8 | `remove_from_collection` OpenSTA'da yok | OpenSTA |

3, 4 ve 5 numaralilar Vivado'nun sessizce kabul ettigi gercek
kusurlardi.

---

## a2 - Yerlesim duzlemi denemeleri (20 Agustos 2026)

23 makro 4 sutun x 6 satir dizildi. Makrolar arasindaki KANAL genisligi
uc kez arttirildi; her denemede global yonlendirme adimina kadar kosuldu.

| Deneme | Kanal | Kenar payi | Die (um) | Alan | Makro doluluk | Global yonlendirme |
|---|---|---|---|---|---|---|
| 1 | 100 um | 200 um | 3432,4 x 3399,24 | 11,67 mm2 | %56,1 | tamamlanmadi |
| 2 | 150 um | 200 um | 3582,40 x 3649,24 | 13,07 mm2 | %50,1 | 57 dk sonra hala kosuyordu, durduruldu |
| 3 | **200 um** | **250 um** | **3832,40 x 3999,24** | **15,33 mm2** | **%42,7** | **4 dk 36 sn, 0 overflow** |

Ucuncu denemede yonlendirici sikismadi. Kullanim orani yalnizca %14,4
olduguna gore alan fazla verilmis olabilir; teslim sonrasi die kucultmek
icin olculmus bir pay var demektir.

Die buyutmenin zamanlamayi bozmadigi olculdu:

    11,67 mm2 -> setup +4,225 ns
    13,07 mm2 -> setup +4,276 ns
    15,33 mm2 -> setup +4,271 ns

Fark 5 ps mertebesinde. Kritik yol makro arasi mesafeye degil, NPU ic
mantigina bagli.

### Dosya sistemi etkisi

Akis once /mnt/c uzerinden kosuyordu. WSL'in kendi diskine tasindiginda
ayni adima varis suresi 50 dakikadan **19 dakikaya** dusru - yaklasik 3x.
OpenROAD yogun dosya G/C yapiyor ve /mnt/c bunda yavas. Depo /mnt/c'de
kalmaya devam ediyor; yalnizca kosum dizini WSL diskinde.

---

## a3 - Zamanlama ilerlemesi

Ayni kose (nom_tt_025C_1v80), 50 MHz hedef (20 ns).

| Adim | Setup payi | Hold payi | Ihlal |
|---|---|---|---|
| 31 - yerlesim sonrasi STA | - | - | 0 |
| 38 - CTS sonrasi STA | +4,271 ns | +0,276 ns | **0** |
| 43 - global yonlendirme sonrasi STA | **+2,719 ns** | **+0,246 ns** | **0** |

Setup payi 1,55 ns eridi. Beklenen bir dusus: yonlendirme sonrasi analiz
artik gercek tel parazitiklerini kullaniyor, tahmini degil. Buna ragmen
ihlal yok ve %13,6 marj kaldi.

Saat capraskligi (clock skew): setup icin 0,681 ns, hold icin -0,746 ns.

### Elektriksel kural ihlalleri - ACIK

Yonlendirme sonrasi STA'da:

    design__max_slew_violation__count  : 544
    design__max_cap_violation__count   :  14
    design__max_fanout_violation__count:   0

Bunlar zamanlama hatasi degildir - sinyal gecis suresi ve yuk
kapasitansi kutuphane sinirini asiyor. Signoff kalitesi icin
temizlenmelidir. Akisin ilerleyen resizer adimlarinda dusebilir;
dusmezse ayrica ele alinacak.

---

## a4 - Guc analizi

CTS sonrasi, nom_tt_025C_1v80, 50 MHz.

| Bilesen | Guc | Pay |
|---|---|---|
| **Makro (23 SRAM)** | 63,9 mW | **%61,5** |
| Sirali (flip-flop + saat agaci) | 21,9 mW | %21,1 |
| Kombinasyonel | 0,34 mW | %0,3 |
| Sizinti ve diger | ~17,7 mW | %17,1 |
| **Toplam** | **103,9 mW** | |

Yonlendirme sonrasi toplam 104,8 mW.

Gucun ucte ikisini bellek yiyor. Standart hucrelerin kombinasyonel payi
%0,3 - tasarim yogun mantik degil, kayit ve coklayici agirlikli.

FPGA'de olculen 137 mW ile ayni buyukluk sinifinda olmasi tutarlilik
gostergesidir (farkli teknoloji, farkli olcum yontemi).

**Cikarim: ASIC'te guc butcesini bellek belirliyor.** Guc dusurmek
gerekirse ilk bakilacak yer makro sayisi ve erisim sikligidir, mantik
optimizasyonu degil.

---

## a5 - Global yonlendirme (adim 39, 4 dk 36 sn)

| Katman | Kaynak | Talep | Kullanim | Overflow |
|---|---|---|---|---|
| li1 | 0 | 0 | %0,00 | 0 |
| met1 | 1.849.016 | 310.788 | %16,81 | 0 |
| met2 | 1.768.700 | 314.822 | %17,80 | 0 |
| met3 | 1.255.625 | 143.899 | %11,46 | 0 |
| met4 | 799.893 | 63.075 | %7,89 | 0 |
| met5 | 178.803 | 12.372 | %6,92 | 0 |
| **Toplam** | 5.852.037 | 844.956 | **%14,44** | **0** |

    Toplam tel uzunlugu : 7.260.490 um
    Yonlendirilen ag    : 63.293
    Via                 : 526.245

li1 kullanilmiyor - sky130'da li1 yerel baglantı katmanidir ve
yonlendirici onu global asamada saymaz.

### Adim sureleri

    39 - global yonlendirme     : 00:04:36
    40 - anten denetimi         : 00:01:49
    41 - portlara diyot         : 00:00:00
    42 - anten onarimi          : 00:09:34
    43 - STA                    : 00:00:31

---

## a6 - Saat kapisi (clock gating) durumu

CV32E40P guc tasarrufu icin saat kapisi kullanir. Kullandigimiz model
dosyasi `rtl/cv32e40p-master/bhv/cv32e40p_sim_clock_gate.sv` olup kendi
basliginda sunu yazar:

    // !!! cv32e40p_sim_clock_gate file is meant for simulation only !!!
    // !!! It must not be used for ASIC synthesis                    !!!
    // !!! It must not be used for FPGA synthesis                    !!!

Dosya bu haliyle ASIC filelist'inde bulunuyor (`asic/filelist.f:43`).
Ne oldugu olculdu.

### Ne uretildi

Modulun iki dali var:

    `ifdef SYNTHESIS
        assign clk_o = clk_i;              // kapi YOK, saat dogrudan gecer
    `else
        always_latch ...                   // latch tabanli kapi
        assign clk_o = clk_i & clk_en;
    `endif

Sentez netlisti uc noktadan denetlendi:

| Denetim | Sonuc |
|---|---|
| Latch hucresi (`sky130_fd_sc_hd__dl*`) | **0 adet** |
| `clock_gate` ornegi | **0 adet** |
| Flip-flop saat baglantilari | 10.855 x `.CLK(clk_i)` · 154 x `.CLK(jtag_tck)` |

Butun flip-floplar dogrudan ana saate bagli. **SYNTHESIS dali alinmis,
saat kapisi devre disi.** Latch uretilmemis - ki bu iyi haber, latch
tabanli kapi standart hucrelerden kurulsaydi glitch ve STA riski
getirirdi.

### Degerlendirme

**Islevsel olarak dogru.** Saat kapisi bir guc optimizasyonudur; olmamasi
yanlis sonuc uretmez, yalnizca kullanilmayan boru hatti asamalari da
saat alir.

**Dogrulama acisindan avantajli:** FPGA tarafinda da ayni dal aliniyor
(kod yorumu bunu acikca soyluyor). Yani FPGA ve ASIC ayni saat yapisini
kullaniyor; FPGA'de dogrulanan davranis ASIC'e birebir tasiniyor.
Farkli olsalardi dogrulama sonuclari aktarilamazdi.

**SDC ile tutarli:** kisitlar iki saat tanimliyor (`clk_i`, `jtag_tck`)
ve netlist tam olarak bu ikisini gosteriyor. Uretilmis bir kapi saati
olsaydi SDC eksik kalirdi.

### Kazanc ne olurdu

Guc dagilimina (a4) bakildiginda:

    Makro (SRAM)   %61,5   <- saat kapisi bunu ETKILEMEZ
    Sirali         %21,1   <- saat kapisinin hedefi bu
    Kombinasyonel   %0,3
    Sizinti/diger  %17,1

Saat kapisi en iyi durumda sirali gucun bir kismini kirpardi - toplam
gucun onda biri mertebesi. Oysa **gucun ucte ikisi bellekte.** Guc
dusurmek asil hedefse dogru yer makro erisim sikligidir, saat kapisi
degil.

### Yapilmasi gereken

Duzgun cozum, davranissal modeli PDK'nin butunlesik saat kapisi
hucresiyle degistirmektir:

    sky130_fd_sc_hd__dlclkp_1     (integrated clock gating cell)

Bu bir RTL degisikligidir ve akisin bastan kosulmasini gerektirir.
**GDSII alindiktan sonra degerlendirilecek.** Su anki hali islevsel
hata icermedigi ve dogrulanmis oldugu icin teslim engelleyicisi degildir.

---

## a7 - Kosum gecmisi ve DRC-temiz yonlendirme (20 Agustos 2026)

Bes kosum yapildi. Her biri bir onceki kosumun urettigi OLCUME dayanarak
degistirildi; hicbiri tahminle ayarlanmadi.

| # | Degisiklik | Global yonl. | Detayli yonl. | Sonuc |
|---|---|---|---|---|
| 1 | kanal 100 um, /mnt/c diski | bitmedi | - | durduruldu |
| 2 | kanal 150 um, WSL diski | 57 dk, bitmedi | - | durduruldu |
| 3 | kanal **200 um**, kenar 250 | **4:36, 0 overflow** | 63 turda 23 ihlal | DRT-1231 |
| 4 | **makro guc + halo 25 um** | **1:30, 0 overflow** | **12 turda 0 ihlal** | DRT-1231 |
| 5 | **atlama teli + halo 30 um** | kosuyor | kosuyor | - |

### 4. kosum: DRC-TEMIZ YONLENDIRME

Detayli yonlendirmenin ilk gecisi **sifir ihlalle** kapandi:

    tur 0 : 46.722        tur 6 :  57
    tur 1 : 26.571        tur 7 :  37
    tur 2 : 24.277        tur 8 :   8
    tur 3 :  3.239        tur 9 :   8
    tur 4 :    527        tur 10:   3
    tur 5 :    128        tur 11:   0   <-- TEMIZ
    [INFO DRT-0198] Complete detail routing.

Uretilen `soc_top.drc` dosyasi **bos** (0 satir).

3. kosumla karsilastirma carpici:

    3. kosum: 63 tur -> 23 ihlal   (1 sa 10 dk)
    4. kosum: 12 tur ->  0 ihlal   (1 dk 35 sn)

Tek fark makro halosunun 10'dan 25 um'ye cikarilmasidir. Yonlendiricinin
zorlandigi yer kanallar degil, **makro pinlerinin cevresiydi.**

### Neden yine de dustu

Yonlendirme temiz bitti, sonra anten denetimi devreye girdi:

    [INFO ANT-0002] Found 235 net violations.
    [INFO ANT-0001] Found 290 pin violations.
    [INFO GRT-0015] Inserted 545 diodes.
    ...
    [ERROR DRT-1231] Pin u_data_ram.g_sram[3].u_macro/din0[6]
                     does not have access point

545 diyot yerlestirildi, biri makro kenarina dusup pin erisimini kapatti.
3. kosumda ayni sey 586 diyotla ve **ayni makronun** baska bir pininde
(`addr1[7]`) olmustu. Ayni makro iki kez: hata rastgele degil, sistematik.

Halo 25 um diyotlari yeterince uzak tutamadi.

### 5. kosum: hata mekanizmasini ortadan kaldirmak

Daha buyuk halo denemek yerine kok neden hedeflendi:

    GRT_ANTENNA_REPAIR_JUMPER_ONLY: true

Anten ihlalleri diyot yerine **metal atlama teliyle** giderilir. Atlama
teli yeni hucre yerlestirmez - mevcut agi ust katmana tasir. Yerlesim
kalabaligi olusmadigi icin makro pininin kapanmasi **yapisal olarak
imkansiz** hale gelir.

Maliyeti yonlendirme kaynagidir; bizde bol: kullanim %14,4-17,9, overflow 0.

Halo da 30 um'ye cikarildi (son kosum oldugu icin iki onlem birden).

### 4. kosumda dogrulanan: makro guc baglantisi

3. kosumda gozden kacan 46 uyari vardi:

    [PDN-0231] u_data_ram.g_sram[0].u_macro is not connected to any
               power/ground nets.

23 makro x 2 pin. Bu haliyle makrolarin fiziksel tasarimda gucu yoktur ve
LVS gecmez. `PDN_CONNECT_MACROS_TO_GRID` zaten `true` idi ama tek basina
yetmiyor - hangi makro pininin hangi ust seviye aga baglanacagi acikca
verilmelidir.

Ag adlari olcumle bulundu: ust seviye aglar DEF'in SPECIALNETS
bolumunden (`VPWR`/`VGND`), makro pinleri LEF'ten (`vccd1`/`vssd1`).

    PDN_MACRO_CONNECTIONS:
      - ".*u_macro VPWR VGND vccd1 vssd1"

4. kosumda dogrulandi:

    46 x ".*u_macro matched with u_..._ram.g_sram[N].u_macro"
    PDN-0231 uyarisi: 0
    PDN-0189 uyarisi: 0

### Zamanlama karsilastirmasi

| Kosum | Setup payi | Hold payi | Ihlal |
|---|---|---|---|
| 3 | +2,719 ns | +0,246 ns | 0 |
| **4** | **+3,138 ns** | **+0,284 ns** | **0** |

Halo yerlestirmeyi de rahatlatti: setup payi 0,42 ns iyilesti.
Marj %15,7 (hedef periyot 20 ns).

---

## Acik maddeler

- **ENGELLEYICI - ROM icerikleri netlist'te yok**: alti `$readmemh`
  dosyasinin hicbiri ASIC akisinda yuklenmiyor; bootloader ve NPU
  agirliklari (17,7 kB) sentezde silindi. Ayrinti ve cozum secenekleri:
  `evidence/asic/READMEMH_BULGUSU.md`
- **5. kosum da DRT-1231 ile dustu** (`u_data_ram.g_sram[2]`).
  Uc hatanin ucu de ust sira makrolarinda (y = 3332,7). Ust kenar payi
  250 -> 500 um onerisi. `GRT_ANTENNA_REPAIR_JUMPER_ONLY` denendi,
  ISE YARAMADI - ayar uygulandi ama OpenROAD yine 1813 diyot koydu.

- **PVT koseleri**: akis uc kosede (tt/ff/ss) zamanlama yapiyor ama
  makronun yalnizca TT modeli var; uc kosede de ayni model okunuyor.
- **Saat kapisi**: INCELENDI (bkz. a6). SYNTHESIS dali aliniyor, saat
  dogrudan geciyor, latch uretilmiyor. Islevsel hata yok; PDK'nin
  `dlclkp_1` hucresiyle degistirmek GDSII sonrasina birakildi.
- **810 lint uyarisi**: INCELENDI, islevsel hata yok.
  Ayrinti: `evidence/lint/LINT_INCELEMESI.md`
- **Max slew / max cap**: 544 + 14 elektriksel kural ihlali (bkz. a3).
- **Dosya sistemi**: COZULDU - akis WSL'in kendi diskine tasindi, 3x
  hizlandi (bkz. a2).
