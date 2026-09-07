# Ucuncu Taraf Bilesenler

TEKNOFEST 2026 - Takim ARKHE / Arkhe SoC

Final ciktilar belgesi geregi, ASIC akisinda kullanilan ucuncu taraf RTL,
IP, makro, model ve betiklerin kaynak, surum, lisans ve degisiklik bilgileri
asagida verilmistir.

---

## 1. CV32E40P RISC-V Islemci Cekirdegi

| | |
|---|---|
| Kaynak | https://github.com/openhwgroup/cv32e40p |
| Depodaki konum | `rtl/cv32e40p-master/` |
| Lisans | Solderpad Hardware License v0.51 (Apache 2.0 tabanli) |
| Lisans dosyasi | `licenses/cv32e40p-LICENSE` |
| Sartname durumu | ZORUNLU - sartname s.282 bu cekirdegin kullanilmasini sart kosuyor |

### Yapilandirma

    COREV_PULP       = 0
    COREV_CLUSTER    = 0
    FPU              = 0        -> RV32IMC
    NUM_MHPMCOUNTERS = 1

`FPU = 0` karari olcume dayanmaktadir. CV32E40P'de `FPU = 1` parametresi
cekirdege yalnizca kayan nokta buyruk cozme mantigi ve APU (koprosesor)
arayuzu ekler; asil hesaplama birimi FPnew ayri bir modul olarak
(`cv32e40p_fp_wrapper.sv`) APU arayuzune baglanmalidir.

Iki ayri sentez kosumuyla olculen maliyet:

| Yapilandirma | LUT | FF | FPU hucresi |
|---|---|---|---|
| FPU = 0 | 18.906 | 5.255 | - |
| FPU = 1 | 21.250 | 6.303 | 17 |

Sistem yazilimi ve INT8 YZ hizlandirici kayan nokta islemi icermedigi icin
`FPU = 0` secilmistir. Olcum raporu: `evidence/fpga/fpu_karar_olcumu.md`

### Degisiklikler

Cekirdek IP **degistirilmemistir**. Depodaki dosyalar yukaridaki kaynaktan
alinan haliyle kullanilmaktadir.

Simulasyon icin `bhv/cv32e40p_sim_clock_gate.sv` kullanilmaktadir; ASIC
akisinda saat kapisi PDK hucresiyle degistirilmelidir (bkz. asagidaki
"Acik maddeler").

---

## 2. PULP Platform Common Cells

| | |
|---|---|
| Kaynak | https://github.com/pulp-platform/common_cells |
| Depodaki konum | `rtl/cv32e40p-master/rtl/vendor/pulp_platform_common_cells/` |
| Lisans | Solderpad Hardware License v0.51 |
| Kullanim | CV32E40P'nin bagimliligi olarak gelir (FIFO, CDC bilesenleri) |

Degistirilmemistir.

---

## 3. SKY130 PDK

| | |
|---|---|
| Kaynak | https://github.com/google/skywater-pdk |
| Surum | `environment/versions.txt` icinde |
| Lisans | Apache License 2.0 |
| Standart hucre kutuphanesi | `sky130_fd_sc_hd` |

PDK, Nix ortami uzerinden LibreLane tarafindan saglanir; depoya
kopyalanmamistir.

---

## 4. LibreLane

| | |
|---|---|
| Kaynak | https://github.com/librelane/librelane |
| Surum | `environment/versions.txt` icinde |
| Lisans | Apache License 2.0 |
| Kullanim | Classic akisi (sentez, floorplan, yerlestirme, CTS, yonlendirme, signoff) |

Akis adimlari degistirilmemis; yalnizca `config.yaml` uzerinden
yapilandirilmistir.

---

## 5. SRAM Makrosu

| | |
|---|---|
| Makro adi | `sky130_sram_2kbyte_1rw1r_32x512_8` |
| Kaynak | SKY130A PDK, `libs.ref/sky130_sram_macros/` (OpenRAM ile uretilmis) |
| PDK surumu | ciel `8afc8346a57fe1ab7934ba5a6056ea8b43078e71` |
| Lisans | Apache License 2.0 (SkyWater PDK ile birlikte) |
| Veri genisligi | **32 bit** |
| Kelime sayisi | **512** (2 kB) |
| Yazma granularitesi | 8 bit (4 bitlik wmask) |
| Port yapisi | Port 0: RW · Port 1: R |
| Fiziksel boyut | 683,1 x 416,54 um = **0,285 mm2** |
| Zamanlama kosesi | TT_1p8V_25C |

### Tasarim icindeki instance adlari

| Instance | Bellek | Kapasite | Makro sayisi |
|---|---|---|---|
| `u_soc/u_npu/u_npu_sram/g_sram[0..14]/u_macro` | NPU TCM | 30 kB | 15 |
| `u_soc/u_instruction_ram/g_sram[0..3]/u_macro` | I-RAM | 8 kB | 4 |
| `u_soc/u_data_ram/g_sram[0..3]/u_macro` | D-RAM | 8 kB | 4 |
| **Toplam** | | **46 kB** | **23** |

Toplam makro alani: 23 x 0,285 = **6,54 mm2**

### Port eslemesi

Makro 1RW+1R yapisindadir; tasarimin bellek portlari bu yapiya gore
duzenlenmistir.

**NPU TCM** (`npu_tcm_sram.sv`):

    Port A (AXI erisimi, okuma+yazma)  -> makro Port 0 (RW)
    Port B (hesaplama motoru, okuma)   -> makro Port 1 (R)

