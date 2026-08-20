# ASIC netlist'inde ROM icerikleri BOS - 20 Agustos 2026

**Onem: ENGELLEYICI.** Bu haliyle uretilecek cip acilmaz ve NPU cop hesaplar.

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
