# ARKHE — S_final2 jüri teknik özeti

13 Eylül 2026 teslim. Esas fiziksel koşu **`S_final2`**; başka koşunun
iyi metrikleriyle birleştirilmemiştir. Teslim edilen `asic/config.yaml`
bu koşuda fiilen kullanılan yapılandırmanın birebir kendisidir
(`results/config/resolved.json` ile karşılaştırılarak doğrulanmıştır).

`S_final2`, önceki `d45_anten2` koşusunun yerini alır. Fark: şartname
§6.2'nin zorunlu tuttuğu **nihai GDSII'den çıkarılmış SPICE** ile
koşulmuştur (`MAGIC_EXT_USE_GDS=true`) ve imzalama doğrudan 23,148 ns'de
yapılmıştır — sonradan yapılan bir periyot taraması değildir.

## Mimari

CV32E40P / RV32IMC (FPU kapalı), AXI4-Lite, NPU, iki UART, I2C, QSPI, GPIO, timer, DMA ve JTAG. SKY130A / sky130_fd_sc_hd; 23 adet 2 KiB SRAM makrosu. Die 3832,40 × 4249,24 µm. LibreLane 3.0.6 Classic.

## Fiziksel sonuçlar

**Esas koşu: `S_final2`** (13 Eylül 2026). PnR hedefi **14 ns**, imzalama
ve beyan edilen çalışma noktası **23,148 ns = 43,2 MHz**. Dokuz PVT
köşesinin tamamında setup ve hold pozitiftir, TNS sıfırdır.

**50 MHz temiz kapanış yoktur** ve ulaşılan frekans olarak sunulmaz.

43,2 MHz'in seçilme nedeni: 43.200.000 / 400.000 = 108, yani I2C SCL
bölücüsü tam sayı çıkar ve EK-2'nin "SCL 400 kHz sabit" isteri tam
karşılanır.

> `constraints/design.sdc` içindeki `20.0` satırı kullanılan değer
> değildir; `CLOCK_PERIOD` ortam değişkeni tanımsızsa devreye giren
> yedektir. Üretilen `results/sdc/pnr_resolved.sdc` `-period 14.0000`
> yazar, akış logları `clk_period = 14 ns` basar. Ayrıntı:
> `asic/README.md` §6.

### Dokuz köşe STA (23,148 ns)

| Köşe | Setup slack ns | Hold slack ns |
|---|---:|---:|
| nom_tt_025C_1v80 | +2,8271 | +0,4936 |
| nom_ss_100C_1v60 | +0,8350 | +1,0878 |
| nom_ff_n40C_1v95 | +3,6716 | +0,2625 |
| min_tt_025C_1v80 | +3,2330 | +0,4891 |
| min_ss_100C_1v60 | +1,3439 | +1,0749 |
| min_ff_n40C_1v95 | +4,0363 | +0,2730 |
| max_tt_025C_1v80 | +2,3327 | +0,4966 |
| max_ss_100C_1v60 | **+0,2782** | +0,7100 |
| max_ff_n40C_1v95 | +3,2157 | **+0,0380** |

En kötü setup `max_ss_100C_1v60` (+0,2782 ns), en kötü hold
`max_ff_n40C_1v95` (+0,0380 ns). **Negatif slack yoktur.**

Kaynak: `asic/reports/timing/summary.rpt`. SRAM'in yalnız TT modeli
vardır; FF/SS köşelerinde de bu model kullanılmıştır — bu bir
yaklaşımdır ve raporda böyle belirtilmiştir.

### İmzalama kontrolleri

