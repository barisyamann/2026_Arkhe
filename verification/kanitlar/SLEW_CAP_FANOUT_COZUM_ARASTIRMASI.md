# Slew / Cap / Fanout ihlalleri: kaynak analizi ve cozum secenekleri
# (11 Eylul 2026, K_diyot uzerinde olculdu)

Kullanici istegi: "slew 16.442, cap 1.911, fanout 81 - su 3 hatayi
cozecek cozum ara, istersen 10 MHz'de de yapabilirsin".

# 1. EN ONEMLI BULGU: SAAT HIZI BU IHLALLERI COZMEZ

K_diyot layout'u uzerinde imzalama periyodu degistirilerek olculdu
(layout'a dokunulmadi, yalnizca STA tekrarlandi):

    periyot  23 ns (43,5 MHz)  -> slew ihlali 3.336
    periyot  50 ns (20 MHz)    -> slew ihlali 3.336
    periyot 100 ns (10 MHz)    -> slew ihlali 3.336

**Periyot dort katina cikti, ihlal sayisi HIC DEGISMEDI.**

NEDEN: slew/cap/fanout ZAMANLAMA kisiti degil, ELEKTRIKSEL YUK
kisitidir. Bir pinin gecis suresi surucu gucune ve yuke baglidir;
saatin ne kadar yavas oldugu bunu etkilemez. Setup/hold ise
periyoda baglidir - bu yuzden 23 ns'de kapandi.

10 MHz'e inmek bu uc kalemi cozmez. Bu secenek ELENDI.

# 2. KOSE BAZLI DAGILIM (ne kadari PVT'ye bagli)

| Kose             | Slew   | Cap  | Fanout |
|------------------|-------:|-----:|-------:|
| max_ss_100C_1v60 | 16.442 | 1911 |     81 |
| nom_ss_100C_1v60 | 13.312 | 1652 |     81 |
| min_ss_100C_1v60 |  9.996 | 1308 |     81 |
| max_tt_025C_1v80 |  5.298 | 1852 |     81 |
| nom_tt_025C_1v80 |  4.526 | 1595 |     81 |
| min_tt_025C_1v80 |  3.775 | 1256 |     81 |
| max_ff_n40C_1v95 |  3.574 | 1853 |     81 |
| nom_ff_n40C_1v95 |  3.069 | 1601 |     81 |
| min_ff_n40C_1v95 |  2.406 | 1255 |     81 |

Uc kalem UC FARKLI davranis gosteriyor:

  - **Fanout: 81, dokuz kosede BIREBIR AYNI.** PVT'den tamamen
    bagimsiz, saf yapisal.
  - **Cap: 1255-1911.** RC kosesiyle degisiyor (min/nom/max), islem
    kosesiyle degismiyor. Yani TEL kapasitesi baskin.
  - **Slew: 2406-16442, yedi kat fark.** Hem RC hem islem kosesine
    duyarli. ss (yavas silikon, 1,60 V, 100 C) kosesinde patliyor.

# 3. KAYNAK ANALIZI (max_ss kosesinde olculdu)

## 3.1 Slew - 3.336 ihlalli pin listelendi

    anten diyotu ....... 1.844  (%55)
    anonim mantik ......   905  (%27)
    SRAM makro .........   506  (%15)
    saat agaci .........    26
    wire/hold tamponu ..    19

En kotu ornekler:

    clone11974/S   limit 1,50  gercek 4,69
    _098022_/S     limit 1,50  gercek 4,67

## 3.2 Cap - 450 ihlalli pin listelendi

    anonim mantik ........... 293  (%65)
    NPU SRAM makro .......... 105  (%23)
    I-RAM / D-RAM makro .....  34  (%8)
    saat agaci ...............  2

En kotu ornekler:

    clkbuf_1_1_1_clk_i/X   limit 0,59  gercek 1,14
    clkbuf_1_0_1_clk_i/X   limit 0,59  gercek 1,06
    _188599_/Q             limit 0,35  gercek 0,74

## 3.3 Fanout - STA LISTESI BOS

`report_check_types -max_fanout -violators` HICBIR pin dondurmedi,
ancak akis metrigi 81 diyor. Bu bir tutarsizliktir:

  - Ya metrik farkli bir kaynaktan (sentez oncesi tahmin) geliyor,
  - Ya da farkli bir esikle sayiliyor.

SDC kisiti `set_max_fanout 16`. Dokuz kosede birebir 81 cikmasi
yapisal bir kaynagi isaret ediyor (reset agaci, enable sinyali gibi
yuksek fanout'lu kontrol netleri olabilir).

BU KALEM ONCE DOGRULANMALI: 81 gercek bir ihlal mi, yoksa olcum
artefakti mi? Suan bilmiyoruz.

# 4. KOK NEDEN: MAKRO LIBERTY KISITLARI

Ucuncu taraf SRAM makrosu, standart hucrelerden CIDDI OLCUDE sikI
limitler dayatiyor:

| Kisit | SRAM makro | sky130 std hucre | SDC'miz |
|---|---:|---:|---:|
| max_transition | **0,04 ns** | 1,5 ns (varsayilan) | 0,75 ns |
| max_capacitance | **0,0276 pF** | - | 0,2 pF |

Makro, slew'de **37 kat**, cap'te **7 kat** daha sikI.

Ve daha onemlisi: makronun karakterizasyon araligi
`index_1 = "0,00125, 0,005, 0,04"` - yani 0,04 ns MODELIN GECERLILIK
SINIRIDIR. Bu degerin otesi olculmemistir.

sky130 std hucre kutuphanesinin EN IYI basarabildigi gecis suresi
0,043 ns'dir (RSZ-0090 hatasinin sebebi). Yani makronun istedigi
0,04 ns FIZIKSEL OLARAK ERISILEMEZ.

# 5. COZUM SECENEKLERI

## 5.1 ELENENLER

**Saat hizini dusurmek (10 MHz):** Olculdu, ihlal sayisi degismiyor.
ELENDI.

**Makro max_transition'i SDC ile buyutmek:** Karakterizasyon
sinirinin otesine ekstrapolasyon olur; STA sayi uretir ama
guvenilmez. ELENDI (daha once de denenmis ve geri alinmisti).

**MAX_TRANSITION_CONSTRAINT'i gevsetmek (0,75 -> 1,5):** Bu, kendi
SDC kisitimizi std hucre varsayilanina cekmek olur. Ihlal sayisi
duser AMA bu gercek bir iyilesme DEGIL, olcunun degismesidir.
Ayrica MAX_TRANSITION_CONSTRAINT ayni zamanda repair_design'in
HEDEFIDIR; gevsetmek onaricinin daha az calismasina yol acar.
Daha once olculmustu: esigi gevsetmek sonucu KOTULESTIRDI.
ELENDI.

## 5.2 DENENEBILIR - olculmedi

### A) Anten diyotlarini azaltmak  (slew'in %55'i)

K_diyot'ta 12.155 anten hucresi var (C_kapanis'te 10.125).
Diyot-only stratejisi GRT-0183 bugunu asmak icin gerekliydi ama
jumper yerine diyot kullanmak pin yukunu artirdi.

Adaylar:
  - `GRT_ANTENNA_REPAIR_ITERS` / `DRT_ANTENNA_REPAIR_ITERS`
    azaltmak: daha az iterasyon, daha az diyot. Ama anten ihlali
    kalabilir (su an 0/0).
  - `DIODE_ON_PORTS` ayarini gozden gecirmek.
  - Yonlendirme katman sinirini degistirmek (RT_MAX_LAYER met5):
    daha ust katmanlar daha az anten riski.

RISK: anten ihlalleri su an 0/0. Diyot azaltmak bunu bozabilir.
Anten ihlali imalat riskidir, slew ihlalinden DAHA CIDDIDIR.

### B) Makro giris pinlerini suren mantigi guclendirmek

139 cap ihlali dogrudan SRAM makro pinlerinde. Bu pinleri suren
hucreler buyutulurse yuk dagilir.

Adaylar:
  - `MAX_FANOUT_CONSTRAINT` dusurmek (16 -> 8): sentez daha cok
    tampon dagitir.
  - Makro cevresinde yerlesim yogunlugunu dusurmek
    (`PL_TARGET_DENSITY_PCT` 45 -> 40): surucu hucreler makroya
    yaklasabilir, tel kisalir.

RISK: dusuk. Alan zaten bol (utilization %49,5).

### C) Saat agaci cap ihlallerini gidermek

En kotu iki cap ihlali saat buffer'larinda:
    clkbuf_1_1_1_clk_i/X  limit 0,59  gercek 1,14

Adaylar:
  - `CTS_SINK_CLUSTERING_SIZE` kucultmek: her buffer daha az yaprak
    surer.
  - `CTS_CLK_BUFFERS` listesine daha buyuk buffer eklemek.

RISK: orta. Saat agaci degisiklikleri skew'i ve dolayisiyla
setup/hold'u etkiler - su an ikisi de 9/9 pozitif, bozulmamali.

### D) Fanout 81'i once DOGRULAMAK

STA listesi bos donduguu icin bu sayinin ne oldugu belirsiz.
Yapilacak: akis metriginin nereden geldigini izlemek
(hangi adim, hangi esik). Gercek ihlalse kaynak netler
bulunmali; degilse raporlamadan cikarilmali.

RISK: yok, sadece olcum.

## 5.3 EN DOGRU AMA EN PAHALI

### E) Makro Liberty'sini yeniden uretmek

Karakterizasyon araligini gercek calisma kosullarini kapsayacak
sekilde genisletmek (OpenRAM karakterizasyon akisi). Bu, hem
max_transition hem max_capacitance limitlerini gercekci hale
getirir ve RSZ-0090'i de kokten cozer.

Maliyet: OpenRAM kurulumu, SPICE karakterizasyonu, dogrulama.
Gun mertebesinde is.

# 6. ONERILEN SIRA

1. **(D) Fanout 81'i dogrula** - risksiz, sadece olcum. Belki
   gercek bir ihlal bile degil.
2. **(B) Makro surucu guclendirme** - dusuk risk, cap'in %31'ini
   hedefler. `MAX_FANOUT_CONSTRAINT` 16->8 ve
   `PL_TARGET_DENSITY_PCT` 45->40 ile tek kosum.
3. **(A) Anten diyot sayisini olcmek** - once mevcut iterasyon
   ayarlariyla kac diyotun gercekten gerekli oldugunu olc; sonra
   azaltmayi dene. Anten 0/0 KORUNMALI.
4. **(C) Saat agaci** - en son, cunku setup/hold su an 9/9 pozitif
   ve bozma riski var.
5. **(E) Liberty** - yukaridakiler yetmezse.

# 7. DURUST DEGERLENDIRME

Bu uc kalemin BUYUK KISMI ucuncu taraf makro kisitlarindan
kaynaklaniyor ve bizim RTL'imizle veya akis ayarlarimizla tam
olarak cozulemez:

  - Makro max_transition 0,04 ns, std hucre en iyi 0,043 ns yapabilir
  - Makro max_capacitance 0,0276 pF, bizim SDC 0,2 pF

C_kapanis'te de ayni kalemler vardi (slew 17.065, cap 1.911,
fanout 66) ve K_diyot slew'de DAHA IYI (16.442).

Yukaridaki (B) ve (A) adimlari birkaç yuz ihlal azaltabilir ama
sifira indirmek makro Liberty'si duzeltilmeden mumkun gorunmuyor.

Teslimde bu, "makro kaynakli bilinen sapma" olarak beyan edilmeli -
tipki nwell.4 DRC ihlalleri gibi.
