# PDK'daki SRAM makro secenekleri (11 Eylul 2026)

Soru: "Bize verilen baska SRAM makrosu yok mu?"

# 1. MEVCUT MAKROLAR

PDK yolu: `sky130A/libs.ref/sky130_sram_macros/`

| Makro | Boyut | Organizasyon |
|---|---|---|
| sky130_sram_1kbyte_1rw1r_8x1024_8 | 1 kB | 1024 x 8 bit |
| sky130_sram_1kbyte_1rw1r_32x256_8 | 1 kB | 256 x 32 bit |
| **sky130_sram_2kbyte_1rw1r_32x512_8** | **2 kB** | **512 x 32 bit** (KULLANDIGIMIZ) |
| sram_1rw1r_32_256_8_sky130 | 1 kB | 256 x 32 bit |

Hepsi 1RW+1R port yapisinda; bizim npu_tcm_sram gereksinimine uyuyor.

# 2. LIMITLER AYNI - MAKRO DEGISTIRMEK SLEW'I COZMEZ

Uc makronun Liberty limitleri KARSILASTIRILDI:

    sky130_sram_2kbyte_1rw1r_32x512_8  max_transition 0.04  max_cap 0.02756
    sram_1rw1r_32_256_8_sky130          max_transition 0.04  max_cap 0.02756
    sky130_sram_1kbyte_1rw1r_32x256_8   max_transition 0.04  max_cap 0.02756

**Birebir ayni.** Hepsi ayni OpenRAM karakterizasyon sablonundan
uretilmis.

Karakterizasyon araligi da ayni:
    index_1 : "0.00125, 0.005, 0.04"
    index_2 : "0.0017225, 0.00689, 0.02756"

SONUC: Makro degistirmek slew/cap ihlallerini COZMEZ.

# 3. AMA ONEMLI BIR FARK VAR: COK KOSELI MODEL

`sram_1rw1r_32_256_8_sky130` icin BIRDEN COK kose modeli mevcut:

    sram_1rw1r_32_256_8_sky130_FF_1p8V_25C.lib     <- hizli silikon
    sram_1rw1r_32_256_8_sky130_SS_1p8V_25C.lib     <- yavas silikon
    sram_1rw1r_32_256_8_sky130_TT_1p7V_25C.lib     <- dusuk voltaj
    sram_1rw1r_32_256_8_sky130_TT_1p8V_0C.lib      <- dusuk sicaklik
    sram_1rw1r_32_256_8_sky130_TT_1p8V_100C.lib    <- yuksek sicaklik
    sram_1rw1r_32_256_8_sky130_TT_1p8V_25C.lib
    sram_1rw1r_32_256_8_sky130_TT_1p9V_25C.lib

Bizim kullandigimiz `sky130_sram_2kbyte_1rw1r_32x512_8` icin
YALNIZCA TT_1p8V_25C var.

## Bu neden onemli

Su an dokuz PVT kosesinin HEPSINDE tek bir TT modeli kullaniyoruz.
Yani SRAM'in ss (yavas, 1,60 V, 100 C) ve ff (hizli, 1,95 V, -40 C)
kosolerinde GERCEKTE nasil davrandigini BILMIYORUZ.

Bu, daha once "yapisal acik" olarak kaydedilmisti. Simdi
ogreniyoruz ki PDK'da cok koseli BIR BASKA makro var.

# 4. DEGISIM MALIYETI

`sram_1rw1r_32_256_8_sky130` 1 kB (256 x 32 bit).
Bizim ihtiyacimiz:

    NPU TCM   30 kB -> 30 makro (su an 15)
    I-RAM      8 kB ->  8 makro (su an 4)
    D-RAM      8 kB ->  8 makro (su an 4)
    TOPLAM           46 makro (su an 23)

**Makro sayisi IKIYE KATLANIR.**

Sonuclari:
  - Magic nwell.4 ihlali: 7.658 -> ~15.300 (makro basina 333 sabit)
  - Mux zinciri derinligi artar (15 -> 30 giris)
  - Alan artar
  - Yonlendirme baskisi artar (N_surucu ve R_delay derslerine gore
    tikaniklik riski yuksek)

# 5. DEGERLENDIRME

| Secenek | Kazanc | Maliyet |
|---|---|---|
| Mevcut 2 kB makro | 23 makro, az mux derinligi | tek kose modeli |
| 1 kB cok koseli | dokuz kosede gercek SRAM modeli | 46 makro, iki kat DRC ihlali, tikaniklik riski |

Slew/cap acisindan FARK YOK - limitler ayni.

Tek gercek kazanc COK KOSELI MODEL olurdu. Ama bedeli makro
sayisinin ikiye katlanmasi ve bu, olculmus tikaniklik sinirlarimizi
zorlar.

## Onerilen

Mevcut makroda kalmak, ancak tek kose modelini teslimde ACIKCA
BEYAN ETMEK:

  "SRAM makrosu icin PDK'da yalnizca TT_1p8V_25C Liberty modeli
   mevcuttur. Dokuz PVT kosesinde bu model kullanilmistir; SRAM'in
   ss/ff kosesi davranisi modellenmemistir. PDK'da cok koseli
   alternatif (sram_1rw1r_32_256_8_sky130, 1 kB) bulunmakla
   birlikte, gerekli makro sayisini 23'ten 46'ya cikaracagi ve
   olculmus yonlendirme tikaniklik sinirlarini asacagi icin tercih
   edilmemistir."
