# ARKHE — S_final2 ASIC teslimi

Bu paket 13 Eylül 2026 tarihli **`S_final2`** koşusunun kaynakları, raporları ve fiziksel çıktılarıdır. Koşu adı akış loglarında da görülebilir (`reports/general/flow.log` → `runs/S_final2/`) ve `environment/versions.txt` ile eşleşir.

**Beyan edilen çalışma noktası: 23,148 ns (43,2 MHz). Dokuz PVT köşesinin tamamında setup ve hold pozitiftir, setup TNS sıfırdır.**

Bu koşu, RTL'de 10 Eylül 2026'da bulunan dört işlevsel hatanın (üç modülde AXI W kanalı veri kaybı, QSPI prescaler taşması) düzeltilmesinden sonra alınan ilk tam koşudur. Önceki ASIC koşuları (örn. `d45_anten2`) düzeltme öncesi RTL ile yapılmıştı ve teslim edilmemektedir; kaynak eşitliği artık `scripts/rtl_manifest.py` ile her koşu öncesi kanıtlanmaktadır.

Açık kalan kalemler gizlenmemiştir; §11'de sayısal olarak verilmiş ve kaynakları belirtilmiştir.

## 1. Tasarım

Üst modül `soc_top`; CV32E40P (RV32IMC, FPU kapalı), NPU ve AXI-Lite çevre birimleri. Ana saat `clk_i`, reset `rst_ni`, JTAG saati `jtag_tck`. GPIO, UART, I2C, QSPI ve JTAG portları vardır; kesin arayüz `rtl/Memory/soc_top.sv` içindedir.

**Saat hedefi:** İmza (signoff) periyodu **23,148 ns = 43,2 MHz**'dir ve `reports/timing/` altındaki dokuz köşe raporu bu periyotta üretilmiştir (`reports/timing/<köşe>/ws.max.rpt` → max_ss için **+0,2782 ns**, `wns.max.rpt` ve `tns.max.rpt` → **0,0**, yani ihlalli yol yoktur; hold da dokuz köşede pozitiftir, en dar köşe max_ff **+0,0380 ns**). PnR sırasında kullanılan **14 ns**'lik hedef bir iç optimizasyon parametresidir, beyan edilen çalışma noktası değildir: PnR SDC'si akışı sıkıştırmak için, imza SDC'si gerçek ölçüm için kullanılır (bkz. §6). Bu ayrımın gerekliliği ölçülerek doğrulanmıştır — PnR hedefi imza hedefine eşitlendiğinde (23/23 ns) akış gevşeyip üç SS köşesinde setup ve hold çökmüştür.

**43,2 MHz neden seçildi:** Bu frekans 400 kHz'e tam bölünür (43.200.000 / 400.000 = 108), böylece I2C SCL bölücüsü tam sayı çıkar ve şartname EK-2'nin *"SCL saat frekansı 400 kHz sabit hızında olacaktır"* isteri ASIC hedefinde de **tam** karşılanır (ölçülen: 400.000,00 Hz, sapma sıfır; `tb/tb_i2c_scl_frekans.sv`, 9 denetim). Çevre birimi bölücüleri `soc_top.sv`'deki tek bir `SYS_CLK_HZ` parametresinden türetilir; FPGA hedefinde 50 MHz, ASIC hedefinde 43,2 MHz verilir. RTL kaynağı iki hedefte **aynıdır** — `ifdef` ile ayrılmamıştır. Ölçüm dökümü `evidence/sartname/ASIC_SAAT_BAGIMLILIGI.md` ve `evidence/denetim_20260910/S_SAAT_KOSU.md` içindedir.

## 2. Araç ve ortam

LibreLane **3.0.6 Classic**, Debian 12 x86_64, SKY130A / `sky130_fd_sc_hd`. Open PDKs sürümü `8afc8346a57fe1ab7934ba5a6056ea8b43078e71`.

| Alan | Değer |
|---|---|
| LibreLane sürümü | **3.0.6** |
| LibreLane commit / Git etiketi | `3.0.6` etiketi; flake revizyonu `ba7193bff33d68941683b2963b90aa30cea117d1` |
| LibreLane akışı | **Classic** |
| PDK | **sky130A** |
| Open PDKs commit | `8afc8346a57fe1ab7934ba5a6056ea8b43078e71` |
| Standart hücre kütüphanesi | `sky130_fd_sc_hd` |
| OpenRAM sürümü | **OpenRAM kullanılmadı** (hazır PDK makrosu `sky130_sram_2kbyte_1rw1r_32x512_8`, 23 örnek) |
| Referans sürümden sapma | Yok — tüm araç ve kütüphaneler referans sürümdedir |
| `versions.txt` konumu | `asic/environment/versions.txt` |
 Araç sürümleri `environment/versions.txt`, Nix bağımlılıkları `environment/flake.nix` ve `environment/flake.lock` içindedir. Ham koşunun her adımındaki `COMMANDS` dosyası kullanılan gerçek araç yolunu korur. Eski WSL ortam anlatımı yalnızca `provenance/historical_versions_20260820.txt` içinde tarihsel belge olarak tutulur.

## 3. Yeniden çalıştırma ve paket doğrulama

Depo kökünden:

**Kaynak gereksinimi ve süre** (S_final2 koşusunun ölçülen değerleri):

