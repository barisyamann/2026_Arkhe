# 6. Koşum Bulgu Analizi ve Düzeltme Planı

**Takım Arkhe — TEKNOFEST 2026 Çip Tasarım Yarışması**
Tarih: 24 Ağustos 2026 · Koşum: `run/arkhe` (6. koşum)

---

## 0. Özet

Akış ilk kez **baştan sona** koştu. Üç denetim geçti, üçü açık kaldı.

| Denetim | Sonuç |
|---|---|
| **Netgen LVS** | ✅ `Circuits match uniquely` — 89 669 ağ |
| **KLayout DRC** | ✅ 0 ihlal (GDS üzerinde) |
| **Checker.XOR** | ✅ Magic ve KLayout GDS'leri örtüşüyor |
| Magic DRC | ❌ 7659 ihlal — tamamı `nwell.4` |
| Hold | ❌ 8 ihlal, `max_ff` köşesinde |
| Max cap / max slew | ⚠️ 9 köşenin tamamında |
| Setup (ss köşesi) | ⚠️ −6,31 ns — belgelenmiş sapma (bkz. `ZAMANLAMA_ANALIZI_RAPORU.md`) |

Üç açık maddenin **ikisinin kök nedeni bulundu ve düzeltildi**; üçüncüsü için
belirleyici bir test tanımlandı.

---

## 1. Hold ihlalleri — kök neden bulundu, düzeltildi

### Bulgu

`max_ff_n40C_1v95` köşesinde 8 ihlal. Diğer köşelerdeki hold ihlalleri
kütükler arası değil (giriş/çıkış yollarında), bu 8'i gerçek iç yollar.

| Yol | Slack (ns) | Modül |
|---|---|---|
| `u_uart2.u_rx.bit_cnt_r[1]` → `[2]` | −0,0622 | UART2 RX bit sayacı |
| `u_uart2.u_rx.state_r[3]` → `[0]` | −0,0593 | UART2 RX durum makinesi |
| `u_npu.ram_wdata_a[12]` → NPU SRAM `din0[14]` | −0,0470 | NPU yazma verisi |
| `u_instruction_ram.rdata_hold[17]` → CPU FIFO `mem_q[17]` | −0,0172 | I-RAM → çekirdek |
| `u_data_ram.aw_addr_reg[7]` → D-RAM SRAM `addr0[5]` | −0,0164 | D-RAM adres |
| `u_instruction_ram.rdata_hold[17]` → `mem_q[49]` | −0,0157 | aynı yol |
| `u_npu.ram_wdata_a[13]` → NPU SRAM `din0[12]` | −0,0094 | NPU yazma verisi |
| `u_npu.ram_wdata_a[14]` → NPU SRAM `din0[13]` | −0,0086 | NPU yazma verisi |

