# Arkhe SoC - ASIC Fiziksel Tasarim Akisi

TEKNOFEST 2026 Cip Tasarim Yarismasi - Mikrodenetleyici Tasarim Kategorisi
Takim ARKHE

Bu dizin **yalnizca** ASIC fiziksel tasarim akisina ait girdi, yapilandirma,
otomasyon, calisma alani, rapor ve ciktilari icerir. Tasarim RTL kaynaklari,
islevsel dogrulama ve testbench dosyalari ile FPGA uygulamasina ozgu dosyalar
deponun diger bolumlerindedir:

    rtl/          tasarim RTL kaynaklari
    tb/           testbench'ler
    sw_nexys/     gomulu yazilim
    vivado/       FPGA projesi
    evidence/     olcum ve dogrulama kanitlari

Belge duzeni Final Ciktilar dokumaninin **Bolum 9** basliklarini izler.

---

# 1. Tasarim Ozeti

**Amac.** Yapay zeka uygulamalari icin optimize edilmis, RISC-V tabanli bir
mikrodenetleyici (SoC). Genel amacli bir mikrodenetleyicinin yani sira
donanimsal bir YZ hizlandirici barindirir; hedef uygulama nicelenmis (INT8)
anahtar kelime tanimadir.

**En ust seviye modul:** `soc_top`

| Blok | Aciklama |
|---|---|
| CV32E40P | RISC-V cekirdek, RV32IMC (`FPU = 0`) |
| AXI4-Lite ara baglayici | 3 master / 13 kole, MMIO adres cozumleme |
| Boot ROM | 1 kB, bootloader makine kodu RTL'e gomulu |
| I-RAM / D-RAM | 8 kB + 8 kB, SRAM makrolari |
| YZ hizlandirici | TinyConv hatti + 30 kB TCM |
| Cevre birimleri | GPIO, Timer, UART x2, I2C, QSPI, DMA, JTAG |

## Temel giris/cikis arayuzleri

    GPIO      gpio_i[15:0] / gpio_o[15:0] / gpio_tx_en_o[15:0]
    UART1     uart1_rxd / uart1_txd            (genel amacli)
    UART2     uart2_rxd / uart2_txd            (veri akisi)
    I2C       i2c_sda_o / _oe / _i , i2c_scl_o / _oe / _i
    QSPI      qspi_sck, qspi_cs_n, qspi_io_o[3:0] / _oe[3:0] / _i[3:0]
    JTAG      jtag_tms, jtag_tck, jtag_tdi, jtag_tdo, jtag_trst_n

`soc_top` **ucdurumlu (tri-state) port icermez**; cift yonlu pinler
cikis / cikis-etkin / giris uclusune ayrilmistir. Ucdurum yalnizca pad
halkasinda olusur (FPGA tarafinda `rtl/Memory/nexys_top.sv`).

YZ hizlandirici yerel bellegi (TCM) **tek yazan porta** indirilmistir:
Port A okuma+yazma, Port B salt okuma. Bu yapi sky130'un 1RW+1R SRAM
makrosuna dogrudan eslenir.

## Saat ve reset portlari

| Port | Yon | Aciklama |
|---|---|---|
| `clk_i` | giris | Ana sistem saati |
| `rst_ni` | giris | Asenkron reset, aktif dusuk |
| `jtag_tck` | giris | JTAG saati, bagimsiz alan |
| `jtag_trst_n` | giris | JTAG reset, aktif dusuk |

## Hedef saat frekanslari

| Saat | Periyot | Frekans |
|---|---|---|
| `clk_i` | 20,0 ns | **50 MHz** |
| `jtag_clk` | 100,0 ns | 10 MHz |

---

# 2. Arac ve Ortam Bilgileri

| | |
|---|---|
| **LibreLane surumu** | **v3.0.6** (yarismanin referans surumu) |
| LibreLane commit | `ba7193bff33d68941683b2963b90aa30cea117d1` |
| LibreLane akisi | **Classic** |
| **PDK** | **sky130A** |
| **Open PDKs commit** | `8afc8346a57fe1ab7934ba5a6056ea8b43078e71` |
| Standart hucre kutuphanesi | `sky130_fd_sc_hd` |
| **OpenRAM surumu** | **OpenRAM kullanilmadi** |
| PDK yoneticisi | ciel |
| Ortam yonetimi | Nix 2.35.2 |

