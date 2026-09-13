# Arkhe SoC — Doğrulama ve Test Planı

**Tarih:** 13 Eylül 2026
**Kapsam:** RTL işlevsel doğrulama (ASIC fiziksel signoff ayrıdır:
`asic/README.md` §11)

Bu belge, şartname **EK-3**'ün ilk satırında istenen planı verir:
*"Yürütülecek doğrulama faaliyetlerinin ana hatları ve doğrulama
faaliyetlerinin tamamlanmış sayılması için gereken hedefler."*

---

## 1. Doğrulama hedefleri ve tamamlanma ölçütü

Her hedef için **ne zaman tamamlanmış sayılacağı** önceden
tanımlanmıştır. "Tamamlandı" demek için testin geçmesi yetmez;
testin **hatayı gerçekten yakaladığı** da kanıtlanmalıdır
(bkz. §4 mutasyon kampanyası).

| # | Hedef | Tamamlanma ölçütü | Durum |
|---|---|---|---|
| H1 | Her çevre birimi EK-2 yazmaç haritasına uyar | Birim başına self-checking test, tüm yazmaçlar okunur/yazılır | ✅ |
| H2 | I2C SCL tam 400 kHz | Ölçülen periyot = 2500,00 ns | ✅ |
| H3 | Çekirdek buyrukları referansla aynı | Spike ISS ile PC **ve yazmaç değeri** karşılaştırması, 0 uyuşmazlık | ✅ |
| H4 | NPU çıkarımı altın modelle aynı | Sınıflandırma uyumu 7/7, softmax birebir | ✅ |
| H5 | NPU yazılımdan hızlı | Ölçülen hızlanma raporlanır | ✅ |
| H6 | AXI4-Lite protokolü ihlal edilmez | İki agent, ARM IHI0022 kuralları, 0 ihlal | ✅ |
| H7 | Boot akışı uçtan uca çalışır | QSPI→I-RAM shadowing + main() self-checking | ✅ |
| H8 | Sistem entegrasyonu bütün | CPU+DMA+NPU+çevre birimi birlikte, gerçek firmware | ✅ |
| H9 | Testler gerçekten hata yakalar | Mutasyon kampanyası, 0 kaçan | ✅ |
| H10 | Kapsam ölçülür ve açıkları belgelenir | Kod + işlevsel kapsam raporu, açıklar yazılı | ✅ |

---

## 2. Doğrulama seviyeleri

### 2.1 Blok seviyesi (EK-3: "Opsiyonel")

Her IP bloğu kendi testbench'iyle izole doğrulanır.

| Blok | Test | Denetim |
|---|---|---|
| UART | `tb_uart` | 42 |
| I2C | `tb_i2c_peripheral` | 38 |
| GPIO | `tb_gpio_peripheral` | 37 |
| Timer | `tb_timer_peripheral` | 36 |
| QSPI | `tb_qspi_master` | 40 |
| DMA | `tb_dma_controller` | 39 |
| JTAG | `tb_jtag_debug` | 27 |
| SRAM | `tb_sram_registered` | 6 |
| NPU motoru | `tb_npu_compute_engine` | 43 |
| NPU sarmalayıcı | `tb_npu_accelerator` | 16 |
| FIFO | `tb_sync_fifo` | 24 |

Çevre birimlerinin **kendi blok testlerindeki** kod kapsamı
%93–97 aralığındadır.

### 2.2 Şartname uyum testleri

EK-2 yazmaç tanımlarının **harfi harfine** karşılandığını
denetleyen ayrı testler:

    sartname_timer  25 denetim     sartname_uart_stream  15
    sartname_gpio   15 denetim     sartname_qspi         27
    sartname_uart   20 denetim

### 2.3 Protokol kontrolleri (EK-3: **Zorunlu**)

`tb/uvm/axil_uvm_pkg.sv` — iki pasif UVM agent:

| Bağlantı noktası | İşlem |
|---|---|
| NPU motoru → TCM | 162.064 |
| SoC ana yolu (`merged_m_*`) | 239.665 |
| **Toplam** | **401.729** |

Denetlenen ARM IHI0022 kuralları: VALID kararlılığı (A3.2.1),
reset'te VALID yasağı (A3.1.2), EXOKAY yasağı (A3.4.4), X/Z,
adres hizalama, `WSTRB != 0`, asılı işlem.

**Çapraz doğrulama:** ham AXI el sıkışma sayımı monitör sayımıyla
birebir tutar (382.691 / 19.038) — monitör hiçbir işlemi
kaçırmıyor.

### 2.4 Çekirdek testleri (EK-3: "Elden gelenin en iyisi")

Spike ISS referans karşılaştırması:

    karsilastirilan buyruk : 927     PC uyusmazligi          : 0
    yazmac karsilastirilan : 765     yazmac DEGER uyusmazligi: 0

Yalnızca buyruk dizisi değil, **her buyruğun yazdığı yazmaç
değeri** de karşılaştırılır.