| Kontrol | Sonuç |
|---|---:|
| Setup (9 köşe) | **9/9 pozitif, 0 ihlalli yol, TNS 0** |
| Hold (9 köşe) | **9/9 pozitif, 0 ihlalli yol, TNS 0** |
| Anten net / pin | **0 / 0** |
| Detailed-route DRC | **0** |
| KLayout DRC | **0** |
| XOR farkı | **0** |
| PDN ihlali | **0** |
| LVS (LEF/DEF kaynaklı) | **Circuits match uniquely** |
| **LVS (nihai GDSII kaynaklı)** | **Circuits match uniquely** |
| LVS hata sayacı | 0 (cihaz/net/pin/özellik farkı hepsi 0) |
| Magic DRC | **7.658** — tamamı `nwell.4`, makro kaynaklı (aşağıda) |
| Max slew / max cap / fanout | 16.030 / 1.952 / 81 |

### Nihai GDSII'den çıkarılan SPICE (§6.2)

`MAGIC_EXT_USE_GDS=true` ile koşulmuştur: SPICE **nihai GDSII'den**
çıkarılmış, LVS'te kullanılan netlist budur.

| | |
|---|---:|
| SPICE dosyası | 119 MB |
| Çıkarılan transistör | **1.809.268** |
| Black-box girdi | **0** |

Gerçek cihaz modelleri (`sky130_fd_pr__pfet_01v8_hvt`,
`nfet_01v8`) w/l değerleriyle çıkarılmıştır.

### Tasarım büyüklüğü

| | |
|---|---:|
| Die | 3832,40 × 4249,24 µm |
| Toplam örnek | 2.053.906 |
| Standart hücre | 269.735 |
| SRAM makrosu | 23 (2 KiB × 23 = **46 KiB**) |
| Anten diyotu | 2.233 |
| Yerleşim doluluğu | %50,3 |
| Toplam güç | ~105,7 mW |

## Magic DRC değerlendirmesi

7.658 nwell.4 bulgusu LEF/DEF soyut görünümündeki tap geometrisiyle ilişkilidir. Ayrı küçük hücre deneylerinde gerçek tap GDS/MAG temiz, aynı tap MAGLEF görünümü ihlalli bulunmuştur. Tam GDS incelemeleri ayrıca SRAM bit hücresinde tekrar üretilebilen farklı katman/kural bulguları göstermiştir. Dolayısıyla bütün Magic bulguları çözülmüş veya resmi waiver alınmış kabul edilmez. KLayout 0 ve XOR 0 tek başına Magic'in bütün kural kapsamını doğrulamaz. Kaynak: `evidence/asic/MAGIC_KOK_NEDEN_DENEYLERI_20260908.md`.

## İşlevsel doğrulama ve FPGA

Tarihsel aday logları ve test kaynakları pakette korunmuştur. 5–6 Eylül NPU doğrulamasında 1.400 girdide sınıf uyuşmazlığı 0; 1.300 etiketli girdide TFLite/RTL doğruluğu %84,15. 100 stres girdisi doğruluk paydasına katılmaz. Tam CPU iş yükünde 68.474.022 çevrim ve NPU motorunda 85.587 çevrim yaklaşık 800,05× hesaplama oranı verir; veri aktarımı ve boot dahil değildir. Bu ölçümler son d45 RTL'sinin yeniden çalıştırılmış tam regresyonu olarak sunulmaz.

8 Eylül QSPI testinde yeni FIFO negatif senaryolarıyla 30 kontrol geçmiştir. Kaynak/test kayıtlarının tarih ve kapsamları `evidence/` altında tutulur. Son UVM veya kod kapsamı için tamamlanmamış loglar başarı kabul edilmez.

## Regresyon ve kod kapsama

13 Eylül 2026 itibarıyla (HEAD) regresyon **37 test / 702 denetim** ile
tamamı geçmektedir. Bütün testler kendi kendini kontrol eder; hata varsa
koşum `$fatal` ile düşer. Koşum: `python scripts/run_regression.py`

