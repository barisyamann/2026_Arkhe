# ASIC netlist'inde ROM icerikleri BOS - 20 Agustos 2026

**Onem: ENGELLEYICI.** Bu haliyle uretilecek cip acilmaz ve NPU cop hesaplar.

> **DURUM: COZULDU (21 Agustos 2026).** Tablolar RTL'e gomuldu, secim
> olcumle yapildi. Ayrinti icin bkz. son bolum: *Cozum ve olcum*.

---

## Bulgu

Sentez logunda:

    soc_top.u_boot_rom.rom_mem: removing const-x lane 0
    soc_top.u_boot_rom.rom_mem: removing const-x lane 1
    ... (32 lane)

Yosys `rom_mem` dizisinin tamaminin tanimsiz (X) oldugunu gorup **sildi**.
Netlist'te boot ROM'un icerigi yok.

Ayni sey ALTI dosyanin hepsinde oldu:

| Tablo | Boyut | Silinen lane |
|---|---|---|
| `boot.hex` -> `rom_mem` | 256 x 32 bit = 8,2 kbit | 32 |
| `fc_weights.mem` | 16.000 x 8 bit = 125 kbit | 8 |
| `dw_weights.mem` | 640 x 8 bit = 5,0 kbit | 8 |
| `dw_bias.mem` | 8 x 32 bit | 32 |
| `fc_bias.mem` | 4 x 32 bit | 32 |
| `softmax_exp_lut.mem` | 256 x 13 bit = 3,3 kbit | 13 |
| **Toplam** | **145.024 bit = 17,7 kB** | |

---

## Kok neden

    rtl/boot/boot_rom.sv:24
        $readmemh("boot.hex", rom_mem);

    rtl/npu/npu_compute_engine.sv:146-150
        $readmemh("dw_weights.mem", dw_weights);
        $readmemh("fc_weights.mem", fc_weights);
        ...

Dosya adlari **ciplak** - yol yok.

`$readmemh` dosyayi CALISMA DIZININE gore arar. Vivado projeye eklenmis
dosyayi cozer ve bulur. LibreLane ise her adimi kendi dizininde kosturur:

    asic/run/arkhe/06-yosys-synthesis/

Oradan `boot.hex` gorunmez. Dosyalar aslinda burada:

    rtl/boot/boot.hex
    weights/fc_weights.mem   (ve digerleri)

Dosya bulunamayinca dizi X kalir. **Hata verilmez, uyari da yeterince
gorunur degildir.** Yosys sonra "hepsi tanimsiz" deyip optimize eder.

---

## Neden simdiye kadar fark edilmedi

Bu, projede bulunan ayni siniftan besinci hatadir: **FPGA akisinda
calisiyor, ASIC akisinda sessizce kayboluyor.**

Oncekiler:

| # | Hata | Yakalayan |
|---|---|---|
| 1 | Bozuk `ifdef` (backtick + bosluk) | Verilator |
| 2 | `sum_exp` bloklayan/bloklamayan atama karisimi | slang |
| 3 | Makro guc pinleri sabite bagli | Verilator |
| 4 | QSPI adres fazi 3 bayt yerine 1 bayt | ASIC/standalone tb |
| 5 | **ROM icerikleri yuklenmiyor** | **Yosys sentez logu** |

Vivado hepsini sessizce kabul etmisti.

Bu bulgu ayrica su anlama geliyor: bes kosumdur yonlendirmeye
calistigimiz 47.926 hucreli tasarim, iceriksiz bir tasarimdir. Alan ve
guc rakamlari **iyimserdir**; tablolar eklenince buyuyecektir.

---

## Cozum secenekleri

Toplam 17,7 kB tablo var. Baskin kalem `fc_weights` (125 kbit, %86).

### Secenek 1 - hepsini mantik olarak sentezlemek

`$readmemh` yerine degerleri dogrudan RTL'e gomek (case / localparam).

Tahmini maliyet (OLCULMEDI, akil yurutme):

    fc_weights 14 bit adres, yuksek entropili INT8 veri
    Shannon tabani : 2^14/14 x 8 = ~9.400 kapi
    Mux agaci      : ~131.000 mux, optimizasyonla 65-90 bin hucre
    Beklenen       : 40.000 - 90.000 hucre

    Diger tablolar (8,7 kbit toplam): 4.000 - 7.000 hucre