### 2.5 YZ hızlandırıcı testleri (EK-3: **Zorunlu**)

| Test | Ne doğrular | Denetim |
|---|---|---|
| `npu_blok` | Motor FSM, MAC, ReLU, softmax | 43 |
| `npu_accelerator` | CSR, TCM, **hakemlik iki dalı** | 16 |
| `npu_golden` | Altın vektörle birebir eşleşme | 1 |
| `npu_dogruluk` | 7 gerçek ses vektörü, sınıf uyumu 7/7 | 77 |
| `npu_hizlanma` | Yazılıma karşı hızlanma ölçümü | 2 |

### 2.6 Sistem seviyesi testler (EK-3: **Zorunlu**)

| Test | Ne doğrular | Denetim |
|---|---|---|
| `sistem` | Boot + çevre birimi + NPU birlikte | 20 |
| `sistem_gercek_boot` | **Gerçek** firmware ile QSPI shadowing | 20 |
| `cekirdek_izi` | Spike iz üretimi | 1 |

Hepsi self-checking; elle inceleme gerekmez.

---

## 3. Sonuç

    Regresyon        : 36/36 test, 689 denetim
    Hata enjeksiyonu : 9/9 mutasyon yakalandı, 0 kaçtı
    İşlevsel kapsam  : 52/52 covergroup = %100
    Kod kapsamı      : %81,7 statement / %75,1 branch (bizim RTL)
    RTL bütünlüğü    : 57/57 dosya

Koşum: `python scripts/run_regression.py`

---

## 4. Testlerin gerçekten hata yakaladığının kanıtı

Bir testin geçmesi, hatayı yakalayacağını göstermez. Bu yüzden
`scripts/hata_enjeksiyon.py` RTL'e kasıtlı hata sokar ve ilgili
testin **kırmızıya döndüğünü** doğrular.

**9 mutasyon, 9'u da yakalandı, 0 kaçtı.** Kampanya sonrası
57/57 RTL dosyası birebir korunur.

Bu yöntem iki kez **dekoratif test** ortaya çıkardı ve düzeltildi:

1. **I2C saat germe testi** — DUT'un iç sayacı yerine testbench'in
   kendi tuttuğu hattı ölçüyordu; `germe_dur = 1'b0` yapılsa bile
   geçiyordu.
2. **NPU hakemlik testi (A1)** — dalın *seçildiğini* ölçüyordu ama
   *doğru veriyi taşıdığını* ölçmüyordu; hakem motor dalını hiç
   seçmese bile geçiyordu. Veri yolu denetimi eklendi.

---

## 5. Bilinen sınırlar — gizlenmiş açık yoktur

| Sınır | Durum | Belge |
|---|---|---|
| Gate-level simülasyon | Netlist iki araçla **sıfır hatayla derlendi**; işlevsel koşum X yayılımı nedeniyle sonuç vermedi (6.296 reset'siz FF — sky130 `dfxtp` hücreleri reset pini taşımaz). Şartname istemiyor. | `kanitlar/GATE_LEVEL_SIM.md` |
| Formal doğrulama | Yapılmadı. Şartname istemiyor. | — |
| UVM agent'ları pasif | Trafiği izler, üretmez. Aktif altyapı (driver/sequencer/sequence) **eklendi** ama teslim edilen regresyon pasif modda koşar. | `kanitlar/UVM_U1_U6_UYGULAMA.md` |
| NPU agent kapsamı %52,1 | `strb %33`, `yanit %33` — NPU motoru TCM'e hep tam kelime yazar, TCM hep OKAY döner. Pasif izlemeyle **kapatılamaz**, eksiklik değil. | `kanitlar/UVM_YAPILABILECEKLER.md` |
| Güç sonuçları tahminî | Açık switching activity girdisi yok; şartname izin veriyor (§9.10). | `asic/README.md` |

Ek iyileştirme önerileri değer/maliyet sıralı olarak
`kanitlar/DOGRULAMA_YAPILABILECEKLER.md` içindedir.

---

## 6. EK-3 tablosuna göre durum

| EK-3 kalemi | Öncelik | Durum |
|---|---|---|
| Doğrulama Planı | Elden gelenin en iyisi | ✅ bu belge |
| Blok Seviyesi Testler | Opsiyonel | ✅ 11 blok |
| **Protokol Kontrolleri** | **Zorunlu** | ✅ 401.729 işlem |
| Çekirdek Testleri | Elden gelenin en iyisi | ✅ Spike, 0 uyuşmazlık |
| **YZ Hızlandırıcı Testleri** | **Zorunlu** | ✅ 5 test, 139 denetim |
| **Sistem Seviyesi Testler** | **Zorunlu** | ✅ 3 test, 41 denetim |
| Code Coverage | Opsiyonel | ✅ `kapsam/kod_kapsami_*` |
| Functional Coverage | Opsiyonel | ✅ 52/52 = %100 |

**Üç zorunlu kalemin üçü de karşılanmıştır.**