**Referans surumden farkli kullanilan arac, PDK veya kutuphane yoktur.**
Gelistirme sirasinda bir sure LibreLane 3.0.10 kullanildi; DDK onay
surecine girmemek icin referans surum 3.0.6'ya donuldu ve teslim edilen
butun ciktilar 3.0.6 ile uretilmistir.

Nix bagimliliklari `environment/flake.lock` ile commit duzeyinde
sabitlenmistir:

    librelane      ba7193bff33d68941683b2963b90aa30cea117d1
    nix-eda        8f990fb77529c09e540e453cd836af9930ec58db
    nixpkgs        b3aad468604d3e488d627c0b43984eb60e75e782
    ciel           afcb23d368614ffa1e7e96584ed33f839c71c576

**Ayrintili surum bilgisi:** `asic/environment/versions.txt`

> `flake.nix` icinde `nixpkgs.follows` zinciri **`librelane/nix-eda/nixpkgs`**
> olmalidir. `librelane/nixpkgs` yazilirsa nix hata verir - LibreLane
> nixpkgs'i dogrudan disari acmaz, nix-eda uzerinden tasir.

---

# 3. Akisin Calistirilmasi

## Ortam

    nix develop ./environment

Alternatif (profil kurulumu):

    nix profile install github:librelane/librelane/3.0.6
    ciel enable --pdk-family sky130 8afc8346a57fe1ab7934ba5a6056ea8b43078e71

> Nix ikili paket onbellegi tanimlanmazsa araclar KAYNAKTAN DERLENIR ve bu
> saatler surer. `/etc/nix/nix.conf` icine ekleyin:
>
>     extra-substituters = https://nix-cache.fossi-foundation.org
>     extra-trusted-public-keys = nix-cache.fossi-foundation.org:3+K59iFwXqKsL7BNu6Guy0v+uTlwsxYQxjspXzqLYQs=

## Zorunlu yeniden calistirma komutu

    cd asic
    make asic_run

`asic_run` sirasiyla su islemleri yapar:

1. `check` - `filelist.f` ile `config.yaml` tutarliligini denetler
2. `run/arkhe/` calisma dizinini hazirlar
3. LibreLane Classic akisini kosar
4. `collect` - ciktilari `reports/` ve `results/` altina toplar

Basarisizlik durumunda **sifirdan farkli cikis kodu** doner. Kullanici
etkilesimi veya grafik arayuz gerektirmez; mutlak dosya yolu icermez.

## Ek otomasyon hedefleri

    make asic_verify    teslim edilen rapor ve ciktilarin varligini denetler
    make asic_clean     run/ altini temizler (.gitkeep birakir)
    make lint           yalnizca Verilator lint adimi
    make synth          sentez adimina kadar kosar
    make sources        config.yaml kaynak listesini filelist.f'ten uretir
    make collect        ciktilari topla

## On kosullar ve ortam degiskenleri

Ozel bir ortam degiskeni gerekmez. `PDK_ROOT` ciel tarafindan yonetilir.

## Yaklasik calisma suresi

Olculen degerler (Ryzen 5 6600H, 6 cekirdek, 11 GB kullanilabilir RAM):

| Adim | Sure |
|---|---|
| Sentez | ~14 dk |
| Yerlestirme + onarim | ~35 dk |
| CTS + resizer | ~30 dk |
| Global + detayli yonlendirme | ~1,5-2 saat |
| STAPostPNR (9 kose) | ~55 dk |
| Signoff (DRC / LVS / XOR) | ~30 dk |
| **Toplam** | **~4 saat** |

## Onerilen donanim

| | Asgari | Onerilen |
|---|---|---|
| CPU | 4 cekirdek | 8+ cekirdek |
| **RAM** | **16 GB** | **32 GB** |
| Disk | 100 GB | 200 GB |

RAM kritiktir: Magic adimlarinda 10 GB'in uzerine cikilmaktadir. 16 GB'lik
bir makinede takas alanina dusulmekte ve adimlar cok yavaslamaktadir.

Akis dosya G/C yogundur. WSL kullaniliyorsa kosum dizini **WSL'in kendi
diskinde** olmalidir; `/mnt/c` uzerinden yaklasik 3 kat yavas calisir
(olculdu).

---

# 4. RTL ve Akis Girdileri

