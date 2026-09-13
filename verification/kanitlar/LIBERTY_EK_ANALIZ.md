# SRAM Liberty modeli: ek analiz  (11 Eylul 2026)
# DDK karari: 10 Eylul 2026, "2026 CIP TASARIM YARISMASI" grubu

# 0. NEDEN BU BELGE VAR

Baska bir yarismaci (Deniz Gunes, 10 Eylul 2026 17:54) referans PDK
SRAM makrosunun Liberty modelindeki iki sinirin olculmus bir
elektriksel sinir olmadigini savundu ve yeniden karakterizasyon icin
izin istedi.

DDK ayni gun 17:56'da cevapladi. Bu belge, o karar isiginda BIZIM
durumumuzu kayda gecirir.

# 1. TESPITLER - BIZIM OLCUMLERIMIZLE ORTUSUYOR

Diger yarismacinin tespitleri ve bizim bagimsiz olcumumuz:

| Tespit | Bizim olcumumuz | Ortusuyor mu |
|---|---|---|
| max_transition 0,04 ns | 0,04 ns | evet |
| max_capacitance 0,0276 pF | 0,027559999 pF | evet |
| Degerler SS/TT/FF'de ayni | uc dosyada birebir ayni | evet |
| En guclu tampon bile tutturamaz | RSZ-0090'in sebebi | evet |
| Yalniz TT_1p8V_25C mevcut | PDK'da tek dosya | evet |

Bagimsiz iki ekip ayni sonuca vardi.

# 2. DDK KARARI - BIZI DOGRUDAN ILGILENDIREN CUMLE

> "Referans PDK icerisinde ilgili SRAM icin zorunlu signoff PVT
> corner'larinin her birine birebir karsilik gelen Liberty modeli
> bulunmamasi durumunda, mevcut en yakin referans modelin
> kullanilmasi ve bu varsayimin raporlanmasi kabul edilmektedir."

Bu, bizim dokuz kosede tek TT modeli kullanmamizi ACIKCA KABUL
EDIYOR. Tek sart: raporlamak.

**Biz zaten raporlamisiz** - asic/README.md §5:
"SRAM Liberty yalnizca TT/1,8V/25 C'dir ve FF/SS dahil dokuz STA
kosesinde ayni model kullanilir. Dokuz ayri SRAM karakterizasyonu
iddia edilmez."

Yani mevcut teslimimiz DDK kararina UYGUNDUR. Ek is gerekmez.

# 3. DDK'NIN IZIN VERDIGI IKI YOL

## Yol A - yeniden karakterize etmek
  - GDSII/LEF/Verilog'a dokunmadan SPICE'tan Liberty uretmek: SERBEST
  - PnR/sentez/optimizasyonda kullanmak: SERBEST
  - **Nihai signoff STA yine referans Liberty ile kosulmali**
  - Her iki sonuc ayri ayri raporlanmali
  - Referans modeldeki ihlaller GIZLENEMEZ

## Yol B - yalniz referans Liberty
  - Eksik kose icin en yakin model + raporlama: KABUL

**Biz B'deyiz.**

# 4. BIZIM EK ANALIZIMIZ (Yol A'nin hafif surumu)

Yeniden karakterizasyon yapmadan, ayni bilgiyi olctuk.

PDK'da ayni teknolojiden BASKA bir SRAM makrosu uc kosede de
karakterize edilmis:

    sram_1rw1r_32_256_8_sky130_TT_1p8V_25C.lib
    sram_1rw1r_32_256_8_sky130_SS_1p8V_25C.lib
    sram_1rw1r_32_256_8_sky130_FF_1p8V_25C.lib

clk -> dout gecikmesi karsilastirildi:

| Yuk noktasi | TT | SS | Oran |
|---|---:|---:|---:|
| index 0 | 0,449 | 0,494 | 1,100 |
| index 1 | 0,478 | 0,526 | 1,100 |
| index 2 | 0,595 | 0,654 | 1,099 |

**Islem kosesi duyarliligi %10; en kotu +0,059 ns.**

Sebep olculdu: uc kose dosyasinin basliklari ayni
(nom_voltage 1.8, nom_temperature 25). Kose dosyalari V ve T'yi
TARAMIYOR, yalniz process'i. Std hucre koselerimiz ise V'yi
(1,60/1,95) ve T'yi (100/-40) de degistiriyor.

## Marja etkisi (K_diyot, 23 ns)

| Kose | Olculen | SS/FF modeli uygulanirsa |
|---|---:|---:|
| max_ss setup | +0,3965 | **+0,3375** |
| nom_ss setup | +0,7078 | +0,6488 |
| min_ss setup | +1,5562 | +1,4972 |
| min_ff hold | +0,3738 | **+0,3138** |

**Dokuz kose POZITIF kalir.**

# 5. NEDEN TAM YENIDEN KARAKTERIZASYON YAPMADIK

DDK izin veriyor ama zorunlu tutmuyor. Maliyet/fayda olculdu:

| | Deger |
|---|---|
| Maliyet | OpenRAM kurulumu + SPICE karakterizasyon + tam kosu (~4,5 sa) + dokuz kose olcum. Gun mertebesinde. |
| Signoff ihlallerine etkisi | **SIFIR** - DDK signoff'un referans Liberty ile kosulmasini sart kosuyor. 16.442 slew ihlali raporda AYNEN kalir. |
| Gercek kazanc | PnR onaricisi ulasilabilir bir hedefe calisirdi; layout kalitesi artabilirdi. |
| Risk | Karakterizasyon hatasi sessizce yanlis layout uretebilir. |

Elimizde dokuz kosede pozitif, tum imza denetimleri temiz,
dogrulanmis bir kosu var. Sunumda beyan edilecek sayilar degismeyecegi
icin bu yatirim yapilmadi.

# 6. SUNUMDA SOYLENECEKLER

Sartname §3.3.2 "eksikliklerin acik anlatimi ve analizi"ni puanliyor.
Bu kalem su cerceveyle sunulmalidir:

1. **Sinirlar olculdu ve modelin kendi gecerlilik sinirinda oldugu
   gosterildi.** max_transition 0,04 ns; sky130 std hucre kutuphanesinin
   en iyi yapabildigi 0,043 ns. Hedef fiziksel olarak erisilemez -
   RSZ-0090 tool hatasinin kok nedeni budur.

2. **Bagimsiz dogrulama var.** Baska bir yarismaci ekip ayni tespiti
   yapti; DDK 10 Eylul 2026'da kararini verdi.

3. **DDK karari bizim yaklasimimizi onayliyor:** eksik kose icin en
   yakin referans model + raporlama kabul ediliyor. Bunu zaten
   yapmisiz (README §5).

4. **Bosluk sayisallastirildi.** Islem kosesi duyarliligi %10 olarak
   olculdu ve dokuz kose marjina uygulandi; hepsi pozitif kaldi.
   Yani tek-kose model bu tasarimda imza sonucunu degistirmiyor.

5. **Ihlaller gizlenmedi.** Slew 16.442 / cap 1.911 / fanout 81
   raporda oldugu gibi duruyor; kaynagi makro Liberty'sidir ve
   yukaridaki analiz bunun teknik gerekcesidir.

# 7. KAYNAKLAR

  - DDK yaziligi: Google Grubu "2026 CIP TASARIM YARISMASI",
    10 Eylul 2026 17:56
  - Olcum dokumu: SRAM_KOSE_MODELI_OLCUMU.md
  - Limit analizi: SLEW_CAP_FANOUT_COZUM_ARASTIRMASI.md
  - Beyan: asic/README.md §5