**Hiçbiri CV32E40P'nin kendi mantığında değil.** Biri çekirdeğe *değiyor*
(I-RAM → ön-getirme FIFO'su) ama kaynağı bizim komut belleğimiz. Yani çözüm
üçüncü taraf IP'ye dokunmadan mümkün.

### Neden önemli

Hold ihlali setup'tan farklıdır: **saati yavaşlatarak düzelmez.** Veri saat
kenarından önce varır ve yanlış değer yakalanır — 1 MHz'de de bozuktur. Bu
yüzden ss köşesindeki setup sapması gibi "belgelenmiş sapma" olarak
bırakılamaz.

### Kök neden

`config/resolved.json`:

```
RUN_POST_GRT_RESIZER_TIMING      False
GRT_RESIZER_HOLD_SLACK_MARGIN    0.05
RSZ_CORNERS                      None
```

**Global yönlendirme sonrası zamanlama onarımı hiç koşmamış.** Hold yalnızca
CTS sonrası, *tahmini* parazitiklerle onarıldı. Gerçek yönlendirme gecikmeleri
eklendikten sonra ortaya çıkan ihlalleri yakalayacak ikinci geçiş devre dışıydı.

İkinci sorun: `RSZ_CORNERS` tanımsız. Hold onarımı **hızlı köşede** yapılmalı —
ihlaller tam da orada (−40 °C / 1,95 V). Yalnızca tipik köşede çalışan bir
onarım ff köşesindeki sorunu görmez.

### Düzeltme (`asic/config.yaml`)

```yaml
RUN_POST_GRT_RESIZER_TIMING: true
GRT_RESIZER_HOLD_SLACK_MARGIN: 0.1     # 0,05 idi; en kötü ihlal -0,0622
RSZ_CORNERS:
  - nom_tt_025C_1v80
  - nom_ff_n40C_1v95                   # hold onarımı için kritik
  - nom_ss_100C_1v60
```

---

## 2. Max cap / max slew — kök neden bulundu, düzeltildi

### Bulgu

Dokuz köşenin tamamında ihlal, en iyi köşede bile sıfır değil:

| Köşe | Max cap | Max slew |
|---|---|---|
| min_ff (en iyi) | 215 | 579 |
| nom_tt | 438 | 1842 |
| max_ss (en kötü) | 1305 | 12364 |

İhlal eden pinlerin dağılımı:

| Pin | Adet | Ne |
|---|---|---|
| `DIODE` | 279 | anten diyotları — yavaş ağlara takılı, ağın slew'ünü miras alıyor |
| `RESET_B` | 215 | reset ağı |
| `A` / `C1` / `A1` / `X` | 324 | genel mantık |
| SRAM `wmask0[*]` | 92 | makro yazma maskesi |

### Kök neden

`asic/constraints/design.sdc` içinde **şu üç kısıt hiç yoktu**:

```tcl
set_max_fanout        # YOK
set_max_transition    # YOK
set_max_capacitance   # YOK
set_driving_cell      # YOK
```

LibreLane'in varsayılan SDC şablonu bunları `config.yaml`'daki değerlerden
üretir. Biz `PNR_SDC_FILE` / `SIGNOFF_SDC_FILE` ile **kendi SDC'mizi verdiğimiz
için o şablon devre dışı kaldı**. Kısıtlar config'de yazıyordu ama araca hiç
ulaşmıyordu:

```
MAX_FANOUT_CONSTRAINT        10       <- hicbir etkisi olmamis
MAX_TRANSITION_CONSTRAINT    0.75     <- hicbir etkisi olmamis
MAX_CAPACITANCE_CONSTRAINT   0.2      <- hicbir etkisi olmamis
```

**Kanıt kesin.** Netlist'te reset ağacı 49 tampona bölünmüş ve **her biri
~150 yük sürüyor**:

```
net6202   159 yuk
net6209   158 yuk
net6193   157 yuk
...
```

Buna rağmen STA `max fanout violation count 0` diyor — çünkü ortada kısıt yok.
Fanout sınırı 10 olsaydı bu ağlar 15 kat daha fazla tampona bölünürdü ve slew
sorunu doğmazdı.

`set_driving_cell` eksikliği de ayrı bir etki yaratmış: giriş portları **ideal
sürücü** varsayıldığı için geçiş süresi gerçekçi hesaplanmıyor. `clk_i` giriş
ağı 0,562 pF yük taşıyor ve ilk saat tamponunun girişinde 1,61 ns slew
ölçülüyordu — bu değer bir sürücü modeliyle hesaplanmış değildi.

### Düzeltme (`asic/constraints/design.sdc`)

```tcl
proc _kisit_degeri {ad varsayilan} {
    if {[info exists ::env($ad)] && $::env($ad) ne ""} { return $::env($ad) }
    return $varsayilan
}

set_max_fanout      [_kisit_degeri MAX_FANOUT_CONSTRAINT      10]   [current_design]
set_max_transition  [_kisit_degeri MAX_TRANSITION_CONSTRAINT  0.75] [current_design]
set_max_capacitance [_kisit_degeri MAX_CAPACITANCE_CONSTRAINT 0.2]  [current_design]

set_driving_cell -lib_cell sky130_fd_sc_hd__inv_2 -pin Y [all_inputs]
```

Değerler `config.yaml`'dan okunur; orada değişirse SDC otomatik uyar.

---

## 3. `nwell.4` (7659 ihlal) — ilk teşhis yanlıştı

### İlk hipotez ve neden çürüdü

İlk okumada "tap hücreleri bazı bölgelere ulaşamamış" denmişti. Ölçüm bunu
**çürüttü**.

DEF'ten 2 080 015 bileşen ayrıştırıldı:

| | |
|---|---|
| `sky130_fd_sc_hd__decap_3` | 1 737 983 |
| `sky130_fd_sc_hd__tapvpwrvgnd_1` | **113 470** |
| `sky130_fd_sc_hd__fill_1` | 108 583 |
| `sky130_fd_sc_hd__fill_2` | 28 696 |

İhlal koordinatlarıyla tap konumları çakıştırıldığında:

> **İhlal şeritlerinin %87,3'ünde tap hücresi VAR.**
> Örnek: 152 µm'lik bir şeritte **17 tap** — yani ~9 µm'de bir, ayarlanan
> 13 µm'den bile sıkı.

Yani "tap eksik" açıklaması geçersiz.

### İhlallerin geometrisi

Her ihlal kutusu **2,83 µm yüksekliğinde** — sky130 `hd` kütüphanesinde iki
ters çevrilmiş hücre sırasının paylaştığı n-kuyu şeridinin tam ölçüsü.
Genişlikler makrolar arasındaki serbest şeritlerin genişliği:

| Genişlik | Adet | Bölge |
|---|---|---|
| 314,56 µm | 2849 | — |
| 139,76 µm | 956 | dikey kanal (200 µm − 2×30 µm halo) |
| 151,95 µm | 771 | sol kenar |
| 209,49 µm | 765 | sağ kenar |

Konum dağılımı:

| Bölge | Adet | Oran |
|---|---|---|
| Dikey kanal (makro sütunları arası) | 4166 | %54,4 |
| Yatay kanal (makro sıraları arası) | 2277 | %29,7 |
| Köşe bölgesi (iki kanalın kesişimi) | 1040 | %13,6 |
| Makro üzerinde | 176 | %2,3 |

İhlaller **makro çevresindeki standart hücre şeritlerinde** yoğunlaşıyor.

### KLayout ikinci görüş vermiyor

```
KLayout deckindeki nwell kurallari: nwell.1, nwell.2a, nwell.6, nwell.9
```

**`nwell.4` KLayout'un kural setinde yok.** Yani KLayout'un "0 ihlal" sonucu
bu kuralı temize çıkarmıyor; Magic tek tanık.

### Kalan hipotez ve belirleyici test

Taplar var, yoğun ve doğru yerde. Geriye tek makul açıklama kalıyor:
**Magic'in DEF kipinde metal bağlantısını izleyememesi.** Kural "metal ile
bağlı N+ tap" istiyor; Magic'in kuyu → tap → li1/met1 → VPWR zincirini soyut
makro görünümlerinin bulunduğu bir DEF'te tam çözememesi mümkündür.

**Belirleyici test:** `MAGIC_DRC_USE_GDS: true` ile DRC'yi **GDS üzerinde**
koşmak. GDS tam gerçek geometriyi taşır, soyutlama yoktur.

- İhlaller **kaybolursa** → DEF kipi yapaydı, tasarımda sorun yok
- İhlaller **kalırsa** → gerçek bir kuyu bağlantı sorunu var, o zaman
  `FP_TAPCELL_DIST` ve halo ayarlarıyla uğraşılır

Bu test §9.8'de zaten "vakit kalırsa yapılacak" diye planlanmıştı. Artık
sadece bütünlük için değil, **teşhis için** gerekli.

Not: bu koşum 64 GB makinede yapılmalı — `PDK` kipinde Magic RSS 10,4 GB'a
çıkıyor ve DRC makro içlerini de tarayacağı için uzun sürer.

---

## 4. Setup (ss köşesi) — durum değişmedi

`TIMING_VIOLATION_CORNERS: ['*tt*']` olduğu için setup denetimi yalnızca
tipik köşelere bakıyor; ss'teki −6,31 ns akışı düşürmedi. Bu LibreLane
varsayılanı, bizim ayarımız değil.

Sapmanın gerekçesi `evidence/asic/ZAMANLAMA_ANALIZI_RAPORU.md`'de. Özet:
en kötü yol `CV32E40P → CV32E40P`, yani çekirdeğin kendi içi; üçüncü taraf
IP'ye dokunmama kararı gereği kapatılmadı.

Yeni koşumda beklenen: `set_driving_cell` ve slew kısıtları gerçekçi geçiş
süreleri getireceği için **ss setup sayıları bir miktar değişecek** — iyiye
de kötüye de gidebilir, ölçülecek.

---

## 5. Yedinci koşum için beklenti

**Yüksek güven**
- Hold ihlalleri kapanır (post-GRT onarım + ff köşesi + 0,1 ns marj)
- Max fanout ihlali 0 kalır ama artık *kısıt olduğu için*
- Reset ağacı çok daha fazla tampona bölünür, slew düşer

**Orta güven**
- Max slew ihlalleri büyük ölçüde azalır; SRAM `wmask` pinlerindekiler kalabilir
- Hücre sayısı ve alan bir miktar artar (fanout 10 sıkı bir sınır)

**Bilinmiyor**
- `nwell.4` — ayrı bir GDS-DRC koşumu gerektiriyor
- ss setup'ın yeni değeri

**Risk**
- Fanout 10 agresif; tampon sayısı çok artarsa yerleştirme yoğunluğu ve
  yönlendirme sıkışması artabilir. Global yönlendirme kullanımı %14,4 idi,
  pay bol — ama izlenmeli.

---

## 6. Yeniden üretim

```bash
cd ~/arkhe && git pull
cd asic
make asic_run 2>&1 | tee /tmp/asic_kosum7.log
```

Floorplan ve sonrası tamamen yeniden koşar (SDC değişikliği sentezi de
etkiler). Süre: ~3–4 saat.

`nwell.4` teşhis koşumu ayrıca:

```bash
# config.yaml icinde MAGIC_DRC_USE_GDS: true yapilir
make asic_resume FROM=Magic.DRC
```
