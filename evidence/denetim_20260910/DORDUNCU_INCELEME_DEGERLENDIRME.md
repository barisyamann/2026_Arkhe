# Dorduncu inceleme degerlendirmesi (11 Eylul 2026)

Dis inceleme slew/cap/fanout icin on maddelik bir plan sundu.
Iddialarini K_diyot uzerinde olctum.

# 1. EN ONEMLI IDDIA: CURUTULDU

## Iddia

"MAX_TRANSITION_CONSTRAINT 0.75 -> 1.5 yapin; 19.341 slew ihlalinin
buyuk kismini kendiniz yaratiyor olabilirsiniz. 0.75-1.5 arasindaki
sahte/ekstra siki ihlalleri ayiklamis olacaksiniz."

## Olcum

K_diyot imza STA'sinda listelenen 3.336 ihlalin slew dagilimi:

    slew > 0.75 ns : 2830  (%85)
    slew > 1.00 ns : 2830  (%85)
    slew > 1.50 ns : 2814  (%84)
    slew > 2.00 ns : 1336  (%40)
    slew > 3.00 ns :  321  (%10)

**0.75 ile 1.5 arasinda yalnizca 16 ihlal var.**

Ihlallerin %84'u zaten 1.5 ns'nin USTUNDE. Constraint'i gevsetmek
sayiyi ~%0,5 dusurur, "buyuk kismini" degil.

## DAHA ONEMLISI: LIMIT ZATEN 1.5

STA raporunda gorunen limit degeri: **1.5**, 0.75 degil.

Sebep: sky130 std hucre kutuphanesinin kendi
`default_max_transition : 1.5` degeri var ve pin bazli limit
SDC'deki tasarim geneli kisittan ONCE gelir. Yani bizim
0.75'lik SDC kisitimiz bu pinlerde zaten ETKISIZ.

Dolayisiyla onerilen degisiklik bu sayilari HIC degistirmez.

# 2. DOGRULANAN TESPITLER

Incelemenin config okumasi dogru:

| Ayar | Mevcut | Incelemenin dedigi |
|---|---|---|
| PL_TIMING_DRIVEN | false | dogru, acilmali |
| SYNTH_STRATEGY | "AREA 3" | dogru, DELAY denenebilir |
| SYNTH_ABC_BUFFERING | false | dogru |
| DESIGN_REPAIR_MAX_WIRE_LENGTH | 0 | dogru, uzun net buffering kapali |
| GRT_DESIGN_REPAIR_MAX_WIRE_LENGTH | 0 | dogru |
| MAX_CAPACITANCE_CONSTRAINT | 0.2 | dogru |

Bunlar gercekten akisin elini baglayan secimler ve denenmeye deger.

## Kucuk duzeltme

Inceleme MAX_FANOUT_CONSTRAINT'i 20 diyor; gercek deger **16**.
Ayrica fanout ihlali 11 degil **81** (imza olcumu).

# 3. ZATEN DENENMIS VE BASARISIZ OLANLAR

Inceleme bunlari bilmiyor:

  - **Fanout siki­lastirma (16->8):** N_surucu kosumunda denendi.
    6.507 ek tampon, yonlendirme kullanimi %18,7 -> %24,6,
    GRT-0116 tikanikligi ile akis oldu.
  - **Anten diyot/jumper:** jumper zaten DENENDI ve GRT-0183
    OpenROAD bugunu tetikledi (E_dengeli, I_makro kosumlari oldu).
    DIODE_ONLY bu yuzden secildi - tercih degil zorunluluk.
  - **PnR hedefi gevsetme:** M_tek23'te denendi, ss koselerinde
    setup/hold cokertti.

# 4. HALA DENENMEMIS VE DEGERLI

Incelemenin en iyi katkilari sunlar:

  a) **PL_TIMING_DRIVEN: true**
     Su an false. Yerlestirici timing'i hic gozetmiyor.

  b) **DESIGN_REPAIR_MAX_WIRE_LENGTH: 0 -> 1000**
     Uzun net buffering tamamen kapali. Die 3832 x 4249 um ve
     23 makro var; binlerce mikronluk netler olmasi beklenir.

  c) **SYNTH_STRATEGY: DELAY + SYNTH_ABC_BUFFERING: true**
     Sentez su an alan odakli; elektriksel yuku OpenROAD'a
     birakiyor.

  d) **Cap dagilimini olcmek** (0.2-0.25 / 0.25-0.5 / >0.5 pF)
     Constraint mi fiziksel sorun mu ayirt eder.

# 5. ONERILEN SIRA (guncellenmis)

Incelemenin sirasini bir noktada degistiriyorum: slew constraint
degisikligi (Fix-0) OLCULDU ve etkisiz. O adim atlanmali.

  1. **PL_TIMING_DRIVEN=true tek basina** - tek degisken, en yuksek
     potansiyel, risk dusuk.
  2. **MAX_WIRE_LENGTH=1000 tek basina** - ikinci tek degisken.
  3. **DELAY 1 + ABC_BUFFERING** - ucuncu, sentez degisikligi.
  4. Cap dagilim olcumu (kosum gerektirmez).

Her birini AYRI kosumda denemek gerekiyor; N_surucu'nun dersi iki
degiskeni ayni anda degistirmenin sonucu okunamaz hale getirdigidir.

