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
