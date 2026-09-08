# ARKHE — d45_anten2 ASIC teslimi

Bu paket 7 Eylül 2026 tarihli **d45_anten2** koşusunun kaynakları, özgün raporları ve fiziksel çıktılarıdır. **Temiz signoff değildir.** İhlaller gizlenmemiştir; akış final görünümleri ürettikten sonra ertelenmiş denetim hatalarıyla sıfırdan farklı çıkmıştır. `asic/reports/general/error.log` korunmuştur.

## 1. Tasarım

Üst modül `soc_top`; CV32E40P (RV32IMC, FPU kapalı), NPU ve AXI-Lite çevre birimleri. Ana saat `clk_i`, reset `rst_ni`, JTAG saati `jtag_tck`. GPIO, UART, I2C, QSPI ve JTAG portları vardır; kesin arayüz `rtl/Memory/soc_top.sv` içindedir. PnR hedefi **10 ns**, final STA hedefi **20 ns**; 50 MHz temiz ASIC kapanışı iddia edilmez.

## 2. Araç ve ortam

LibreLane **3.0.6 Classic**, Debian 12 x86_64, SKY130A / `sky130_fd_sc_hd`. Open PDKs sürümü `8afc8346a57fe1ab7934ba5a6056ea8b43078e71`. Araç sürümleri `environment/versions.txt`, Nix bağımlılıkları `environment/flake.nix` ve `environment/flake.lock` içindedir. Ham koşunun her adımındaki `COMMANDS` dosyası kullanılan gerçek araç yolunu korur. Eski WSL ortam anlatımı yalnızca `provenance/historical_versions_20260820.txt` içinde tarihsel belge olarak tutulur.

## 3. Yeniden çalıştırma ve paket doğrulama

Depo kökünden:

```bash
python3 tools/restore_release.py --delivery
nix develop ./asic/environment
export PDK_ROOT=/kendi/pdk/dizininiz
cd asic
make asic_verify
make asic_run
```

`PDK_ROOT`, sabitlenmiş sürümün `sky130A` alt dizinini içeren dizindir; makineye göre ayarlanır. PDK lisanslı kaynakları Nix/Ciel kurulumuyla sağlanır; sistem Nix store veya tüm PDK teslim arşivine kopyalanmamıştır. OpenRAM çalıştırılmamıştır.

`make asic_run` temiz, zaman etiketli bir `asic/run/` çalışma alanı kullanır; LibreLane'in varsayılan `runs` yolu bu dizine yönlendirilir. Mevcut koşu üzerine yazılmaz. Akış bittikten sonra raporlar kaynak adım eşlemesiyle toplanır ve aynı GDS için ek çıkarım/LVS aşaması çağrılır; akış başarısızlığı toplama başarılı olsa da nonzero olarak döndürülür. `make collect RUN=run/<etiket>` elle toplama, `make gds_lvs` ek GDS kontrolü içindir. Önceki raporlar tarihli collection dizininde korunur. `make asic_verify` yayımlanan dosya ve SHA-256 bütünlüğünü kontrol eder; signoff başarısı anlamına gelmez. Yeniden üretilmiş sonuçların özgün teslim hash'leriyle aynı olması beklenmez; bu durumda yeni raporlar ayrıca değerlendirilmelidir.

Paketleme sırasında yapılandırma/lint çalıştırıldı; tam PnR yeniden çalıştırılmadı. Kanıt `evidence/packaging_config_check_runs`; etkin ayar karşılaştırması `provenance/config_comparison.json` (boş fark). Çok saat süren fiziksel akış için 8 çekirdek ve yaklaşık 62 GB RAM kullanılan referanstır; 16 GB ham koşuya ek PDK/geçici alan gerekir. Temiz makinede en az 40 GB boş çalışma alanı önerilir; bitiş süresi garanti edilmez.

## 4. RTL ve girdiler

`filelist.f` depo köküne göre kaynakları listeler. `config.yaml` aynı 57 kaynak için `asic/` dizinine göre yollar kullanır; JSON biçimi geçerli YAML'dır. Include dizinleri, `USE_SRAM_MACRO` tanımı ve bütün etkin ayarlar bu dosyada bulunur. `results/config/resolved.json` özgün, değiştirilmemiş koşu yapılandırmasıdır; tarihsel mutlak yollar burada bilerek korunmuştur.