---

# 6. INCELEMENIN ONERDIGI UC TESHIS - OLCULDU

Bu uc olcum KOSUM GEREKTIRMEDI; K_diyot layout'u uzerinde
yapildi (max_ss_100C_1v60 kosesi, 23 ns).

## 6.1 CAP DAGILIMI

Listelenen 450 cap ihlalinin dagilimi:

    0,20 - 0,25 pF : 133   (%50 listelenenler icinde)
    0,25 - 0,30 pF :  60
    0,30 - 0,40 pF :  47
    0,40 - 0,50 pF :  21
    0,50 - 0,75 pF :   6
    0,75 - 1,00 pF :   0
    > 1,00 pF      :   2
    (kalan 181 pin farkli limitli makro pinleri)

En kotu uc:
    clkbuf_1_1_1_clk_i/X   limit 0,59  gercek 1,14
    clkbuf_1_0_1_clk_i/X   limit 0,59  gercek 1,06
    _188599_/Q             limit 0,35  gercek 0,74

YORUM: Listelenenlerin yarisi 0,20-0,25 araliginda, yani limitin
hemen ustunde. Ama 0,3 pF ustunde 76 pin var ve ikisi 1 pF'i
asiyor - bunlar gercek fiziksel problem. Inceleme "1700 tanesi
0,200-0,220 ise constraint konservatif" demisti; bizde oyle
degil, dagilim genis.

## 6.2 SLEW - CAP KESISIMI  (incelemenin en degerli sorusu)

    |S| slew ihlalli pin : 3336
    |C| cap ihlalli pin  :  450
    |S n C| kesisim      :  311

    C'nin %69'u ayni zamanda slew ihlalli
    S'nin %9'u  ayni zamanda cap ihlalli

YORUM - inceleme KISMEN hakli:

  - Cap yonunden bakinca: evet, cap ihlallerinin %69'u ayni
    zamanda slew ihlali. Yani agir yuklu netler hem cap hem slew
    bozuyor - TEK KOK PROBLEM.

  - Ama slew yonunden bakinca: slew ihlallerinin yalnizca %9'u
    cap ihlalli. Yani 3025 slew ihlali (yaklasik %91) YUKSEK
    KAPASITE OLMADAN olusuyor.

  Bu, slew'in buyuk kisminin yuk degil SURUCU GUCU / GECIS
  KALITESI kaynakli oldugunu gosterir. Daha once olculmustu:
  slew ihlallerinin %55'i anten diyotlarinda (1844 pin).
  Diyotlar kapasite eklemez ama zayif surulen dugumlerde
  gecis suresini bozar.

  SONUC: "tek kok problem" tezi CAP icin gecerli, SLEW icin
  degil. Iki farkli mekanizma var.

## 6.3 FANOUT SINIFLANDIRMASI

81 ihlalli NET, dagilimi:

    anonim mantik : 64
    saat neti     : 16
    npu_irq       :  1

Siddet (daha once olculdu):
    fanout 17-19 : 55 net  (%68, limitin 1-3 ustu)
    fanout 20-24 : 23 net
    fanout 28-29 :  2 net

YORUM: Inceleme "5 net -> 81 violation ise lokal problem" demisti.
Bizde 81 ihlal 81 FARKLI NETTE - yani yaygin, lokal degil.
Ama siddeti dusuk: %68'i limitin 1-3 ustunde.

Tek bir surucunun onlarca ihlal uretmesi durumu YOK. Dolayisiyla
hedefli mudahale edilebilecek bir odak nokta da yok.

# 7. TESHIS AGACININ SONUCU

Incelemenin onerdigi agac su sekilde dolduruldu:

    3336 slew ihlali
       |
       +-- yuksek kapasiteli (311, %9)  -> uzun net / agir yuk
       |
       +-- normal kapasiteli (3025, %91)
             |
             +-- anten diyotu (1844, %55) -> zayif surulen dugum
             +-- anonim mantik (905)
             +-- SRAM makro (506)        -> makro pin limiti

En buyuk kol (anten diyotlari) PL_TIMING_DRIVEN veya
MAX_WIRE_LENGTH ile DEGISMEZ - cunku sorun tel uzunlugu veya
yerlesim degil, diyotun eklendigi dugumun surulus kalitesi.

# 8. GUNCELLENMIS BEKLENTI

Incelemenin onerdigi uc deney hala denenmeye deger, ama
beklentim dusuk:

  PL_TIMING_DRIVEN=true     -> 311 cap-kesisimli slew ihlalini
                               hedefler (%9)
  MAX_WIRE_LENGTH=1000      -> ayni %9'luk kesisimi hedefler
  DELAY + ABC_BUFFERING     -> surucu gucunu artirabilir, en
                               genis kolu (diyot) hedefleyebilir

Ucuncu secenek artik EN UMUT VERICI gorunuyor, cunku slew'in
buyuk kismi surucu gucu kaynakli.

Olcut olarak incelemenin onerdigi histogram kullanilacak:

    1,50-2,00 ns
    2,00-2,50 ns
    2,50-3,00 ns
    3,00-4,00 ns
    > 4,00 ns

Mevcut baseline (K_diyot):
    > 1,5 ns : 2814
    > 2,0 ns : 1336
    > 3,0 ns :  321