Toplam tasarim 47.926 -> ~95.000-145.000 hucre.

**Alan sorun degil**: die 15,33 mm2, makrolar 6,55 mm2, geriye 8,78 mm2
kaliyor ve su an sadece %7'si dolu.

**Riskler**:
- 14 katmanli coklayici agaci derin kombinasyonel yol -> setup payi
  +3,138 ns'yi yiyebilir, kritik yol olabilir
- Hucre sayisini 2-3 katina cikarmak, zaten tikandigimiz yonlendirmeyi
  daha da zorlar
- Sentez suresi ciddi artar

### Secenek 2 - flash'tan yukleme

Agirliklar QSPI flash'ta durur, bootloader boot sirasinda SRAM'e yukler.

    17,7 kB -> 9 makro (toplam 32), die ~%20 buyur

**OTR bunu zaten tarif ediyor** (bolum 3.1):

> **Harici Bellek (NOR Flash):** Program kodlarinin yuklendigi harici
> bellektir... Boot surecinde program kodlari bu birimden okunarak
> buyruk bellegine aktarilir.
>
> **BOOT ROM:** ...harici bellekteki programin ana bellekler**e**
> tasinmasini yoneten bootloader yazilimini bulunduran kalici bellektir.

"Ana bellekler**e**" - cogul. Sapma yok, mevcut mimarinin genisletilmesi.

**NOT**: Agirliklarin 1 kB'lik boot ROM'un ICINE konmasi MUMKUN DEGILDIR.
17,7 kB, boot ROM'un 17,7 katidir. Flash'ta dururlar, ROM'da degil.

### Secenek 3 - MELEZ (onerilen)

Sorun tek tabloda. Digerleri kucuk.

| Tablo | Boyut | Nereye |
|---|---|---|
| `fc_weights` | 125 kbit (%86) | **SRAM makrosu** -> 8 makro |
| `dw_weights` | 5,0 kbit | RTL'e gom |
| `softmax_exp_lut` | 3,3 kbit | RTL'e gom |
| biaslar | 0,4 kbit | RTL'e gom |
| `boot.hex` | 8,2 kbit | RTL'e gom |

