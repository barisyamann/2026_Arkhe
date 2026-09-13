> ## ⚠️ BU KOŞU TESLİM EDİLMEDİ
>
> `S_final` koşusu imzalamada **hold'u 6/9 köşede negatif** kapattı
> ve teslim edilmedi. Bu belge, o koşunun künyesi ve koşu öncesi
> çözülen üç engelin kaydı olarak korunmaktadır.
>
> **Teslim edilen koşu: `S_hold2`** (hold 9/9 pozitif).
> Hold sorununun kök neden analizi ve çözümü:
> [`HOLD_KOK_NEDEN_CTS.md`](HOLD_KOK_NEDEN_CTS.md)

---

# S_final koşusu — teslim EDİLMEYEN deneme (kayıt)

**Başlangıç:** 12 Eylül 2026, 18:51 UTC
**Sunucu:** `arkhe-asic` (136.92.13.113)
**Araç:** LibreLane **v3.0.6**, Classic akışı
**Koşu etiketi:** `S_final`

---

## Neden yeni bir koşu

Teslim öncesi son port taraması `jtag_debug` ve `i2c_peripheral`
içinde **iki işlevsel eksiklik** buldu (ayrıntı:
`KULLANILMAYAN_PORT_DUZELTMELERI.md`). RTL düzeltildiği için fiziksel
akışın da düzeltilmiş RTL ile yeniden koşulması gerekti.

Önceki `S_saat` koşusu düzeltme **öncesi** RTL'i yansıtıyordu.

---

## Yapılandırma — DEĞİŞTİRİLMEDİ

    config_S_saat.yaml
    md5 0eee1595ceb3037657bf302252196ddd

Yerel yedek (`sunucu_yedek/config/config_S_saat.yaml`) ile **birebir
aynı**. Koşu yapılandırması hiçbir şekilde değiştirilmemiştir.

| Anahtar | Değer |
|---|---|
| `DESIGN_NAME` | `soc_top` |
| `CLOCK_PERIOD` | **14** (PnR optimizasyon hedefi) |
| `CLOCK_PORT` | `clk_i` |
| `SYNTH_PARAMETERS` | `SYS_CLK_HZ=43200000` |
| `SIGNOFF_SDC_FILE` | `constraints/signoff_50mhz_hedef.sdc` |
| `PDK` | `sky130A` |
| `STD_CELL_LIBRARY` | `sky130_fd_sc_hd` |
| `VERILOG_FILES` | 57 kaynak |

Signoff SDC varsayılan periyodu **23,148 ns** (= 43,2 MHz beyanı).

### İki-SDC tasarımı

PnR SDC'si 14 ns ile **optimizasyon baskısı** uygular; imzalama SDC'si
23,148 ns ile **gerçek ölçümü** yapar. Bu ayrım `M_tek23` koşusunda
kanıtlanmıştı: PnR doğrudan 23 ns ile koşulduğunda araç yeterli
optimizasyon yapmadı ve `max_ss` setup **−6,387 ns** çıktı.

---

## Koşu öncesi bulunan ve çözülen üç engel

### 1. Signoff SDC yerel varsayılanı yanlıştı

Yerel `asic/constraints/signoff_50mhz_hedef.sdc` hâlâ **20,0 ns**
varsayılanı taşıyordu; beyan edilen 23,148 değil. (Sunucudaki kopya
zaten doğruydu.)

`SIGNOFF_CLOCK_PERIOD` bir LibreLane değişkeni **değildir** — bu
dosyanın kendi `::env` okumasıdır. Akışa `-c` ile verilemez, sessizce
yok sayılır. Tek geçerli yol varsayılanı değiştirmektir.

Dosyanın kendi başlığı bu hatanın **18. koşuyu zaten boşa
harcadığını** kaydediyor. Düzeltildi.

### 2. Disk yetersizdi

Sunucuda 11 GB boş vardı; koşu ~20 GB istiyor — yarıda dolardı.

