# GRT-0116 tikanikligi: kok neden ve cozum stratejisi (10 Eylul 2026)

D_hold kosumu adim 44'te `[ERROR GRT-0116] Global routing finished with
congestion` ile oldu. Bu belge hem kendi olcumlerimizi hem de dis kaynak
taramasini kaydeder.

## OLCULEN GERCEK: BU BIR "SIKISIK TASARIM" DEGIL

Adim 44'un son tikaniklik raporu:

    Layer      Resource     Demand    Usage(%)   MaxH/MaxV/Overflow
    li1               0          0      0.00%      0 / 0 / 0
    met1        2141507     522627     24.40%      0 / 0 / 0
    met2        1969040     490641     24.92%      0 / 1 / 1
    met3        1396532     194642     13.94%      0 / 0 / 0
    met4         890400      94467     10.61%      0 / 0 / 0
    met5         198097      12512      6.32%      0 / 0 / 0
    Total       6595576    1314889     19.94%      0 / 1 / 1

Kullanim **%20**, toplam tasma **1**. Yani kaynak bollugu icinde TEK BIR
GCell tasmis. Yaygin tikaniklik yok.

## ADIM ICI SIRA: SORUNU HOLD ONARIMI DOGURDU

Adim 44'un log sirasi (satir numaralariyla):

     18  + global_route            -> Total ... 0 / 0 / 0   TEMIZ
    109  + repair_timing -setup    -> 1071 uc nokta
   1036  + repair_timing -hold     -> hold_margin 0.15
   1062  [RSZ-0032] Inserted 168 hold buffers.
   1077  + global_route            -> Total ... 0 / 1 / 1
   2178  [ERROR GRT-0116]

Tasarim adima TERTEMIZ girdi (0 tasma). 168 hold tamponu eklendikten
sonra tek bir GCell tasti. Ilginc: kullanim %20,09'dan %19,94'e DUSTU
(tampon eklendi ama toplam tel kisaldi) - yani problem kapasite degil,
tamponlarin NOKTASAL YIGILMASI.

## C ILE FARK: "DUZELTMEM" ISE YARADIGI ICIN OLDU

    C_kapanis  hold_margin 0.6   -> 12226 uc nokta bulundu,   5 tampon
    D_hold     hold_margin 0.15  ->   198 uc nokta bulundu, 168 tampon

C'de hold onarimi butce yetersizliginden PES ETTIGI icin (5 tampon)
tikaniklik dogmadi ve kosu sonuna gitti - ama hold ihlalleri acik kaldi.
D'de onarim BASARILI oldu (198 uc noktanin hepsi), 168 tampon girdi ve
yonlendirme tikandi. Yani C'nin "gecmesi" bir basari degil, onarimin
yapilmamasiydi.

Konfigurasyon farki yalnizca 5 kalem:
    CLOCK_PERIOD                     10   -> 22
    GRT_RESIZER_HOLD_SLACK_MARGIN    0.6  -> 0.15
    GRT/PL_RESIZER_HOLD_MAX_BUFFER_PCT 50 -> 70
    MAX_SLEW_VIOLATION_CORNERS       [""] -> ["*"]

## MAKRO YERLESIMI SUCLU DEGIL (olculdu)

Dis kaynaklar makro cevresi tikanikligini one cikariyor. Bizde degil:

    Makro olcusu      683,10 x 416,54 um
    Yatay adim        883,10 um -> kanal 200,00 um
    Dikey adim        616,50 um -> kanal 199,96 um
    Yerlesim          duzenli 4 x 6 izgara, 23 makro, hepsi "N"
    Halo              30 um

200 um kanal fazlasiyla genis. Makro yerlesimi eleme disi.

## DIS KAYNAK TARAMASI

OpenROAD resmi dokumani (grt README):
  - `-allow_congestion`: tikaniklikla birlikte devam etmeyi saglar
  - `set_global_routing_layer_adjustment`: kapasiteyi azaltir; DUSURMEK
    kapasiteyi ARTIRIR
  - Overflow > 0 = talep kapasiteyi asiyor

OpenROAD/OFS issue'lari ve tartismalari:
  - "Check how many buffers are being inserted... can cause extra
    congestion if you have very bad timing"  <- bizim durum
  - "Overrepair can lead to ... too much buffering being added, which can
    present itself as congestion of hold cells or buffer cells"
  - "Using a slack margin that is low enough, even negative, can help
    avoid overrepair"
  - "Blockages near macros often cause congestion hotspots" (bizde degil)

ONEMLI UYARI: OFS issue #3656'da bildiren kisi yogunlugu 0,4'e dusurmus,
die alanini buyutmus, padding eklemis - HICBIRI COZMEMIS ve issue
cozumsuz kapanmis. Yani "yogunlugu dusur / alani buyut" genel tavsiyesi
bu hata sinifinda guvenilir degil. Bizim olcumumuz de zaten yogunlugun
sucsuz oldugunu gosteriyor (%20 kullanim).

## AKISIN KENDI KALDIRACI (kaynak koddan okundu)

`librelane/scripts/openroad/rsz_timing_postgrt.tcl` sonu:

    source .../dpl.tcl
    unset_dont_touch_objects
    if { $::env(GRT_RESIZER_RUN_GRT) } {
        source .../grt.tcl          <- GRT-0116 TAM BURADA DOGUYOR
    }

`GRT_RESIZER_RUN_GRT` (openroad.py:2854), resmi tanimi:
  "Gates running global routing after resizer steps."  varsayilan True

Bunu false yapmak hatayi GIZLEMEK DEGILDIR: tikaniklik asil sinavini
adim 46 detayli yonlendirmede verir ve C_kapanis orada 0 DRC uretmisti.
Adim 44'teki GRT yalnizca bir ara dogrulamadir.

Ikinci kaldirac, ayni betikte:
    `-max_utilization` <- GRT_RESIZER_HOLD_MAX_UTIL_PCT
Tampon eklemeyi yerel yogunluk sinirina baglar, yigilmayi onler.

## STRATEJI

E_dengeli (kosuyor): slew/cap onarim marjlari 30/20 -> 10/5.
  Amac adim 32'deki 12093 tamponu azaltmak.

F_saglam (hazir, yedekte): E de adim 44'te olurse devreye girer.
    GRT_RESIZER_RUN_GRT          true -> false   (hatanin dogdugu nokta)
    GRT_RESIZER_HOLD_MAX_UTIL_PCT null -> 60     (yigilmayi frenle)
    PL_RESIZER_HOLD_MAX_UTIL_PCT  null -> 60

Iki kaldirac birbirini tamamliyor: biri semptomu (ara GRT kontrolu),
digeri kok nedeni (tampon yigilmasi) hedefliyor.
