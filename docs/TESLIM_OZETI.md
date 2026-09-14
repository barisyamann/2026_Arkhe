# ARKHE SoC — TEKNOFEST 2026 Çip Tasarım Yarışması
# Mikrodenetleyici Tasarım Kategorisi — Final Teslimi

Bu dizin, final teslimi için hazırlanan çıktıların düzenli bir
görünümüdür. Her bölüm kendi açıklama belgesiyle (`README.md` veya
`OKUBENI.md`) anlatılmıştır.

---

## Hızlı özet

| | |
|---|---|
| **Beyan edilen çalışma noktası** | 23,148 ns = **43,2 MHz** |
| **Dokuz PVT köşesi** | setup ve hold **9/9 pozitif**, TNS sıfır (koşu **S_final2**) |
| **Fiziksel signoff** | Route DRC 0 · KLayout DRC 0 · LVS eşleşiyor · XOR 0 · anten 0/0 · illegal overlap 0 · **Magic DRC'de 7.658 açık bulgu** (makro kaynaklı, aşağıda) |
| **Regresyon** | **37/37 test, 702 denetim** |
| **İşlevsel kapsam** | **52/52 = %100** |
| **Kod kapsamı (bizim RTL)** | %81,6 statement / %74,9 branch |
| **Hata enjeksiyonu** | **9/9 mutasyon yakalanıyor** |

---

## Dizin yapısı

### `asic/` — ASIC fiziksel tasarım

ASIC teslim paketi deponun **`asic/`** dizinindedir (7,7 GB).
Şartname (PDF Bölüm 4, Tablo 8) yapının orada olmasını istediği için
kopyalanmadı. Ayrıntı: `asic/README.md`

Doğrulama: `cd asic && make asic_verify` → çıkış kodu 0

### `verification/` — Doğrulama ve testler

    raporlar/     regresyon sonucu, hata enjeksiyonu kampanyası
    testler/      36 testbench + UVM paketi (SystemVerilog)
    betikler/     regresyon koşucusu, hata enjeksiyonu, Spike, kapsam araçları
    kapsam/       kod kapsamı (blok + sistem) ve işlevsel kapsam raporları
    spike_iss/    Spike ISS izi, RTL izi, karşılaştırma sonucu
    kanitlar/     25 ölçüm ve bulgu belgesi

### `fpga/` — FPGA demo

    nexys_demo/        güncel sürüm: bitstream, firmware, kısıtlar, RTL, raporlar
    JURI_FPGA_TESTI/   jüri tanılama sürümü (tek USB)

Vivado ara dosyaları (`build/`, 61 MB) dahil edilmedi.

### `docs/` — Şartname uyumu

    SARTNAME_UYUMU_VE_SAPMALAR.md   uyum tablosu (ölçülmüş durum), dört sapma analizi
    ASIC_SAAT_BAGIMLILIGI.md        ASIC/FPGA frekans farkı değerlendirmesi

---

## Şartname uyumu (özet)

| Bölüm | Durum |
|---|---|
| §4.2.2.1 Genel İsterler | **12/12** |
| EK-1 YZ Hızlandırıcı | **6/6** — hızlanma **177×**, altın referansla birebir (%100, 156/156) |
| EK-2 Çevre Birimi Yazmaçları | 5 birim tam uyumlu |
| EK-3 Doğrulama | Zorunlu maddelerin tamamı |
| §5.2 Ödül Minimum Kriterleri | Ölçülmüş durum `docs/SARTNAME_UYUMU_VE_SAPMALAR.md`'de; puanlama jürinin takdirindedir |

### Şartnamenin üstüne çıkılan yerler

| İster | Şartname | Bizde |
|---|---|---|
| Protokol kontrolü | zorunlu | **İki UVM agent + 5 SVA checker**, 401.729 işlem, 13/13 adres bölgesi, fonksiyonel kapsam |
| Blok testleri | opsiyonel | **17 blok** |
| Spike ISS | "tür ve sıra" | 927 buyruk + **765 yazmaç değeri** — sonuç doğruluğu da |
| Code coverage | opsiyonel | %81,6 / %74,9 |
| — | *istenmiyor* | **Hata enjeksiyonu** — testlerin gerçekten hata yakaladığı kanıtlı |
| — | *istenmiyor* | Dokuz köşe PVT imza STA |

---

## Bilinen sapmalar (hepsi analiz edilmiş)

| Sapma | Değerlendirme |
|---|---|
| Flash parçası S25FL128S | Kart üstü parça, 17/17 komut, DDK'nın 3 emsal onayı |
| Timer PRE yorumu | Şartname kendi içinde tutarsız; kuralı tanımlayan örneklere uyuldu |
| QSPI 4-bayt mekanizması | Şartname tanımlamıyor, "Yarışmacı Tanımlı" alan kullanıldı |
| Magic DRC 7.658 | Makro kaynaklı `nwell.4` — makro tek başına 1,39M ihlal verir |
| Slew/cap/fanout | Makro Liberty limiti fiziksel olarak erişilemez (0,04 ns hedef, std hücre en iyi 0,043 ns) |
| SRAM tek köşe modeli | **DDK 10 Eylül 2026 kararıyla açıkça kabul** |

Şartname §3.3.2 "eksikliklerin açık anlatımı ve analizi"ni puanlıyor;
hepsi ölçümle gerekçelendirilmiştir.

---

## Bilinen doğrulama sınırları

Gizlenmeyen, ölçülmüş ve belgelenmiş açıklar:

1. **Gate-level simülasyon** — netlist iki araçla sıfır hatayla derlendi
   ama işlevsel koşum X yayılımı nedeniyle anlamlı sonuç vermedi
   (6.296 reset'siz flip-flop). Belge: `verification/kanitlar/GATE_LEVEL_SIM.md`

2. **Formal doğrulama** — yapılmadı, şartname istemiyor.

> **13 Eylül 2026'da kapatılan açık:** `npu_accelerator` hakemliğinin
> motor dalı artık uyarılıyor **ve** veri yolu düzeyinde doğrulanıyor.
> Testin ilk hâli dekoratifti (dalın seçildiğini ölçüyor, doğru
> veriyi taşıdığını ölçmüyordu); mutasyon denemesi bunu ortaya
> çıkardı ve düzeltildi.
> Belge: `verification/kanitlar/A1_NPU_HAKEM_MOTOR_DALI.md`

---

## Yeniden üretim

    # ASIC akışı
    cd asic && make asic_run

    # Doğrulama regresyonu
    python scripts/run_regression.py

    # Hata enjeksiyonu (testlerin hata yakaladığını kanıtlar)
    python scripts/hata_enjeksiyon.py

    # Kapsam ölçümü
    python scripts/run_regression.py --coverage
    python scripts/kapsam_analiz.py

    # Spike ISS karşılaştırması
    python scripts/spike_karsilastir.py
