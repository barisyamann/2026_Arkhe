# Slew/cap icin YENI BULGU: RC tahmini gercegi hafife aliyor
# (11 Eylul 2026, K_diyot uzerinde olculdu)

Soru: "Slew/cap'i kazanacak hicbir sey yok mu?"

Akisi adim adim izledim ve onceki tum varsayimlarimi degistiren
bir sey buldum.

# 1. SLEW IHLALININ AKIS BOYUNCA IZI

    adim 12  sentez sonrasi ......... 41.045
    adim 31  yerlesim sonrasi ....... 59.528
    adim 32  ONARIM calisti:
               Resized 2508 instances
               Inserted 11601 buffers in 4762 nets
    adim 38  CTS sonrasi ............    541    <- %99 DUSUS
    adim 44  postGRT ................  1.290
    adim 45  detayli yonlendirme
    adim 55  RCX (gercek parazit cikarimi)
    adim 56  IMZA .................. 16.442    <- 12 KAT ARTIS

# 2. BU NE ANLAMA GELIYOR

**Onarim adimi gorevini YAPIYOR.** 59.528'den 541'e indiriyor.

Sorun onarim eksikligi DEGIL. Sorun, adim 55'te gercek yonlendirme
paraziti cikarilinca sayinin 12 kat artmasi.

Yani: akis boyunca kullanilan TAHMINI RC, gercek RC'den ciddi
olcude DUSUK.

Bu, onceki tum teshislerimi duzeltiyor:
  - "Surucu gucu yetersiz" -> kismen dogru ama kok neden degil
  - "repair_design kapali oldugu icin" -> pre-GRT onarim ACIK ve
    calisiyor (RUN_POST_GPL_DESIGN_REPAIR: true)
  - "makro limitleri" -> yalnizca 506 pin (%15)

# 3. KOK NEDEN: RC TAHMIN KATMANI

LibreLane `set_wire_rc` ile tahmini RC'yi belirli katmanlara gore
hesapliyor. PDK varsayilani:

    DATA_WIRE_RC_LAYER  = met2
    CLOCK_WIRE_RC_LAYER = met5

Config'imizde `SIGNAL_WIRE_RC_LAYERS` ve `CLOCK_WIRE_RC_LAYERS`
ikisi de **null** - yani bu varsayilanlar gecerli.

## Ama gercek yonlendirme dagilimi farkli (olculdu, adim 45)

    met1 : 3.474.718 um   (%40)   <- EN COK KULLANILAN
    met2 : 3.303.734 um   (%38)
    met3 : 1.283.491 um   (%15)
    met4 :   602.137 um   (%7)
    met5 :    75.178 um   (%1)     <- saat tahmini BURAYA gore

Telin %40'i met1'de ama RC tahmini yalnizca met2'ye gore yapiliyor.

met1 daha ince ve daha DIRENCLI bir katmandir. Dolayisiyla tahmin
gercegi HAFIFE ALIYOR.

Saat tarafinda durum daha da carpici: tahmin met5'e gore yapiliyor
ama saat telinin buyuk kismi met1-met3'te.

# 4. DENENEBILIR COZUM (henuz denenmedi)

    "SIGNAL_WIRE_RC_LAYERS": ["met1", "met2"]
    "CLOCK_WIRE_RC_LAYERS":  ["met1", "met2"]

Gerekce: gercek kullanimin %78'i met1+met2'de. Tahmini bu ikisinin
ortalamasina cekmek, akisin gercek duruma daha yakin calismasini
saglar.

Beklenen etki:
  - Onarim adimi (32) daha AGRESIF davranir cunku RC'yi daha yuksek
    gorur
  - Adim 38'deki 541 sayisi belki artar (tahmin daha gercekci)
  - AMA adim 56'daki 16.442 DUSMELI cunku onarim dogru hedefe
    calismis olur

Risk:
  - Daha agresif onarim = daha cok tampon = tikaniklik riski
    (N_surucu ve R_delay bu duvara carpti)
  - Dikkatli olculmeli

NOT: Bu ayar LibreLane dokumaninda "pdk=True" olarak isaretli,
yani PDK'dan gelmesi beklenen bir deger. Degistirmek PDK
varsayilanini ezmek olur - gerekcesi belgelenmeli.

# 5. NEDEN BU ONCEKILERDEN FARKLI

Onceki bes deneme akisin DAVRANISINI degistirmeye calisiyordu
(daha cok tampon, farkli sentez, farkli hedef). Hepsi tikanikliga
carpti.

Bu ise akisin GORDUGU VERIYI duzeltiyor. Arac zaten dogru
calisiyor ama yanlis girdiyle.
