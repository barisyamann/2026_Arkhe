# AXI/UVM Kapsam Matrisi

**Sartname Bolum 5.2 (odul icin asgari basari kriteri):**

> "Cevre birimleri ve YZ hizlandiricinin {AXI or AXI-Lite} arayuzlerinin
> en azindan protocol check duzeyinde AXI agent'lariyla dogrulanmasi."

Bu belge, **hangi cevre biriminin hangi agent/checker tarafindan
gorulduğunu** olculmus sayilarla gosterir. Rakamlar iddia degil,
`uvm_axi_agent` regresyon kosumunun kendi ciktisindandir
(`build/regression/uvm_axi_agent/sim.log`).

---

## 1. Dogrulama noktalari

Tasarimda **iki UVM agent** ve **bes SVA protokol denetleyicisi** vardir.

### UVM agent'lari

| Agent | Baglanti noktasi | Gorduğu adres uzayi | Islem |
|---|---|---|---|
| `env.agent` | `u_npu.eng_*` | NPU motoru -> TCM (`0x0`–`0x76bc`) | **162.064** |
| `env.soc_agent` | `uut.merged_m_*` | **Tum SoC** (CPU+DMA+JTAG birlesimi) | **239.665** |
| | | **TOPLAM** | **401.729** |

`merged_m_*`, CPU, DMA ve JTAG master'larinin birlestigi ve
interconnect'e giren noktadir (`rtl/soc_top.sv:449-465`). **Butun SoC
trafigi buradan gecer**, dolayisiyla her slave erisimi bu agent
tarafindan gorulur.

### SVA protokol denetleyicileri (`axil_protocol_checker`)

Bunlar `UVM_AXI` bayragi olmadan da, **her regresyon kosumunda** aktiftir.

| Ornek | Bind edildigi nokta | Kapsam |
|---|---|---|
| `u_protocol_checker` | `soc_top.merged_m_*` | Birlesik master yolu |
| `u_pc_cpu` | `soc_top.data_axil_*` | M0 - CPU veri portu (OBI->AXI koprusu) |
| `u_pc_jtag` | `soc_top.jtag_m_*` | M1 - JTAG/Debug master |
| `u_pc_dma` | `soc_top.dma_m_*` | M2 - DMA master |
| `u_pc_npu_eng` | `npu_accelerator.eng_*` | NPU motoru AXI master |

---

## 2. Cevre birimi kapsam matrisi

SoC ana yolu agent'inin covergroup'u **13 ayri bolge bin'i** tutar
(`tb/uvm/axil_uvm_pkg.sv`, `soc_islem_kapsami.bolge_cp`).

**Olculen bolge kapsami: %100,0** — yani asagidaki bolgelerin
**tamami** gercek trafikle uyarilmistir.

| # | Cevre birimi / bolge | Adres araligi | UVM agent | SVA checker | Yonlendirilmis test |
|---|---|---|---|---|---|
| 1 | Boot ROM | `0x0000_0000`–`0x0000_03FF` | `soc_agent` | `u_protocol_checker`, `u_pc_cpu` | `sistem_gercek_boot` |
| 2 | I-RAM | `0x0100_0000`–`0x0100_1FFF` | `soc_agent` | ayni | `sistem`, `sistem_gercek_boot` |
| 3 | D-RAM | `0x2000_0000`–`0x2000_1FFF` | `soc_agent` | ayni | `sistem`, `sram_w_yakalama` |
| 4 | NPU bellegi (TCM) | `0x2001_0000`–`0x2001_77FF` | `soc_agent` **+ `agent`** | `u_pc_npu_eng` | `npu_blok`, `npu_accelerator` |
| 5 | **GPIO** | `0x4000_0000`–`0x4000_0FFF` | `soc_agent` | `u_protocol_checker` | `gpio`, `sartname_gpio` |
| 6 | **Timer** | `0x4001_0000`–`0x4001_0FFF` | `soc_agent` | ayni | `timer`, `sartname_timer` |
| 7 | **UART1** | `0x4002_0000`–`0x4002_0FFF` | `soc_agent` | ayni | `uart`, `sartname_uart` |
| 8 | **UART2 (stream)** | `0x4003_0000`–`0x4003_0FFF` | `soc_agent` | ayni | `sartname_uart_stream` |
| 9 | **I2C** | `0x4004_0000`–`0x4004_0FFF` | `soc_agent` | ayni | `i2c`, `i2c_scl_frekans`, `i2c_saat_germe` |
| 10 | **QSPI** | `0x4005_0000`–`0x4005_0FFF` | `soc_agent` | ayni | `qspi`, `sartname_qspi`, `qspi_sck_olcum` |
| 11 | **NPU CSR** | `0x4006_0000`–`0x4006_0FFF` | `soc_agent` | ayni | `npu_accelerator` |
| 12 | **DMA** | `0x4007_0000`–`0x4007_0FFF` | `soc_agent` | `u_pc_dma` | `dma` |
| 13 | **JTAG** | `0x4008_0000`–`0x4008_0FFF` | `soc_agent` | `u_pc_jtag` | `jtag_debug`, `jtag_cdc`, `jtag_yanit_kodu` |

