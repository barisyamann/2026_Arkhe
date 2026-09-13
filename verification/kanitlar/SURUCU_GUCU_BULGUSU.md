# Surucu gucu bulgusu: slew ihlallerinin gercek sebebi
# (11 Eylul 2026, K_diyot netlisti + imza STA uzerinde olculdu)

Dis inceleme sunu onerdi: "1844 diyotlu violator'in driver-strength
dagilimini cikarmak, tek bir full ASIC kosumundan bile daha degerli
olabilir. Cogunun X1/X2 surucu oldugunu gorursek hedef neon tabelayla
yanar."

Olcum yapildi. **Tahmin dogru cikti.**

# 1. IHLALLI DIYOTLARIN SURUCU GUCU

1844 diyot kaynakli slew ihlalinin surucu hucre gucu:

    X1   :    3  (%0)
    X2   : 1655  (%90)
    X4   :  109  (%6)
    X6   :   15  (%1)
    X8   :   19  (%1)
    X12  :   40  (%2)
    X16  :    3  (%0)

    X1+X2 (ZAYIF) : 1658  (%90)

**Diyot kaynakli ihlallerin %90'i X2 gucunde bir hucre tarafindan
suruluyor.**

# 2. SURUCU HUCRE TIPLERI

    mux2_2    893
    a31o_2    310
    a221o_2   226
    and2_2     68
    dfrtp_4    66
    dfrtp_2    45
    buf_12     40
    inv_2      32
    ...

En buyuk grup **mux2_2** (893) - yani NPU SRAM okuma coklayicisinin
hucreleri. Bu, daha once olculen kritik yol bulgusuyla ortusuyor:
kritik yolun %91'i mux zinciriydi ve zincirdeki hucreler mux2_2'ydi.

# 3. IHLALLI PININ AIT OLDUGU HUCRE (tum 3336)

    sky130_fd_sc_hd__diode_2      1844  (%55)
    (makro pini, isimsiz)          506  (%15)
    sky130_fd_sc_hd__mux2_2        434  (%13)
    sky130_fd_sc_hd__a22o_2         89
    sky130_fd_sc_hd__a221o_2        64
    sky130_fd_sc_hd__a31o_2         55
    sky130_fd_sc_hd__mux2_4         35
    sky130_fd_sc_hd__nand2_2        32
    sky130_fd_sc_hd__clkbuf_8       28
    digerleri                      249

Grup ozeti:
    diyot   1844
    mantik  1438
    saat      54

# 4. BU NE DEGISTIRIYOR

## Onceki (YANLIS) sonucum

"Slew'in %55'i anten diyotlarinda. Diyotlar DIODE_ONLY kararimizin
bedeli, azaltmak GRT-0183 bugunu geri getirir. Bu kol MUDAHALE
EDILEMEZ."

## Duzeltme

Inceleme hakli: "diyotlari kaldiramiyoruz" ile "diyot kaynakli
slew'e mudahale edemiyoruz" ayni sey DEGIL.

Diyotun ekledigi kapasiteyi degistiremeyiz, ama o dugumu suren
hucreyi buyutebiliriz:

    driver(X2) --- net --- diode + sinks     slew KOTU
    driver(X4) --- net --- diode + sinks     slew IYI olabilir

%90'i X2 oldugu icin buyutme alani GENIS. X4, X8, X12, X16
varyantlari kutuphanede mevcut ve yasakli degil (no_synth.cells
kontrol edildi; yalnizca mux2i yasakli).

# 5. NEDEN SENTEZ ZATEN BUYUTMEDI

Diyotlar YERLESIM/YONLENDIRME sonrasi ekleniyor (anten onarimi).
Sentez o anda diyot yukunu bilmiyor ve X2 secmis oluyor.

Diyot eklendikten SONRA bu dugumleri buyutecek adim ise
`RUN_POST_GRT_DESIGN_REPAIR` idi - ve biz onu RSZ-0090 hatasi
yuzunden KAPATTIK.

Yani zincir su:

    RSZ-0090 (makro Liberty siniri)
        -> RUN_POST_GRT_DESIGN_REPAIR = false
            -> diyot sonrasi surucu buyutme YAPILMIYOR
                -> 1658 X2 surucu zayif kaliyor
                    -> 1844 slew ihlali

# 6. SONUC: YENI VE UMUT VERICI ADAY

Slew ihlallerinin buyuk kismi **makro kaynakli degil, bizim
kapattigimiz bir onarim adiminin eksikligi**.

Secenekler:

  a) RUN_POST_GRT_DESIGN_REPAIR'i acip RSZ-0090'i baska yolla asmak
     (orn. makro pinlerini `set_dont_touch` ile onarimin disinda
     birakmak, ya da RSZ_DONT_TOUCH_RX ile filtrelemek)

  b) Sentezde daha guclu hucre tercih ettirmek (SYNTH_SIZING,
     DELAY stratejisi) - R_delay kosumu bunu test ediyor

  c) `PL_RESIZER_*` veya `GRT_RESIZER_*` ayarlariyla diyot sonrasi
     onarimi baska bir adimda yaptirmak

(a) en dogrudan yol gorunuyor ve HENUZ DENENMEDI.

# 7. DUZELTILMESI GEREKEN ONCEKI IFADELERIM

  - "Slew'in %55'i mudahale edilemez" -> YANLIS, %90'i X2 surucu,
    buyutulebilir.
  - "Bu kalemler makro kaynakli" -> kismen yanlis; makro payi
    yalnizca 506 pin (%15).
  - "Sifira indirmek makro Liberty'si duzeltilmeden mumkun degil"
    -> fazla kesin; 1658 zayif surucu duzeltilebilirse buyuk
    dusus mumkun.