| | Konum |
|---|---|
| Kaynak listesi | `asic/filelist.f` |
| Ana yapilandirma | `asic/config.yaml` |
| Zamanlama kisitlari | `asic/constraints/design.sdc` |

## Include dizinleri

    ../rtl/cv32e40p-master/rtl/include
    ../rtl/Memory
    ../rtl/Cevre_Birimleri/files_1

## Derleme tanimlari

| Tanim | Aciklama |
|---|---|
| `USE_SRAM_MACRO` | Bellekleri cikarimsal dizi yerine SRAM makrosuyla gerceklestirir |

`USE_SLANG: true` - SystemVerilog paket import'lari modul basliklarinda
kullanildigi icin Yosys'in varsayilan on-isleyicisi yetersiz kalmaktadir.

## Ana RTL kaynaklarinin konumu

    rtl/Memory/             soc_top, ara baglayici, SRAM sarmalayicilari
    rtl/npu/                YZ hizlandirici
    rtl/Cevre_Birimleri/    GPIO, Timer, UART, I2C, QSPI, DMA, JTAG
    rtl/boot/               Boot ROM ve icerigi
    rtl/cv32e40p-master/    CV32E40P cekirdegi (ucuncu taraf)

`filelist.f` bu kaynaklara **goreli yollarla** referans verir
(`../rtl/...`). Mutlak yol kullanilmamaktadir. Dosya sirasi HDL derleme
bagimliliklarini karsilayacak sekilde duzenlenmistir (paketler once).

## Ucuncu taraf RTL ve IP

`asic/THIRD_PARTY.md` - CV32E40P, PULP common cells, SKY130 PDK,
SRAM makrosu, LibreLane.

## Tutarlilik denetimi

    python3 scripts/check_filelist.py

Bu betik dort denetim yapar:

1. `filelist.f` icindeki her dosya var mi
2. `config.yaml`'daki uretilen blok `filelist.f` ile ayni mi
3. `asic/` altinda RTL kaynagi veya testbench var mi
4. Listede testbench veya FPGA'e ozgu dosya var mi

`config.yaml` icindeki `VERILOG_FILES` blogu **uretilmistir**; tek
dogruluk kaynagi `filelist.f`'tir:

    make sources    bloku yeniden uret

---

# 5. SRAM ve Fiziksel Makrolar

| | |
|---|---|
| **Makro adi** | `sky130_sram_2kbyte_1rw1r_32x512_8` |
| Kaynak | Referans SKY130A PDK, `libs.ref/sky130_sram_macros/` |
| Kapasite | 2 KiB |
| Derinlik | 512 kelime |
| Veri genisligi | 32 bit |
| Port yapisi | 1RW + 1R |
| Yazma granulaligi | 8 bit |
| Fiziksel boyut | 683,10 x 416,54 um = 0,285 mm2 |
| **Toplam ornek** | **23** |

## Instance adlari ve dagilim

| Bellek | Kapasite | Instance | Adet |
|---|---|---|---|
| YZ hizlandirici TCM | 30 kB | `u_npu.u_npu_sram.g_sram[0..14].u_macro` | 15 |
| Buyruk bellegi (I-RAM) | 8 kB | `u_instruction_ram.g_sram[0..3].u_macro` | 4 |
| Veri bellegi (D-RAM) | 8 kB | `u_data_ram.g_sram[0..3].u_macro` | 4 |

YZ hizlandirici bellegi tam **30 kB**'dir (7680 kelime x 32 bit).

## Dosya konumlari

    macros/sky130_sram_2kbyte_1rw1r_32x512_8/
        gds/       fiziksel gorunum
        lef/       soyut fiziksel gorunum
        lib/       Liberty zamanlama modeli
        verilog/   islevsel model
        spice/     SPICE netlisti

## Guc ve toprak pinleri

| Makro pini | Ust seviye ag |
|---|---|
| `vccd1` | `VPWR` |
| `vssd1` | `VGND` |

Baglanti `config.yaml` icinde acikca verilmistir:

    PDN_CONNECT_MACROS_TO_GRID: true
    PDN_MACRO_CONNECTIONS:
      - ".*u_macro VPWR VGND vccd1 vssd1"

> **Bu satir olmadan makrolarin fiziksel tasarimda GUCU YOKTUR.**
> `PDN_CONNECT_MACROS_TO_GRID` tek basina yetmez; OpenROAD hangi makro
> pininin hangi aga baglanacagini bilemez ve 46 uyari (23 makro x 2 pin)
> uretir.