RTL, testbench ve yazılım kökteki `rtl/`, `tb/`, `sw_nexys/`, `scripts/` dizinlerindedir. Model/ağırlık ve yardımcı proje dosyaları da korunmuştur. `provenance/source_hashes.json` paketleme anındaki RTL hash'lerini içerir. 5 Eylül aday manifestinden farklı dosya `rtl/npu/npu_tcm_sram.sv`'dir. Hiçbir RTL dosyasının mtime'ı bu koşunun sentez başlangıcından yeni değildir. Ek kontrol: senteze giren 57 dosyanın tamamı GitHub `d800acb` commit’inin byte içerikleriyle eşleşmiştir; `provenance/git_source_match.json` sonucu kaydeder.

5 Eylül doğrulama logları `evidence/candidate_validation` altında **tarihsel aday testi** olarak korunmuştur; değiştirilmiş son RTL için yeni tam regresyon sonucu olarak sunulmaz.

## 5. SRAM ve makrolar

`sky130_sram_2kbyte_1rw1r_32x512_8`: 32 bit × 512 kelime, 2 KiB, 1RW+1R. Toplam 23 instance: NPU TCM 15, komut RAM 4, veri RAM 4. Instance adları ve konumları `config.yaml/MACROS` içinde; GDS/LEF/Verilog/Liberty/SPICE görünümleri `macros/` altında teslim edilir. Makro güç pinleri `vccd1/vssd1`, SoC güç ağları `VPWR/VGND`; bağlantı eşlemeleri `PDN_MACRO_CONNECTIONS` içindedir.

SRAM Liberty yalnızca TT/1,8V/25°C'dir ve FF/SS dahil dokuz STA köşesinde aynı model kullanılır. Dokuz ayrı SRAM karakterizasyonu iddia edilmez. SRAM anten modelinin kapsamı `15-odb-checkmacroantennaproperties` ve `63-odb-checkdesignantennaproperties` özgün adım kayıtlarında görülebilir. İç makro doğrulaması ile üst düzey bağlantı kontrolü ayrı kapsamlardır.

## 6. Saatler ve istisnalar

PnR girdisi `constraints/design.sdc`, signoff girdisi `constraints/signoff_50mhz_hedef.sdc`; teslim kopyaları `results/sdc/pnr.sdc` ve `signoff.sdc`. Akışın yazdığı `pnr_resolved.sdc` **10 ns** içerir; signoff raporundaki ana saat **20 ns**'dir. Tek SDC'yi iki rol için kullanmak doğru değildir. JTAG saati 100 ns'dir; saat grupları asenkrondur. Input/output delay, transition/load, uncertainty ve reset/diğer istisnaların kapsam ve gerekçeleri SDC yorumlarında korunmuştur. Hiçbir kısıt teslimde ihlalleri saklamak için değiştirilmemiştir.

## 7. Fiziksel yapılandırma

Die: `0 0 3832.40 4249.24` µm; yönlendirme katmanları met1–met5. SRAM yerleşimleri, core/utilization/density, pin düzeni, CTS, güç dağıtımı ve anten onarım ayarları `config.yaml` içinde aynen aktarılmıştır. Makro/hücre/pin/PDN geometrisinin kanıtı `results/def/soc_top.def` ve `results/odb/soc_top.odb`'dir. Yerleşim görüntüsü `results/images/soc_top.png`.

## 8. Lint ve yapısal kontroller

Özgün akış: lint hata 0, uyarı **818**, inferred latch 0, unmapped cell 0. Ayrıntılar `reports/lint` ve `reports/synthesis` altında. Kapatılan lint türleri ve diğer denetim ayarları `config.yaml/LINTER_*` ve `ERROR_ON_*` değerleridir; bunlar genel temizlik onayı değildir. Boş/makro güç pinleri ve kullanılmayan sinyaller dahil uyarılar özgün logda korunur; toplu resmi waiver kabulü iddia edilmez.

## 9. Bilinen sorunlar ve kapsam

Setup ve elektriksel sınır ihlalleri devam eder. Orijinal Magic DRC **LEF/DEF** kaynaklıdır (`MAGIC_DRC_USE_GDS=false`); özgün LVS çıkarımı da LEF/DEF kullanmıştır (`MAGIC_EXT_USE_GDS=false`, makro iç SPICE dahil edilmemiş). Bu eski LVS başarısı GDS içinin kontrol edildiği anlamına gelmez. Ek GDS kontrolünün kapsamı ve sonucu `reports/lvs_gds/` içinde ayrıca verilir; makro iç transistör doğrulaması iddia edilmez. Özgün sonuçlar değişmeden korunmuştur.

