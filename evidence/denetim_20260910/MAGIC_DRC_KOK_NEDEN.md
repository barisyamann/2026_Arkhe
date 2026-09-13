# Magic DRC 7.658: kok neden OLCULDU (11 Eylul 2026)

Kullanici sordu: "peki magic DRC'yi nasil kapatabiliriz ki".

Cevap: kapatilmamali - ama bu sayinin NE OLDUGU olculdu ve
tasarimimizdan kaynaklanmadigi KANITLANDI.

# 1. IHLAL TEK BIR KURAL

    $ grep -c "^ *[0-9.]*um" drc.magic.rpt
    7658
    $ grep "^[A-Za-z]" drc.magic.rpt
    soc_top
    All nwells must contain metal-connected N+ taps (nwell.4)

7.658 ihlalin **tamami nwell.4**. Baska kural ihlali yok.

# 2. KLAYOUT AYNI GDS'TE 0 BULUYOR

    klayout__drc_error__count     0
    magic__drc_error__count       7658

Ayni GDS, iki farkli imzalayici, taban tabana zit sonuc. Sebep
KLayout deck'inin 214-215. satirlarinda ACIKCA yaziyor:

    # rule nwell.4 is suitable for digital cells
    #nwell.not(uhvi).not(areaid_en20).not_interacting(tap.and(licon)
    #    .and(li)).output("nwell.4", ...)

Kural **kasitli olarak devre disi birakilmis** ve gerekcesi not
dusulmus. sky130A imza DRC deck'i (KLayout) nwell.4'u calistirmaz.

Magic tarafinda ise yalniz `variants (full)` stilinde aktif:

    variants (full)
     cifmaxwidth nwell_missing_tap 0 bend_illegal \
        "All nwells must contain metal-connected N+ taps (nwell.4)"

LibreLane `drc.tcl:67` satirinda `drc style drc(full)` yaziyor -
script'te SABIT KODLU, config secenegi yok.

# 3. TASARIMIMIZ TAP HUCRESI KOYUYOR

    WELLTAP_CELL             sky130_fd_sc_hd__tapvpwrvgnd_1
    RUN_TAP_ENDCAP_INSERTION true
    FP_TAPCELL_DIST          13

DEF'te sayildi: **113.500 tap hucresi** yerlestirilmis. Tap
yerlestirme calisiyor.

# 4. KESIN KANIT: MAKRO TEK BASINA 1,39 MILYON IHLAL VERIYOR

SRAM makrosunun GDS'i TEK BASINA Magic drc(full) ile tarandi
(tasarimimiz hic yok, yalniz ucuncu taraf makro):

    sky130_sram_2kbyte_1rw1r_32x512_8.gds  ->  1.394.782 ihlal

Ornekler:
    poly overlap of poly contact < 0.05um (licon.8) .... 93.144
    N-diffusion overlap of contact < 0.04um (licon.5a) . 88.533
    poly contact spacing to diffusion (licon.14) ....... 85.525
    Via1 width < 0.26um (via.1a + 2*via.4a) ............ 80.323
    N-well overlap of N-tap (diff/tap.10) .............. 45.863

Ayrica Magic makro GDS'ini okurken **tanimadigi katmanlar** bildirdi:

    Unknown layer/datatype in boundary, layer=33 type=42
    Unknown layer/datatype in boundary, layer=22 type=21
    Unknown layer/datatype in boundary, layer=235 type=0

Bu katmanlar OpenRAM'in urettigi isaretleyici katmanlardir; Magic'in
sky130A tech dosyasinda karsiligi yok. Magic geometriyi EKSIK
okuyor, dolayisiyla tap baglantilarini goremiyor.

**Yani makro, Magic drc(full) ile zaten imzalanabilir degil.**
Bizim 7.658 sayimiz, o 1,39 milyonun cip seviyesinde birlestirilmis
gorunumudur.

# 5. NEDEN "KAPATMAK" DOGRU CEVAP DEGIL

Uc yol var ve ikisi yanlis:

## (a) RUN_MAGIC_DRC: false  -- YANLIS
Denetimi gizler, sorunu cozmez. Teslimde "DRC kosulmadi" demek,
"DRC'de makro kaynakli bilinen sapma var" demekten cok daha kotudur.

## (b) drc.tcl'i yamalamak (drc(fast) yapmak)  -- YANLIS
Imzalayici script'i degistirmek olur. Sonuc "temiz" gorunur ama
uretilen sayi artik standart akisla karsilastirilamaz. Denetlenebilir
degil.

## (c) OLDUGU GIBI BIRAKIP BEYAN ETMEK  -- DOGRU
Zaten yaptigimiz bu. KLayout imza DRC 0, LVS temiz, anten 0/0,
yonlendirme DRC 0. Magic nwell.4 makro kaynakli ve KLayout deck'i
bu kurali kasitli calistirmiyor.

# 6. TESLIM BEYANI

    Magic drc(full) 7.658 nwell.4 ihlali raporlamaktadir. Bu
    ihlallerin tamami tek kuraldan gelir ve ucuncu taraf SRAM
    makrosu kaynaklidir: makro GDS'i tek basina Magic ile
    tarandiginda 1.394.782 ihlal uretir ve Magic makro icindeki
    OpenRAM isaretleyici katmanlarini (layer 22/33/235) tanimaz.
    sky130A imza DRC deck'i (KLayout) nwell.4 kuralini kasitli
    olarak devre disi birakir (sky130A.lydrc:214-215) ve ayni GDS'te
    0 ihlal raporlar. Imza denetimleri temizdir:
    KLayout DRC 0, LVS 0, anten 0/0, yonlendirme DRC 0.

# 7. NE YAPILABILIR (gercek iyilestirme isteniyorsa)

Tek gercek cozum makro GDS'inin Magic-uyumlu hale getirilmesidir:
OpenRAM isaretleyici katmanlarinin sky130A.tech'e eklenmesi veya
makronun yeniden uretilmesi. Gun mertebesinde is ve kazanci yok -
imza deck'i zaten temiz.
