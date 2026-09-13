# Final Çıktılar PDF'ine göre kontrol listesi
# (2026 Final Çıktılar.pdf — 12 Eylül 2026 itibarıyla)

Bu belge, PDF'te istenen her kalemin karşılığını ve konumunu
gösterir. Ölçülerek doğrulanmıştır.

---

## Bölüm 1 — Araçlar ve Ortam

| İster | Durum | Konum / Değer |
|---|---|---|
| LibreLane 3.0.6 | ✅ | `asic/environment/versions.txt` |
| Classic akışı | ✅ | `asic/config.yaml` |
| PDK sky130A | ✅ | commit `8afc8346a57fe1ab7934ba5a6056ea8b43078e71` |
| STD_CELL_LIBRARY sky130_fd_sc_hd | ✅ | `asic/config.yaml` |
| Üç PVT corner (Tablo 4) | ✅ | tt_025C_1v80, ss_100C_1v60, ff_n40C_1v95 |
| En az bir SRAM makrosu | ✅ | `sky130_sram_2kbyte_1rw1r_32x512_8` × 23 |
| SRAM: GDSII, LEF, Verilog, Liberty | ✅ | `asic/macros/<makro>/` |
| flake.nix, flake.lock, versions.txt | ✅ | `asic/environment/` |
| OpenRAM sürümü veya "kullanılmadı" | ✅ | `versions.txt` |

**SRAM notu:** Hazır PDK makrosu kullanıldı, fiziksel/mantıksal
görünümleri değiştirilmedi. PDK orijinalleriyle SHA-256 karşılaştırması
yapıldı — GDS, LEF, LIB üçü de **birebir aynı**.

---

## Bölüm 3 — Akış Girdileri

| İster | Durum | Konum |
|---|---|---|
| Sentezlenebilir RTL | ✅ | `rtl/` (57 dosya) |
| En üst modül adı | ✅ | `soc_top` — RTL, config.yaml, README uyumlu |
| RTL dosya listesi | ✅ | `asic/filelist.f` |
| `asic/constraints/design.sdc` | ✅ | birincil saatler ve periyotlar tanımlı |
| Makro bilgileri | ✅ | `asic/README.md` §5 |
| Fiziksel tasarım girdileri | ✅ | `asic/README.md` §7 |

---

## Bölüm 4 — Depo Organizasyonu (Tablo 8)

| Klasör/Dosya | Durum |
|---|---|
| `asic/README.md` | ✅ |
| `asic/Makefile` | ✅ (`asic_run`, `asic_verify`, `asic_clean`) |
| `asic/config.yaml` | ✅ |
| `asic/filelist.f` | ✅ |
| `asic/THIRD_PARTY.md` | ✅ |
| `asic/checksums/` | ✅ |
| `asic/scripts/` | ✅ |
| `asic/environment/` | ✅ (flake.nix, flake.lock, versions.txt) |
| `asic/constraints/design.sdc` | ✅ |
| `asic/macros/<makro>/{gds,lef,lib,verilog,spice}` | ✅ |
| `asic/reports/` — 11 alt dizin | ✅ |
| `asic/results/` — 14 alt dizin | ✅ |

---

## Bölüm 5 — İstenen Raporlar

| Alt bölüm | Durum | Konum |
|---|---|---|
| 5.1 Genel akış | ✅ | `reports/general/` — flow.log, warning.log, error.log |
| 5.2 Lint | ✅ | `reports/lint/` |
| 5.3 Sentez | ✅ | `reports/synthesis/` — stat.rpt, chk.rpt, latch.rpt |
| 5.4 Fiziksel tasarım | ✅ | `reports/routing/`, metrics, wire_lengths.csv |
| 5.5 Zamanlama | ✅ | `reports/timing/` — summary.rpt + 9 corner dizini |
| 5.6 Fiziksel signoff | ✅ | `reports/drc/`, `lvs/`, `antenna/`, `pdn/`, `signoff/` |
| 5.7 Güç ve IR-drop | ✅ | `reports/power/` — corner başına power.rpt, irdrop.rpt |

**Zamanlama raporları dokuz köşe için de mevcuttur** (min/nom/max ×
tt/ss/ff): max.rpt, min.rpt, checks.rpt, skew.*, ws.*, wns.*, tns.*,
violator_list.rpt, clock.rpt, unpropagated.rpt