RTL'de guc pinleri **bilerek baglanmamistir**: makro modelinde `inout`
tipindedirler ve sabit deger baglamak elektriksel kisa devredir (Verilator
bunu `%Error-PORTSHORT` ile dogru sekilde hata sayar). Baglanti PDN
adiminda fiziksel olarak yapilir.

## Zamanlama modeli ve varsayim

Makronun PDK ile gelen **tek** Liberty modeli vardir:

    sky130_sram_2kbyte_1rw1r_32x512_8_TT_1p8V_25C.lib

Yarismanin zorunlu tuttugu uc signoff corner'ina (tt / ss / ff) birebir
karsilik gelen model **bulunmamaktadir**. Bu nedenle uc corner'da da TT
modeli okunmaktadir.

**Varsayim ve etkisi:** SRAM makrosunun gecikmeleri ss corner'inda
oldugundan iyimser, ff corner'inda kotumser degerlendirilmektedir. Setup
analizi ss corner'inda makro yollari icin iyimser olabilir. Standart hucre
yollari uc corner'da da dogru modellenmektedir.

---

# 6. Zamanlama Kisitlari ve Istisnalari

Kisit dosyasi: `asic/constraints/design.sdc`
PnR ve signoff ayni dosyayi kullanir.

## Birincil saatler

| Saat | Port | Periyot | Frekans |
|---|---|---|---|
| `clk_i` | `clk_i` | 20,0 ns | 50 MHz |
| `jtag_clk` | `jtag_tck` | 100,0 ns | 10 MHz |

    create_clock -name clk_i    -period 20.0  [get_ports clk_i]
    create_clock -name jtag_clk -period 100.0 [get_ports jtag_tck]

## Generated clock

**Yoktur.** Tasarimda uretilmis veya bolunmus saat bulunmamaktadir.

## Saat alanlari arasindaki iliski

Iki saat alani **asenkron**tur:

    set_clock_groups -asynchronous \
        -group [get_clocks clk_i] \
        -group [get_clocks jtag_clk]

**Gerekce:** `jtag_tck` disaridan gelir ve sistem saatiyle iliskisizdir.
`jtag_debug` modulunde iki alan arasindaki gecisler senkronizasyon
yazmaclari uzerinden yapilir (`jtag_cmd_valid_sync1` / `sync2`). Iki alan
arasinda zamanlama analizi anlamli degildir.

## Giris ve cikis gecikmeleri

    set io_delay [expr 20.0 * 0.20]     ;# 4,0 ns
    set_input_delay  4.0 -clock clk_i <saat disi butun girisler>
    set_output_delay 4.0 -clock clk_i [all_outputs]

Periyodun %20'si. Cevre birimi pinleri yavas dis dunyaya baglanir
(UART, I2C, QSPI, GPIO, JTAG).

> `all_inputs` ciktisindan saat portlari **Tcl liste islemleriyle**
> cikarilir. `remove_from_collection` bir Synopsys DC komutudur ve
> OpenSTA'da YOKTUR.

## Onerilen kisitlar

| Kisit | Deger |
|---|---|
| Clock uncertainty | 0,25 ns |
| Clock transition | 0,15 ns |
| Output load | 0,02 pF |

## Zamanlama istisnalari

| Istisna | Kapsam | Gerekce |
|---|---|---|
| `set_false_path -from [get_ports rst_ni]` | Asenkron reset | `rst_ni` disaridan gelir, saatle iliskisizdir. Senkronizasyon pad / `nexys_top` seviyesinde yapilir. |
| `set_false_path -from [get_ports jtag_trst_n]` | JTAG reset | Ayni gerekce, JTAG alani icin. |

**Multicycle path tanimi yoktur.**

Gercekte zamanlanmasi gereken hicbir yol false path veya asenkron saat
grubu olarak tanimlanmamistir. Iki istisna da gercek asenkron kontrol
yollaridir.

## Bilinen kisitlama eksikligi

Bilinen bir kisitlama eksikligi bulunmamaktadir.

---

# 7. Fiziksel Tasarim Yapilandirmasi

## Die ve core alani

    FP_SIZING: absolute
    DIE_AREA: [0, 0, 3832.40, 4249.24]

    Die : 3832,40 x 4249,24 um = 16,28 mm2