| Test | Denetim | Test | Denetim |
|---|---:|---|---:|
| npu_dogruluk | 77 | sartname_gpio | 15 |
| npu_blok | 43 | sartname_uart_stream | 15 |
| uart | 42 | interconnect_adres | 13 |
| qspi | 40 | uvm_aktif | 13 |
| dma | 39 | wstrb_kismi_yazma | 11 |
| i2c | 38 | i2c_scl_frekans | 9 |
| uvm_axi_agent | 38 | jtag_yanit_kodu | 9 |
| gpio | 37 | sram_registered | 6 |
| timer | 36 | axi_protokol | 6 |
| sartname_qspi | 27 | qspi_sck_olcum | 5 |
| jtag_debug | 27 | sram_w_yakalama | 4 |
| sartname_timer | 25 | qspi_presc_sinir | 4 |
| sync_fifo | 24 | axi_w_yakalama | 4 |
| sartname_uart | 20 | i2c_scl_periyot | 4 |
| sistem | 20 | i2c_saat_germe | 4 |
| sistem_gercek_boot | 20 | jtag_cdc | 4 |
| npu_accelerator | 16 | sinir_degerleri | 3 |
| | | npu_hizlanma | 2 |
| | | npu_golden | 1 |
| | | cekirdek_izi | 1 |

Önceki sürümlerde bildirilen "16 test / 454 denetim" 9 Eylül tarihlidir;
aradan geçen sürede 21 yeni test eklenmiştir (şartname uyum testleri,
sınır durum testleri, SRAM/AXI yazma yakalama, WSTRB kısmi yazma, QSPI
prescaler/SCK ölçümü, I2C saat germe, JTAG CDC, interconnect adres
çözme, NPU accelerator sarmalayıcı ve aktif UVM testi).

Kod kapsama **üç ayrı seviyede** ölçülür ve hangi seviyeden söz edildiği
belirtilmelidir:

| Seviye | Statement | Branch |
|---|---:|---:|
| Blok testleri (her modül kendi ortamında) | %93,6 – %97,5 | %70,8 – %92,4 |
| Bizim yazdığımız RTL (sistem seviyesi) | %81,6 | %74,9 |
| Genel rapor (CV32E40P ve paketler dahil) | %62,5 | %44,6 |

Blok testi ölçümleri:

| Blok | Statement | Branch |
|---|---:|---:|
| timer | %97,5 | %74,7 |
| gpio | %96,9 | %92,4 |
| uart | %96,9 | %87,7 |
| sync_fifo | %96,5 | %77,3 |
| npu_blok | %96,4 | %88,0 |
| dma | %96,1 | %82,7 |
| i2c | %95,6 | %79,4 |
| qspi | %94,4 | %73,0 |
| jtag_debug | %93,6 | %70,8 |

Genel rapordaki %62,5 / %44,6 rakamı **üç farklı şeyi birlikte sayar**:
bizim yazdığımız RTL, üçüncü taraf CV32E40P çekirdeği ve çalıştırılabilir
kod içermeyen SystemVerilog paket dosyaları. Paketler yalnızca tip ve sabit
tanımı içerir; kapsama metriği bunları %0 sayarak ortalamayı düşürür.
CV32E40P PULP Platform tarafından ayrıca doğrulanmış bir çekirdektir ve
bizim test kapsamımızın hedefi değildir. Ayrıştırma
`scripts/kapsam_analiz.py` ile yeniden üretilebilir; çıktı
`evidence/dogrulama/KAPSAMA_ANALIZ_20260909.txt` altındadır.

Kapsama, şartname EK-3'te **"Opsiyonel***"** olarak işaretlidir.

FPGA bitstream'lerinin yönlendirme sonrası zamanlaması, her biri kendi raporundan:

| Bitstream | Kullanım | WNS | WHS | Kaynak |
|---|---|---:|---:|---|
| `nexys_top.bit` | Demo A (resmi araç) | **+1,207 ns** | **+0,033 ns** | `fpga/nexys_demo_20260908/reports/nexys_top_timing_summary_routed.rpt` |
| `nexys_usb_top.bit` | Demo C (tam SoC + ESP32 I2C) | **+1,270 ns** | **+0,023 ns** | `fpga/DEMO_C_I2C/build_result.txt` |