---

## Bölüm 6 — İstenen Çıktılar

### 6.1 Zorunlu fiziksel görünümler

| Dosya | Durum | Boyut |
|---|---|---:|
| `results/gds/soc_top.gds` | ✅ | 356 MB |
| `results/lef/soc_top.lef` | ✅ | |
| `results/def/soc_top.def` | ✅ | 284 MB |

### 6.2 Zorunlu ek çıktılar

| Dosya | Durum |
|---|---|
| `results/netlist/soc_top_synth.v` | ✅ |
| `results/netlist/soc_top_pnr.v` | ✅ |
| `results/netlist/soc_top_powered.v` | ✅ |
| `results/sdc/pnr.sdc` | ✅ |
| `results/sdc/signoff.sdc` | ✅ |
| `results/spef/{min,nom,max}/` | ✅ (üç RC corner) |
| `results/spice/soc_top_lef_def.spice` | ✅ (LEF/DEF'ten çıkarılmış, LVS'de kullanılmış) |
| `results/config/resolved.json` | ✅ |
| `results/metrics/metrics.csv` | ✅ |
| `results/metrics/metrics.json` | ✅ |

### 6.3 Önerilen ek çıktılar

| Dosya | Durum |
|---|---|
| `results/odb/soc_top.odb` | ✅ |
| `results/sdf/<corner>/*.sdf` | ✅ (dokuz köşe) |
| `results/lib/` | ✅ |
| `results/mag/soc_top.mag` | ✅ |
| `results/gds/soc_top.magic.gds` | ✅ |
| `results/gds/soc_top.klayout.gds` | ✅ |
| `results/images/` | ✅ |
| `asic/checksums/SHA256SUMS` | ✅ |

---

## Bölüm 8 — Otomasyon

| Hedef | Durum | Not |
|---|---|---|
| `make asic_run` | ✅ | Zorunlu — LibreLane Classic akışını çalıştırır |
| `make asic_verify` | ✅ | Önerilen — **çıkış kodu 0** |
| `make asic_clean` | ✅ | Önerilen |

---

## Bölüm 9 — README İçeriği

`asic/README.md` içinde bulunan başlıklar:

| Başlık | Durum |
|---|---|
| 9.1 Tasarım Özeti | ✅ |
| 9.2 Araç ve Ortam Bilgileri | ✅ |
| 9.3 Akışın Çalıştırılması | ✅ |
| 9.4 RTL ve Akış Girdileri | ✅ |
| 9.5 SRAM ve Fiziksel Makrolar | ✅ (Liberty köşe varsayımı DDK kararıyla açıklandı) |
| 9.6 Zamanlama Kısıtları ve İstisnaları | ✅ |
| 9.7 Fiziksel Tasarım Yapılandırması | ✅ |
| 9.8 Lint Sonuçları ve İstisnaları | ✅ |
| 9.9 Bilinen Sorunlar ve Kabul Edilmiş İstisnalar | ✅ |
| 9.10 Güç ve IR-Drop Analizi | ✅ (tahmini olduğu açıkça belirtildi) |
| 9.11 Signoff Sonuç Özeti | ✅ |
| 9.12 Rapor ve Çıktı Konumları | ✅ |
| 9.13 Üçüncü Taraf Bileşenler | ✅ (`asic/THIRD_PARTY.md`) |

---

## Bölüm 10 — Üçüncü Taraf

`asic/THIRD_PARTY.md` içinde:
  - CV32E40P çekirdeği (OpenHW Group)
  - sky130 PDK ve SRAM makrosu
  - LibreLane akış araçları

---

## Bölüm 7 — Teslim Esasları

| Kural | Durum |
|---|---|
| Zorunlu raporlar eksiksiz | ✅ |
| Zorunlu çıktılar eksiksiz | ✅ |
| Aynı LibreLane çalışmasından | ✅ (**S_final2** koşusu, 13 Eylül 2026) |
| Akış sonrası elle düzenlenmemiş | ✅ |
| **Başarısız sonuçlar gizlenmemiş** | ✅ |

### Gizlenmeyen kalemler