Die alani **makro izgarasindan hesaplanmistir**, otomatik boyutlandirmayla
degil. Uretici betik: `scripts/gen_floorplan.py`

## Makro yerlesimi

23 makro **4 sutun x 6 satir** izgarasina sabit yerlestirilmistir. Konum ve
yonelim bilgileri `config.yaml` icindeki `MACROS.instances` altindadir
(hepsi `N` yonelimli).

| Parametre | Deger |
|---|---|
| Kanal genisligi (makrolar arasi) | 200 um |
| Kenar payi (sol / sag / alt) | 250 um |
| **Ust kenar payi** | **500 um** |
| Makro halosu | **30 um** |
| PDN halosu | 30 um |
| Makro doluluk | %40,2 |

**Ust kenar payi neden farkli:** Uc ayri kosumda detayli yonlendirme
`DRT-1231 Pin ... does not have access point` hatasiyla dustu ve ucunde de
dusen makro **en ust siradaydi**. O sirada makronun ustunde die kenarina
250 um kaliyordu; anten onariminin yerlestirdigi diyotlar orayi doldurunca
pin erisimi kapandi. Ust pay 500 um'ye cikarildi.

**Makro halosu neden 30 um:** Varsayilan 10 um'de detayli yonlendirme 63
turda 23 ihlalde takiliyordu. Halo 25 um yapilinca ayni yonlendirme **12
turda 0 ihlalle** kapandi ve global yonlendirme 4:36'dan 1:30'a dustu.
Darbogaz makrolar arasi kanal degil, **makro pinlerinin cevresiydi**.

## Hedef utilization ve en boy orani

`FP_CORE_UTIL` kullanilmamaktadir (mutlak die alani verilmistir).

    En boy orani : 3832,40 / 4249,24 = 0,90

## Giris/cikis pin yerlesimi

LibreLane varsayilan IO yerlesimi kullanilmaktadir
(`OpenROAD.IOPlacement`). Ozel bir pin sirasi dosyasi verilmemistir.

## Yonlendirme katmanlari

PDK varsayilanlari: `li1`, `met1` - `met5`. Sikisiklik raporunda `li1`
kullanilmaz (yerel baglanti katmani, global yonlendirmede sayilmaz).

## Guc ve toprak aglari

| | |
|---|---|
| Guc agi | `VPWR` |
| Toprak agi | `VGND` |
| Makro guc pinleri | `vccd1` / `vssd1` |

PDN yapilandirmasi LibreLane varsayilanlarini kullanir; makro baglantisi
`PDN_MACRO_CONNECTIONS` ile acikca verilmistir (bkz. Bolum 5).

## Clock tree synthesis

`RUN_CTS` varsayilan olarak etkindir. Ozel CTS parametresi verilmemistir;
LibreLane / PDK varsayilanlari gecerlidir.

Tasarimda **saat kapisi (clock gating) etkin degildir**. CV32E40P'nin
`cv32e40p_sim_clock_gate.sv` modeli `SYNTHESIS` dalinda saati dogrudan
gecirir; netlist denetlendi, **latch uretilmemistir (0 adet)** ve butun
flip-floplar dogrudan `clk_i`'ye baglidir. Islevsel hata yoktur, guc
tasarrufu kaybi vardir.

## Otomasyon dosyalari

    Makefile                     asic_run, asic_verify, asic_clean
    scripts/gen_sources.py       config.yaml kaynak blogunu filelist.f'ten uretir
    scripts/check_filelist.py    kaynak tutarlilik denetimi
    scripts/gen_floorplan.py     makro izgarasi ve DIE_AREA hesabi
    scripts/collect_outputs.py   ciktilari reports/ ve results/ altina toplar
    scripts/check_teslim.py      teslim eksik denetimi
    scripts/check_yaml.py        config.yaml sozdizimi denetimi

---

# 8. Lint Sonuclari ve Istisnalari

Verilator lint akisin **zorunlu** parcasidir (`RUN_LINTER: true`).

| Metrik | Deger |
|---|---|
| **Lint hatasi** | **0** |
| Lint uyarisi | 810 |
| Inferred latch | **0** |

## Kullanilan waiver

**Lint waiver veya kapatilmis uyari YOKTUR.** Hicbir uyari bastirilmamis,
hicbir yapilandirma dosyasiyla susturulmamistir.

## Uyarilarin kaynagi

