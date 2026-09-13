# ARKHE SoC — TEKNOFEST 2026 Çip Tasarım Yarışması

**Kategori:** Mikrodenetleyici Tasarım
**Takım:** ARKHE · **Başvuru ID:** 4721248

RISC-V (CV32E40P) tabanlı, TFLite Micro Speech modelini donanımda
çalıştıran bir YZ hızlandırıcı içeren mikrodenetleyici.

---

## Sonuçlar

| | |
|---|---|
| **Zamanlama** (9 PVT köşesi, 23,148 ns) | setup **9/9 pozitif** · hold **9/9 pozitif** · ihlal 0 |
| **LVS** | `Circuits match uniquely` (GDS'ten çıkarılan netlist) |
| **DRC** | KLayout **0** · Routing **0** · XOR **0** · Magic 7.658 (makro kaynaklı, belgeli) |
| **Anten** | 0 / 0 |
| **Doğrulama** | 37/37 test · 702 denetim · 9/9 mutasyon yakalandı |
| **FPGA** | route error 0 · WNS +1,572 ns · WHS +0,042 ns |

Beyan edilen çalışma noktası **43,2 MHz** (23,148 ns). ASIC koşu
etiketi **`S_final2`**.

---

## Depo düzeni

| Dizin | İçerik |
|---|---|
| **`asic/`** | ASIC fiziksel tasarım akışı — şartname Tablo 8 yapısı. Girdi, yapılandırma, otomasyon, `reports/`, `results/`. **Akış buradan koşulur.** |
| `rtl/` | Sentezlenebilir RTL kaynakları (57 dosya `asic/filelist.f` içinde listelenir) |
| `tb/` | Testbench'ler ve UVM paketi |
| `verification/` | Doğrulama planı, regresyon/kapsam raporları, kanıt belgeleri, Spike ISS karşılaştırması |
| `fpga/` | FPGA demo ve jüri test sürümü, bitstream, firmware, **demo adımları** |
| `docs/` | Şartname uyum listesi, sapmalar, koşu incelemesi, teslim özeti |
| `sunum/` | `soc_top` render'ları (sunum için) |
| `provenance/` | Kaynak eşlemesi, zorunlu dosya listesi, checksum kayıtları |
| `evidence/` | Tarihsel ölçüm ve denetim kayıtları |

---

## ASIC akışını yeniden çalıştırma

```bash
nix develop ./asic/environment
export PDK_ROOT=<sky130A içeren PDK üst dizini>
cd asic
make asic_run       # akışı koşar
make asic_verify    # teslim paketini doğrular (çıkış kodu 0 beklenir)
```

Gereksinim: 8+ çekirdek, 32 GB RAM, ~20 GB boş disk. Süre ~5,5 saat.
Ayrıntı: [`asic/README.md`](asic/README.md).

## RTL doğrulamasını çalıştırma

```bash
python scripts/run_regression.py       # 37 test, 702 denetim
python scripts/hata_enjeksiyon.py      # 9 mutasyon kampanyası
```

Plan ve hedefler: [`verification/DOGRULAMA_VE_TEST_PLANI.md`](verification/DOGRULAMA_VE_TEST_PLANI.md)

## FPGA demosu

Adım adım kılavuz: [`fpga/FPGA_DEMO_ADIMLARI.md`](fpga/FPGA_DEMO_ADIMLARI.md)

Bitstream `fpga/nexys_demo_20260908/bitstream/nexys_top.bit`,
demo aracı ve hazır ICD `fpga/nexys_demo_20260908/demo/` altındadır.

---

## Bilinen sınırlar — gizlenmemiştir

- **Magic DRC 7.658** — tamamı `nwell.4`, kaynağı hazır SRAM makrosudur;
  aynı GDS'te KLayout DRC 0 verir. Ölçüm: `evidence/denetim_20260910/MAGIC_DRC_KOK_NEDEN.md`
- **Max slew / cap / fanout** — makro Liberty limiti fiziksel olarak
  erişilemez (hedef 0,04 ns, std hücrenin en iyisi 0,043 ns)
- **Güç sonuçları tahminî** — açık switching activity girdisi yok (şartname izin verir)
- **Gate-level simülasyon** — netlist sıfır hatayla derlendi, işlevsel koşum
  X yayılımı nedeniyle sonuç vermedi (şartname istemiyor)

Tam liste ve gerekçeler: [`docs/SARTNAME_UYUMU_VE_SAPMALAR.md`](docs/SARTNAME_UYUMU_VE_SAPMALAR.md)