---

# 8. RSZ_DONT_TOUCH YAKLASIMI - INCELENDI, ZAYIFLIK BULUNDU

Dis inceleme "RSZ-0090'i olusturan makro instance/netlerini dar
kapsamli RSZ_DONT_TOUCH_RX ile haric tut" onerdi. Once mekanizmayi
ve hedefi olctum.

## 8.1 RSZ-0090'i hangi pinler tetikliyor - BULUNDU

Makro Liberty'sinde 0,04 ns max_transition tasiyan pin gruplari:

    bus addr0   yon=input
    bus addr1   yon=input
    bus wmask0  yon=input

Bu pinlere bagli benzersiz net sayisi: **506**

Bu sayi, slew ihlallerindeki "SRAM makro" grubuyla (506) BIREBIR
AYNI. Yani hedef kesin olarak tespit edildi.

## 8.2 ZAYIFLIK: net adlari kosumlar arasi DEGISIYOR

    K_diyot  addr0: net9089, net9094, net9099, ...
    P_mux    addr0: \u_data_ram.aw_addr_reg[10], ...

K'nin netlistindeki jenerik `netNNNN` adlari, tampon eklendikten
sonra olusuyor ve her kosumda farkli. Dolayisiyla:

  - `RSZ_DONT_TOUCH_LIST` ile K'dan cikarilan 506 netlik liste
    yeni kosumda GECERSIZ olur.

## 8.3 Makro instance regex'i de yeterli degil

Makro instance adlari sabit (`u_data_ram.g_sram[0].u_macro` gibi),
regex `.*u_macro$` ile 23 makro yakalanabilir.

ANCAK: `set_dont_touch` bir INSTANCE'a uygulandiginda o hucrenin
degistirilmesini engeller. Makro zaten hard makro - degistirilemez.
Makroya GIDEN netleri korumaz. RSZ-0090 ise tam o netlerin slew'ini
olcuyor.

## 8.4 BELIRLEYICI OLCUM: onarim zaten HICBIR SEY yapmiyor

H_yeniRTL logunda RSZ-0090 oncesi iterasyon tablosu:

    Iteration | Area  | Resized | Buffers | Nets repaired | Remaining
            0 | +0.0% |       0 |       0 |             0 |    118434
         1000 | +0.0% |       0 |       0 |             0 |    117434
         2000 | +0.0% |       0 |       0 |             0 |    116434
         ...
         7000 | +0.0% |       0 |       0 |             0 |    111434

**7000 iterasyon boyunca 0 resize, 0 buffer, 0 net onarildi.**

Yani repair_design makro pinlerine takilip ERKEN CIKIYOR - digerlerine
sira gelmeden. Alan artisi %0.

Bu su anlama gelir: adimi acmak tek basina yetmez; makro pinleri
onarim kapsamindan cikarilmadikca arac hicbir sey yapamadan
duruyor.

## 8.5 SONUC

Dont-touch yaklasimi DOGRU YONDE ama uygulanabilir bir yolu
su an gorunmuyor:

  - Net listesi: adlar kosumlar arasi degisiyor -> kullanilamaz
  - Makro instance regex: netleri korumaz -> ise yaramaz

Denenebilecek tek yol: onarim adimini makro pinleri ICIN
calistirmamak, digerleri icin calistirmak. Bu LibreLane'in
mevcut ayarlariyla dogrudan ifade edilemiyor.

Alternatif: `repair_design`'a `-slew_margin` yerine pin bazli
istisna verebilecek bir OpenROAD komutu var mi arastirilmali
(`set_max_transition` pin bazli uygulanabiliyor ama bu STA
kisiti, repair hedefi degil).

---

# 9. R_delay SONUCU: BASARISIZ (GRT-0116)

    SYNTH_STRATEGY: "AREA 3" -> "DELAY 1"
    SYNTH_ABC_BUFFERING: false -> true

Kosu adim 39'da tikaniklikla oldu.

## Olculen sebep

| | K_diyot | R_delay |
|---|---:|---:|
| Hucre sayisi (adim 32) | 238.684 | **227.223** |
| Yonlendirme kullanimi | %18,72 | **%26,19** |
| Tasma | 0/0/0 | **0/1/1** |

**Daha AZ hucre (-11.461) ama %40 daha COK yonlendirme kaynagi.**

Bu, DELAY sentezinin daha buyuk hucreler sectigini dogruluyor:
az sayida ama genis hucre = daha cok pin, daha cok tel, daha cok
yonlendirme talebi.

Adim 12 olcumu zaten isaret vermisti:
    hucre 102.314 -> 84.331  (-%18)
    slew  41.045 -> 45.533   (+%11)
    cap      74 -> 203       (+%174)

Yani sentez asamasinda da ayni desen vardi: az hucre, cok ihlal.

## DERS

"Daha az hucre" fiziksel tasarimda iyi haber DEGIL. Her hucre
daha fazla is yapiyorsa yonlendirme baskisi artiyor.

N_surucu (fanout 16->8) TERSINI yapmisti: +6.507 hucre, kullanim
%18,7 -> %24,6. Iki zit yaklasim AYNI sonuca vardi - tikaniklik.

Bu, K_diyot'un yapilandirmasinin dar bir dengede oldugunu
gosteriyor: hem hucre sayisini artirmak hem azaltmak tikaniklik
uretiyor.