| Kaynak | Adet | Pay |
|---|---|---|
| LibreLane'in urettigi PDK hucre blackbox dosyasi | 447 | %55,2 |
| Ucuncu taraf kod (OpenHW CV32E40P) | 223 | %27,5 |
| **Takim tarafindan yazilan RTL** | **140** | **%17,3** |

447 uyarinin tamami `TIMESCALEMOD`'dur: LibreLane sky130 standart
hucreleri icin otomatik bir blackbox dosyasi uretir ve o dosyaya zaman
olcegi direktifi koymaz.

## Kabul edilen uyarilar ve gerekceleri

Islevsel hataya donusebilecek **yedi uyari tek tek incelenmistir**; hicbiri
gercek hata cikmamistir:

| Uyari | Adet | Inceleme sonucu |
|---|---|---|
| `UNOPTFLAT` | 6 | AXI `ready` yolunda dongu suphesi. **Yosys ve OpenSTA hicbir kombinasyonel dongu bildirmedi**, STA kapandi. Yanlis pozitif. |
| `PINMISSING` | 4 | `vccd1` / `vssd1` **kasitli** baglanmiyor; RTL'de sabite baglamak elektriksel kisa devre olurdu. Guc PDN adiminda baglanir. |
| `WIDTHTRUNC` | 3 | `get_slave_id` 0..13 dondurur, 4 bit yeter. `fc_idx` tavani 3999, 12 bit yeter. **Bilgi kaybi yok.** |
| `UNSIGNED` | 2 | `addr >= 0` sabit dogru; adres araliklarinin tek duzen yazilmasindan kaynaklanir. |
| `BLKSEQ` | 1 | `write_addr` saf gecici; tek atama, tek okuma, karisim yok. |
| `CASEINCOMPLETE` | 1 | Uc durumlu FSM 2 bitte. `case` oncesi varsayilan atama var, **latch olusmuyor**. |

**Ayrinti:** `evidence/lint/LINT_INCELEMESI.md`

## Inferred latch

**Yoktur.** Netlist denetlendi: `sky130_fd_sc_hd__dl*` hucresi 0 adet.

---

# 9. Bilinen Sorunlar ve Kabul Edilmis Istisnalar

## 9.1 `KLayout.Render` adimi atlanmaktadir

**Sorun:** Adim su hatayla dusuyor:

    The layout has multiple top cells in Layout.top_cell

**Kok neden:** Magic varsayilan `MAGIC_MACRO_STD_CELL_SOURCE: macro`
kipinde makroyu BOS bir kabuk olarak yaratip icerigi yazma aninda GDS
dosyasindan kopyalar. Makronun alt hucre tanimlari da GDS'e girer ve
**hicbir hucre onlari referans vermez** - dolayisiyla "ust hucre"
sayilirlar. GDS'te 13 ust hucre olusur: `soc_top` ve SRAM makrosunun 12 ic
hucresi.

**Tasarim saglamdir.** GDS KLayout ile denetlendi:

| Denetim | Sonuc |
|---|---|
| `sky130_sram_2kbyte_1rw1r_32x512_8` hucresi | var |
| Ust hucre mi | hayir - `soc_top` altinda |
| Icindeki ornek | 7.357 |
| Sinir kutusu | 683,1 x 416,54 um (dogru) |
| `soc_top` icindeki makro ornegi | **23** |

Fazla 12 tanim **artik tanimdir**; geometri `soc_top` altinda eksiksizdir.

**Denenen cozum:** `MAGIC_MACRO_STD_CELL_SOURCE: PDK` kipi sorunu **cozdu**
(render 17 saniyede gecti). Ancak bu kipte Magic butun makro hiyerarsisini
bellege alir: Magic RSS 10,4 GB olculdu ve 16 GB'lik gelistirme
makinesinde takas alanina dusuldu. **Yeterli bellegi olan (32 GB+) bir
makinede bu kip tercih edilmelidir.**

**Kabul gerekcesi:** `KLayout.Render`'in urettigi yerlesim goruntusu Final
Ciktilar **Bolum 6.3 "Onerilen Ek Ciktilar"** listesindedir, zorunlu
degildir. Atlanmasinin sebebi bir arac/bellek kisitidir; sonuc gizleme
amaci tasimaz. **Zorunlu hicbir dogrulama veya signoff adimi
kapatilmamistir.**

