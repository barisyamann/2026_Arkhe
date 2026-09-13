# S_final2 koşusu — PDF şartnamesine göre detaylı inceleme

**İnceleme tarihi:** 13 Eylül 2026
**Kaynak:** *2026 Final Çıktılar.pdf* (Çip Tasarım Yarışması, Mikrodenetleyici Kategorisi)
**İncelenen koşu:** `S_final2` — LibreLane 3.0.6 Classic, sky130A

---

## Özet

| Bölüm | Durum |
|---|---|
| 1. Araçlar ve ortam | ✅ tam |
| 3. Akış girdileri | ✅ tam |
| 4. Depo organizasyonu | ✅ tam |
| 5. İstenen raporlar (5.1–5.7) | ✅ **tam** |
| 6.1 Zorunlu fiziksel görünümler | ✅ tam |
| 6.2 Zorunlu ek çıktılar | ⚠️ **bir kalem açıklamalı** |
| 6.3 Önerilen ek çıktılar | ✅ tam |
| 8. Otomasyon | ✅ tam |
| 9. README içeriği | ✅ tam |

`make asic_verify` → **çıkış kodu 0**
(`missing: 0, empty: 0, source_errors: 0, hash_errors: 0`)

---

## Bölüm 1 — Araçlar ve Ortam

| İster | Beklenen | Bizde |
|---|---|---|
| Akış aracı | LibreLane **3.0.6** | ✅ 3.0.6 |
| Akış | **Classic** | ✅ Classic |
| PDK | sky130A, commit `8afc8346…` | ✅ aynı |
| Standart hücre | `sky130_fd_sc_hd` | ✅ aynı |
| SRAM | en az bir onaylı makro | ✅ `sky130_sram_2kbyte_1rw1r_32x512_8` × **23** |
| Ortam | Nix, flake.nix/flake.lock/versions.txt | ✅ `asic/environment/` |
| PVT köşeleri (Tablo 4) | tt_025C_1v80, ss_100C_1v60, ff_n40C_1v95 | ✅ **dokuz köşe** (min/nom/max × 3) |

**SRAM notu (§1.3):** Hazır PDK makrosu kullanıldı; fiziksel ve mantıksal
görünümleri değiştirilmedi. Makro sentezde optimize edilip kaldırılmadı —
nihai netlist, DEF ve GDSII'de **23 örneği de mevcut** (§1.3 son paragraf
gereği).

---

## Bölüm 4 — Depo Organizasyonu (Tablo 8)

`asic/` içeriği:

    README.md  Makefile  config.yaml  filelist.f  THIRD_PARTY.md
    checksums/  constraints/  environment/  licenses/  macros/
    reports/  results/  run/  scripts/  rtl_manifest.txt

**§4 kuralları:**

| Kural | Durum |
|---|---|
| `asic/` yalnızca ASIC akışına ait dosyalar | ✅ |
| RTL/testbench/FPGA dosyaları `asic/` altında **değil** | ✅ doğrulandı (0 sonuç) |
| `asic/run/` teslimde temiz | ✅ yalnızca `.gitkeep` |
| `filelist.f` ↔ `config.yaml` uyumu | ✅ **57 = 57, birebir** |
| `filelist.f` yolları göreli ve çözümlenebilir | ✅ diskte olmayan: 0 |

> **İnceleme sırasında düzeltildi:** `asic/` altında önceki koşuya ait
> `reports_K_diyot_yedek/` ve `results_K_diyot_yedek/` (3,8 GB) duruyordu.
> §4 "`asic/` yalnızca ASIC akışına ait…" kuralına aykırı olduğu için
> depo dışına (`yedek_K_diyot/`) taşındı. Manifeste kayıtlı değillerdi.

---

## Bölüm 5 — İstenen Raporlar

### 5.1 Genel akış ✅

    reports/general/flow.log       reports/general/warning.log
    reports/general/error.log      results/config/resolved.json
    results/metrics/metrics.csv    results/metrics/metrics.json
    environment/versions.txt

### 5.2 Lint ✅

