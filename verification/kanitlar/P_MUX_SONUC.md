# P_mux sonucu: iki kademeli mux agaci OLCULDU (11 Eylul 2026)

Degisiklik: `rtl/npu/npu_tcm_sram.sv` icinde 15 makroluk duz mux,
4'lu gruplar + gruplar arasi secim olacak sekilde iki kademeli
agaca cevrildi. Config K_diyot ile BIREBIR AYNI (diff bos).

# 1. RTL'in gercekten kullanildigi DOGRULANDI

Sunucudaki dosya su an K surumu (11:48'de geri alinmis), ancak
P_mux sentezi 10:20'de kosmus - yani P surumunu okumus.

Sentez netlisti farki bunu kanitliyor:

| | K_diyot | P_mux |
|---|---:|---:|
| mux2_ hucresi | 13.176 | 12.640 (-536) |
| a22o hucresi | 1.833 | 2.310 (+477) |
| u_npu_sram referansi | 2.778 | 2.348 (-430) |

# 2. 23 ns DOKUZ KOSE - IKISI DE POZITIF

| Kose | K setup | P setup | K hold | P hold |
|---|---:|---:|---:|---:|
| max_ss_100C_1v60 | +0,3965 | **+1,3189** | +1,1817 | +0,5561 |
| nom_ss_100C_1v60 | +0,7078 | **+1,6804** | +1,1717 | +0,6404 |
| min_ss_100C_1v60 | +1,5562 | **+2,3683** | +1,1638 | +0,7521 |
| max_tt_025C_1v80 | +4,9112 | +5,2771 | +0,5943 | +0,2368 |
| nom_tt_025C_1v80 | +5,2083 | +5,6288 | +0,5885 | +0,2696 |
| min_tt_025C_1v80 | +5,7672 | +6,1140 | +0,5841 | +0,3321 |
| max_ff_n40C_1v95 | +6,3171 | +6,7906 | +0,3813 | **+0,1701** |
| nom_ff_n40C_1v95 | +6,8813 | +7,1218 | +0,3770 | +0,2025 |
| min_ff_n40C_1v95 | +7,3622 | +7,5294 | +0,3738 | +0,2405 |

Setup TNS: her iki kosuda, dokuz kosede de **0,0**.

## En dar noktalar

    K_diyot : setup +0,3965 (max_ss)   hold +0,3738 (min_ff)
    P_mux   : setup +1,3189 (max_ss)   hold +0,1701 (max_ff)

P setup'ta **3,3 kat** marj kazandi (+0,922 ns).
P hold'ta marj kaybetti: en dar nokta +0,374 -> +0,170 (-0,204 ns).

# 3. DIGER KALEMLER

| Kalem | K_diyot | P_mux |
|---|---:|---:|
| KLayout imza DRC | 0 | 0 |
| LVS | match uniquely | match uniquely |
| Anten net/pin | 0/0 | 0/0 |
| Yonlendirme DRC | 0 | 0 |
| Magic DRC (nwell.4) | 7.658 | 7.658 |
| Slew ihlali | 16.442 | 16.700 (+258) |
| Cap ihlali | 1.911 | **2.298 (+387)** |
| Fanout ihlali | 81 | 96 (+15) |
| Hucre sayisi | 2.073.157 | 2.071.422 |

# 4. SRAM KOSE MODELI UYGULANDIGINDA

Olculen %10 islem duyarliligi (+0,059 ns) uygulanirsa:

    K setup max_ss : +0,3965 -> +0,3375
    P setup max_ss : +1,3189 -> +1,2599

    K hold min_ff  : +0,3738 -> +0,3138
    P hold max_ff  : +0,1701 -> +0,1101

Ikisi de pozitif kalir. P'nin hold marji daha dar ama hala pozitif.

# 5. DEGERLENDIRME

Bu bir DEGIS-TOKUS, tek tarafli ustunluk degil:

  P LEHINE : setup marji 3,3 kat (+0,922 ns). 20 ns akis olcumunde
             setup ihlali 38 -> 8, hold ihlali 1 -> 0.
  K LEHINE : cap ihlali 387 daha az, hold marji 2,2 kat genis.

Iki kosu da dokuz kosede pozitif ve tum imza denetimleri temiz.
Yani ikisi de teslim edilebilir.

Karar kullanicinin onceligine baglidir ve ASAGIDA SUNULMUSTUR -
tek tarafli verilmemistir.
