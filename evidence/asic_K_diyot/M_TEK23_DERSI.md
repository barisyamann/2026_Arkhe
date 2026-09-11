# M_tek23 deneyi: "tek hedef" yaklasimi BASARISIZ (11 Eylul 2026)

## AMAC

Kullanici hakli bir istek iletti: "hem 20 ns hem 23 ns gibi istemiyorum,
tek bir tanesi olsun, her sey pozitif olsun". Yani ikili anlatim yerine
tek bir frekans beyani.

Bunun icin PnR hedefi de imza hedefi de 23 ns'e sabitlendi.
Ek olarak CTS_MACRO_CLUSTERING_SIZE=2 denendi (saat agaci asimetrisi
icin).

## SONUC: DAHA KOTU

Ayni 23 ns periyotta olculen iki kosum:

| max_ss_100C_1v60 | K_diyot (PnR 14 ns) | M_tek23 (PnR 23 ns) |
|------------------|--------------------:|--------------------:|
| Setup            |            **+0,397** |             -6,387 |
| Hold             |            **+1,182** |             -1,377 |

Uc ss kosesinin hepsinde hem setup hem hold IHLALLI:

    min_ss  setup -4,234  hold -0,505
    nom_ss  setup -5,437  hold -0,913
    max_ss  setup -6,387  hold -1,377

tt ve ff koseleri pozitif (+2,1 ... +3,8) ama ss koseleri cokmus.

## KOK NEDEN

Tampon sayilari neredeyse AYNI:
    CTS tamponu        K: 1659   M: 1666
    Timing repair buf  K: 26557  M: 26678

Yani yapisal bir fark yok. Fark OPTIMIZASYON BASKISINDA:

  K_diyot: PnR 14 ns hedefiyle calisti -> akis SIKI optimize etti
           sonra 23 ns'de olctuk -> 9 ns fazladan pay -> 9/9 pozitif

  M_tek23: PnR 23 ns hedefiyle calisti -> akis GEVSEK davrandi
           23 ns'de olctuk -> fazladan pay yok -> ss koseleri coktu

PnR hedefi gevsek olunca akis daha az hucre buyutuyor, daha az yol
optimize ediyor, saat agacini dengelemeye daha az ozen gosteriyor.

## OGRENILEN: IKI-SDC TASARIMI DOGRUYMUS

asic/README.md'de belgelenen ilke dogrulandi:

    "Tek SDC'yi iki rol icin kullanmak dogru degildir."

PnR SDC'si bir OPTIMIZASYON HEDEFIDIR, imza SDC'si ise GERCEK
OLCUMDUR. Ikisini esitlemek, akisin kendini sikistirma sebebini
ortadan kaldiriyor.

Bu, benim "tek hedef daha temiz olur" varsayimimin YANLIS oldugunu
gosterdi. Kullanicinin istegi (tek frekans beyani) hakliydi ama
bunu saglamanin yolu PnR hedefini esitlemek DEGIL.

## DOGRU YAKLASIM

Tek frekans beyani su sekilde saglanir:
  - PnR hedefi SIKI kalir (14 ns) - bu bir ic optimizasyon parametresidir,
    beyan edilen deger degildir
  - Imza hedefi tek bir deger olur (23 ns) ve TUM raporlar bu periyotta
    uretilir
  - Beyan: "43,5 MHz, dokuz kosede setup ve hold pozitif"

K_diyot bu tanima zaten UYUYOR. Eksik olan tek sey, imza raporlarinin
20 ns yerine 23 ns'de uretilmis olmasi.

## SIRADAKI ADIM

K_diyot'un layout'u degismeden, imza STA'si 23 ns'de yeniden kosulup
tum dokuz kose raporu uretilecek. Bu, d45_anten2 icin yapilan
23 ns analiziyle ayni yontemdir ve YENI PnR GEREKTIRMEZ.

CTS_MACRO_CLUSTERING_SIZE=2 denemesi de ayri degerlendirilmeli;
bu kosumda etkisi olcemedik cunku saat hedefi degisikligi baskin cikti.