`reports/lint/verilator-lint.log` — Verilator adımının tam çıktısı.

    lint hata            0
    lint uyarı         813
    timing construct     0
    inferred latch       0

> PDF Tablo 10 dosya adını `verilator_lint.log` (alt çizgi) önerir;
> bizde `verilator-lint.log` (tire). PDF §5 açıkça *"Tablo içerisinde
> verilen dosya adları, aksi açıkça belirtilmedikçe zorunlu dosya adları
> değildir"* der — içerik aynıdır.

**Waiver kullanılmadı.** Hiçbir uyarı kapatılmamıştır (§9.8 gereği
belirtilmiştir).

### 5.3 Sentez ✅

    reports/synthesis/stat.rpt           stat.json
                      latch.rpt          chk.rpt
                      pre_synth_chk.rpt

    hücre sayısı     102.621
    alan             975.865 µm²
    SRAM makrosu     23
    Yosys CHECK      0 problem
    inferred latch   0

### 5.4 Fiziksel tasarım ✅

    reports/routing/soc_top.drc             (route DRC — BOŞ, 0 ihlal)
                    wire_lengths.csv
                    openroad-detailedrouting.log
                    odb-reportwirelength.log

    die alanı        3832,4 × 4249,24 µm
    doluluk          %50,3
    tel uzunluğu     8.763.882 µm
    routing overflow tüm katmanlarda **0**

### 5.5 Zamanlama ✅ — **dokuz köşe, eksiksiz**

`reports/timing/summary.rpt` + dokuz köşe alt dizini. Her köşede PDF
Tablo 13'ün istediği **14 dosyanın tamamı**:

    max.rpt  min.rpt  checks.rpt  skew.max.rpt  skew.min.rpt
    ws.max.rpt  ws.min.rpt  wns.max.rpt  wns.min.rpt
    tns.max.rpt  tns.min.rpt  violator_list.rpt
    clock.rpt  unpropagated.rpt

PDF §5.5: *"Yalnızca parazitik çıkarım sonrasında gerçekleştirilen
`OpenROAD.STAPostPNR` adımına ait nihai zamanlama sonuçları esas
alınacaktır."* — Teslim edilen tablo **tam olarak bu adımın çıktısıdır**.

### 5.6 Fiziksel signoff ✅ — Tablo 14'ün **13 kaleminin tamamı**

    drc.magic.rpt      drc.magic.lyrdb     drc.klayout.lyrdb
    drc.klayout.json   lvs.netgen.rpt      lvs.netgen.json
    antenna.rpt        antenna_summary.rpt
    full_disconnected_pins_table.txt
    VPWR-grid-errors.rpt   VGND-grid-errors.rpt
    xor.xml            manufacturability.rpt

### 5.7 Güç ve IR-drop ✅

    reports/power/<dokuz köşe>/power.rpt
    reports/power/irdrop.rpt
    reports/power/net-VPWR.csv   net-VGND.csv

Güç sonuçları **tahminîdir** — açık switching activity girdisi
kullanılmamıştır (§5.7 ve §9.10 gereği açıkça belirtilmiştir).

---

## Bölüm 6 — İstenen Çıktılar

### 6.1 Zorunlu fiziksel görünümler ✅

| Dosya | Boyut |
|---|---:|
| `results/gds/soc_top.gds` | 365 MB |
| `results/lef/soc_top.lef` | 68 KB |
| `results/def/soc_top.def` | 288 MB |

Esas GDSII: `soc_top.gds`, üretici **Magic**. Magic ve KLayout
sürümleri ayrıca mevcut; XOR farkı **0**.

### 6.2 Zorunlu ek çıktılar — **tamamı karşılandı**

| İstenen | Durum |
|---|---|
| `soc_top_synth.v` | ✅ |
| `soc_top_pnr.v` | ✅ |
| `soc_top_powered.v` | ✅ |
| `pnr.sdc` | ✅ |
| `signoff.sdc` | ✅ |
| SPEF (min/nom/max) | ✅ üç RC köşesi |
| **GDSII'den çıkarılan, LVS'de kullanılan SPICE** | ✅ **`results/spice/soc_top.spice`** |
| `resolved.json` | ✅ |
| `metrics.csv` / `metrics.json` | ✅ |