## 9.2 SRAM makrosunun tek PVT modeli

Uc signoff corner'inda da TT modeli okunmaktadir (bkz. Bolum 5).

## 9.3 Saat kapisi etkin degil

CV32E40P'nin saat kapisi `SYNTHESIS` dalinda pass-through'dur. Islevsel
hata yoktur; guc tasarrufu kaybi vardir (bkz. Bolum 7).

## 9.4 OBI -> AXI koprusunde cevrim optimizasyonu geri alindi

Kopru her islemde `ST_IDLE`'a ugrar. Bu cevrimi atlama denendi ve
**islevsel olarak yanlis** cikti: CV32E40P yanit beklerken `req`'i eski
adresle yuksek tutabiliyor, kod ayni islemi ikinci kez baslatiyordu. Geri
alindi; `ST_IDLE` cevrimi CPU'nun adres guncellemesi icin gereken ayrim
noktasidir.

## 9.5 DDK tarafindan onceden kabul edilmis istisna yoktur

Referans surumden sapma, ozel akis veya ozel adim kullanilmamistir.

---

# 10. Guc ve IR-Drop Analizi

| | |
|---|---|
| **Saat frekansi** | 50 MHz (`clk_i`, 20 ns) |
| **Timing / guc corner'lari** | `nom_tt_025C_1v80`, `nom_ss_100C_1v60`, `nom_ff_n40C_1v95` |
| **Besleme gerilimi** | 1,80 V (tt) / 1,60 V (ss) / 1,95 V (ff) |
| **Switching activity girdisi** | **Kullanilmamistir** |
| Switching activity dosyasi | yok |
| **Ozel gerilim kaynagi konum dosyasi** | **Kullanilmamistir** |

> **Guc sonuclari TAHMINIDIR.** Acik bir switching activity girdisi
> (VCD / SAIF) kullanilmamistir; OpenSTA'nin varsayilan gecis olasiligi
> varsayimlari gecerlidir.

## Guc dagilimi (nom_tt_025C_1v80)

| Bilesen | Guc | Pay |
|---|---|---|
| **SRAM makrolari (23)** | 63,9 mW | **%61,5** |
| Sirali (flip-flop + saat agaci) | 21,9 mW | %21,1 |
| Kombinasyonel | 0,34 mW | %0,3 |
| Sizinti ve diger | ~17,7 mW | %17,1 |
| **Toplam** | **~108 mW** | |

**Cikarim: guc butcesini bellek belirlemektedir.** Guc dusurmek gerekirse
ilk bakilacak yer makro erisim sikligidir, mantik optimizasyonu degil.

## Rapor konumlari

    reports/power/<corner>/power.rpt    corner basina guc
    reports/power/irdrop.rpt            IR-drop analizi
    reports/power/net-VPWR.csv          dugum bazli gerilim (guc)
    reports/power/net-VGND.csv          dugum bazli gerilim (toprak)

---

# 11. Signoff Sonuc Ozeti

> **Bu bolum akisin tamamlanmasiyla doldurulacaktir.** Asagidaki alanlar
> `reports/` altindaki nihai raporlardan aktarilacaktir.

## Kullanilan signoff PVT corner'lari

| Isim | Process | Voltaj | Sicaklik |
|---|---|---|---|
| `tt_025C_1v80` | {T, T} | 1,80 V | 25 C |
| `ss_100C_1v60` | {S, S} | 1,60 V | 100 C |
| `ff_n40C_1v95` | {F, F} | 1,95 V | -40 C |

`OpenROAD.STAPostPNR` her corner icin `min` / `nom` / `max` varyantiyla
toplam 9 analiz kosar.

## Zamanlama

| Metrik | Deger |
|---|---|
| Setup WNS | *(doldurulacak)* |
| Setup TNS | *(doldurulacak)* |
| Hold WNS | *(doldurulacak)* |
| Hold TNS | *(doldurulacak)* |

## Fiziksel signoff

| Kontrol | Sonuc |
|---|---|
| Magic DRC | *(doldurulacak)* |
| KLayout DRC | *(doldurulacak)* |
| Netgen LVS | *(doldurulacak)* |
| Anten ihlali | *(doldurulacak)* |
| XOR farki | *(doldurulacak)* |
| Baglantisiz pin | *(doldurulacak)* |
| PDN ihlali | *(doldurulacak)* |

---

# 12. Rapor ve Cikti Konumlari

