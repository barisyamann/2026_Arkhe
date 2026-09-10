# RSZ-0090: SRAM makro geçiş sınırı (10 Eylul 2026)

H_yeniRTL adim 41'de durdu:

    [RSZ-0090] Max transition time from SDC is 0.040ns.
    Best achievable transition time is 0.043ns with a load of 0.01pF

## KENDI ILK ONERIM YANLISTI - DUZELTILDI

Ilk tepkim, makro pinlerine SDC istisnasi yazip max_transition'i 0,5
ns'ye cikarmakti. Dis inceleme buna itiraz etti ve HAKLI cikti.
Liberty dosyasindaki karakterizasyon araligi olculdu:

    index_1 : "0.00125, 0.005, 0.04"      <- en buyuk deger 0.04

Yani tablolar GERCEKTEN 40 ps'ye kadar karakterize edilmis.
`max_transition : 0.04` keyfi bir kisit degil, MODELIN GECERLILIK
SINIRIDIR. Onu 0,5'e cikarmak STA'yi tablonun ~12 kati otesine
EKSTRAPOLASYON yapmaya zorlardi: sayi uretir ama guvenilmez olur.

Yazdigim `constraints/makro_slew_istisna.tcl` bu nedenle KALDIRILDI.

## MARJ DUSURMEK COZMEZ - AMA BENIM ILK GEREKCEM YANLISTI

ILK YAZDIGIM (hesap, TAHMIN):
    repair_design -slew_margin N -> hedef = 0.04 * (1 - N/100)
        N=20% -> 0.0320   N=0% -> 0.0400
    "Marj sifir olsa bile 0.040 < 0.043, yol kapali."

Bu hesap DOGRULANMADI. Iki isaret vardi:
  - Hata mesajindaki 0.040, ham lib limiti (0.04) ile BIREBIR AYNI;
    yani slew_margin 20 o sayiya hic yansimamis.
  - OpenROAD dokumani "Add a slew margin" diyor (ekleme), benim
    varsayimim ise cikarmaydi. Yon belirsizdi.

Bu yuzden TAHMIN YERINE OLCTUM. H_yeniRTL'in adim 41 checkpoint'i
LibreLane'in kendi Step altyapisiyla iki kez kosuldu (tam kosum
gerekmedi, her deneme ~4-5 dk):

    slew_margin=20 -> [RSZ-0090] SDC is 0.040ns, best 0.043ns
    slew_margin= 0 -> [RSZ-0090] SDC is 0.040ns, best 0.043ns
                                     ^^^^^ DEGISMEDI

OLCULEN SONUC:
  slew_margin bu kontrolu HIC ETKILEMIYOR. 0.040 dogrudan makro
  Liberty limitidir ve marjdan bagimsizdir.

  Yani sonuc ayni (marj ayariyla asilamaz) ama GEREKCE farkli:
  "marj sifirda bile yetmiyor" degil, "marj bu yola hic
  uygulanmiyor".

## SORUN BIZE OZGU DEGIL

OpenLane issue #1982'de BIREBIR AYNI sayilarla bildirilmis
(0.040 vs 0.043), yine OpenRAM sky130 makrolariyla. Issue
COZUMSUZ duruyor; maintainer yanit vermemis. Kayitta hatanin iki
OpenLane commit'i arasinda bir REGRESYON olarak ortaya ciktigi
belirtiliyor.

Kaynak: https://github.com/The-OpenROAD-Project/OpenLane/issues/1982

## ETKILENEN PINLER (olculdu)

Liberty'de 0.04 kisiti tam olarak uc bus'ta:

    bus(addr0)   direction: input
    bus(addr1)   direction: input
    bus(wmask0)  direction: input

Yani makronun ADRES ve YAZMA MASKESI girisleri.

## NEDEN C/G GECTI DE H GECMEDI

Ayarlar birebir ayni (slew_margin 20, cap_margin 10 - config'ler
karsilastirildi). G ayni adimda 510 tampon ekleyip gecmisti.

Fark tasarimda: duzeltilmis sram_module.sv okuma yolunu kayitli hale
getirdigi icin makro pinlerini suren mantik degisti ve yeni bir yol
o pinlere ulasti.

BU, DUZELTMENIN YANLIS OLDUGU ANLAMINA GELMEZ. Olcumler tersini
soyluyor (adim 36, nom_tt):

    H: setup +0,8637   hold +0,2641   skew -0,5456
    G: setup -0,5464   hold  0,0000   skew -0,7963

Ayrica adim 39 global yonlendirmesi TIKANIKLIKSIZ bitti (0/0/0,
kullanim %18,7).

## SECENEKLER (guncellenmis)

1) `RUN_POST_GRT_DESIGN_REPAIR: false`
   LibreLane'in KENDI VARSAYILANI zaten `False` ve aciklamasi:
     "This is experimental and may result in hangs and/or
      extended run times."
   Bizim config'imizde `true` yapilmis. Kapatmak varsayilana
   donmektir, hile degildir. En dusuk riskli secenek.
   ANCAK: bu adimin yaptigi slew/cap onarimindan da vazgecilir;
   sonucun imza STA'sinda ne getirdigi OLCULMELIDIR.

2) Makro giris pinlerini suren mantigi guclendirmek
   (daha buyuk surucu / daha kisa tel). Kok nedene en yakin
   cozum ama yerlesim etkisi olcume baglidir.

3) Dogrulanmis Liberty temini veya karakterizasyon araligini
   genisleterek modeli yeniden uretmek. En dogru ama en pahali;
   OpenRAM karakterizasyon akisi gerektirir.

Secenek 1 once denenmeli, ancak SONUCU IMZA STA'SI ILE
DOGRULANMADAN "cozuldu" denmemelidir.

## TANI YONTEMI CALISIYOR

Dis incelemenin 1. onerisi (checkpoint'ten yalniz 41. adimi
tekrarlamak) DENENDI VE CALISTI.

Ilk denemem ham OpenROAD ile Tcl kosmakti; LibreLane'in `io.tcl`
dosyasi kose tanimini kendi ic degiskenleriyle
(`_CURRENT_CORNER_NAME`, `_CURRENT_CORNER_LIBS`) source aninda
kurdugu icin disaridan saglanamadi (STA-0577).

Calisan yontem: LibreLane'in kendi `Step.load()` API'si ile
adim 41'i checkpoint'ten yeniden kosmak. Boylece tam kosum
beklemeden ayar denenebiliyor (deneme basina ~4-5 dakika).
`marj_deney.py` bu yontemi kullanir ve baska ayarlari sinamak icin
de tekrar kullanilabilir.