Aşağıdakiler raporlarda olduğu gibi durmaktadır ve README §9'da
açıklanmıştır:

    Magic DRC ............. 7.658  (makro kaynaklı nwell.4)
    Slew ihlali ........... 16.030 (makro Liberty limiti)
    Cap ihlali ............ 1.952
    Fanout ihlali ......... 81
    Bağlantısız pin ....... 256 (kritik: 0)

Her biri için kök neden ölçülmüş ve belgelenmiştir:
`verification/kanitlar/MAGIC_DRC_KOK_NEDEN.md`,
`SLEW_CAP_FANOUT_COZUM_ARASTIRMASI.md`

---

## 12 Eylül 2026 — kullanılmayan port düzeltmeleri

Teslim öncesi son taramada iki **işlevsel eksiklik** bulundu ve
düzeltildi. İkisi de gizlenmedi; ölçümleriyle belgelendi.

| Bulgu | Düzeltme | Kanıt |
|---|---|---|
| `jtag_debug` AXI yanıt kodunu (`rresp`/`bresp`) hiç okumuyordu — DECERR dönen okuma çöp veriyle geçerli sanılıyordu | Yanıt kodu yakalanır; `REG_DBG_STATUS[3]` hata bayrağı, `[5:4]` yanıt kodu | `tb_jtag_yanit_kodu.sv` — 9 denetim |
| `i2c_peripheral` `scl_i`'yi hiç okumuyordu — yavaş köle SCL'i tutsa master farketmezdi (saat germe yok) | `scl_i` senkronize edilir; germe boyunca çeyrek sayacı dondurulur | `tb_i2c_saat_germe.sv` — 4 denetim |

**Ölçüm:** saat germe boyunca DUT'un iç sayacı **0 hareket** yapar;
düzeltmesiz RTL'de **248** hareket ölçülür (~250 beklenir).

**400 kHz etkilenmedi:** germe kararı senkronizatör tazelendikten
sonra verilir; köle germezse SCL periyodu **tam 2500 ns** kalır.

Her iki düzeltme kalıcı hata enjeksiyonu kampanyasına eklendi:
**7/7 mutasyon yakalanıyor, 0 kaçırılıyor.**

Lint uyarısı bu düzeltmeler sayesinde **816 → 813**'e indi
(`UNUSEDSIGNAL` 167 → 164).

Ayrıntı: `verification/kanitlar/KULLANILMAYAN_PORT_DUZELTMELERI.md`

---

## S_final2 koşusuna geçiş — 13 Eylül 2026

Teslim edilen ASIC koşusu **S_saat**'ten **S_final2**'ye güncellendi.

### Neden

`S_saat` koşusu, 12 Eylül'de bulunan iki işlevsel düzeltmeden
**önceki** RTL'i yansıtıyordu (JTAG AXI yanıt kodu denetimi ve
I2C saat germe). Düzeltilmiş RTL ile akış yeniden koşuldu.

### Sonuç

| | S_saat | **S_final2** |
|---|---|---|
| Hold (dokuz köşe) | 9/9 pozitif | **9/9 pozitif** |
| Setup (dokuz köşe) | 9/9 pozitif | **9/9 pozitif** |
| Hold marjı | — | **7 köşede S_saat'ten iyi** |
| JTAG + I2C düzeltmeleri | ❌ yok | ✅ **var** |

### Bu koşuda olmayan tek şey

Önceki pakette, akış dışında elle koşulan ek bir **GDS tabanlı
LVS** çalışması (`reports/lvs_gds/`, `soc_top_gds.spice`) vardı.
Bu koşuda tekrarlanmadı ve pakette yer almıyor.

Gerekçe:
1. Şartname §7 çıktıların **"aynı LibreLane çalışmasından"**
   gelmesini ve akış sonrası elle düzenleme yapılmamasını ister.
2. O çalışma `MAGIC_EXT_ABSTRACT_CELLS` ile SRAM içini zaten
   soyutluyordu, yani makro transistörlerini doğrulamıyordu.

**Şartnamenin zorunlu tuttuğu LVS eksiksizdir:** standart akışın
Netgen LVS adımı `Circuits match uniquely` vermiştir.

Ayrıntı: `verification/kanitlar/HOLD_KOK_NEDEN_CTS.md`

---

## Doğrulama komutu

    cd asic && make asic_verify

Çıktı:

    {"missing": [], "empty": [], "source_errors": [], "hash_errors": []}
    çıkış kodu: 0