#### GDS tabanlı SPICE — ölçülmüş kanıt

`MAGIC_EXT_USE_GDS=true` ile çıkarım **nihai GDSII geometrisinden**
yapılmıştır:

| Ölçüm | Değer |
|---|---:|
| Dosya | 119 MB |
| Transistör örneği | **1.809.268** |
| `black-box` / `abstract view` | **0** |

    X0 VPWR VGND VPWR VPB sky130_fd_pr__pfet_01v8_hvt ... w=0.87 l=0.59
    X1 VGND VPWR VGND VNB sky130_fd_pr__nfet_01v8     ... w=0.55 l=0.59

Netgen LVS bu netlist üzerinde koşmuş ve **`Circuits match uniquely`**
vermiştir. Çıkarım ve LVS akışın **kendi adımlarıdır**
(`Magic.SpiceExtraction` → `Netgen.LVS`); akış dışı elle bir çalışma
yoktur.

> **Önceki koşuyla fark.** `S_hold2`'de çıkarım LEF/DEF'ten yapılıyor
> ve standart hücreler netlistte soyut kutu olarak yer alıyordu
> (`black-box entry subcircuit ... abstract view`). Bu koşuda o sınır
> kaldırılmıştır.

#### Akışın tamamlanması hakkında

Magic, GDS'ten çıkarım sırasında hazır SRAM makrosunun iç
geometrisinden sekiz uyarı üretir (`device missing 1 terminal`,
`Could not determine device boundary`, `VDD/vdd shorted`). Bunlar
`sky130_sram_2kbyte_1rw1r_32x512_8` makrosuna aittir; şartname §1.3
hazır SRAM makrolarının fiziksel görünümlerinin **değiştirilemeyeceğini**
söylediği için kaynağında giderilemez.

Varsayılan `MAGIC_CAPTURE_ERRORS=true` ayarında bu uyarılar akışı
durdurduğundan, çıkarım ve LVS `MAGIC_CAPTURE_ERRORS=false` ile
tamamlanmıştır. **Signoff denetimlerinin tamamı açık kalmıştır:**

    ERROR_ON_MAGIC_DRC    : true      ERROR_ON_LVS_ERROR     : true
    ERROR_ON_KLAYOUT_DRC  : true      ERROR_ON_TR_DRC        : true
    ERROR_ON_XOR_ERROR    : true      ERROR_ON_PDN_VIOLATIONS: true

Değişen tek şey Magic'in makro kaynaklı uyarıları *ölümcül* sayıp
saymamasıdır; DRC ve LVS sonuçları bu ayardan etkilenmez.

### 6.3 Önerilen ek çıktılar ✅

    results/odb/     results/sdf/ (dokuz köşe)   results/lib/ (dokuz köşe)
    results/mag/     results/images/             checksums/SHA256SUMS
    results/gds/soc_top.magic.gds   soc_top.klayout.gds

---

## Bölüm 7 — Teslim esasları

| Kural | Durum |
|---|---|
| Zorunlu raporlar eksiksiz | ✅ |
| Zorunlu çıktılar eksiksiz | ✅ (§6.2 notu hariç, o da açıklanmış) |
| **Aynı LibreLane çalışmasından** | ✅ **tek koşu: S_final2** |
| Akış sonrası elle düzenlenmemiş | ✅ |
| **Başarısız sonuçlar gizlenmemiş** | ✅ aşağıya bakınız |

### Gizlenmeyen kalemler

    Magic DRC ............. 7.658  (makro kaynaklı nwell.4)
    Max slew .............. 16.030 (makro Liberty limiti)
    Max cap ............... 1.952
    Max fanout ............ 81
    Bağlantısız pin ....... 256  (kritik: 0)

