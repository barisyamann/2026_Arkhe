# G_saat ara sonuc: CTS gecildi (10 Eylul 2026)

## DENEY GERCEKTEN UYGULANDI (dogrulandi)

Ozel adim `35-arkhe-ctssaatonarim` olarak kostu. Loglardan birebir:

    + clock_tree_synthesis -buf_list sky130_fd_sc_hd__clkbuf_8 \
      sky130_fd_sc_hd__clkbuf_4 sky130_fd_sc_hd__clkbuf_2 \
      -root_buf sky130_fd_sc_hd__clkbuf_16 -sink_clustering_enable \
      -obstruction_aware -balance_levels -apply_ndr half \
      -repair_clock_nets

Secenek cagrinin sonunda; deney amaclandigi gibi calisti.

## ILK OLCUM: SKEW YARIDAN FAZLA KUCULDU

nom_tt_025C_1v80 kosesi:

| Olcut       | C_kapanis (final) | G_saat (post-CTS) |
|-------------|------------------:|------------------:|
| Hold skew   |           -1,7925 |           **-0,7963** |
| Setup skew  |            2,1029 |            **0,8007** |
| Hold WNS    |           -0,3556 |           -0,3163 |

DIKKAT - BU KARSILASTIRMA ESIT SARTLARDA DEGIL: C'nin degeri AKIS
SONU (final), G'ninki POST-CTS ara olcumdur. C'nin ara adimlari disk
temizliginde silindigi icin ayni asama karsilastirilamiyor. Sonraki
adimlar (setup onarimi, yonlendirme) skew'i degistirebilir.
Kesin hukum icin G'nin kendi final'i beklenmeli.

Yine de yon umut verici: skew hem hold hem setup tarafinda yariya
yakin kuculmus.

## UYARI: POST-CTS SETUP IHLALI

    timing__setup__ws__corner:nom_tt_025C_1v80 = -2,1064

Post-CTS asamada setup ihlali var. Bu normal olabilir (adim 37
`resizertimingpostcts` tam da bunu onarmak icin var), ama takip
edilmeli: C'de o adim 12.176 tampon eklemisti ve bu tamponlar
D_hold'da tikanikligin kaynagi olmustu.

## YAPISAL BULGU: SAAT AGI IKI DALA BOLUNMUS

    [CTS-0011] Clock net "clk_i" for macros has 46 sinks.
    [CTS-0011] Clock net "clk_i_regs" for registers has 12124 sinks.
    Total number of Buffers Inserted: 1588.
    Total number of Sinks: 12324.

46 sink'lik makro dali ile 12.124 sink'lik register dali arasindaki
263 kat asimetri, skew'in muhtemel kaynagidir. Skew raporundaki yol
bunu dogruluyor:

    kaynak: u_npu.u_npu_sram.g_sram[6].u_macro/clk1  (latency  1,6685)
    hedef : _189765_/CLK                             (latency -2,3648)

Yani en kotu skew tam olarak MAKRO dalindan REGISTER dalina olan
yolda. Bu, dis incelemenin "makro saat agina oncelik ver" tezini
destekler ve sonraki deneyin (makro kume boyutu 4 -> 2 -> 1)
neden mantikli oldugunu gosterir.

## DURUM

Kosu adim 38'de, devam ediyor. Kesin degerlendirme final metrikleriyle
`scripts/kose_karsilastir.py` uzerinden yapilacak.
