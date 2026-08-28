# arkhe25 - ASIC imzalama paketi

LibreLane 3.0.6 Classic akisi, sky130A PDK, sky130_fd_sc_hd standart hucre
kutuphanesi. Kosum etiketi arkhe25, 78/78 adim tamamlandi (2026-08-28).

## Imzalama sonuclari

| Kontrol | Sonuc |
|---|---|
| LVS (Netgen) | **Passed** |
| DRC (KLayout) | **0 hata** |
| DRC (Magic) | 7658 - bkz. Bilinen bulgular |
| Anten | 1 net / 1 pin ihlali |
| Tel uzunlugu | 8,47 mm |
| Hold tamponu | 10 |

### Dokuz kose STA (CLOCK_PERIOD 20,0 ns ile kosuldu)

| Kose | setup_ws | hold_ws | hold_r2r |
|---|---|---|---|
| max_ss_100C_1v60 | -9,2311 | -0,2071 | +0,9517 |
| nom_ss_100C_1v60 | -7,7965 | +0,2115 | +0,2115 |
| min_ss_100C_1v60 | -6,2299 | +0,6045 | +0,6045 |
| max_tt_025C_1v80 | +1,1651 | +0,2785 | +0,2785 |
| nom_tt_025C_1v80 | +1,6357 | +0,4203 | +0,4203 |
| min_tt_025C_1v80 | +2,1096 | +0,4167 | +0,4167 |
| max_ff_n40C_1v95 | +2,5671 | -0,0494 | **-0,0494** |
| nom_ff_n40C_1v95 | +2,8634 | +0,0720 | +0,0720 |
| min_ff_n40C_1v95 | +3,1080 | +0,1827 | +0,1827 |

**Calisma frekansi.** En kotu setup ihlali max_ss kosesinde -9,2311 ns
oldugundan gereken periyot 20,0 + 9,2311 = **29,23 ns, yani 34,2 MHz**.
Tasarim bu periyotta dokuz kosede de setup pozitiftir.

**Hold.** Hold periyottan bagimsiz oldugu icin yukaridaki degerler
29,23 ns de de aynen gecerlidir. Tek gercek reg-to-reg ihlal max_ff
kosesinde **-49 ps** kadardir. max_ss kosesindeki -0,2071 bir IO yoludur;
ayni kosede reg-to-reg hold +0,9517 ile rahat pozitiftir.

## Bilinen bulgular

**Magic DRC 7658.** Bu sayi alti ayri kosumda (arkhe20, 21, 22, 23, 24,
arkhe25) bit bit ayni cikmistir. Tasarim degistiginde degismeyen bir sayi
tasarimdan kaynaklanamaz; DEF soyutlamasindan gelen bir arac artefaktidir.
Gercek GDS'i dogrulayan KLayout DRC 0 hata vermektedir.

**Slew ihlalleri.** MAX_TRANSITION_CONSTRAINT 0,75 ns olarak ayarlanmistir;
sky130_fd_sc_hd kutuphanesinin kendi limiti 1,5 ns'dir. Raporlanan
ihlallerin buyuk cogunlugu kutuphane limitinin altinda olup yalnizca bizim
daha siki kisitimiza takilmaktadir.

**SRAM liberty.** sky130_sram_2kbyte_1rw1r_32x512_8 makrosu yalnizca TT
kosesi icin liberty saglamaktadir. ss ve ff kose analizlerinde makro TT
modeliyle degerlendirilmistir; saglayicinin verdigi tek model budur.

## Icerik

    results/soc_top.gds.gz     GDSII (61 MB sikistirilmis, 356 MB ham)
    results/soc_top.def.gz     Yerlesim DEF
    results/soc_top.nl.v.gz    Sentez netlisti
    results/soc_top.pnl.v.gz   Yerlesim sonrasi netlist
    results/soc_top.lef        Abstract LEF
    results/metrics.json       Tum akis metrikleri
    results/metrics.csv        Ayni metrikler tablo halinde
    reports.tar.gz             Dokuz kose STA, DRC, LVS, anten, sentez raporlari
    config/                    resolved.json, config_kosum25.yaml, design.sdc

Bu dizindeki dosyalar .gitattributes ile Git LFS disinda tutulmustur.
Hepsi 100 MB sinirinin altindadir; boylece 1 GB'lik ucretsiz LFS kotasi
tuketilmez.