Port B 18 Agustos 2026'da salt-okunur hale getirildi. Oncesinde hesaplama
motoru softmax sonuclarini Port B uzerinden geri yaziyordu; yani IKI YAZAN
PORT vardi ve bu yapi makroya eslenemezdi. Sonuc yazimlari
`npu_accelerator` icinde Port A'ya yonlendirildi, cakisma ise
`npu_axi_controller`'a eklenen `stall_i` ile cozuldu (erisim dusurulmez,
dort cevrim ertelenir).

**I-RAM / D-RAM** (`sram_module.sv`):

    AXI yazma kanali  -> makro Port 0 (RW)
    AXI okuma kanali  -> makro Port 1 (R)

Bu modul yazma ve okumayi zaten ayri AXI kanallarindan yapiyordu;
esleme dogaldir. Port 0'in `dout0` cikisi kullanilmaz.

### Kosullu derleme

Makro yalnizca `USE_SRAM_MACRO` tanimliyken orneklenir:

    `ifdef USE_SRAM_MACRO   -> gercek makro ornekleme (ASIC + dogrulama)
    varsayilan              -> cikarimsal dizi (FPGA Block RAM cikarimi)

Sartname makronun "islevsel dogrulama testlerinde kullanilmasini" sart
kostugu icin regresyon her iki kipte de kosulur ve ayni sonuclari
uretmesi beklenir.

### Okuma coklayicisi

Makro cikisi KAYITLIDIR: `dout`, adres verildikten sonraki cevrimde
gecerli olur. Coklayici anlik secim sinyaliyle surulurse yanlis makronun
cikisi alinir. Her iki modulde de secim sinyali bir cevrim geciktirilerek
kullanilmaktadir.

### Satici dosyasinda yapilan degisiklikler

Makronun Verilog modelinde UC degisiklik yapildi. Hicbiri davranisi,
boyutu veya zamanlamayi etkilemez:

| # | Degisiklik | Neden |
|---|---|---|
| 1 | `mem` bildirimi yukari tasindi | Vivado xvlog "identifier 'mem' is used before its declaration" hatasi veriyordu; ozgun dosyada `$display` satirlari bildirimden once mem'i kullaniyordu |
| 2 | `VERBOSE` varsayilani 1 -> 0 | Model her okuma/yazmada `$display` yapiyordu; 23 makro ile simulasyon logu kullanilamaz hale geliyordu. Ornekleme sirasinda parametre gecersiz kilmak Verilator lint'te blackbox oldugu icin cozumlenemiyordu |
| 3 | Basa `/// sta-blackbox` eklendi | OpenSTA dosyayi gate-level netlist sanip okumaya calisiyor ve satir 20'de sozdizimi hatasi veriyordu. Aracin kendi onerdigi cozum; zamanlama bilgisi zaten `.lib` dosyasindan geliyor |

Fiziksel gorunumler (gds, lef, lib, spice) **degistirilmemistir**.

### PVT koseleri - bilinen sinir

LibreLane akisi uc kosede zamanlama analizi yapiyor:

    nom_tt_025C_1v80    tipik
    nom_ff_n40C_1v95    hizli  (-40 C, 1,95 V)
    nom_ss_100C_1v60    yavas  (100 C, 1,60 V)

Standart hucre kutuphanesinin ucu icin de modeli var. Ancak kullandigimiz
SRAM makrosunun YALNIZCA `TT_1p8V_25C` modeli mevcut; akis uc kosede de
ayni tipik modeli okuyor.

Bu, makronun hizli ve yavas kosedeki davranisinin gercekci
modellenmedigi anlamina gelir. Alternatif `sram_1rw1r_32_256_8_sky130`
makrosunda FF/SS koseleri var, ancak 1 kB oldugu icin 46 kB toplam icin
46 ornekleme gerekirdi (23 yerine).

Karar: akis tamamlanana kadar tek koseyle devam; cok koseli imzalama
zorunlu tutulursa makro degisimi degerlendirilecek.

### `config/` dizini bos

Hazir PDK makrosu kullanildigi icin OpenRAM uretim yapilandirmasi
bulunmamaktadir. Kendi makromuzu uretseydik OpenRAM yapilandirma dosyalari
bu dizinde olacakti.

## Acik maddeler

1. **PVT koseleri** - kullanilan makronun yalnizca TT_1p8V_25C zamanlama
   modeli mevcuttur. Cok koseli imzalama gerekirse
   `sram_1rw1r_32_256_8_sky130` makrosuna gecilebilir (FF/SS koseleri var,
   ancak 1 kB oldugu icin 46 kB toplam 46 ornekleme gerektirir).
2. **Saat kapisi hucresi** - `cv32e40p_sim_clock_gate.sv` simulasyon
   icindir; ASIC akisinda `sky130_fd_sc_hd__dlclkp` benzeri bir PDK
   hucresiyle degistirilmelidir.
3. **ROM icerikleri** - `$readmemh` ile yuklenen `.mem` / `.hex` dosyalari
   (`dw_weights`, `fc_weights`, `dw_bias`, `fc_bias`, `softmax_exp_lut`,
   `boot.hex`). Bunlar takimin kendi urettigi verilerdir, ucuncu taraf
   degildir; ancak ASIC akisinda cozumlenebilmeleri icin yol
   yapilandirmasi gerekir.
