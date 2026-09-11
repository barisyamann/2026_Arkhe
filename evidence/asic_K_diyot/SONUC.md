# K_diyot: duzeltilmis RTL ile ilk tam kosum (11 Eylul 2026)

## KOSUMUN ANLAMI

10 Eylul'de kesfedildi ki TUM onceki ASIC kosumlari (A, C, D, E, G ve
teslim edilmis d45_anten2) ESKI RTL ile yapilmisti: sunucudaki
sram_module.sv 22 Agustos tarihliydi ve SRAM okumasini dogrudan
geciriyordu (bypass).

K_diyot, duzeltilmis RTL ile SONUNA VARAN ILK kosumdur.
RTL esitligi manifest ile kanitlandi (57/57 dosya).

## YAPILANDIRMA

    CLOCK_PERIOD (PnR)              14 ns
    SIGNOFF (akis ici)              20 ns
    RUN_POST_GRT_DESIGN_REPAIR      false   (LibreLane varsayilani)
    GRT/DRT_ANTENNA_REPAIR_DIODE_ONLY true  (GRT-0183 bugu icin)

Son iki ayar, akisi olduren iki araç hatasini asmak icindir:
  RSZ-0090  SRAM makro Liberty'sinde max_transition 0.04 (model
            gecerlilik siniri; asilamaz)
  GRT-0183  OpenROAD jumper hatasi (OpenLane issue #1982 benzeri)

## GECEN IMZA DENETIMLERI

| Denetim                  | K_diyot | C_kapanis |
|--------------------------|---------|-----------|
| **LVS (netgen)**         | **Circuits match uniquely** | ayni |
| **KLayout imza DRC**     | **0**   | 0 |
| Detayli yonlendirme DRC  | **0**   | 0 |
| Anten net / pin          | **0/0** | 0/0 |
| GDS XOR farki            | **0**   | 0 |
| Magic DRC                | 7658    | 7658 (makro kaynakli) |

Magic'in 7658 ihlali iki kosumda BIREBIR AYNI. Daha once kanitlanmisti:
7658/23 makro ~ 333 sabit, tap_cell sayisi 113.500, KLayout ayni GDS'te
0 buluyor. RTL degisti, tasarim degisti, sayi sabit kaldi - ucuncu
taraf SRAM makro GDS'inden geldiginin bir kaniti daha.

## ZAMANLAMA - 20 ns IMZA (akisin kendi olcumu)

### Saat skew: 9/9 kosede IYILESTI

| Kose             | C_kapanis | K_diyot | Kazanc |
|------------------|----------:|--------:|-------:|
| max_ss_100C_1v60 |   -3,6222 | -2,1209 | +1,50  |
| nom_ss_100C_1v60 |   -3,2566 | -1,9295 | +1,33  |
| min_ss_100C_1v60 |   -3,0225 | -1,7640 | +1,26  |
| max_tt_025C_1v80 |   -2,1701 | -1,2994 | +0,87  |
| nom_tt_025C_1v80 |   -1,7925 | -1,1666 | +0,63  |

Hicbir kosede kotulesme YOK. "Hold, skew'in artigidir" tezi dogrulandi.

### Hold: 8/9 kosede SIFIRLANDI

C_kapanis'te 8 kose ihlalliydi; K_diyot'ta yalnizca max_ss'de
-0,0222 ns kaldi (neredeyse sifir). Diger sekiz kose TAM 0,0000.

### Setup: 3 ss kosesinde ihlal (20 ns'de)

    min_ss -0,2230   nom_ss -1,0563   max_ss -1,3674
    diger alti kose pozitif (+1,80 ... +3,29)

## 23 ns EK IMZA ANALIZI - 9/9 TEMIZ

d45_anten2 icin kullanilan yontemin aynisi: LAYOUT DEGISMEDEN yalnizca
imzalama periyodu buyutulerek yeniden analiz. Yeni yerlestirme,
yonlendirme veya optimizasyon YOK.

Periyot taramasi (max_ss, en kotu kose):

    20,0 ns  setup_wns -1,1035  tns -4,5639
    21,0 ns  setup_wns -0,6035  tns -1,0208
    22,0 ns  setup_wns -0,1035  tns -0,1035
    23,0 ns  setup_wns +0,3965  tns  0,0000   <- kapaniyor

23 ns (43,5 MHz) dokuz kose:

| Kose             | Setup WNS | Setup TNS | Hold WNS |
|------------------|----------:|----------:|---------:|
| min_ss_100C_1v60 |   +1,5562 |       0,0 |  +1,1638 |
| nom_ss_100C_1v60 |   +0,7078 |       0,0 |  +1,1717 |
| max_ss_100C_1v60 |   +0,3965 |       0,0 |  +1,1817 |
| min_tt_025C_1v80 |   +5,7672 |       0,0 |  +0,5841 |
| nom_tt_025C_1v80 |   +5,2083 |       0,0 |  +0,5885 |
| max_tt_025C_1v80 |   +4,9112 |       0,0 |  +0,5943 |
| min_ff_n40C_1v95 |   +7,3622 |       0,0 |  +0,3738 |
| nom_ff_n40C_1v95 |   +6,8813 |       0,0 |  +0,3770 |
| max_ff_n40C_1v95 |   +6,3171 |       0,0 |  +0,3813 |

**SETUP 9/9 POZITIF, HOLD 9/9 POZITIF, TNS 9/9 SIFIR.**

Bu, projede ilk kez hem setup hem hold'un dokuz kosede birden
kapanmasidir. d45_anten2'nin 23 ns analizinde setup 9/9 pozitifti ama
o kosum ESKI RTL ile yapilmisti.

## DIGER OLCUMLER

    Slew ihlali (en kotu kose)   16.442  (C: 17.065)
    Cap ihlali                    1.911  (C: 1.911)
    Fanout ihlali                    81  (C: 66)
    Toplam guc                  124,1 mW (C: 86,2 mW)

Guc %44 artti; 14 ns hedefinin daha cok tampon/hucre gerektirmesinden
kaynaklandigi degerlendiriliyor. Bu ayrica olculmelidir.

## BASARISIZ DENEME: 12 ns (L_12ns)

Setup marjini geri kazanmak icin PnR hedefi 12 ns denendi. Adim 43'te
router tikanikligi gideremedi: "extra iteration 20/50" noktasinda 45
dakika takildi, CPU %31 -> %17 dustu. D_hold'un (10 ns) oldugu desenin
aynisi. Kosu durduruldu.

SONUC: saat hedefini sikarak setup kazanma yolu bu tasarimda tikali.
    10 ns -> tikaniklik (D_hold oldu)
    12 ns -> tikaniklik (L_12ns durduruldu)
    14 ns -> TEMIZ (K_diyot), setup 20 ns'de zayif ama 23 ns'de kapali

## ACIK KALAN

  - 20 ns (50 MHz) hedefinde uc ss kosesinde setup ihlali var.
    23 ns (43,5 MHz) hedefinde dokuz kose de temiz.
    Hangi frekansin beyan edilecegi bir PROJE KARARIDIR.
  - Guc artisi (86 -> 124 mW) ayrica incelenmeli.
  - Magic nwell.4 ihlalleri makro kaynakli; teslimde beyan edilmeli.