Her ikisinde de TNS ve THS sıfırdır; tüm tanımlı zamanlama kısıtları sağlanmıştır.

8 Eylül 17:31'de yarışma paketiyle gelen `demo_harness.py` aracı, public dataset'in tamamıyla kart üzerinde koşulmuştur. Ham çıktılar `fpga/demo_teknofest/sonuclar/` altındadır.

| Metrik | Değer |
|---|---:|
| Gönderilen örnek | 156 |
| Golden referansı olan | 156 |
| **Golden ile uyum** | **%100,00 (156/156)** |
| Uyuşmazlık | 0 |
| Zaman aşımı | 0 |
| Gecikme (medyan / p95 / maks) | 7,74 / 8,78 / 21,58 ms |
| Ölçülen hızlanma | 183,3× |
| Sağlamlık senaryoları | **9 PASS / 1 FAIL / 1 SKIP** (FAIL: `back_to_back`; SKIP: `peripheral_interleave`, opsiyonel) |

Uyum matrisi tamamen köşegendir (silence 6, unknown 16, yes 50, no 84); köşegen dışı hücre yoktur. Donanım doğruluğu ve golden model doğruluğu %72,44 ile aynıdır, fark 0,00 puandır; bu oran veri setinin zorluğudur ve puanlamada kullanılmaz.

Başarısız tek senaryo `back_to_back`'tir: tam sırada koşulduğunda aralıksız beş çerçevenin dördüne yanıt gelmiştir. Tek başına koşulduğunda üç bağımsız tekrarda 5/5 geçmiştir; fark, kendinden önceki senaryodan devreden geçiş etkisidir. Kök nedeni `uart_stream_peripheral.sv` içindeki toplayıcı sayacının (`pack_cnt_r`) `UARTS_FIFO_CLR` ile sıfırlanmamasıdır. Düzeltmesi hazırdır ancak bu teslim yamasız RTL'e SHA-256 ile bağlı olduğu için **dahil edilmemiştir**; ayrı bir fiziksel koşumla girecektir. `peripheral_interleave` senaryosu şartname gereği opsiyoneldir ve `hooks.interleave_core_hex` tanımlanmadığı için ATLANDI olarak raporlanır.

Demo imajı DEMO_MODE ile derlenir. Normal kart imajından iki farkı vardır: çıkarımlar arası 3 saniyelik bekleme yoktur ve `UART_RDR` bayt yolu doğrulama bloğu atlanır. O blok çerçeve başına 1960 değil 1964 bayt tüketir; araç tam 1960 bayt gönderdiği için fazladan istenen 4 bayt bir sonraki çerçevenin başından karşılanır ve o çerçeve kaymış işlenirdi. Normal ve simülasyon imajları bloğu hâlâ koşar, kapsama kaybı yoktur. Ayrıntı: `fpga/demo_teknofest/OKUBENI.md`.

5 Eylül tek USB jüri provası ayrı bir firmware/wrapper sürümüdür.

Fonksiyonel doğrulama Vivado xsim 2025.2 (`xvlog`/`xelab`/`xsim`) ile yapılmıştır; DSim kullanılmamıştır.

## Teslimin kullanımı

Zorunlu raporlar `asic/reports`, nihai görünümler/netlistler/SDC/SPEF/GDS-SPICE/config/metrikler `asic/results` altındadır. `asic/run` teslimde boştur. Büyük fiziksel çıktılar (GDSII, DEF, ODB, MAG, SPEF, SDF, SPICE, netlistler) **bu depodadır** ve 100 MB'ı aşanlar **Git LFS** ile saklanır. Depoyu klonlarken `git lfs install` yapılmalıdır; yapılmazsa bu dosyalar işaretçi metni olarak iner. Yedek olarak `asic/` dizininin tamamı bulut arşivinde de sunulmuştur (ayrıntı ve SHA-256: `asic/README.md` §12.1). `make asic_verify` bütünlüğü denetler. Kurulum ve `make asic_run` açıklaması `asic/README.md` içindedir.