| | |
|---|---|
| **LibreLane calisma etiketi** | `arkhe` |
| **Esas nihai GDSII** | `results/gds/soc_top.gds` |
| **GDSII'yi ureten arac** | **Magic** (`Magic.StreamOut`) |

Akis iki GDSII gorunumu uretir:

| Dosya | Ureten | Rol |
|---|---|---|
| `soc_top.gds` | Magic | **esas nihai cikti** |
| `soc_top.klayout.gds` | KLayout | karsilastirma (XOR) icin |

`KLayout.XOR` adimi bu iki gorunumu geometrik olarak karsilastirir.

## Zorunlu raporlar (Bolum 5)

    reports/general/      flow.log, warning.log, error.log, resolved.json
    reports/lint/         Verilator lint ciktisi
    reports/synthesis/    stat.rpt, chk.rpt, latch.rpt
    reports/routing/      congestion, wirelength, via
    reports/timing/       summary.rpt + <corner>/ alt dizinleri
    reports/drc/          Magic ve KLayout DRC
    reports/lvs/          Netgen LVS
    reports/antenna/      anten kontrol sonuclari
    reports/pdn/          PDN grid-errors
    reports/signoff/      manufacturability, XOR, baglantisiz pin
    reports/power/        <corner>/power.rpt, irdrop.rpt, net-*.csv

## Zorunlu ciktilar (Bolum 6)

    results/gds/          nihai GDSII
    results/lef/          nihai LEF
    results/def/          nihai DEF
    results/netlist/      sentez, post-PnR ve powered netlistler
    results/sdc/          PnR ve signoff SDC
    results/spef/         parazitik SPEF
    results/spice/        LVS SPICE / CDL netlisti
    results/config/       resolved.json
    results/metrics/      metrics.csv, metrics.json

## Onerilen ek ciktilar (Bolum 6.3)

    results/odb/          OpenROAD veritabani
    results/sdf/          SDF gecikme dosyasi
    results/lib/          tasarimin Liberty modeli
    results/mag/          Magic layout
    checksums/SHA256SUMS  teslim dosyalarinin ozet degerleri

`results/images/` **bostur** - `KLayout.Render` adimi atlanmaktadir
(bkz. Bolum 9.1).

## Calisma alani

`run/` LibreLane Classic akisinin **gecici** calisma alanidir. Icerigi
silindikten sonra akis yeniden calistirilabilir:

    make asic_clean
    make asic_run

Teslim sirasinda `run/` yalnizca `.gitkeep` icerir.

## Teslim denetimi

    make asic_verify

Bu komut Final Ciktilar Bolum 5, 6, 9 ve Tablo 8'e gore eksikleri sayar.

---

# 13. Ucuncu Taraf Bilesenler ve Lisanslar

Ayrintili bilgi: **`asic/THIRD_PARTY.md`**
Lisans metinleri: **`asic/licenses/`**

| Bilesen | Kaynak | Surum / commit | Lisans |
|---|---|---|---|
| CV32E40P | OpenHW Group | - | Solderpad v0.51 |
| PULP Platform Common Cells | PULP Platform | - | Solderpad v0.51 |
| SKY130 PDK | open_pdks | `8afc8346a57fe1ab7934ba5a6056ea8b43078e71` | Apache 2.0 |
| `sky130_sram_2kbyte_1rw1r_32x512_8` | SKY130A PDK | PDK ile birlikte | Apache 2.0 |
| LibreLane | librelane/librelane | `ba7193bff33d68941683b2963b90aa30cea117d1` | Apache 2.0 |

## Takim tarafindan yapilan degisiklikler

**SRAM makro Verilog modeli** - uc degisiklik, hepsi dosya icinde yorumla
isaretli:

1. `mem` bildirimi kullanimdan once gelecek sekilde yukari tasindi
2. `VERBOSE` varsayilani 1 -> 0 (simulasyon logunu bogmamasi icin)
3. `/// sta-blackbox` isareti eklendi (OpenSTA modeli netlist saniyordu)

Makronun **fiziksel gorunumleri (GDS, LEF, Liberty) degistirilmemistir.**

**CV32E40P** - degisiklik yapilmamistir; `FPU = 0` parametresiyle ornekleme
yapilmaktadir.

Ucuncu taraf bilesenlerdeki mevcut lisans ve telif bildirimleri
korunmustur.