Sartnamenin saydigi **butun** cevre birimleri (GPIO, Timer, UART x2,
I2C, QSPI, DMA) ve **YZ hizlandirici** (NPU CSR + TCM/motor) hem UVM
agent'i hem SVA checker tarafindan gorulmektedir.

---

## 3. Olculen protokol denetimleri

Pasif kosumda otomatik denetlenen ve **gecen** maddeler:

| Denetim | Sonuc |
|---|---|
| Yakalanan AXI4-Lite islemi | 401.729 |
| Gecersiz yanit kodu (EXOKAY) | **0** — AXI4-Lite yanit kumesi dogru |
| Asili kalmis islem (>10 us) | **0** |
| WSTRB == 0 olan yazma | **0** (her yazma en az bir bayt yazar) |
| Adres hizalamasi | Tumu 4 bayta hizali |
| Master kanal kararliligi (AR/AW/W) | VALID dusmedi, bilgi degismedi |
| Slave kanal kararliligi (R/B) | VALID dusmedi, yanit degismedi |
| El sikisan cevrimlerde X/Z | **0** |
| Reset aktifken VALID yuksek | **0** cevrim |
| Monitor kacirma (ham sinyal capraz kontrolu) | R: 382.691 = 382.691 · B: 19.038 = 19.038 |

### Referans model (veri dogrulugu)

Protokol dogru ama **veri yanlis yere yazildi** hatalarini yakalar:

| | Izlenen adres | Dogrulanan okuma |
|---|---|---|
| SoC yolu | 3.647 | **1.038** |
| NPU TCM | 4 | 0 (*) |

`[OK] 1038 okumada yazilan deger BIREBIR geri okundu`

(*) NPU TCM'e yazilan degerler simulasyon boyunca geri okunmadigi icin
dogrulama firsati dogmaz. Bu bir eksiklik degil, trafigin dogasidir.

---

## 4. Fonksiyonel kapsam

| Kapsam noktasi | NPU agent | SoC agent |
|---|---|---|
| Islem turu (okuma/yazma) | %100,0 | %100,0 |
| **Adres bolgesi** | %75,0 | **%100,0** |
| WSTRB deseni | %33,3 | %66,7 |
| Yanit kodu | %33,3 | %100,0 |
| **TOPLAM** | %52,1 | **%91,0** |

### NPU agent'inin %52,1'i neden dusuk

Gercek NPU motoru yalnizca **tam-word** (`strb=0xf`) erisim yapar ve
slave her zaman **OKAY** doner. Pasif izleme tanim geregi var olmayan
trafigi uyaramaz; bu bir dogrulama bosluğu degil, trafigin dogasidir.

Bu bin'leri kapatmak icin **aktif test** eklenmistir (`uvm_aktif`):
sequence'ler kismi WSTRB desenleri ve SLVERR/DECERR yanitlari uretir.
Aktif kosumda `strb` kapsami **%100**'e cikar.

---

## 5. Aktif test hakkinda durust not

`uvm_aktif` testi, agent'lari `UVM_ACTIVE` kurar ve dort sequence kosar
(`axil_wstrb_seq`, `axil_yanit_seq`, `axil_rastgele_seq`,
`axil_sanal_seq`).

**Bagimsiz bir arayuz uzerinde kosar, tasarima surmez.** Sebebi:
`soc_bus_if` ve `npu_eng_if` pasif gozlem noktalaridir — sinyalleri
`assign` ile tasarima baglidir ve surekli atama driver'i ezer. SoC'ta
bos (kullanilmayan) bir AXI slave portu da yoktur; aktif agent'i
tasarima baglamak RTL degisikligi gerektirirdi ve teslim edilen GDS'nin
kaynak SHA-256 butunlugunu bozardi.

Dolayisiyla:

- **Tasarimin AXI uyumu**, pasif agent (401.729 islem) + 5 SVA checker
  ile dogrulanir. Yukaridaki matris ve denetim tablosu budur.
- **`uvm_aktif`**, UVM ortaminin kendi altyapisini (driver, sequencer,
  sequence, scoreboard, coverage kapanisi) dogrular ve kapsam kapatma
  yolunu gosterir.

Bu ayrim bilerek korunmustur; aktif testin urettigi kapsam, tasarim
dogrulamasi olarak sunulmamaktadir.

---

## 6. Ozet

| Sartname Bolum 5.2 gereksinimi | Durum |
|---|---|
| Cevre birimlerinin AXI arayuzleri protocol-check | **13/13 bolge**, bolge kapsami %100 |
| YZ hizlandiricinin AXI arayuzu protocol-check | NPU CSR + TCM, ayrica ozel agent (162.064 islem) |
| AXI agent kullanimi | 2 UVM agent + 5 SVA checker |
| Protokol ihlali | **0** |

Kaynak: `build/regression/uvm_axi_agent/sim.log`
Kosum: 13 Eylul 2026, HEAD · 37/37 test, 702 denetim