| | |
|---|---|
| Çalışma süresi | **~5,5 saat** (sentezden LVS'e, 79 adım) |
| En uzun adımlar | Detailed routing ~2 sa · KLayout DRC ~1 sa · Magic DRC ~40 dk |
| Önerilen CPU | 8+ çekirdek (`NPROC` ile paralelleşir) |
| Önerilen RAM | **32 GB** (Magic GDS çıkarımı tepe 8,8 GB) |
| Gereken disk | **~20 GB** boş alan (`asic/run/` çalışma alanı için) |

```bash
nix develop ./asic/environment
export PDK_ROOT=/kendi/pdk/dizininiz
cd asic
make asic_verify
make asic_run
```

`PDK_ROOT`, sabitlenmiş sürümün `sky130A` alt dizinini içeren dizindir; makineye göre ayarlanır. PDK lisanslı kaynakları Nix/Ciel kurulumuyla sağlanır; sistem Nix store veya tüm PDK teslim arşivine kopyalanmamıştır. OpenRAM çalıştırılmamıştır.

`make asic_run` temiz, zaman etiketli bir `asic/run/` çalışma alanı kullanır; LibreLane'in varsayılan `runs` yolu bu dizine yönlendirilir. Mevcut koşu üzerine yazılmaz. Akış bittikten sonra raporlar kaynak adım eşlemesiyle toplanır ve aynı GDS için ek çıkarım/LVS aşaması çağrılır; akış başarısızlığı toplama başarılı olsa da nonzero olarak döndürülür. `make collect RUN=run/<etiket>` elle toplama, `make gds_lvs` ek GDS kontrolü içindir. Önceki raporlar tarihli collection dizininde korunur. `make asic_verify` yayımlanan dosya ve SHA-256 bütünlüğünü kontrol eder; signoff başarısı anlamına gelmez. Yeniden üretilmiş sonuçların özgün teslim hash'leriyle aynı olması beklenmez; bu durumda yeni raporlar ayrıca değerlendirilmelidir.

Paketleme sırasında yapılandırma/lint çalıştırıldı; tam PnR yeniden çalıştırılmadı. Kanıt `evidence/packaging_config_check_runs`; etkin ayar karşılaştırması `provenance/config_comparison.json` — **380 anahtar aynı, gerçek tasarım farkı 0** (30 fark akışın kendi eklediği mutlak yollardır). `python scripts/config_karsilastir.py` ile yeniden üretilir. Çok saat süren fiziksel akış için 8 çekirdek ve yaklaşık 62 GB RAM kullanılan referanstır; 16 GB ham koşuya ek PDK/geçici alan gerekir. Temiz makinede en az 40 GB boş çalışma alanı önerilir; bitiş süresi garanti edilmez.

## 4. RTL ve girdiler

`filelist.f` depo köküne göre kaynakları listeler. `config.yaml` aynı 57 kaynak için `asic/` dizinine göre yollar kullanır; JSON biçimi geçerli YAML'dır. Include dizinleri, `USE_SRAM_MACRO` tanımı ve bütün etkin ayarlar bu dosyada bulunur. `results/config/resolved.json` özgün, değiştirilmemiş koşu yapılandırmasıdır; tarihsel mutlak yollar burada bilerek korunmuştur.

RTL, testbench ve yazılım kökteki `rtl/`, `tb/`, `sw_nexys/`, `scripts/` dizinlerindedir. Model/ağırlık ve yardımcı proje dosyaları da korunmuştur. `provenance/source_hashes.json` paketleme anındaki RTL hash'lerini içerir. 5 Eylül aday manifestinden farklı dosya `rtl/npu/npu_tcm_sram.sv`'dir. Hiçbir RTL dosyasının mtime'ı bu koşunun sentez başlangıcından yeni değildir. Ek kontrol: senteze giren 57 dosyanın tamamı `asic/rtl_manifest.txt` ile SHA-256 düzeyinde eşleşir:

```bash
python scripts/rtl_manifest.py dogrula asic/rtl_manifest.txt
# SONUC: TUM DOSYALAR ESLESIYOR  (57 dosya)
```

Hash'ler satır sonları LF'e normalize edilerek alınır; CRLF/LF farkı gerçek kaynak farkı sayılmaz.

> **Not.** `provenance/git_source_match.json` dosyası **önceki `d45_anten2` koşusuna** aittir ve o koşunun kaynağının `d800acb` commit'iyle eşleştiğini kaydeder. S_final2'nin kaynak kanıtı yukarıdaki manifest doğrulamasıdır; iki dosya karıştırılmamalıdır.

5 Eylül doğrulama logları `evidence/candidate_validation` altında **tarihsel aday testi** olarak korunmuştur; değiştirilmiş son RTL için yeni tam regresyon sonucu olarak sunulmaz.

## 5. SRAM ve makrolar

`sky130_sram_2kbyte_1rw1r_32x512_8`: 32 bit × 512 kelime, 2 KiB, 1RW+1R. Toplam 23 instance: NPU TCM 15, komut RAM 4, veri RAM 4. Instance adları (nihai `results/netlist/soc_top_pnr.v` içinden sayılmıştır):

| Üst modül | Instance deseni | Adet |
|---|---|---:|
| `u_npu` | `u_npu.u_npu_sram.g_sram[0..14].u_macro` | **15** |
| `u_instruction_ram` | `u_instruction_ram.g_sram[0..3].u_macro` | **4** |
| `u_data_ram` | `u_data_ram.g_sram[0..3].u_macro` | **4** |
| | **TOPLAM** | **23** |

23 × 2 KiB = **46 KiB** (NPU TCM 30 KiB + I-RAM 8 KiB + D-RAM 8 KiB). Yerleşim konumları `config.yaml/MACROS` içinde; GDS/LEF/Verilog/Liberty/SPICE görünümleri `macros/` altında teslim edilir. Makro güç pinleri `vccd1/vssd1`, SoC güç ağları `VPWR/VGND`; bağlantı eşlemeleri `PDN_MACRO_CONNECTIONS` içindedir.

SRAM Liberty yalnızca TT/1,8V/25°C'dir ve FF/SS dahil dokuz STA köşesinde aynı model kullanılır. Dokuz ayrı SRAM karakterizasyonu iddia edilmez. Bu tek köşe modelinin imza marjına etkisi ölçülmüştür: aynı teknolojide çok köşeli olarak karakterize edilmiş muadil makro (`sram_1rw1r_32_256_8_sky130_{TT,SS,FF}_1p8V_25C.lib`) üzerinden clk→dout gecikmesinin işlem köşesi duyarlılığı **%10** çıkmıştır (en kötü +0,059 ns; SS/TT oranı 1,100/1,100/1,099). Köşe dosyalarının başlıkları (`nom_voltage 1.8`, `nom_temperature 25`) aynı olduğundan bu fark yalnızca işlem (P) bileşenini kapsar. Bu artış dokuz köşe marjlarına uygulandığında tüm köşeler pozitif kalır: en dar setup max_ss +0,3965 → **+0,3375 ns**, en dar hold min_ff +0,3738 → **+0,3138 ns**. Ölçüm ve yöntem `evidence/denetim_20260910/SRAM_KOSE_MODELI_OLCUMU.md` içindedir. Bu bir tahmindir; makronun kendi dokuz köşe karakterizasyonu yerine geçmez.

Bu yaklaşım DDK kararıyla uyumludur. 10 Eylül 2026 tarihinde "2026 ÇİP TASARIM YARIŞMASI" grubunda aynı makronun Liberty sınırları hakkında yöneltilen soruya verilen cevapta şu hüküm yer alır: *"Referans PDK içerisinde ilgili SRAM için zorunlu signoff PVT corner'larının her birine birebir karşılık gelen Liberty modeli bulunmaması durumunda, mevcut en yakın referans modelin kullanılması ve bu varsayımın raporlanması kabul edilmektedir."* Bu paketteki dokuz köşe STA'sı referans PDK Liberty modeliyle koşulmuştur; yeniden karakterize edilmiş bir model kullanılmamıştır. Karar metni ve bizim ek analizimiz `evidence/denetim_20260910/LIBERTY_EK_ANALIZ.md` içindedir. SRAM anten modelinin kapsamı `15-odb-checkmacroantennaproperties` ve `63-odb-checkdesignantennaproperties` özgün adım kayıtlarında görülebilir. İç makro doğrulaması ile üst düzey bağlantı kontrolü ayrı kapsamlardır.

## 6. Saatler ve istisnalar

PnR girdisi `constraints/design.sdc`, signoff girdisi `constraints/signoff_50mhz_hedef.sdc`; teslim kopyaları `results/sdc/pnr.sdc` ve `results/sdc/signoff.sdc`.

**Birincil saatler**

| Saat | Port | Periyot | Rol |
|---|---|---|---|
| `clk_i` (PnR) | `clk_i` | **14 ns** | İç optimizasyon hedefi |
| `clk_i` (signoff) | `clk_i` | **23,148 ns** (43,2 MHz) | **Beyan edilen çalışma noktası** |
| `jtag_clk` | `jtag_tck` | 100 ns | Hata ayıklama arayüzü |

İki ayrı SDC kullanılmasının gerekçesi ve ölçülmüş kanıtı bu bölümün devamındadır; tek SDC'yi iki rol için kullanmak ölçülerek elenmiştir.

**`design.sdc` içindeki `20.0` sayısı hakkında** (sık sorulan)

`constraints/design.sdc` dosyasında `set clk_period 20.0` satırı görülür.
Bu **kullanılan değer değildir**; yalnızca `CLOCK_PERIOD` ortam değişkeni
tanımsızsa devreye giren yedek değerdir:

```tcl
if {[info exists ::env(CLOCK_PERIOD)]} {
    set clk_period $::env(CLOCK_PERIOD)
} else {
    set clk_period 20.0        ;# yalnizca yedek - akista kullanilmaz
}
```

Akış `config.yaml`'daki `CLOCK_PERIOD: 14`'ü daima ortam değişkeni olarak
geçirir, dolayısıyla 20.0 dalına hiç girilmez. Üç bağımsız kanıt:

| Kanıt | Nerede | Değer |
|---|---|---|
| Çözümlenmiş PnR SDC | `results/sdc/pnr_resolved.sdc` | `create_clock ... -period 14.0000` |
| Akış logları | `reports/*/openroad-*.log` (ilk satırlar) | `design.sdc: clk_period = 14 ns` |
| Signoff STA saat kenarı | `reports/timing/*/max.rpt` | `11.573999` = 23,148 / 2 |

Kendiniz doğrulamak için:

```bash
grep create_clock asic/results/sdc/pnr_resolved.sdc
grep -m1 "clk_period" asic/reports/routing/openroad-detailedrouting.log
```

Özetle üç sayının rolleri: **14 ns** PnR optimizasyon hedefi (fiilen
kullanılan), **23,148 ns** signoff ve beyan edilen çalışma noktası (dokuz
köşenin tamamı bu periyotta), **20,0 ns** yalnızca ölü yedek satır.

**Diğer kısıtlar** (tamamı `results/sdc/` içinde, gerekçeleri SDC yorumlarında):

| Kısıt | Değer |
|---|---|
| `set_clock_uncertainty -setup` | 0,25 ns |
| `set_clock_uncertainty -hold` | 0,10 ns |
| `set_input_delay` / `set_output_delay` | Ana saat periyodunun bir oranı (`$io_delay`); JTAG portları için ayrı (`$jtag_io_delay`) |
| `set_input_transition` / `set_load` | SDC'de tanımlı |
| `set_clock_groups -asynchronous` | `clk_i` ↔ `jtag_clk` (gerçekten asenkron; CDC senkronizatörleri `tb_jtag_cdc` ile doğrulanmıştır) |

**Zamanlama istisnaları.** Tek istisna `set_false_path -from [get_ports jtag_trst_n]`'dir: `jtag_trst_n` asenkron bir reset girişidir ve hiçbir senkron yolu kısıtlamaz. Bunun dışında **false path veya multicycle path tanımı yoktur**; gerçekte zamanlanması gereken hiçbir yol istisna ile kapsam dışına alınmamıştır. Hiçbir kısıt, ihlalleri gizlemek amacıyla değiştirilmemiştir.

## 7. Fiziksel yapılandırma

Die: `0 0 3832.40 4249.24` µm; yönlendirme katmanları met1–met5. SRAM yerleşimleri, core/utilization/density, pin düzeni, CTS, güç dağıtımı ve anten onarım ayarları `config.yaml` içinde aynen aktarılmıştır. Makro/hücre/pin/PDN geometrisinin kanıtı `results/def/soc_top.def` ve `results/odb/soc_top.odb`'dir. Yerleşim görüntüsü `results/images/soc_top.png`.

## 8. Lint ve yapısal kontroller

Özgün akış: lint **hata 0**, **uyarı 813**, **inferred latch 0**, unmapped cell 0, timing construct 0. Ham log `reports/lint/verilator-lint.log` altındadır ve değiştirilmemiştir.

**Not:** Uyarı sayısı 816'dan 813'e düşmüştür. Sebebi 12 Eylül 2026'da
düzeltilen üç kullanılmayan porttur (`i2c_peripheral.scl_i`,
`jtag_debug.m_axi_rresp`, `jtag_debug.m_axi_bresp`) — bu portlar artık
gerçekten okunduğu için `UNUSEDSIGNAL` sayısı 167'den 164'e inmiştir.
Ayrıntı §9 ve
`verification/kanitlar/KULLANILMAYAN_PORT_DUZELTMELERI.md`.

### Uyarı kategorileri ve değerlendirme

| Kategori | Adet | Değerlendirme |
|---|---:|---|
| `TIMESCALEMOD` | 450 | Modüller arası `timescale` tutarsızlığı. Sentezi etkilemez; simülasyonda testbench'in timescale'i geçerlidir. |
| `UNUSEDSIGNAL` | 164 | Kullanılmayan sinyaller. Bir kısmı aşağıdaki kullanılmayan portlarla örtüşür (§9). 12 Eylül düzeltmeleriyle 167'den 164'e indi. |
| `UNUSEDPARAM` | 53 | Kullanılmayan parametreler; çoğu üçüncü taraf CV32E40P kaynağında. |
| `WIDTHEXPAND` | 52 | Bit genişletme. Değer aralığı hedef genişliğe sığdığı için güvenlidir. |
| `WIDTHTRUNC` | 30 | Bit kesme. **İncelendi:** en belirgin ikisi `axi_lite_interconnect.sv:373,515` — `get_slave_id()` 32 bit döndürür, 4 bitlik `write_sel_d`/`read_sel_d`'ye atanır. Fonksiyonun döndürdüğü değer aralığı **0–13** olduğundan 4 bit yeterlidir ve kesme veri kaybına yol açmaz. |
| `PINCONNECTEMPTY` | 26 | Kasıtlı boş bırakılan port bağlantıları. |
| `VARHIDDEN` | 9 | İsim gölgeleme; işlevsel etkisi yoktur. |
| `UNOPTFLAT` | 8 | Verilator optimizasyon uyarısı; sentezi etkilemez. |
| `CASEINCOMPLETE` | 7 | **Tamamı üçüncü taraf CV32E40P kaynağındadır**, bizim RTL'imizde yoktur. `inferred latch` sayısı 0 olduğu için latch üretilmemiştir. |
| `GENUNNAMED` | 6 | İsimsiz generate blokları. |
| `PINMISSING` | 4 | Eksik port bağlantısı; üçüncü taraf kaynakta. |
| `UNSIGNED` | 2 | İşaretsiz karşılaştırma uyarısı. |
| `COMBDLY` | 1 | Kombinasyonel blokta gecikmeli atama; üçüncü taraf kaynakta. |
| `BLKSEQ` | 1 | Sıralı blokta bloklayan atama; üçüncü taraf kaynakta. |

### Kaynak dağılımı

    rtl/Memory/            542
    rtl/cv32e40p-master/   349   (üçüncü taraf)
    rtl/Cevre_Birimleri/    50
    rtl/npu/                38
    rtl/boot/                2

**Hiçbir uyarı waiver ile kapatılmamıştır.** `config.yaml/LINTER_*` ve
`ERROR_ON_*` ayarları akışın hata eşiklerini belirler; bunlar bir
temizlik onayı değildir. Toplu resmi waiver kabulü iddia edilmez.

**Latch yoktur:** `design__inferred_latch__count = 0`.

## 9. Bilinen sorunlar ve kapsam

### Buyruk getirme adres çözücüsü — geçersiz adres için hata yolu yok

**Bulgu (13 Eylül 2026, dış inceleme).** `rtl/Memory/soc_top.sv:550`
buyruk tarafı adres çözümünü **iki yollu** yapar:

```systemverilog
assign instr_to_rom    = (instr_axil_araddr[31:24] == 8'h00);
assign iram_m0_arvalid = instr_axil_arvalid && !instr_to_rom;
```

Yani üst bayt `0x00` ise Boot ROM'a, **diğer her adres** I-RAM'e
yönlendirilir. Üçüncü bir yol — geçersiz adres için DECERR/trap —
yoktur.

`sram_module.sv:168` adresin yalnızca gerekli alt bitlerini kullanır
(`s_axil_araddr[$clog2(RAM_DEPTH)+1 : 2]`, I-RAM için `[12:2]`).
Sonuç olarak CPU'nun PC'si hatayla örneğin `0x4000_0000`'a giderse
istek I-RAM'e yönlenir ve alt bitlerine göre **I-RAM içindeki başka
bir komuta alias olur**; hata sinyali üretilmez.

**Etkisi.** Normal program akışı Boot ROM → I-RAM olduğu için mevcut
testlerin tamamı geçer ve bu davranış gözlenmez. Şartnamenin asgari
kriterlerini ihlal etmez. Ancak sağlamlık (robustness) açısından
gerçek bir tasarım açığıdır: kaçak bir sıçrama sessizce yanlış komut
yürütür.

**Doğrusu ne olurdu.** Buyruk tarafında üç yol:

| Adres | Hedef |
|---|---|
| Boot ROM aralığı | ROM |
| I-RAM aralığı | I-RAM |
| **diğer her adres** | **DECERR / buyruk erişim hatası** |

**Neden bu teslimde düzeltilmedi.** Düzeltme `soc_top.sv`'yi
değiştirir. Teslim edilen GDSII (`S_final2`) bu dosyanın mevcut
hâlinden sentezlenmiştir ve kaynak bütünlüğü `asic/rtl_manifest.txt`
ile SHA-256 düzeyinde bu koşuya bağlıdır
(`provenance/git_source_match.json`, commit `098d1b0`). RTL'i
değiştirmek GDS ile kaynak arasındaki kanıt zincirini koparır; tam
fiziksel akışın (~5,5 saat) yeniden koşulması ve bütün imzalama
sonuçlarının yenilenmesi gerekir.

Bu nedenle **sessizce değiştirilmemiş**, bilinen sınırlama olarak
burada beyan edilmiştir. Düzeltme, fiziksel akışın yeniden
koşulabileceği bir sonraki revizyona planlanmıştır.


### Kullanılmayan giriş portları

RTL sistematik olarak tarandı: her giriş portunun modül gövdesinde kaç
kez okunduğu sayıldı. Sonuç 1 ise port **yalnızca tanımda** geçiyor,
gövdede hiç okunmuyor demektir. Yedi port bu durumdaydı.

**Bunlardan ikisi gerçek işlevsel eksiklikti ve 12 Eylül 2026'da
düzeltildi**; kalan beşi zararsızdır.

| Modül | Port | Sonuç | Değerlendirme |
|---|---|---|---|
| `i2c_peripheral` | `scl_i` | **Saat germe (clock stretching) eklendi** | **12 Eylül 2026'da düzeltildi.** Yavaş bir köle SCL'i aşağıda tutarsa master artık zamanlamasını dondurur. Ölçüm: germe boyunca iç çeyrek sayacı **0 hareket** (düzeltmesiz RTL'de 248). Kanıt: `tb_i2c_saat_germe.sv`. |
| `jtag_debug` | `m_axi_rresp` | **JTAG okuma yanıt kodu artık denetleniyor** | **12 Eylül 2026'da düzeltildi** — aşağıya bakınız. |
| `jtag_debug` | `m_axi_bresp` | **JTAG yazma yanıt kodu artık denetleniyor** | **12 Eylül 2026'da düzeltildi.** |
| `i2c_peripheral` | `s_axi_awprot`, `s_axi_arprot` | AXI4-Lite koruma sinyalleri | Standartta opsiyoneldir; tasarımda tek koruma seviyesi kullanılır. |
| `timer_peripheral` | `s_axi_awprot`, `s_axi_arprot` | Aynı | Aynı. |

Her iki düzeltme de kalıcı hata enjeksiyonu kampanyasına eklendi
(`i2c_saat_germe`, `jtag_yanit_kodu` mutasyonları). Kampanya 13 Eylül
2026'da iki mutasyon daha eklenerek genişletildi (`sram_rdata_bit`,
`npu_hakem_motor_dali`): **9/9 mutasyon yakalanıyor, 0 kaçırılıyor**. Ayrıntı ve ölçümler:
`verification/kanitlar/KULLANILMAYAN_PORT_DUZELTMELERI.md`

**Saat germenin 400 kHz'e etkisi yoktur.** Germe kararı yalnızca
senkronizatör boru hattı tazelendikten sonra verilir; hiçbir köle
germezse sayaç hiç durmaz ve SCL periyodu **tam 2500 ns** kalır
(`tb_i2c_scl_periyot`, %0,5 tolerans ile ölçülmüştür).


Elektriksel sınır ihlalleri (slew/kapasite/fanout) devam eder; zamanlama ise dokuz köşede kapanmıştır (§11).

Magic DRC **LEF/DEF** kaynaklıdır (`MAGIC_DRC_USE_GDS=false`). LVS çıkarımı ise **GDSII kaynaklıdır** (`MAGIC_EXT_USE_GDS=true`): standart hücreler ve makrolar transistör düzeyinde açılır, soyutlanmaz (`MAGIC_EXT_ABSTRACT_CELLS: None`). Netgen sonucu **`Circuits match uniquely`**'dir.

Bu, akışın **kendi** `Magic.SpiceExtraction` → `Netgen.LVS` adımlarıyla üretilmiştir; akış dışında elle koşulan ek bir çalışma **yoktur**. Şartname §7'nin *"aynı LibreLane çalışmasından"* ve *"akış sonrası elle düzenlenmemiş"* koşulları korunmuştur.

**Akışın tamamlanması hakkında bir not.** Magic, GDS'ten çıkarım sırasında hazır SRAM makrosunun iç geometrisinden gelen sekiz uyarı üretir:

    device missing 1 terminal; connecting remainder to node VGND/VPWR
    Could not determine device boundary
    Ports "VDD" and "vdd" are electrically shorted

Bu uyarılar `sky130_sram_2kbyte_1rw1r_32x512_8` makrosuna aittir ve şartname §1.3 hazır SRAM makrolarının fiziksel görünümlerinin **değiştirilemeyeceğini** söylediği için kaynağında giderilemez. Varsayılan `MAGIC_CAPTURE_ERRORS=true` ayarında bu uyarılar akışı durdurduğundan, çıkarım ve LVS adımları `MAGIC_CAPTURE_ERRORS=false` ile tamamlanmıştır.

Bu bir **hata eşiği gevşetmesi değildir**; signoff denetimlerinin tamamı açık kalmıştır:

    ERROR_ON_MAGIC_DRC    : true      ERROR_ON_LVS_ERROR     : true
    ERROR_ON_KLAYOUT_DRC  : true      ERROR_ON_TR_DRC        : true
    ERROR_ON_XOR_ERROR    : true      ERROR_ON_PDN_VIOLATIONS: true

Değişen tek şey, Magic'in makro kaynaklı uyarıları *ölümcül* sayıp saymamasıdır; DRC ve LVS sonuçları bu ayardan etkilenmez ve raporlarda olduğu gibi verilmiştir.

Bağımsız GDS DRC deneylerindeki sonuçlar standart akış raporunun yerine geçirilmez. Magic/SRAM model/katman yorumlamasına ilişkin şüpheler tüm bulguların otomatik muafiyeti değildir. DDK tarafından kabul edilmiş bir waiver belgesi bu pakette bulunmamıştır.

Raporlanan **7.658 Magic DRC ihlalinin tamamı tek kuraldır**: `nwell.4` ("All nwells must contain metal-connected N+ taps"). Kaynağı ölçülmüştür. (i) Aynı GDS'te KLayout imza DRC **0** ihlal raporlar; sky130A KLayout deck'i bu kuralı kasıtlı olarak devre dışı bırakmıştır (`libs.tech/klayout/drc/sky130A.lydrc:214-215`, not: *"rule nwell.4 is suitable for digital cells"*). (ii) Kural Magic'te yalnızca `drc(full)` stilinde etkindir ve LibreLane bu stili kendi paketindeki `librelane/scripts/magic/drc.tcl` dosyasının 67. satırında sabit kodlar (araç içi dosyadır; bu depoda bulunmaz). (iii) Tasarımda tap yerleştirme çalışmıştır: DEF'te **113.500** `sky130_fd_sc_hd__tapvpwrvgnd_1` örneği sayılmıştır (`RUN_TAP_ENDCAP_INSERTION: true`, `FP_TAPCELL_DIST: 13`). (iv) Üçüncü taraf SRAM makrosunun GDS'i **tek başına** Magic `drc(full)` ile tarandığında **1.394.782** ihlal üretir ve Magic makro içindeki OpenRAM işaretleyici katmanlarını tanımaz (`Unknown layer/datatype ... layer=22/33/235`), yani geometriyi eksik okur. Ölçüm dökümü `evidence/denetim_20260910/MAGIC_DRC_KOK_NEDEN.md` içindedir. Bu bulgu bir muafiyet talebi değildir; Magic DRC raporu pakette değiştirilmeden korunmuştur ve `RUN_MAGIC_DRC` kapatılmamıştır.

## 10. Güç ve IR-drop

Her köşenin internal/switching/leakage/toplam tahmini `reports/power/<corner>/power.rpt`; `irdrop.rpt`, `net-VPWR.csv`, `net-VGND.csv` aynı dizindedir.

| Alan | Değer |
|---|---|
| Analizde kullanılan saat frekansı | **43,2 MHz** (23,148 ns — signoff SDC) |
| Kullanılan köşeler | Dokuz PVT köşesi: min/nom/max RC × TT(25 °C, 1,80 V), SS(100 °C, 1,60 V), FF(−40 °C, 1,95 V) |
| Besleme gerilimi | Köşeye göre **1,80 / 1,60 / 1,95 V** |
| Switching activity girdisi | **Kullanılmadı** — açık VCD/SAIF verilmemiştir |
| Switching activity dosyası | Yok |
| Özel gerilim kaynağı konum dosyası | **Kullanılmadı** (`VSRC_LOC_FILES` tanımsız) |
| Sonuçların niteliği | **TAHMİNÎ** |

Açık aktivite girdisi bulunmadığından güç değerleri LibreLane'in varsayılan geçiş olasılığı varsayımıyla üretilmiştir ve **tahminîdir**. `VSRC_LOC_FILES` verilmediği için IR-drop analizi kaynak konumunu kendi belirler; akış bu durumu bir uyarıyla bildirir (`warning.log`) ve uyarı pakette korunmuştur. Bu değerler ölçülmüş kart güç tüketimi olarak sunulmaz.

## 11. Signoff özeti — S_final2, 23,148 ns (43,2 MHz)

### Dokuz köşe zamanlama

Aşağıdaki tablo **akışın kendi imza adımının** (`OpenROAD.STAPostPNR`) ölçümüdür: çıkarılmış SPEF, yayılmış saat, dokuz PVT köşesi, 23,148 ns. Değerler `reports/timing/summary.rpt` ve `results/metrics/metrics.json` ile birebir aynıdır.

| Köşe | Setup WNS | Setup TNS | Hold WNS | Hold TNS |
|---|---:|---:|---:|---:|
| min_ss_100C_1v60 | +1,3439 | 0,0 | +1,0749 | 0,0 |
| nom_ss_100C_1v60 | +0,8350 | 0,0 | +1,0878 | 0,0 |
| max_ss_100C_1v60 | +0,2782 | 0,0 | +0,7100 | 0,0 |
| min_tt_025C_1v80 | +3,2330 | 0,0 | +0,4891 | 0,0 |
| nom_tt_025C_1v80 | +2,8271 | 0,0 | +0,4936 | 0,0 |
| max_tt_025C_1v80 | +2,3327 | 0,0 | +0,4966 | 0,0 |
| min_ff_n40C_1v95 | +4,0363 | 0,0 | +0,2730 | 0,0 |
| nom_ff_n40C_1v95 | +3,6716 | 0,0 | +0,2625 | 0,0 |
| max_ff_n40C_1v95 | +3,2157 | 0,0 | +0,0380 | 0,0 |

**Setup 9/9 pozitif, hold 9/9 pozitif, her iki TNS 9/9 sıfır, ihlalli yol sayısı 0.**

En kötü değerler: setup **+0,2782 ns** (max_ss), hold **+0,0380 ns** (max_ff). Akışın kendi denetleyicileri de bunu doğrular: `Checker.SetupViolations` ve `Checker.HoldViolations` adımları "no violations found" vermiştir.

> **Not — önceki sürümden fark:** Bu bölümün eski hâli, pakete ek olarak elle koşulan bağımsız bir OpenSTA ölçümünü listeliyordu. Bu koşuda öyle bir ek ölçüm yapılmamıştır; yukarıdaki tablo doğrudan **akışın kendi imza çıktısıdır**. Böylece beyan edilen sayılar ile `reports/` altındaki ham raporlar tek kaynaktan gelir.

### Fiziksel doğrulama ve açık kalemler

| Kalem | S_final2 sonucu |
|---|---:|
| Setup worst slack (23,148 ns) | **+0,2782 ns** |
| Hold worst slack (23,148 ns) | **+0,0380 ns** |
| Setup / hold ihlalli yol | **0 / 0** |
| Setup / hold TNS (dokuz köşe) | **0,0 / 0,0** |
| Anten net / pin | 0 / 0 |
| Detailed-route DRC | **0** |
| KLayout DRC | **0** |
| Magic DRC (LEF/DEF) | 7.658 |
| Netgen LVS (LEF/DEF) | **Circuits match uniquely** |
| XOR (Magic ↔ KLayout) | **0** |
| Magic illegal overlap | **0** |
| PDN ihlali | 0 |
| Bağlantısız / kritik bağlantısız pin | 256 / **0** |
| Maksimum slew / kapasite / fanout ihlali | 16.030 / 1.952 / 81 |
| Hücre örneği | 2.053.906 |
| Die alanı | 16.284.800 µm² |
| Doluluk | %50,3 |
| Yönlendirme tel uzunluğu | 8.763.882 µm |

### Bu koşuya özgü yapılandırma

Teslim edilen `config.yaml`, bu koşuda fiilen kullanılan yapılandırmanın birebir kendisidir. **Bu iddia yeniden üretilebilir:**

```bash
python scripts/config_karsilastir.py
```

Betik, teslim edilen `config.yaml` ile koşumun kendi ürettiği `results/config/resolved.json` dosyasını karşılaştırır ve gerçek tasarım farkı varsa sıfırdan farklı çıkış kodu döner. Ölçülen sonuç:

| | |
|---|---:|
| Aynı anahtar | **380** |
| Akış türetmesi (mutlak yol / ortam) | 30 |
| **Gerçek tasarım farkı** | **0** |

30 fark, akışın koşum sırasında kendi eklediği mutlak yollardır (PDK hücre dosyaları, `DESIGN_DIR`, `KLAYOUT_*`, `FALLBACK_SDC`). Bunlar teslim dosyasında bulunmaz çünkü makineye özgüdür ve başka bir makinede yeniden çözülür. Tam döküm: `provenance/config_comparison.json`. Tasarım hedefleri önceki koşularla **aynı** kalmıştır (`CLOCK_PERIOD 14`, `SYS_CLK_HZ=43200000`, signoff 23,148 ns, 57 kaynak); yalnızca saat ağacı ve hold onarım parametreleri ayarlanmıştır:

    CTS_MACRO_CLUSTERING_SIZE          4       (önce: sınırsız)
    CTS_MACRO_CLUSTERING_MAX_DIAMETER  200     (önce: sınırsız)
    CTS_MAX_CAP                        0,3 pF  (önce: sınırsız)
    GRT_RESIZER_HOLD_SLACK_MARGIN      0,8     (önce: 0,6)
    PL_RESIZER_HOLD_SLACK_MARGIN       0,25    (önce: 0,1)
    *_RESIZER_FIX_HOLD_FIRST           true    (önce: false)
    *_RESIZER_HOLD_MAX_BUFFER_PCT      30      (önce: 50)
    *_RESIZER_HOLD_REPAIR_TNS_PCT      85      (önce: tanımsız)
    *_RESIZER_HOLD_MAX_UTIL_PCT        85      (önce: tanımsız)

Bu değerler tahminle değil **ölçümle** seçilmiştir. Varsayılan ayarlarla (marj 0,6) hold onarıcısı yalnızca 17 tampon ekleyip ihlalleri kapsam dışı bırakıyor, marj 1,2 yapıldığında ise 12.828 tampon ekleyip yönlendirmeyi boğuyordu (`GRT-0232`). 0,8 marj ile 6.803 tampon eklenmiş ve zamanlama kapanmıştır. Ayrıntılı kök neden analizi: `verification/kanitlar/HOLD_KOK_NEDEN_CTS.md`.

Dokuz köşe: nom/min/max × TT(25°C,1,80V), SS(100°C,1,60V), FF(−40°C,1,95V). Kesin değerler ve her köşenin WNS/TNS/yol kontrolleri `reports/timing/summary.rpt` ve alt dizinlerde; makine tarafından seçilmiş metrikler `provenance/signoff_metrics.json`.


### Parazitik açıklaması yapılmamış (unannotated) netler

`results/metrics/metrics.json` dokuz köşenin tamamında şunu raporlar:

    timing__unannotated_net__count           = 1493
    timing__unannotated_net_filtered__count  = 0

**Ne anlama geliyor.** İlk sayı, çıkarılan SPEF'te parazitik kaydı
bulunmayan net sayısıdır. İkinci sayı, akışın kendi eleme adımından
(`filter_unannotated`, `OpenROAD.STAPostPNR` içinde) **sonra geriye
kalan** net sayısıdır. LibreLane bu elemede güç/toprak şebekesi,
besleme bağlantıları ve makro içi soyut netler gibi zamanlama yolu
oluşturmayan netleri ayıklar.

**Filtrelenmiş sayı sıfırdır.** Yani 1.493 netin tamamı akış tarafından
bilinen ve zamanlama analizini etkilemeyen kategorilere girmiştir;
geriye zamanlama yolu üzerinde açıklaması eksik **tek bir net
kalmamıştır**. Sayının dokuz köşede birebir aynı (1493/0) olması da bunu
destekler — köşeye göre değişen bir çıkarım eksikliği olsaydı bu sayılar
farklılaşırdı.

**Sınır.** Bu netlerin tek tek dökümü teslim paketinde yoktur; eleme
adımının ayrıntılı logu koşu çalışma dizininde kalır
(`runs/S_final2/56-openroad-stapostpnr/<köşe>/filter_unannotated.log`)
ve rapor toplamasına dahil edilmemiştir. Dolayısıyla burada beyan edilen
şey akışın kendi ölçümüdür: **filtrelenmiş unannotated net sayısı 0**.

## 12. Çıktı konumları ve bütünlük

Esas GDS `results/gds/soc_top.gds`, üretici Magic. Magic/KLayout alternatifleri aynı dizinde; XOR raporu `reports/signoff/xor.xml`. Üç netlist rolü `_synth.v`, `_pnr.v`, `_powered.v` ile ayrılır. Tüm SPEF köşeleri `results/spef/{min,nom,max}` altındadır.

**SPICE çıkarımı hakkında:** Bu koşuda SPICE **nihai GDSII görünümünden** çıkarılmıştır (`results/spice/soc_top.spice`, `MAGIC_EXT_USE_GDS=true`) ve Netgen LVS bu netlist üzerinde koşulmuştur — sonuç **`Circuits match uniquely`**.

Netlist transistör düzeyindedir; standart hücreler soyut (black-box) değildir:

| Ölçüm | Değer |
|---|---:|
| Dosya boyutu | 119 MB |
| Transistör örneği | **1.809.268** |
| `black-box` / `abstract view` girdisi | **0** |

İlk satırlar gerçek PDK cihaz modellerini gösterir:

    X0 VPWR VGND VPWR VPB sky130_fd_pr__pfet_01v8_hvt ad=0.2262 ... w=0.87 l=0.59
    X1 VGND VPWR VGND VNB sky130_fd_pr__nfet_01v8     ad=0.143  ... w=0.55 l=0.59

Böylece PDF Bölüm 6.2'nin *"Nihai GDSII görünümünden çıkarılan ve LVS'de kullanılan SPICE/CDL netlisti"* zorunlu çıktısı **tam olarak** karşılanmıştır. Önceki `S_final2` koşusunda çıkarım LEF/DEF'ten yapılıyordu ve standart hücreler netlistte soyut kutu olarak yer alıyordu; bu koşuda o sınır kaldırılmıştır.

`provenance/output_mapping.json` her özgün rapor/çıktının kaynak adımını gösterir; dosya seçimi mtime'a dayanmaz. `provenance/requirements.json` zorunlu dosya listesi, `provenance/package_files.json` ve `asic/checksums/SHA256SUMS` bütünlük kayıtlarıdır.

## 12.1 Büyük fiziksel çıktıların konumu

Nihai GDSII, DEF, ODB, SPEF, netlist ve büyük raporların **tamamı bu
depoda**, `asic/results/` ve `asic/reports/` altında doğrudan
bulunmaktadır.

| Çıktı | Konum | Boyut |
|---|---|---:|
| Nihai GDSII | `results/gds/soc_top.gds` | 382 MB |
| Magic GDSII | `results/gds/soc_top.magic.gds` | 382 MB |
| KLayout GDSII | `results/gds/soc_top.klayout.gds` | 215 MB |
| Nihai DEF | `results/def/soc_top.def` | 301 MB |
| ODB | `results/odb/soc_top.odb` | 783 MB |
| Magic MAG | `results/mag/soc_top.mag` | 492 MB |
| Netlistler | `results/netlist/soc_top_{synth,pnr,powered}.v` | 227 MB (powered) |
| SPEF (üç RC köşesi) | `results/spef/{min,nom,max}/` | 199–211 MB |
| SDF (dokuz köşe) | `results/sdf/<köşe>/` | |
| **SPICE (nihai GDSII'den)** | `results/spice/soc_top.spice` | 119 MB |
| Zamanlama raporları | `reports/timing/` + dokuz köşe alt dizini | |
| Güç raporları | `reports/power/` + dokuz köşe alt dizini | 110 MB (net-VPWR) |

`asic/` dizininin tamamı **249 dosya / 4,68 GB**'dır.

### Git LFS

100 MB'ı aşan dosyalar GitHub'ın dosya başına sınırı nedeniyle **Git
LFS** ile saklanır (`.gitattributes` kuralları: `*.gds`, `*.def`,
`*.odb`, `*.mag`, `*.spef`, `*.sdf`, SPICE, netlist ve büyük raporlar).
Depoyu klonlarken bu dosyaların gerçek içeriğinin inmesi için LFS
kurulu olmalıdır:

```bash
git lfs install
git clone <depo-adresi>
# zaten klonladıysanız:
git lfs pull
```

LFS kurulu değilse bu dosyalar birkaç yüz baytlık işaretçi metni olarak
görünür. Kontrol:

```bash
git lfs ls-files        # 34 dosya listelenmelidir
git lfs fsck            # "Git LFS fsck OK"
```

### Yedek arşiv (bulut)

LFS'e erişilemediği durumlar için `asic/` dizininin tamamı tek arşiv
olarak da sunulmaktadır. Arşiv, depodaki dosyaların **birebir
kopyasıdır**; ayrı veya farklı bir koşum değildir.

| | |
|---|---|
| Dosya adı | `arkhe_soc_S_final2_fiziksel_ciktilar.tar.gz` |
| Boyut | **692.043.282 bayt** (660 MiB / 692 MB) |
| SHA-256 | `395134199f8e0b1b84b6a3aed989a0825207897a9006e6cd5f169fc7739329e0` |
| İndirme bağlantısı | <https://drive.google.com/drive/folders/12KrecGAQVRhM7vGnPL8ZmkDDyxLFeYo1?usp=sharing> (Google Drive klasörü; arşiv ve `.sha256` dosyası bu klasörün içindedir) |
| İçerik | `asic/` dizininin tamamı: **249 dosya**, açılmış hâli 4,68 GB — nihai GDSII (`soc_top.gds`), Magic ve KLayout GDSII, nihai DEF, ODB, MAG, üç RC köşesi SPEF, dokuz köşe SDF, nihai GDSII'den çıkarılan SPICE, üç netlist, dokuz köşe zamanlama ve güç raporları, `config.yaml`, `filelist.f`, `rtl_manifest.txt`, kısıt dosyaları (`constraints/`), `checksums/SHA256SUMS` |
| Arşiv biçimi | `tar -czf` — açıldığında tek bir `asic/` dizini oluşturur |

Doğrulama:

```bash
sha256sum -c arkhe_soc_S_final2_fiziksel_ciktilar.tar.gz.sha256
tar -xzf arkhe_soc_S_final2_fiziksel_ciktilar.tar.gz
```

> **Not.** Önceki teslimlerde (`d45_anten2`, 8 Eylül 2026) bu büyük
> çıktılar ayrı bir GitHub Release arşivinde sunuluyordu. Bu teslimde
> çıktılar **depo içindedir** (LFS ile); bulut arşivi yalnızca yedektir.
> Bütünlük `asic/checksums/SHA256SUMS` ve
> `provenance/package_files.json` üzerinden doğrulanır
> (`make asic_verify`).

## 12.2 Akış değişikliği beyanı

Bu teslimde **LibreLane Classic akışına eklenmiş özel bir adım, harici bir
OpenROAD Tcl betiği veya elle yapılmış bir düzenleme yoktur.** Zamanlama
kapanışı yalnızca akışın kendi yapılandırma değişkenleriyle sağlanmıştır
(`PL_RESIZER_HOLD_SLACK_MARGIN`, `GRT_RESIZER_HOLD_SLACK_MARGIN`,
`RUN_POST_GRT_RESIZER_TIMING`, `RUN_POST_GRT_DESIGN_REPAIR` ve benzeri;
tam liste `config.yaml` içindedir). Hiçbir zorunlu akış veya signoff adımı
devre dışı bırakılmamış, PDK / standart hücre kütüphanesi / SRAM modelleri
/ zamanlama kısıtları değiştirilmemiştir. Nihai DEF, GDSII ve diğer fiziksel
çıktılar üzerinde elle düzenleme yapılmamıştır.

Depo, kaynakların yanı sıra **tüm fiziksel çıktıları da doğrudan içerir** (§12.1); harici bir arşiv indirmeye gerek yoktur. **PDF Bölüm 4 gereği `asic/run/` teslimde yalnız `.gitkeep` içerir**; LibreLane'in geçici çalışma alanı teslim paketine dahil edilmemiştir. Yeniden üretim taşınabilir `config.yaml` ile yapılır. Özgün rapor ve config dosyalarındaki mutlak yollar, koşunun yapıldığı ortamın tarihsel kaydıdır.

## 13. Üçüncü taraf kaynakları

`THIRD_PARTY.md`, `licenses/`, çekirdek ve makro dizinlerindeki lisans/telif dosyaları korunmuştur. CPU, SRAM ve yardımcı betik kaynak/sürüm bilgileri bu belgelerde verilir. Yeni paketleme betikleri yalnız toplama, doğrulama ve arşiv geri yükleme içindir; fiziksel sonuçları değiştirmez.