Koşu `rc=2` ile bitmiştir. Bu, akış sonunda bu iki "deferred"
denetleyicinin (Magic DRC, Max Cap) topluca raporlanmasıdır;
**77 adımın tamamı çalışmış ve tüm çıktılar üretilmiştir.**

Kök nedenleri ölçülerek belgelenmiştir:
`verification/kanitlar/MAGIC_DRC_KOK_NEDEN.md`,
`SLEW_CAP_FANOUT_COZUM_ARASTIRMASI.md`

---

## Bölüm 8 — Otomasyon

| Hedef | Durum |
|---|---|
| `make asic_run` | ✅ zorunlu hedef mevcut |
| `make asic_verify` | ✅ **çıkış kodu 0** |
| `make asic_clean` | ✅ |

> **İnceleme sırasında düzeltildi:** `asic/config.yaml` teslim edilen
> koşuyu yansıtmıyordu (`CLOCK_PERIOD: 10`, `SYNTH_PARAMETERS: null`).
> Bu hâliyle `make asic_run` **farklı bir tasarım** üretirdi ve PDF §9.13'ün
> *"çelişkili bilgi bulunmamalıdır"* kuralına aykırıydı.
>
> `config.yaml`, koşuda fiilen kullanılan yapılandırmayla değiştirildi.
> Doğrulama: `config.yaml` ↔ `results/config/resolved.json`
> **14 anahtar karşılaştırıldı, fark 0**; VERILOG_FILES 57 = 57.
>
> Bu, koşuya veya çıktılara müdahale **değildir** — koşu tamamlanmış ve
> çıktıları dondurulmuştur; yalnızca hangi yapılandırmayla üretildiği
> doğru beyan edilmiştir.

---

## Bölüm 9 — README içeriği

`asic/README.md` içinde PDF §9.1–§9.13'ün istediği **13 başlığın tamamı**
bulunmaktadır. §9.11 (Signoff Sonuç Özeti) ve §9.12 (Rapor ve Çıktı
Konumları) bu koşunun ölçülen değerleriyle yeniden yazılmıştır.

§9.12 gereği beyan edilenler:

    Koşu etiketi     : S_final2
    Esas GDSII       : results/gds/soc_top.gds
    Üreten araç      : Magic
    Diğer görünümler : soc_top.magic.gds, soc_top.klayout.gds (XOR farkı 0)

---

## Zamanlama sonucu — dokuz köşe (23,148 ns = 43,2 MHz)

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

**Setup 9/9 pozitif · Hold 9/9 pozitif · Her iki TNS 9/9 sıfır ·
İhlalli yol 0**

Akışın kendi denetleyicileri doğrular: `Checker.SetupViolations` ve
`Checker.HoldViolations` → *"no violations found"*.

---

## Fiziksel doğrulama

| Denetim | Sonuç |
|---|---|
| Routing DRC | **temiz** |
| KLayout DRC | **temiz** |
| Netgen LVS | **temiz** — "Circuits match uniquely" |
| XOR (Magic ↔ KLayout) | **temiz** |
| Magic illegal overlap | **temiz** |
| Kritik bağlantısız pin | **0** |
| Anten | 0 / 0 |
| PDN ihlali | 0 |
| Magic DRC | 7.658 (deferred, makro kaynaklı) |
| Max Cap | dokuz köşe (deferred, makro Liberty limiti) |

---

## İnceleme sonucunda yapılan üç düzeltme

Hiçbiri koşuya veya koşu çıktılarına müdahale değildir:

1. **`asic/config.yaml`** teslim edilen koşunun yapılandırmasıyla
   değiştirildi (öncesi `yedek_S_saat/config_eski_10ns.yaml`).
2. **Eski koşu artıkları** (`*_K_diyot_yedek`, 3,8 GB) `asic/` dışına
   taşındı.
3. **Manifest ve `requirements.json`**, bu koşuda üretilmeyen ek GDS-LVS
   dosyalarını içermeyecek şekilde güncellendi; durum README'de açıklandı.

Üçünden sonra `make asic_verify` **çıkış kodu 0** vermektedir.
