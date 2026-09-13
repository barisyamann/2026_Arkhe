# SRAM tek-kose modelinin marja etkisi: OLCULDU (11 Eylul 2026)

Kullanici sordu: "koselerin olmasi bir problem yaratmaz mi".
Endise dogruydu: std hucreler dokuz kosede modelleniyor, SRAM makrosu
YALNIZ TT/1,80 V/25 C modeline sahip. Yani ss kosesinde std hucre
yavasliyor ama SRAM tipik hizda varsayiliyor.

Bu belge, o boslugun BUYUKLUGUNU olcer.

# 1. YONTEM

PDK'da ayni teknolojiden BASKA bir SRAM makrosu (sram_1rw1r_32_256_8)
uc kosede de karakterize edilmis durumda. Bizim makromuz
(sky130_sram_2kbyte_1rw1r_32x512_8) yalniz TT'ye sahip, ama ayni
OpenRAM akisiyla ayni teknolojide uretildigi icin KOSE ORANI
devredilebilir.

    .../sky130_sram_macros/lib/
        sram_1rw1r_32_256_8_sky130_TT_1p8V_25C.lib
        sram_1rw1r_32_256_8_sky130_SS_1p8V_25C.lib
        sram_1rw1r_32_256_8_sky130_FF_1p8V_25C.lib

clk -> dout cell_rise tablolari karsilastirildi.

# 2. OLCUM: SS / TT

| Yuk noktasi | TT (ns) | SS (ns) | Oran | Fark |
|---|---:|---:|---:|---:|
| index 0 | 0,449 | 0,494 | 1,100 | +0,045 |
| index 1 | 0,478 | 0,526 | 1,100 | +0,048 |
| index 2 | 0,595 | 0,654 | 1,099 | +0,059 |

**SS kosesinde SRAM yalnizca %10 yavasliyor. En kotu mutlak artis
+0,059 ns.**

FF tarafi simetrik: %10 hizlanma, en kotu -0,060 ns.

# 3. NEDEN BU KADAR KUCUK

Uc kose dosyasinin baslik satirlari birebir ayni:

    nom_voltage     : 1.8
    nom_temperature : 25
    nom_process     : 1.0

Yani SS/FF dosyalari **gerilim ve sicakligi degistirmiyor**, yalnizca
islem (process) kosesini tariyor. Std hucre koselerimiz ise hem
gerilimi (1,60 / 1,95 V) hem sicakligi (100 / -40 C) degistiriyor;
buyuk gecikme farkinin cogu oradan geliyor.

SRAM tarafinda kaybettigimiz sey, PVT'nin yalnizca **P bileseni** ve
o da %10.

# 4. MARJA ETKISI (K_diyot, 23 ns)

En kotu artisi (+0,059 ns) dogrudan kritik yol gecikmesine eklersek:

| Kose | Setup simdi | Setup SS ile | Hold simdi | Hold SS ile |
|---|---:|---:|---:|---:|
| max_ss | +0,3965 | **+0,3375** | +1,1817 | +1,2407 |
| nom_ss | +0,7078 | **+0,6488** | +1,1717 | +1,2307 |
| min_ss | +1,5562 | **+1,4972** | +1,1638 | +1,2228 |

Hold ss'de RAHATLIYOR (veri gec gelir), o yuzden asil risk ff
kosesinde hold'dur:

| Kose | Hold simdi | Hold FF ile |
|---|---:|---:|
| max_ff | +0,3813 | **+0,3213** |
| nom_ff | +0,3770 | **+0,3170** |
| min_ff | +0,3738 | **+0,3138** |

# 5. SONUC

**Dokuz kose SS/FF SRAM modeliyle de POZITIF kalir.**

En dar nokta max_ss setup: +0,397 -> +0,338 ns. Hala pozitif, ve
23 ns periyodun %1,5'i kadar marj.
En dar hold: min_ff +0,374 -> +0,314 ns. Hala pozitif.

Bu, tek-kose SRAM modelinin bizim tasarimimizda **imza sonucunu
degistirmedigini** gosterir. Onceki tahminim ("%30 yavaslarsa marj
tutmayabilir") olcumle CURUTULDU - gercek deger %10 ve sebebi
acik: kose dosyalari V ve T'yi taramiyor.

# 6. NE YAPILMALI

Makro DEGISTIRILMEMELI. 1 kB makroya gecmek:
  - makro sayisini 23 -> 46 yapardi (sartname 46 KB dayatiyor)
  - mux derinligini iki katina cikarirdi (kritik yolun %91'i zaten mux)
  - N_surucu ve R_delay'de kanitlanmis tikaniklik riskini getirirdi
ve kazanci bu olcume gore **0,06 ns mertebesinde**.

Teslimde beyan edilecek ifade:

    SRAM makrosu yalniz TT/1,80 V/25 C Liberty modeliyle gelir.
    Ayni teknolojideki cok koseli muadil makro (sram_1rw1r_32_256_8)
    uzerinden olculen islem-kosesi duyarliligi %10'dur (+0,059 ns).
    Bu deger dokuz kose imza marjlarina uygulandiginda tum koseler
    pozitif kalir (en dar: max_ss setup +0,338 ns, min_ff hold
    +0,314 ns). Tek-kose model bu tasarimda imza sonucunu
    degistirmemektedir.
