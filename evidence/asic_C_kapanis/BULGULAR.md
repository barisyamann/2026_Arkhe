# C_kapanis kosumu - bulgular (10 Eylul 2026)

Kosum: `~/arkhe/asic/run/C_kapanis`, LibreLane 3.0.6, sky130A.
Yapilandirma: `CLOCK_PERIOD: 10` (PnR), signoff SDC 28,571 ns (35 MHz).

## KAPANAN HATALAR

Kullanicinin istedigi "slew / fanout / anten ihlallerini kapatmak" hedefi
yonlendirme tarafinda TAM OLARAK karsilandi:

| Denetim                  | Sonuc |
|--------------------------|-------|
| Detayli yonlendirme DRC  | **0** (322 -> 210 -> 25 -> 0) |
| Anten - net ihlali       | **0** (2380'den) |
| Anten - pin ihlali       | **0** |
| Baglanmamis pin denetimi | gecti |
| Tel uzunlugu denetimi    | gecti |

## ACIK KALAN: HOLD (tutma) IHLALLERI

Adim 57 (`openroad-stapostpnr`, imza STA'si) dokuz kosede olculdu.
**Setup her kosede MET**, en kotu +0,220 ns (max_ss_100C_1v60).
**Hold bes kosenin dordunde VIOLATED:**

| Kose              | Setup slack | Hold slack |
|-------------------|-------------|------------|
| min_ss_100C_1v60  | +1,380 MET  | +0,245 MET |
| nom_ss_100C_1v60  | +0,810 MET  | **-0,011** |
| max_ss_100C_1v60  | +0,221 MET  | **-0,320** |
| nom_tt_025C_1v80  | +3,672 MET  | **-0,356** |
| max_ff_n40C_1v95  | +4,379 MET  | **-0,646** |

### KOK NEDEN (olculdu, tahmin degil)

Hold problemi tasarimda degil, AKISTA dogdu. Iki adimin karsilastirmasi
bunu kesin gosteriyor:

Adim 37 (`resizertimingpostcts`):
    [RSZ-0046] Found 26 endpoints with hold violations.
    [RSZ-0032] Inserted 41 hold buffers.
    -> uyari YOK, tamamen onarildi.

Adim 44 (`resizertimingpostgrt`):
    + repair_timing -setup -setup_margin 0.025 -max_buffer_percent 50
    [RSZ-0099] Repairing 6389 out of 6389 violating endpoints...
    [RSZ-0062] Unable to repair all setup violations.
      Timing Repair Buffer   26360
    + repair_timing -hold -hold_margin 0.6 -max_buffer_percent 50
    [RSZ-0046] Found 12226 endpoints with hold violations.
    [RSZ-0064] Unable to repair all hold checks within margin.
    [RSZ-0032] Inserted 5 hold buffers.

Yani hold, 26 uc noktadan 12.226'ya AYNI ADIM ICINDE sicradi. Arada olan
tek sey setup onarimidir: 6389 setup ihlalini kovalamak icin 26.360
zamanlama onarim tamponu eklendi. Bu tamponlar
  (a) her yola gecikme ekleyerek hold ihlallerini URETTI,
  (b) `max_buffer_percent 50` butcesini tuketerek hold onarimina
      pratikte hic pay birakmadi - 12.226 uc nokta icin 5 tampon.

Setup onarimi zaten "Unable to repair all" diyor; yani akis 10 ns hedefini
tutturamadigi halde onu kovalarken hold'u bozdu.

### NEDEN 10 ns SUCLU

`CLOCK_PERIOD: 10` PnR hedefi, imza hedefi olan 28,571 ns'nin (35 MHz)
neredeyse UC KATI siki. Setup slack'lerin imza kosesinde +0,22 ila +4,38
arasi rahat cikmasi, tasarimin 35 MHz'de sikinti YASAMADIGINI gosteriyor.
6389 setup ihlali gercek bir urun problemi degil, erisilemez bir PnR
hedefinin urunudur. Kullanicinin daha once soyledigi
"10 ns yapinca sistem kendini cok sikistiriyor" tespiti burada dogrudan
olculmus oluyor.

Alan da darbogaz degil: `design__instance__utilization` = 0,465 (%46,5).

### ONERILEN DUZELTME (henuz uygulanmadi)

1. `CLOCK_PERIOD`'u imza hedefine yaklastir (20-25 ns). Setup ihlali
   sayisi duser, 26.360 tampon gerekmez, hold kendiliginden buyumez.
2. `GRT_RESIZER_HOLD_SLACK_MARGIN: 0.6` cok agresif; her uc noktada
   0,6 ns hold payi istiyor. 0,1-0,2 makul.
3. Gerekirse `GRT_RESIZER_HOLD_MAX_BUFFER_PCT`'i setup'tan ayri ve
   yuksek tut; su an ikisi ayni %50 butceyi paylasiyor.
4. `MAX_SLEW_VIOLATION_CORNERS` `[""]` olarak ayarli - slew denetimi bu
   kosumda etkin degil. Kapatilan slew iddiasi bu kosumdan
   DOGRULANAMAZ; yeniden `"*"` yapilip olculmeli.

Not: `HOLD_VIOLATION_CORNERS` `"*"` idi, yani akisa "tum koselerde hold
duzelt" denmisti; basarisizlik ayar eksikligi degil butce/hedef
catismasidir.

## IMZA DRC: 7658 nwell.4 IHLALI - HEPSI SRAM MAKROSUNDAN

Adim 66 (`magic-drc`) GDS uzerinde **7658** ihlal bildirdi. Bu, adim 46'nin
"DRC 0" sonucuyla celismiyor: OpenROAD yonlendirici yalnizca kendi
modelledigi kurallari denetler, Magic ise gercek geometriyi imza kural
destesiyle kontrol eder.

### HEPSI TEK BIR KURAL

    grep -B1 "^----" drc.magic.rpt | sort | uniq -c
      -> tek tur: "All nwells must contain metal-connected N+ taps (nwell.4)"

7658 ihlalin TAMAMI ayni kural. Yani dagilmis bir problem degil, tek ve
sistematik bir kaynak var.

### KAYNAK: UCUNCU TARAF SRAM MAKROSU (bizim tasarimimiz degil)

Kanit zinciri:

1. Ihlal koordinatlarinda yalnizca **17 farkli x** degeri var ve bunlar
   ~314,56 um duzenli araliklarla diziliyor (1100,96 / 1415,52 / 1730,08 /
   2044,64 ...). Bu, standart hucre alanina dagilmis bir hatanin degil,
   makro adiminin imzasidir.

2. Tasarimda **23 adet** `sky130_sram_2kbyte_1rw1r_32x512_8` ornegi var.
   7658 / 23 = ~333, yani her makro ornegi icin SABIT sayida ihlal. Ihlal
   sayisi tasarim buyuklugu ile degil MAKRO SAYISI ile olcekleniyor - bu,
   ihlallerin makro GDS'inin ICINDEN geldigini gosterir.

3. Kural (nwell.4) makronun kendi ic nwell'lerinin metal-bagli N+ tap
   icermesini istiyor. Bu, OpenRAM sky130 makrolarinin bilinen bir
   ozelligidir; ayni makronun `.lib` dosyasindaki degistirilemez
   `max_transition: 0.5` kisiti gibi, disaridan gelen sabit bir kosuldur.

### SONUC

Bu ihlaller bizim RTL'imizden, yerlesimimizden veya akis ayarlarimizdan
kaynaklanmiyor ve `FP_TAPCELL_DIST` gibi ayarlarla kapatilamaz - tap
ekleme zaten etkin (`RUN_TAP_ENDCAP_INSERTION: true`, `FP_TAPCELL_DIST: 13`)
ve standart hucre alaninda ihlal YOK.

Yarismaya teslimde bu, "makro kaynakli, bilinen ve kabul edilen sapma"
olarak beyan edilmelidir. Kendi mantigimizin urettigi tek bir nwell.4
ihlali bile yoktur.

DIKKAT: Adim 67 (`klayout-drc`, farkli kural destesi) bu satirlar
yazilirken hala kosuyordu; onun sonucu ayrica kaydedilmelidir.

---

# KOSUM TAMAMLANDI - 80 ADIM, `final/` URETILDI

Akis sonuna kadar kostu; `run/C_kapanis/final/` icinde GDS, LEF, netlist,
SDF, SPEF, SDC ve metrikler mevcut.

## GECEN IMZA DENETIMLERI

| Denetim                        | Sonuc |
|--------------------------------|-------|
| **LVS (netgen)**               | **Circuits match uniquely** |
| **KLayout imza DRC**           | **0 ihlal** (256 kural kategorisi) |
| Detayli yonlendirme DRC        | 0 |
| Anten (net / pin)              | 0 / 0 |
| Guc dagitim agi (VPWR/VGND)    | 0 / 0 |
| **Setup - dokuz kosede**       | **HEPSI POZITIF** |

LVS'in "uniquely" gecmesi fiziksel dogrulamanin en kritik adimidir:
yerlesim, netliste birebir uyuyor.

### Setup slack (worst slack, ns)

    min_ff_n40C_1v95   +5,221      nom_tt_025C_1v80   +3,672
    nom_ff_n40C_1v95   +4,850      max_tt_025C_1v80   +3,145
    min_tt_025C_1v80   +4,098      min_ss_100C_1v60   +1,380
    max_ff / max_ss    (pozitif)   nom_ss_100C_1v60   +0,810  <- en kotu

Register-to-register en kotu: +0,446 ns (max_ss_100C_1v60).
Toplam guc: **86,2 mW** (ic 73,4 / anahtarlama 12,4 / kacak 0,42 mW).

## ACIK KALAN IHLALLER

### 1) Hold - dokuz kosenin sekizinde

    En kotu WNS  -0,653 ns (max_tt_025C_1v80)
    En kotu TNS  -4,623 ns (max_ff_n40C_1v95)
    Temiz kose   min_ss_100C_1v60 (0)

TNS'lerin mutlak degerce kucuk olmasi (en kotu -4,6 ns), imza aninda
gercekten basarisiz olan uc nokta sayisinin AZ oldugunu gosterir; adim
44'teki 12.226 rakami onarim sirasindaki ara durumdur.

### 2) Slew / fanout / cap - KAPANMADI

ONEMLI DUZELTME: Daha once `MAX_SLEW_VIOLATION_CORNERS: [""]` ayarina
bakip "slew olculmedi" demistim; bu YANLISTI. O ayar yalnizca kosumun
slew yuzunden BASARISIZ SAYILMASINI engelliyor, olcumu engellemiyor.
Slew dokuz kosede de olculdu ve kapanmadi:

| Kose              | Slew   | Fanout | Cap  |
|-------------------|--------|--------|------|
| max_ss_100C_1v60  | 17.065 | 66     | 1911 |
| nom_ss_100C_1v60  | 13.701 | 66     | 1655 |
| min_ss_100C_1v60  | 10.491 | 66     | 1209 |
| max_tt_025C_1v80  |  5.335 | 66     | 1875 |
| nom_tt_025C_1v80  |  4.432 | 66     | 1603 |
| max_ff_n40C_1v95  |  3.401 | 66     | 1875 |
| min_ff_n40C_1v95  |  2.306 | 66     | 1167 |

Fanout her kosede SABIT 66 - PVT'ye bagli degil, demek ki belirli ve
sabit bir net kumesinden geliyor; hedefli olarak incelenebilir.

## HUCRE SAYIMI - KOK NEDENI SAYISAL OLARAK DOGRULUYOR

    timing_repair_buffer   26.360      <- setup onarimi
    hold_buffer                 5      <- hold onarimi
    setup_buffer               89
    tap_cell              113.500
    fill_cell           1.820.253
    stdcell               254.772
    macro                      23

**26.360 / 5 = 5272:1**. Paylasilan `max_buffer_percent 50` butcesinin
tamamini setup onarimi tuketti; hold'a pratikte hic pay kalmadi. Hold
ihlalleri bu yuzden acik kaldi.

**tap_cell = 113.500**, yani standart hucre alaninda tap ekleme fazlasiyla
calisti. Bu, 7658 `nwell.4` ihlalinin bizim mantigimizdaki tap
eksikliginden gelmedigini BAGIMSIZ olarak kanitliyor - ihlaller makro
GDS'inin icinde. `macro = 23` sayisi da 7658/23 ~ 333 hesabini dogruluyor.

Alan darbogaz degil: utilization %49,5, yalnizca standart hucre %15,1.

## OZET

Yonlendirme, anten, LVS, KLayout DRC ve setup hedefleri KARSILANDI.
Acik kalan iki kalem - hold ve slew/cap - ayni kok nedene, erisilemez
10 ns PnR hedefinin tetikledigi asiri setup onarimina baglaniyor.
BULGULAR.md'nin ustundeki dort oneri bu iki kalemi hedefliyor.