RTL'e gomulecek toplam: **8,7 kbit** -> ~4.000-7.000 hucre, mevcut
tasarimin %10'undan az. Adres genisligi kucuk (8-10 bit), derin agac yok,
zamanlama riski yok.

    die 15,33 -> ~18 mm2  (+%17, secenek 2'nin tamamindan az)

Ayrica `$readmemh` bagimliligi TAMAMEN kalkar - bu sinif hata bir daha
olmaz.

---

## Yapilacaklar sirasi

1. Boot ROM'u RTL'e gom                      (kucuk, kesin)
2. Kucuk tablolari RTL'e gom                 (ayni yontem)
3. `fc_weights` icin SRAM blogu + bootloader eklentisi   **KARAR BEKLIYOR**
4. Ust kenar payini 250 -> 500 um yap        (bkz. OLCUMLER.md a7)
5. Akisi kosturup GDSII al

1 ve 2 adimlar `fc_weights` kararindan BAGIMSIZDIR ve her durumda
gereklidir.

---

## Dogrulama

Duzeltmeden sonra sentez logunda su SATIRLAR OLMAMALIDIR:

    grep "removing const-x lane" run/arkhe/*yosys-synthesis*/*.log
    -> bos olmali

Ayrica netlist'te ROM icerigi aranabilir:

    grep -c "u_boot_rom" run/arkhe/*yosys-synthesis*/soc_top.nl.v
    -> 0'dan buyuk olmali (su an 0)

---

# Cozum ve olcum - 21 Agustos 2026

## Ne yapildi

`scripts/gen_rom_paketleri.py` yazildi. Alti tablonun degerlerini
SystemVerilog paketine gomer:

    rtl/boot/boot_rom_pkg.sv        256 deger     8,2 kbit
    rtl/npu/npu_weights_pkg.sv   16.908 deger   136,8 kbit
                                   TOPLAM       145.024 bit = 17,7 kB

`$readmemh` cagrilarinin tamami kaldirildi. Dosya bagimliligi yok;
hangi aracta kosarsa kossun ayni sonucu verir.

### Dogrulama betigin icinde

Betik uretimden sonra urettigi dosyayi GERI OKUR ve kaynak `.mem` ile
deger deger karsilastirir:

    [OK] BOOT_ROM_ICERIK     256 deger x 32 bit
    [OK] DW_WEIGHTS          640 deger x  8 bit
    [OK] DW_BIAS               8 deger x 32 bit
    [OK] FC_WEIGHTS       16.000 deger x  8 bit
    [OK] FC_BIAS               4 deger x 32 bit
    [OK] SOFTMAX_EXP_LUT     256 deger x 13 bit
    [BASARILI] butun tablolar kaynak dosyalarla birebir ayni.

Bu denetim gereksiz degil: tek bit kaymasi NPU'yu SESSIZCE yanlis
siniflandirir ve ancak donanimda fark edilirdi.

`--denetle` kipi de var; kaynak `.mem` degisip paket guncellenmezse
yakalar.

### Bagimsiz capraz denetim

Boot ROM icerigi disassembly ile karsilastirildi:

    paket : 32'h4e214381
    kod   : 0x08: 4381  li t2,0     (RV32C, 2 bayt)
            0x0a: 4e21  li t3,8     (RV32C, 2 bayt)

Little-endian dogru paketlenmis. Bu iki buyruk onemli - 20 Agustos'ta
geri cekilen sahte "Spike" referans dizisi tam da bunlari atliyordu.

## Olcum: `fc_weights` mantik olarak ne kadar yer kapliyor

`make synth` ile olculdu (20 dk 32 sn).

| Metrik | Iceriksiz (20 Agu) | **Tablolar gomulu (21 Agu)** | Fark |
|---|---|---|---|
| Standart hucre | 47.926 | **87.850** | +39.924 (+%83) |
| Cip alani | 0,631 mm2 | **1,028 mm2** | +%63 |
| Flip-flop | 10.908 | **11.586** | +678 |
| SRAM makrosu | 23 | 23 | - |
| `removing const-x lane` | 32+ | **0** | cozuldu |
| Sentez suresi | ~15 dk | 20:32 | +%37 |

Tahmin araligi 40.000-90.000 hucreydi; gercek deger **39.924** cikti -
alt sinirin da altinda. Yosys `memory_bmux2rom` ile 259.143 donusum
yaparak verimli ROM kodlamasi uretti, saf coklayici agaci kurmadi.

En cok kullanilan hucreler degisti:

    mux2_1    10.163 -> 12.053   (+1.890)
    nand2_2        - ->  5.509   (yeni)
    nor2_2         - ->  5.161   (yeni)

`nand2`/`nor2` patlamasi ROM kodlamasindan geliyor; coklayici sayisi
gorece az artti. Bu, mantik minimizasyonunun ise yaradiginin gostergesi.

## Karar: mantik olarak birakildi

Alan hesabi:

    Die (ust pay 500 um)     16,28 mm2
    Makrolar (23 x 0,285)   - 6,55 mm2
                            ----------
    Standart hucreye kalan    9,73 mm2
    Kullanilan                1,028 mm2  ->  %10,6 doluluk

**Rahat sigiyor.** SRAM'e tasima, +8 makro, bootloader eklentisi -
hicbirine gerek kalmadi. Secenek 3 (melez) gereksizlesti.

Kalan risk zamanlamadir: ROM coklayici agaci derin bir kombinasyonel
yol olusturabilir. Tam akis kosumunda olculecek.

## Beklenmeyen bulgu: silinen yalnizca ROM'lar degildi

Flip-flop sayisi da 678 artti. ROM gomek flip-flop EKLEMEZ.

Aciklamasi: tablolar X iken Yosys onlara bagli AsAGI AKIS mantigini da
optimize edip siliyordu. Yani 20 Agustos'taki 47.926 hucre yalnizca
ROM'lari degil, ROM ciktisini kullanan devrenin bir kismini da
kaybetmisti.

**Sonuc: 20 Agustos'un alan ve guc rakamlari sanildigindan daha
iyimserdi.** Tasarim ilk kez tam.
