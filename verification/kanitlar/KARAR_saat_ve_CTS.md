# Bilincli kararlar: saat hedefi ve CTS secenegi (10 Eylul 2026)

Dis inceleme hakli olarak sunu soyledi: H'nin PnR hedefi (14 ns) ile
planlanan imza hedefi (20 ns) ve G'deki `-repair_clock_nets`
seceneginin H'de bulunmamasi BILINCSIZ farklardi. Bu belge ikisini de
olculmus veriyle karara baglar.

## KARAR 1: `-repair_clock_nets` KULLANILMAYACAK

G_saat, C_kapanis ile AYNI saat hedefleriyle (PnR 10 ns, imza 20 ns)
ve AYNI eski RTL ile kosuldu. Tek fark bu secenekti. Imza setup
sonuclari:

| Kose             | C (standart CTS) | G (-repair_clock_nets) | Fark   |
|------------------|-----------------:|-----------------------:|-------:|
| min_ss_100C_1v60 |          +1,3799 |                -3,7389 | -5,12  |
| nom_ss_100C_1v60 |          +0,8097 |                -4,9293 | -5,74  |
| max_ss_100C_1v60 |          +0,2206 |                -5,8422 | -6,06  |
| nom_tt_025C_1v80 |          +3,6715 |                +0,9748 | -2,70  |
| max_ff_n40C_1v95 |          +4,3794 |                +1,7728 | -2,61  |

Secenek setup'i HER KOSEDE 2,6-6,1 ns KOTULESTIRDI ve uc ss kosesini
pozitiften negatife dusurdu.

NEDEN: secenek saat agina tampon ekleyerek skew'i duzeltiyor, ama
eklenen tamponlar saat gecikmesini artiriyor. Yavas silikon (ss)
kosolerinde bu gecikme setup butcesini yiyor.

Skew tarafinda kazanci vardi (nom_tt: -1,79 -> -0,80) ama:
  H_yeniRTL, duzeltilmis RTL ile ve BU SECENEK OLMADAN
  adim 36'da skew -0,5456 aldi - yani G'nin secenekli sonucundan
  DAHA IYI.

Dolayisiyla secenek hem gereksiz hem zararli. KULLANILMAYACAK.

## KARAR 2: PnR HEDEFI 14 ns, IMZA 20 ns

Iki-SDC tasarimi asic/README.md'de belgeli ve KASITLIDIR:
  "Tek SDC'yi iki rol icin kullanmak dogru degildir."
PnR agresif hedefle sikistirir, imza gercek hedefte olcer.

Sorun hedefin KENDISI degil, DERECESIYDI. 10 ns'de olculen:
  6389 setup ihlali -> 26360 timing repair buffer -> D_hold'da
  GRT-0116 tikanikligi.

14 ns secimi:
  - Imza hedefine (20 ns) gore hala %30 pay birakir, yani PnR'in
    sikistirma islevi korunur.
  - 10 ns'nin asiri onarim davranisini tetiklemez.

Adim 12 olcumu bu secimi destekliyor (G 10 ns / H 14 ns, ayni adim):
  nom_tt setup WNS: -5,4592 -> -1,0891
  nom_tt setup TNS: -20.662 -> -2.389   (8,6 kat iyilesme)

DIKKAT: bu iki kosum arasinda RTL de degisti, dolayisiyla iyilesmenin
tamami saat hedefine atfedilemez. Ancak 14 ns'nin 10 ns'den daha az
zorlayici oldugu tanim geregi dogrudur.

## ACIK KALAN

Imza hedefi 20 ns'de kalacaksa 50 MHz iddia edilir. C_kapanis'in
23 ns'lik ek analizinde setup 9/9 pozitifti (bkz. reports/timing_23ns).
Yeni RTL ile 20 ns'de setup kapanmazsa, 23 ns (43,5 MHz) secenegi
ayrica degerlendirilmelidir. Bu karar I_makro'nun imza sonucundan
SONRA verilmelidir.