Eski `S_saat` koşu dizini (20 GB) silindi. Bu dizinin **tüm çıktıları
yerelde** duruyor (`asic/` 8,2 GB: GDS, DEF, netlist, SPEF, raporlar)
ve sunucuda `S_saat_tam.tar.gz` (2,8 GB) arşivi mevcut. Silinen şey
yeniden üretilebilir ara dizindir.

Sonuç: **31 GB boş**.

### 3. `make asic_run` hemen abort ediyordu

`asic_run` hedefi `check`'e bağlı; `check` ise
`gen_sources.py --check` çağırıyor. O betik `CONFIG=` değişkenini
**yok sayıp her zaman `config.yaml`'a bakıyor** —
`config_S_saat.yaml`'ı hiç görmüyor.

Şartnamenin istediği tutarlılık aslında **sağlanmış** durumda;
doğrulandı:

    config_S_saat.yaml VERILOG_FILES : 57
    filelist.f                       : 57
    AYNI MI                          : True

Bu yüzden `librelane` doğrudan çağrıldı (`start_S_final.sh`).
Yapılandırmaya dokunulmadı.

Ayrıca `asic/` altında kalmış 806 MB'lık eski `collection_*` dizini
`filelist` denetimini düşürüyordu (içinde Yosys üretimi SRAM blackbox
`.bb.v` dosyaları var — tasarım RTL'i değil). Silinmedi, `~/arsiv_collection/`
altına taşındı.

---

## Sonuçlar

### Lint

    hata              0
    timing construct  0
    inferred latch    0
    uyarı           813

Uyarı sayısı 816'dan **813**'e indi. Sebebi düzeltilen üç porttur
(`scl_i`, `m_axi_rresp`, `m_axi_bresp`) — artık gerçekten okundukları
için `UNUSEDSIGNAL` 167'den **164**'e düştü. Bu, düzeltmelerin
etkili olduğunun bağımsız kanıtıdır.

### Sentez

    hücre sayısı       102.621
    alan               975.865 µm²
    SRAM makrosu       23 × sky130_sram_2kbyte_1rw1r_32x512_8
    Yosys CHECK        0 problem
    inferred latch     0

23 makro = **46 KB** (şartname zorunlu belleği). NPU 15, I-RAM 4,
D-RAM 4.

### Fiziksel

    die alanı          3832,4 × 4249,24 µm  (~16,3 mm²)

Önceki koşuyla **aynı** — düzeltmeler tasarımın fiziksel yapısını
değiştirmedi, yalnızca daha önce okunmayan portları bağladı.

### STA Pre-PnR

| Köşe | Hold WNS | Setup WNS |
|---|---:|---:|
| `nom_tt_025C_1v80` | +0,2652 | −1,0998 |
| `nom_ss_100C_1v60` | +0,6103 | −12,5978 |
| `nom_ff_n40C_1v95` | +0,1416 | +3,7415 |

**Pre-PnR setup negatifliği beklenendir ve sorun değildir:** bu ölçüm
yerleştirme öncesi, ideal saatli, optimize edilmemiş netlist
üzerinedir. Anlamlı erken sinyal hold'un pozitif olmasıdır ve üç
köşede de pozitiftir. Önceki `S_saat` koşusu da aynı desende başlayıp
imzalamada dokuz köşede pozitif kapanmıştı.

---

## Çıktı toplama notu

`collect_delivery.py`, `provenance/output_mapping.json` içindeki
**sabit adım numaralarına** bakar (216 girdi, örn.
`47-openroad-checkantennas-1/reports/antenna.rpt`). Adım
numaralandırması koşudan koşuya kayar — `S_saat`'te Pre-PnR STA 11.
adımken `S_final`'da 12'dir.

Bu yüzden `mapping_yenile.py` yazıldı: adım *adlarından* eşleme kurar,
aynı adın tekrarlarında sırayı korur ve üretilen her yolun diskte
gerçekten var olduğunu doğrular.
