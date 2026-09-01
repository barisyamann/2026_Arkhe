# t50_7 - 50 MHz calismasi, ASIC imzalama paketi

LibreLane 3.0.6 Classic akisi, sky130A PDK, sky130_fd_sc_hd standart hucre
kutuphanesi. Kosum etiketi t50_7, 78/78 adim tamamlandi (2026-08-30).
`arkhe25` (34,2 MHz, teslim edilen ilk paket) uzerine yapilan bir dizi
akis ve RTL iyilestirmesinin sonucudur.

## Imzalama sonuclari

| Kontrol | Sonuc |
|---|---|
| LVS (Netgen) | **Passed** |
| DRC (KLayout) | **0 hata** |
| DRC (Magic) | 7658 - bkz. Bilinen bulgular |
| Anten | **Passed** (arkhe25'te 1 net/1 pin ihlali vardi) |
| Tel uzunlugu | 7,95 mm (arkhe25: 8,47 mm) |
| Hold tamponu | 22 |

### Dokuz kose STA (CLOCK_PERIOD 20,0 ns ile kosuldu)

| Kose | setup_ws | hold_ws |
|---|---|---|
| max_ss_100C_1v60 | -4,5890 | +0,0813 |
| nom_ss_100C_1v60 | -3,6533 | +0,3700 |
| min_ss_100C_1v60 | -2,6856 | +0,6250 |
| max_tt_025C_1v80 | +0,2525 | +0,2276 |
| nom_tt_025C_1v80 | +0,7082 | +0,3735 |
| min_tt_025C_1v80 | +1,1398 | +0,4494 |
| max_ff_n40C_1v95 | +1,5776 | +0,0490 |
| nom_ff_n40C_1v95 | +1,9830 | +0,1678 |
| min_ff_n40C_1v95 | +2,3565 | +0,2454 |

**Calisma frekansi.** En kotu setup ihlali max_ss kosesinde -4,5890 ns
oldugundan gereken periyot 20,0 + 4,5890 = **24,59 ns, yani 40,7 MHz**.

**Hold.** Hold periyottan bagimsiz oldugu icin yukaridaki degerler 24,59 ns
de de aynen gecerlidir. **Dokuz kosenin dokuzunda da hold pozitiftir** -
IO yollari dahil. arkhe25'te max_ff kosesinde -49 ps ile tek bir ihlal
vardi; bu kosumda o da kapanmistir.

arkhe25'e (34,2 MHz) gore **%19 hizlanma**.

## Buraya nasil gelindi

Uc RTL degisikligi ve iki akis ayari, hepsi hedefli testlerle dogrulandi:

**RTL:**
- `sram_module.sv`: okuma coklayicisi yakalamadan SONRAYA tasindi. Makro
  cikisi (dout1) her posedge'de X'e cekildigi icin yarim cevrim yolu
  yapisal olarak kisaltilamiyordu; coklayiciyi bir cevrim geciktirmek
  yolun butcesini genisletti. 17/17 hedefli AXI-Lite testinden gecti.
- `cv32e40p_core.sv`: CSR adres kapisi (`csr_access_ex ? ... : '0`)
  kaldirildi. Kapi, cs_registers'in adres kod cozucusunun onune geç
  gelen bir sinyal koyuyordu; yazmalar zaten csr_we_int ile korunuyor,
  kapi islevsel olarak gereksizdi.
- `axi_lite_interconnect.sv`: 14 kademeli sirali if-else adres kod
  cozucusu paralel ust-bit esitligine cevrildi. 441.190 adreste eski ve
  yeni kod cozucu birebir ayni sonucu verdigi kanitlandi.

**Akis:**
- `SYNTH_STRATEGY`: `AREA 3` -> `DELAY 0`. Sentez bugune kadar ALAN icin
  optimize ediyordu, zamanlama icin degil - 50-74 kademelik derin
  koniler bunun dogrudan sonucuydu.
- `CTS_CLK_BUFFERS`: `clkbuf_16` eklendi (listede en guclusu `clkbuf_8`
  idi). Saat yerlestirme gecikmesi 6,83 ns'den 5,31 ns'ye dustu.
- `PL_TIMING_DRIVEN`: `false` -> `true`. Yerlestirici bugune kadar
  kritik yollari hic gozetmiyordu; acilinca +2,09 ns geldi.

Her degisiklik, `core_test.hex` (Spike ISS komut izi karsilastirmasi) ve
tam sistem regresyonu (arkhe25 tabanina karsi birebir karsilastirma) ile
dogrulandi; hicbiri regresyon yaratmadi.

## Denendi, islemedi (kayit icin)

Kalan zamanlama acigini kapatmak icin dort ek iyilestirme denendi;
dorduir de **zamanlamada degil yonlendirilebilirlikte** dustu:

- `SYNTH_ADDER_TYPE: CSA` + `SYNTH_MUL_BOOTH: true`: alan %9,5 buyudu,
  yonlendirme boguldu (2438 -> ancak 1225 ihlal, bir turda 3751'e sicradi).
- `PL_TARGET_DENSITY_PCT: 55`: teller %13 uzadi, 861 GCell taskin.
- `MAX_TRANSITION_CONSTRAINT: 1.0`: kalin teller, 10,5 saatte kapanmadi.
- Carpim on-hesaplamasi (MULH icin): kendi testinde 124/124 gecti, ara
  olcumde setup +0,29 ns kazandirdi, ama urettigi netlist 5,7 saatte
  kapanmadi ve bir OpenROAD ic hatasini (GRT-0183) tetikledi.

Kok sebep bulundu: `GRT_LAYER_ADJUSTMENTS` `[0.99, 0, 0, 0, 0, 0]`
olarak duruyordu - met1/met2 disinda hicbir katman tercihi yoktu,
yonlendirici trafigi standart hucre pinleriyle paylasilan en sikisik iki
katmana yigiyordu. Met1'e %30, met2'ye %15 ceza eklenince yonlendirme
talebi %19 dustu ve detayli yonlendirme iki turda sifira kapandi
(`t50_10` kosumu) - ama bu, t50_7'nin **UZERINE** henuz entegre
edilmedi; t50_7 hala eski (katman ayari olmadan) konfigurasyondadir.
Sonraki adim bu ayari t50_7'nin RTL'iyle birlestirmektir.

## Bilinen bulgular

**Magic DRC 7658.** Bu sayi dokuz ayri kosumda (arkhe20-25, t50_4, t50_7,
t50_10) bit bit ayni cikmistir. DEF soyutlamasindan gelen bir arac
artefaktidir. Gercek GDS'i dogrulayan KLayout DRC 0 hata vermektedir.

**SRAM liberty.** `sky130_sram_2kbyte_1rw1r_32x512_8` makrosu yalnizca TT
kosesi icin liberty saglamaktadir. ss ve ff kose analizlerinde makro TT
modeliyle degerlendirilmistir; saglayicinin verdigi tek model budur.

## Icerik

    results/soc_top.gds.gz     GDSII (61 MB sikistirilmis)
    results/soc_top.def.gz     Yerlesim DEF
    results/soc_top.nl.v.gz    Sentez netlisti
    results/soc_top.pnl.v.gz   Yerlesim sonrasi netlist
    results/soc_top.lef        Abstract LEF
    results/metrics.json/.csv  Tum akis metrikleri
    reports.tar.gz             Dokuz kose STA raporlari, uretilebilirlik hukmu
    config/                    resolved.json, config_50mhz_t5.yaml

Bu dizindeki dosyalar .gitattributes ile Git LFS disinda tutulmustur.
Hepsi 100 MB sinirinin altindadir; boylece 1 GB'lik ucretsiz LFS kotasi
tuketilmez.