Bağımsız GDS DRC deneylerindeki sonuçlar standart akış raporunun yerine geçirilmez. Magic/SRAM model/katman yorumlamasına ilişkin şüpheler tüm bulguların otomatik muafiyeti değildir. DDK tarafından kabul edilmiş bir waiver belgesi bu pakette bulunmamıştır.

## 10. Güç ve IR-drop

Her köşenin internal/switching/leakage/toplam tahmini `reports/power/<corner>/power.rpt`; `irdrop.rpt`, `net-VPWR.csv`, `net-VGND.csv` aynı dizindedir. Açık VCD/SAIF aktivite girdisi kullanılmadığından değerler **tahminidir**. Besleme/köşe, saat ve kaynak varsayımları özgün rapor/config içinde korunur; özel kaynak konumu `VSRC_LOC_FILES` ayarıyla belirlenir. Ölçülmüş kart güç tüketimi olarak sunulmaz.

## 11. Özgün signoff özeti

| Kalem | d45_anten2 sonucu |
|---|---:|
| Setup worst slack | −1,8149 ns |
| Hold worst slack | +0,1642 ns |
| Setup / hold ihlalli yol | 115 / 0 |
| En kötü köşe setup TNS | −34,7940 ns |
| Anten net / pin | 0 / 0 |
| Detailed-route DRC | 0 |
| KLayout DRC | 0 |
| Magic DRC (LEF/DEF) | 7.658 |
| Özgün Netgen LVS (LEF/DEF) | Circuits match uniquely |
| XOR | 0 |
| PDN ihlali | 0 |
| Bağlantısız / kritik bağlantısız pin | 257 / 0 |
| Maksimum slew / kapasite / fanout ihlali | 19.341 / 1.888 / 11 |

Dokuz köşe: nom/min/max × TT(25°C,1,80V), SS(100°C,1,60V), FF(−40°C,1,95V). Kesin değerler ve her köşenin WNS/TNS/yol kontrolleri `reports/timing/summary.rpt` ve alt dizinlerde; makine tarafından seçilmiş metrikler `provenance/signoff_metrics.json`.

## 12. Çıktı konumları ve bütünlük

Esas GDS `results/gds/soc_top.gds`, üretici Magic. Magic/KLayout alternatifleri aynı dizinde; XOR raporu `reports/signoff/xor.xml`. Üç netlist rolü `_synth.v`, `_pnr.v`, `_powered.v` ile ayrılır. Tüm SPEF köşeleri `results/spef/{min,nom,max}` altındadır. GDS kaynaklı SPICE ile özgün LEF/DEF kaynaklı SPICE farklı adlarla tutulur.

`provenance/output_mapping.json` her özgün rapor/çıktının kaynak adımını gösterir; dosya seçimi mtime'a dayanmaz. `provenance/requirements.json` zorunlu dosya listesi, `provenance/package_files.json` ve `asic/checksums/SHA256SUMS` bütünlük kayıtlarıdır.

Git dalı kaynakları ve küçük raporları içerir. Büyük çıktılar aynı GitHub Release'in delivery arşivinde sunulur. Yalnız GitHub “Source code.zip” indirmek bütün fiziksel çıktıları vermez. `tools/restore_release.py --delivery` tam teslim ağacını oluşturur. **Final s.20 gereği `asic/run/` teslimde yalnız `.gitkeep` içerir; ham koşu teslim paketine dahil değildir.** Yeniden üretim taşınabilir `config.yaml` ile yapılır. Özgün rapor/config dosyalarındaki mutlak yollar tarihsel kayıttır.

## 13. Üçüncü taraf kaynakları

`THIRD_PARTY.md`, `licenses/`, çekirdek ve makro dizinlerindeki lisans/telif dosyaları korunmuştur. CPU, SRAM ve yardımcı betik kaynak/sürüm bilgileri bu belgelerde verilir. Yeni paketleme betikleri yalnız toplama, doğrulama ve arşiv geri yükleme içindir; fiziksel sonuçları değiştirmez.
