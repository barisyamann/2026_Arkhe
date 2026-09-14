# Arkhe SoC — Jüri Sunumu İçeriği

**TEKNOFEST 2026 Çip Tasarımı Yarışması — Mikrodenetleyici Kategorisi**
Hazırlık tarihi: 9 Eylül 2026

---

## Bu belge nasıl kullanılır

Buradaki **her sayı ölçülmüştür**; tahmin veya yuvarlama yoktur. Her bölümün
sonunda o sayının hangi dosyadan geldiği yazılıdır — jüri sorarsa doğrudan
gösterilebilir.

Sunumda **söylenmemesi gereken** şeyler de işaretlenmiştir. Bunlara dikkat
edin: yanlış bir iddia, doğru sayıları da şüpheli hale getirir.

Önerilen süre dağılımı 15 dakikalık bir sunum içindir. Kısaltmanız gerekirse
6, 8 ve 9. bölümlerden kısın; 3, 5 ve 10. bölümler en güçlü kısımlarımızdır.

---

## 1. Kapak ve özet — 1 slayt (30 sn)

**Arkhe SoC** — RISC-V tabanlı, yapay zekâ hızlandırıcılı mikrodenetleyici

Tek cümlelik özet:

> 32-bit RISC-V çekirdeği, TinyConv sinir ağı hızlandırıcısı ve yedi çevre
> birimi içeren; SKY130 üzerinde fiziksel tasarımı tamamlanmış, FPGA'da
> uçtan uca doğrulanmış bir mikrodenetleyici.

Üç rakamla vitrin:

| | |
|---|---|
| Fiziksel tasarım | Detailed-route DRC 0 · KLayout DRC 0 · LVS eşleşiyor · Anten 0 · Magic DRC'de 7.658 açık bulgu (§10.4-b) |
| Zamanlama | Setup **9/9** · Hold **9/9** @ **43,2 MHz** |
| Fonksiyonel | FPGA'da **156/156** altın referans uyumu |

---

## 2. Sistem mimarisi — 2 slayt (2 dk)

### 2.1 Blok diyagram (çizilecek)

```
                    ┌─────────────────────────────┐
   JTAG ────────────┤  jtag_debug (hata ayıklama) │
                    └──────────────┬──────────────┘
                                   │
        ┌──────────────────────────┴──────────────────────────┐
        │              AXI4-Lite Ara Bağlantı                  │
        └─┬────────┬─────────┬────────┬────────┬────────┬─────┘
          │        │         │        │        │        │
    ┌─────┴───┐ ┌──┴───┐ ┌───┴───┐ ┌──┴──┐ ┌───┴──┐ ┌───┴────┐
    │CV32E40P │ │I-RAM │ │ D-RAM │ │ NPU │ │ DMA  │ │ Çevre  │
    │RV32IMC  │ │ 8 kB │ │ 8 kB  │ │+TCM │ │      │ │Birimleri│
    └─────────┘ └──────┘ └───────┘ └──┬──┘ └──────┘ └───┬────┘
                                      │                  │
                                 TCM 30 kB      UART×2, I2C, QSPI,
                                 (15 makro)     GPIO, Timer
```

### 2.2 Bellek haritası

| Bölge | Taban adres | Boyut |
|---|---|---|
| Boot ROM | `0x0000_0000` | 1 kB |
| Buyruk belleği (I-RAM) | `0x0100_0000` | 8 kB |
| Veri belleği (D-RAM) | `0x2000_0000` | 8 kB |
| NPU TCM | `0x2001_0000` | 30 kB |
| GPIO | `0x4000_0000` | — |
| Timer | `0x4001_0000` | — |
| UART-1 (genel) | `0x4002_0000` | — |
| UART-2 (stream) | `0x4003_0000` | — |
| I2C | `0x4004_0000` | — |
| QSPI | `0x4005_0000` | — |
| NPU denetim | `0x4006_0000` | — |
| DMA | `0x4007_0000` | — |
| JTAG | `0x4008_0000` | — |

> **Söyleyin:** "Bellek haritasının ayrık olduğunu, yani hiçbir iki çevre
> biriminin aynı adresi çözmediğini sistem testinde otomatik olarak
> denetliyoruz." Bu, blok testlerinin göremeyeceği bir hatadır.

**Kaynak:** `rtl/Memory/memory_map_pck.sv`

### 2.3 Fiziksel büyüklük

| | Değer |
|---|---:|
| Die alanı | 3.832,40 × 4.249,24 µm |
| Çekirdek alanı | 16.151.800 µm² |
| Toplam hücre örneği | 2.073.891 |
| Bunun dolgu hücresi | 1.823.385 |
| **Gerçek mantık** | **250.506** |
| Yazmaç (flip-flop) | 12.273 |
| SRAM makrosu | 23 |
| Saat tamponu | 2.350 |
| Anten diyotu | 6.380 |
| Toplam tel uzunluğu | 7.355.100 µm (≈ 7,4 m) |

**Kaynak:** `asic/results/metrics/metrics.json`

---

## 3. İşlemci çekirdeği ve doğrulaması — 1 slayt (1,5 dk)

**CV32E40P**, RV32IMC komut kümesi (FPU kapalı), PULP Platform kaynaklı,
açık kaynak.

### Bu bölümün en güçlü noktası: Spike ISS karşılaştırması

Şartname EK-3, çekirdeğin komut izlerinin bir komut kümesi simülatörü
(ISS) ile karşılaştırılmasını bekliyor. Yaptığımız:

| | Değer |
|---|---:|
| Karşılaştırılan buyruk | **927** |
| PC dizisi uyuşmazlığı | **0** |
| Makine kodu uyuşmazlığı | **0** |

Uyarılan komut yolları: RV32I aritmetik/mantık, RV32M çarpma-bölme, RV32C
sıkıştırılmış biçimler, **bölme kenar durumları** (`x/0 = −1`, `x%0 = x`,
`INT_MIN/−1` taşması), kaydırma miktarı maskeleme, gerçek `jal`/`jalr`
çağrıları, iç içe özyineleme, salt okunur CSR erişimi.

> **Bu slaytta anlatılacak hikâye:** İlk raporumuzda "Spike ile %100 uyum"
> yazıyordu ama Spike hiç kurulmamıştı — karşılaştırma kaynak koda elle
> yazılmış 20 elemanlı sabit bir listeye dayanıyordu. Bunu **kendi
> denetimimizde bulduk, raporda açıkça geri çektik** ve gerçek Spike'ı
> kurup koşturduk. Bu, dürüstlüğümüzün somut kanıtıdır.

**Kaynak:** `evidence/spike_20260908/`, `tb/T2.1_core_trace/T2.1_test_report.md`

---

## 4. Çevre birimleri — 3-4 slayt (3 dk)

Her çevre birimi AXI4-Lite üzerinden bağlıdır ve kendi blok testine sahiptir.
Aşağıdaki kapsama değerleri **blok testinde**, modül bazında ölçülmüştür.

### 4.1 UART × 2

| | |
|---|---|
| Adet | 2 (genel amaçlı + akış) |
| Baud | Programlanabilir (`CPB` yazmacı); 115.200 ve 1 Mbps ölçüldü |
| Stop bit | **1 / 1,5 / 2** — üçü de gerçek gönderimle test edildi |
| FIFO | 256 bayt (akış UART'ında) |
| Denetim sayısı | **42** |
| Kapsama | `uart_peripheral` %100 stmt / %92,1 branch · `uart_tx` %98,2 / %94,1 |

> **Anlatılacak:** İki farklı baud hızı aynı anda çalışır — genel UART
> 115.200'de kalırken akış UART'ı 1 Mbps'te 1960 baytlık çıkarım vektörünü
> alır. Bu, şartname EK-2'nin 1 Mbps zorunluluğunu karşılar.

### 4.2 I2C

| | |
|---|---|
| Mod | Master, 7-bit adres, Fast Mode (400 kHz) |
| Yazmaçlar | NBY, ADR, RDR, TDR, CFG |
| Özel davranış | `NBY` 1-4 aralığına kırpılır (0→1, 25→4) — şartname gereği |
| Denetim sayısı | **29** |
| Kapsama | %94,8 stmt / %70,6 branch |

> **Anlatılacak:** Açık drenaj kuralına uyum sistem testinde otomatik
> denetlenir: hat hiçbir koşulda '1' sürülmez, yalnızca aşağı çekilir.
> Yanlış uygulama çok-master veriyolunda kısa devre demektir.

### 4.3 QSPI

| | |
|---|---|
| Arayüz | 1/2/4 hat (SPI, Dual, Quad) |
| Komut | 17 flash komutu; 8 farklı yol test edildi |
| Adresleme | 3 bayt (varsayılan) ve 4 bayt modu |
| Denetim sayısı | **40** |
| Kapsama | %88,7 stmt / %80,2 branch |

> **Anlatılacak:** Uygulama ve NPU ağırlıkları QSPI flash'tan yüklenir —
> SRAM uçucu olduğu için ağırlıkların kalıcı kaynağı flash olmalıdır.

### 4.4 GPIO

| | |
|---|---|
| Pin | 16 |
| Pin modu | Giriş / Çıkış / Açık drenaj-0 / Açık drenaj-1 (dördü de test edildi) |
| Kesme | Yükselen kenar, düşen kenar, seviye-yüksek, seviye-düşük |
| Yazmaçlar | IDR, ODR, MODE, SET, CLEAR, TOGGLE + 5 kesme yazmacı |
| Denetim sayısı | **37** |
| Kapsama | %95,6 stmt / %93,6 branch |

### 4.5 Timer

| | |
|---|---|
| Sayaç | 32-bit, yukarı/aşağı |
| Prescaler | 32-bit programlanabilir |
| Mod | Otomatik yeniden yükleme, olay + kesme |
| Denetim sayısı | **36** |
| Kapsama | %97,1 stmt / %93,0 branch |

### 4.6 DMA

| | |
|---|---|
| İşlev | Sabit kaynak → artan hedef (ve tersi) |
| Kullanım | UART akış FIFO'sundan NPU TCM'ine 490 kelime aktarım |
| Denetim sayısı | **39** |
| Kapsama | %97,9 stmt / %89,7 branch |

> **Anlatılacak:** Çıkarım vektörü CPU'ya hiç uğramaz. UART-2 → FIFO →
> DMA → TCM yolu donanımda tamamlanır; işlemci yalnızca yapılandırmayı
> yazıp `wfi` ile uyur.

### 4.7 JTAG hata ayıklama

| | |
|---|---|
| Komutlar | IDCODE, MEM_READ, MEM_WRITE, DBG_CTRL, BYPASS |
| İşlev | CPU durdur/devam ettir, bellek okuma/yazma, hata yakalama |
| Denetim sayısı | **27** |
| Kapsama | %89,3 stmt / %70,4 branch |

---

## 5. NPU — yapay zekâ hızlandırıcı — 2 slayt (2,5 dk)

### 5.1 Ne yapıyor

TensorFlow Lite Micro "Micro Speech" modelinin donanım gerçeklemesi —
dört anahtar kelime sınıflandırması: **silence, unknown, yes, no**.

Boru hattı:

1. 1960 INT8 girdi → 49×40×1 tensöre adres eşlemesiyle yeniden şekillendirme
2. **DepthwiseConv2D** 10×8, stride 2×2, 8 kanal, SAME dolgu
3. **ReLU** aktivasyon
4. **Fully Connected** — akış hâlinde düzleştirme ve MAC, 4 sınıfa
5. **Softmax** — Q0.12 sabit nokta, iteratif bölücü
6. **Argmax** — sınıf seçimi

### 5.2 Bellek ve arayüz

| | |
|---|---|
| TCM | 30 kB (7.680 kelime × 32 bit), 15 SRAM makrosu |
| TCM yerleşimi | 0–489 girdi tensörü · 3584–7583 **FC ağırlıkları** · 7596–7599 çıkış |
| Arayüz | AXI4-Lite master (TCM erişimi) + slave (denetim yazmaçları) |
| Kesme | Çıkarım bittiğinde IRQ |
| Denetim sayısı | **27** (blok) + 77 (doğruluk) |

### 5.3 Ölçülen sonuçlar

| | Değer |
|---|---:|
| **FPGA'da altın referans uyumu** | **156/156 (%100)** |
| Uyuşmazlık | 0 |
| Donanım vs yazılım model doğruluğu farkı | **0,00 puan** |
| Ölçülen hızlanma | **177×** |
| Çıkarım gecikmesi (medyan) | 8,02 ms |

Uyum matrisi tamamen köşegen: silence 6, unknown 16, yes 50, no 84 —
köşegen dışı hücre yok.

> **Anlatılacak:** Donanımın doğruluğu ile yazılım modelinin doğruluğu
> **birebir aynı** (%72,44). Bu oran veri setinin zorluğudur, tasarımın
> kusuru değildir — önemli olan aradaki farkın sıfır olmasıdır.

> **Söylemeyin:** "%72,44 doğruluk" rakamını başarı olarak sunmayın.
> Doğru çerçeve: "altın referansa %100 sadakat".

**Kaynak:** `fpga/demo_teknofest/sonuclar/`, `evidence/accuracy_extended_20260906/`

---

## 6. Ara bağlantı (bus) — 1 slayt (1 dk)

**AXI4-Lite**, tek master (CPU) + DMA ve NPU master'ları, çoklu slave.

### İki katmanlı protokol doğrulaması

| Katman | Ne denetler | Sonuç |
|---|---|---|
| SVA — 5 × `axil_protocol_checker` | Sinyal/çevrim düzeyi | **0 ihlal** |
| UVM — 2 passive agent | İşlem düzeyi | **401.729 işlem, 0 ihlal** |

**Beş SVA denetleyicisi** bind edilmiştir ve `UVM_AXI` bayrağı olmadan
da her regresyon koşumunda aktiftir: birleşik master yolu, CPU veri
portu (M0), JTAG master (M1), DMA master (M2), NPU motoru.

**İki UVM agent:**

| Agent | Bağlantı noktası | İşlem |
|---|---|---:|
| `env.agent` | NPU motoru → TCM | 162.064 |
| `env.soc_agent` | `merged_m_*` — **tüm SoC trafiği** | 239.665 |

### Şartname §5.2 kapsam kanıtı

> "Çevre birimleri ve YZ hızlandırıcının AXI/AXI-Lite arayüzlerinin en
> azından protocol-check düzeyinde AXI agent'larıyla doğrulanması."

SoC ana yolu agent'ının covergroup'u **13 ayrı bölge bin'i** tutar ve
ölçülen **bölge kapsamı %100,0**'dır — yani Boot ROM, I-RAM, D-RAM,
NPU belleği, **GPIO, Timer, UART1, UART2, I2C, QSPI, NPU CSR, DMA,
JTAG** bölgelerinin **tamamı** gerçek trafikle uyarılmıştır.

Hangi çevre biriminin hangi agent/checker/test tarafından görüldüğü,
ölçülmüş sayılarla: **`verification/AXI_UVM_KAPSAM_MATRISI.md`**

### UVM ajanının denetimleri

- Yanıt kodu geçerliliği (AXI4-Lite'ta EXOKAY olamaz) — **0**
- Askıda kalmış işlem (>10 µs) — **0**
- Yazmada `WSTRB == 0` (hiçbir bayt yazılmaz) — **0**
- Adres 4 bayta hizalı — tümü
- **Kararlılık** (ARM IHI0022 A3.2.1): VALID yükseldikten sonra READY
  gelene kadar düşürülemez, adres/veri/strobe değiştirilemez — **0 ihlal**
- El sıkışan çevrimlerde X/Z bilinmeyen değer — **0**
- Monitör kaçırma çapraz kontrolü: ham sinyal sayımı = monitör sayımı

### Referans bellek modeli (veri doğruluğu)

Protokol doğru ama **veri yanlış yere yazıldı** hatalarını yakalar:
SoC yolunda 3.647 adres izlendi, **1.038 okumada yazılan değer birebir
geri okundu**.

### Fonksiyonel kapsam

| | NPU agent | SoC agent |
|---|---:|---:|
| İşlem türü | %100,0 | %100,0 |
| **Adres bölgesi** | %75,0 | **%100,0** |
| WSTRB deseni | %33,3 | %66,7 |
| Yanıt kodu | %33,3 | %100,0 |

NPU agent'ının düşük kalması bir boşluk değil: gerçek NPU motoru
yalnızca tam-word erişim yapar ve slave her zaman OKAY döner. Pasif
izleme var olmayan trafiği uyaramaz. Bu bin'leri kapatmak için **aktif
test** eklenmiştir (`uvm_aktif`) — sequence'ler kısmi WSTRB ve
SLVERR/DECERR üretir, `strb` kapsamı %100'e çıkar.

> **Anlatılacak:** Şartname EK-3 "tam teşekküllü UVM ortamı
> beklenmemektedir, protokol kontrolü yeterlidir" diyor. Biz protokol
> kontrolünün ötesine geçip işlem düzeyi scoreboard, referans bellek
> modeli ve fonksiyonel kapsam ekledik; ayrıca aktif sequence altyapısı
> yazıp regresyona bağladık.

**Kaynak:** `tb/uvm/axil_uvm_pkg.sv` ·
`verification/AXI_UVM_KAPSAM_MATRISI.md`

---

## 7. Bellek alt sistemi — 1 slayt (1 dk)

| Bellek | Boyut | Gerçekleme |
|---|---|---|
| Boot ROM | 1 kB | Sentezlenen ROM |
| I-RAM | 8 kB | 4 SRAM makrosu |
| D-RAM | 8 kB | 4 SRAM makrosu |
| NPU TCM | 30 kB | 15 SRAM makrosu |
| **Toplam SRAM** | **46 kB** | **23 makro** |

Makro: `sky130_sram_2kbyte_1rw1r_32x512_8` (2 kB, çift portlu)

> **Anlatılacak:** ASIC'te gerçek SRAM makroları, FPGA'da çıkarımsal BRAM
> kullanılır. Bu ayrım `USE_SRAM_MACRO` ön işlemci tanımıyla yönetilir —
> aynı RTL iki hedefte de doğrulanır.

---

## 8. Boot akışı — 1 slayt (1 dk)

```
  Güç / Reset
      │
      ▼
  Boot ROM (0x0000_0000)  ── 168 bayt yükleyici
      │
      ├─► QSPI flash 0x800000'den uygulamayı I-RAM'e kopyala   (8 kB)
      │
      ├─► QSPI flash 0x802000'den FC ağırlıklarını TCM'e kopyala (16 kB)
      │
      ▼
  Uygulamaya atla (0x0100_0000)
      │
      ▼
  Çevre birimi testleri → "Stream ready" → çıkarım döngüsü
```

> **Anlatılacak:** SRAM uçucudur — üretilmiş çipte güç verildiğinde TCM
> boştur. Ağırlıkların kalıcı kaynağı flash olmalıdır; yükleyici bunu
> açılışta TCM'e kopyalar. Bu, gerçek bir silikon gereksinimidir.

**Kaynak:** `sw_nexys/src/bootloader.S`, `sw_nexys/scripts/gen_flash_image.py`

---

## 9. Doğrulama ve testler — 2 slayt (2 dk)

### 9.1 Regresyon

**37 test · 702 denetim · tamamı geçiyor**
*(13 Eylül 2026, HEAD — `python scripts/run_regression.py`)*

| Test | Denetim | Test | Denetim |
|---|---:|---|---:|
| npu_dogruluk | 77 | sartname_gpio | 15 |
| npu_blok | 43 | sartname_uart_stream | 15 |
| uart | 42 | interconnect_adres | 13 |
| qspi | 40 | **uvm_aktif** | **13** |
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

Bütün testler **kendi kendini kontrol eder** (self-checking); hata varsa
koşum başarısız biter. Şartname EK-3 bunu zorunlu tutuyor.

### 9.2 Kod kapsama

Kapsama üç farklı seviyede ölçülür ve **hangi seviyeden bahsedildiği
belirtilmelidir**:

| Seviye | Statement | Branch |
|---|---:|---:|
| Blok testleri (her modül kendi ortamında) | %62–100 | %69–100 |
| **Bizim yazdığımız RTL** (sistem seviyesi) | **%81,6** | **%74,9** |
| Genel rapor (CV32E40P ve paketler dahil) | %62,5 | %44,6 |

> **Bu slaytta anlatılacak:** Genel rakam üç farklı şeyi karıştırıyor —
> bizim RTL'imiz, üçüncü taraf CV32E40P çekirdeği ve **çalıştırılabilir kod
> içermeyen paket dosyaları**. Paketler yalnızca tip/sabit tanımı içerir;
> kapsama metriği onları %0 sayarak ortalamayı haksız yere düşürür.
> Ayrıştırma `scripts/kapsam_analiz.py` ile tekrar üretilebilir.

### 9.3 Doğrulama katmanları

| Katman | Yöntem | Sonuç |
|---|---|---|
| Blok | 19 testbench (çevre birimi + sınır durum) | 702 denetimin çoğu |
| Sistem | Tam SoC, gerçek boot zinciri | 40 denetim (2 test) |
| Protokol | 5 × SVA + 2 UVM passive agent | 401.729 işlem |
| Komut kümesi | **Spike ISS** karşılaştırması | 927 buyruk, 0 uyuşmazlık |
| Uçtan uca | FPGA + resmi demo aracı | 156/156 |

**Simülatör:** Vivado xsim 2025.2 (`xvlog`/`xelab`/`xsim`). DSim
kullanılmamıştır.

---

## 10. ASIC akışı ve fiziksel sonuçlar — 2 slayt (2,5 dk)

### 10.1 Akış

| | |
|---|---|
| Araç | LibreLane 3.0.6 Classic |
| PDK | SKY130A, `sky130_fd_sc_hd` |
| PDK sürümü | `8afc8346a57fe1ab7934ba5a6056ea8b43078e71` |
| Ortam | Nix (`flake.nix` + `flake.lock` ile sabitlenmiş) |

> **Önemli — sorulursa:** Akışa **eklenmiş özel bir adım, harici Tcl betiği
> veya elle düzenleme yoktur.** Zamanlama kapanışı yalnızca akışın kendi
> yapılandırma değişkenleriyle sağlanmıştır. Hiçbir zorunlu adım devre dışı
> bırakılmadı; PDK, kütüphane, SRAM modelleri ve kısıtlar değiştirilmedi.
> Bu beyan `asic/README.md` 12.2'de yazılıdır.

### 10.2 İmzalama sonuçları

| Kontrol | Sonuç |
|---|---|
| Yönlendirme (detailed-route) DRC | **0** |
| KLayout DRC | **0** |
| Magic DRC | **7.658** — tamamı `nwell.4`, makro kaynaklı (§10.4-b) |
| Anten ihlali (net / pin) | **0 / 0** |
| LVS — LEF/DEF kaynaklı | **Circuits match uniquely** |
| LVS — GDS kaynaklı | **Circuits match uniquely** |
| XOR | **0** |
| Güç şebekesi (PDN) ihlali | **0** |
| **Setup @ 23,148 ns (43,2 MHz)** | **9/9 köşe pozitif, 0 ihlal** (worst +0,2782 ns) |
| **Hold** | **9/9 köşe pozitif, 0 ihlal** (worst +0,0380 ns) |

Dokuz köşe: nom/min/max (RC) × TT(25 °C, 1,80 V) / SS(100 °C, 1,60 V) /
FF(−40 °C, 1,95 V)

### 10.3 Güç

| | Değer |
|---|---:|
| Toplam | **105,7 mW** |
| İç (internal) | 90,6 mW |
| Anahtarlama | 14,6 mW |
| Sızıntı | 0,42 mW |
| En kötü IR düşümü | **5,13 mV** (VPWR; 1,80 V'un ~%0,28'i) |
| PDN ihlali | 0 |

> **Bu değerler TAHMİNÎdir ve slaytta öyle söylenmelidir.** Açık
> switching-activity girdisi (VCD/SAIF) yoktur; `VSRC_LOC_FILES`
> kullanılmamıştır. Doğru ifade: *"LibreLane varsayılan switching-activity
> kabulü altında tahminî toplam güç yaklaşık 105,7 mW."*
> **"Ölçüldü" demeyin.** Kaynak: `results/metrics/metrics.json`
> (`power__total = 0,10566 W`).

### 10.4 Dürüstlükle sunulacak açık kalemler

Bunları **kendiniz söyleyin**, jüri sormadan. Gizlemeye çalışmak çok daha
kötü görünür ve bizim en güçlü yanımız şeffaflığımızdır.

**a) Slew / kapasite / fanout ihlalleri — 16.030 / 1.952 / 81**

Söylenecek: "Bu ihlaller açıktır ve kapatılamamıştır. İki farklı yaklaşım
denedik — geçiş eşiğini kütüphane sınırına çekmek ve DRV onarım marjlarını
artırmak. Her ikisi de ölçümle tasarımı **kötüleştirdi**: ortalama slew
1,10 ns'den 1,95 ns'ye çıktı ve hold 9/9 temizliği kayboldu. Bu yüzden
özgün koşuyu koruduk. Denemelerin sayısal sonuçları teslimde belgelidir."

**b) Buyruk getirme adres çözücüsünde hata yolu yok**

Söylenecek: "Dış incelemede bulundu ve **biz de doğruladık**. Buyruk
tarafı iki yollu: üst bayt `0x00` ise Boot ROM, diğer her adres I-RAM.
Geçersiz adres için DECERR yolu yok; kaçak bir PC I-RAM içinde alias
oluyor. Normal akış Boot ROM → I-RAM olduğu için testler görmüyor,
şartname kriterlerini de ihlal etmiyor — ama gerçek bir sağlamlık
açığı. Düzeltmesi üç yollu çözücü.

Bu teslimde **bilerek düzeltmedik**: `soc_top.sv` değişirse teslim
edilen GDS ile kaynak arasındaki SHA-256 kanıt zinciri kopar ve 5,5
saatlik fiziksel akışın tamamı yenilenmeli. Sessizce değiştirmek
yerine `asic/README` §9'da bilinen sınırlama olarak beyan ettik."

**c) Magic DRC — 7.658 bulgu**

Söylenecek: "Kök nedeni tespit ettik: LEF/DEF soyut görünümündeki tap
geometrisi `nsubdiff` katmanını içermiyor ve Magic bunu `nwell.4` ihlali
sayıyor. Ayrı küçük hücre deneylerinde gerçek tap GDS temiz çıkıyor, aynı
tapın MAGLEF görünümü ihlalli. KLayout aynı GDS'te 0 veriyor. Ancak bunu
'çözülmüş' saymıyoruz — tek bir aracın temiz sonucu diğerinin kural
kapsamını doğrulamaz."

**d) İki ayrı SDC: PnR 14 ns, signoff 23,148 ns**

Söylenecek: "İki farklı kısıt dosyası kullanıyoruz ve bu bilinçli bir
tercih. PnR'a 14 ns veriyoruz — optimizasyonu zorlamak için. İmzalama
ise 23,148 ns'de yapılıyor ve beyan ettiğimiz çalışma noktası bu:
**43,2 MHz**. Dokuz PVT köşesinin tamamında setup ve hold pozitif,
TNS sıfır. Bu ek bir analiz değil, akışın kendi imza adımının
(`OpenROAD.STAPostPNR`) çıkarılmış SPEF ile ürettiği sonuç."

43,2 MHz'in seçilme nedeni sorulursa: 43.200.000 / 400.000 = 108, yani
I2C SCL bölücüsü tam sayı çıkıyor ve EK-2'nin "SCL 400 kHz sabit"
isteri **tam** karşılanıyor.

> `constraints/design.sdc` içinde görülen `20.0` sayısı kullanılan değer
> değildir; yalnızca `CLOCK_PERIOD` ortam değişkeni tanımsızsa devreye
> giren yedek satırdır. Üretilen `results/sdc/pnr_resolved.sdc`
> `-period 14.0000` yazar. Ayrıntı: `asic/README.md` §6.

---

## 11. FPGA demosu — 1 slayt (1,5 dk)

| | |
|---|---|
| Kart | Nexys A7-100T (XC7A100T) |
| Saat | 50 MHz |
| Bitstream zamanlaması | Demo A: WNS **+1,207** / WHS **+0,033** ns · Demo C: **+1,270** / **+0,023** ns · TNS ve THS sıfır |
| Arayüz | Core UART (kart üstü USB) + Stream UART (Pmod JB, harici 3,3 V modül) |

### Resmi demo aracıyla ölçülen sonuç

Bitstream **14 Eylül 2026'da güncel RTL'den yeniden üretilmiştir** — ASIC
teslimiyle aynı kaynaktan. Aynı bitstream'le iki koşum alındı; fark
yalnızca firmware'in UART'a ne yazdırdığıdır.

| Metrik | Normal firmware | Skor yazdıran firmware |
|---|---:|---:|
| Gönderilen örnek | 156 | 156 |
| **Altın referans uyumu** | **%100,00** | **%100,00** |
| Uyuşmazlık | **0** | **0** |
| Zaman aşımı | **0** | **0** |
| Gecikme (medyan) | **8,02 ms** | 23,96 ms |
| **Ölçülen hızlanma** | **177×** | 59× |
| Skor karşılaştırması | — | **156 örnek** |
| **Skor hatası (MAE)** | — | **%0,078** |
| Sağlamlık | 9 PASS / 1 FAIL / 1 SKIP | 9 PASS / 1 FAIL / 1 SKIP |

Ham çıktılar: `evidence/fpga_demo_20260914_normal/` ve
`evidence/fpga_demo_20260914_skorlu/` · açıklama:
`evidence/FPGA_DEMO_A_IKI_KOSUM.md`

> **Söylenecek:** "Hızlanma **177×**. Ayrıca nicemlemenin doğruluğunu da
> ölçtük: donanımın ürettiği dört olasılık altın referans modelle
> ortalama **%0,078** hatayla eşleşiyor. Bu ölçüm için dört skoru
> UART'tan yazdırmak gerekti; o da ISR'yi uzattığı için aynı koşumda
> gecikme 24 ms'ye çıktı. İkisini ayrı koşumlarda aldık, ikisini de
> teslim ettik — ölçülen gecikme farkı UART yazdırma süresidir, NPU
> çıkarım süresi değil."

### Kart üzerinde tam SoC testi (kendi doğrulama firmware'imiz)

Demo aracı sınıflandırma doğruluğunu ölçer. Ayrıca **SoC'un tamamını**
kart üzerinde sınayan kendi test firmware'imiz vardır
(`fpga/DEMO_C_I2C/run_jury.py`, 14 Eylül 2026):

| | |
|---|---:|
| Sonuç | **GEÇTİ** (`passed: true`) |
| Öztest | **2 × 86 kontrol** |
| NPU çıkarımı | **21** (7 vektör × 3 tur), referansla 0 uyuşmazlık |
| Kullanıcı arayüzü | **PASS** — 16 anahtar, yükselen/düşen kenar IRQ, 4 LED deseni |
| **I2C harici cihaz** | **ESP32 slave ile gerçek yaz-oku, 3/3 doğru** |

Kapsanan zincir: Flash → CPU açılışı → CPU aritmetik/mantık/çarpma-bölme
ve uç durumlar → D-RAM → NPU TCM (15 banka) → GPIO → Timer (3 kesme) →
DMA (banka sınırı, koruma kelimeleri) → Bus fault → **I2C (harici ESP32
slave)** → UART2 tüm bayt değerleri → NPU uçtan uca (UART2 → DMA →
çıkarım → ISR).

Dört sınıfın (SILENCE/UNKNOWN/YES/NO) tamamı kapsandı; üç turun hepsinde
aynı sınıf üretildi. Elle kontroller **atlanmadı**.

Ham çıktı: `evidence/fpga_democ_20260914/`.

> **I2C hakkında söylenecek:** "Önceki sürümde I2C yalnızca 'master
> işlemi başlattı, TX_DONE kuruldu' seviyesindeydi — karşı tarafta cihaz
> yoktu. Bunu kendi raporumuzda eksik olarak yazmıştık. Şimdi ESP32'yi
> I2C slave yapıp kapattık: kart bir bayt yazıyor, ESP32 tersini
> döndürüyor, kart geri okuyup doğruluyor. Üç değerde de tuttu. I2C
> kontrolcüsü ACK bitini yazılıma açmıyor, ama NACK'te veri hiç gelmez —
> dolayısıyla doğru verinin geri okunması ACK'in kesin kanıtıdır."

> Kapsam dışı kalanlar raporda açıkça listelidir: I2C flash
> programlama/silme ve çoklu-slave hakemliği, QSPI flash yazma/silme,
> JTAG halt/resume, CPU tam ISA.

> **Dürüstlükle söylenecek:** Başarısız tek senaryo `back_to_back` —
> aralıksız beş çerçevenin dördüne yanıt geldi. **İki koşumda da birebir
> aynı sonuç**, yani rastgele bir kararsızlık değil, deterministik ve kök
> nedeni bilinen bir sınır.
>
> Kök nedeni tek satıra indirdik: `rtl/Cevre_Birimleri/files_1/uart_stream_peripheral.sv`
> içindeki toplayıcı sayacı `pack_cnt_r`, yalnızca reset ve tam kelime
> okumasıyla sıfırlanıyor; `UARTS_FIFO_CLR` komutuyla sıfırlanmıyor. Bir
> önceki senaryodan devreden yarım kelime kalıntısı sonraki çerçeveyi
> kaydırıyor. Kanıt: senaryo **tek başına koşulduğunda üç bağımsız
> tekrarda 5/5 geçiyor**.
>
> Düzeltmesi hazır, ancak ASIC teslimi yamasız RTL'e SHA-256 ile bağlı
> olduğu için bu teslime **bilerek** dahil edilmedi — dahil edilseydi
> teslim edilen GDS'nin kaynak hash'i tutmazdı.

---

## 12. Kapanış — 1 slayt (30 sn)

Üç cümlelik kapanış:

> Fiziksel tasarımı tamamlanmış, detailed-route ve KLayout DRC'sinden
> temiz geçen, LVS'i eşleşen, dokuz PVT
> köşesinde setup ve hold kapanışı sağlanmış bir SoC teslim ediyoruz.
>
> Yapay zekâ hızlandırıcısı FPGA üzerinde resmi demo aracıyla 156 vektörde
> altın referansa %100 sadakat gösterdi.
>
> Açık kalan kalemlerimizi gizlemedik; her birinin kök nedenini ölçtük ve
> raporladık.

---

## Ek: Jüri sorabilir — hazır cevaplar

**"Neden 50 MHz değil?"**
PnR hedefi 14 ns, imzalama 23,148 ns. Dokuz köşenin tamamında setup ve
hold pozitif (43,2 MHz). Frekans yarışmanın puanlama ölçütü değil;
biz temiz kapanışı tercih ettik.

**"Slew ihlallerini neden kapatmadınız?"**
İki yaklaşım denedik, ikisi de ölçümle tasarımı kötüleştirdi. Sayısal
sonuçlar teslimde. Zorlamak yerine özgün koşuyu korumayı seçtik çünkü hold
9/9 temizliği daha değerliydi.

**"UVM ortamınız neden passive?"**
Şartname EK-3 tam teşekküllü UVM ortamı beklemediğini, protokol kontrolünün
yeterli olduğunu söylüyor. Tasarım zaten gerçek trafikle (CPU, DMA, NPU)
sürülüyor ve self-checking sistem testleriyle doğrulanıyor. Sürücü eklemek
mevcut testleri tekrarlamak olurdu. Bunun yerine işlem düzeyi scoreboard ve
fonksiyonel kapsam ekledik.

**"Kapsama neden %62?"**
O rakam üçüncü taraf CV32E40P çekirdeğini ve çalıştırılabilir kod içermeyen
paket dosyalarını da sayıyor. Bizim yazdığımız RTL %81,6 statement / %74,9
branch; blok testlerinde modüller %89–100 arasında. Ayrıştırma betiği
teslimde.

**"Testler gerçekten kendi kendini kontrol ediyor mu?"**
Evet. Her testbench bir `check`/`denetle` görevi kullanır, hata sayacı tutar
ve sıfırdan farklıysa `$fatal` ile koşumu düşürür. Regresyon betiği bu
sonuçları toplar. Manuel göz denetimi gerektiren hiçbir test yoktur.

**"Ağırlıklar nereden geliyor?"**
QSPI flash'tan. SRAM uçucu olduğu için üretilmiş çipte TCM güç verildiğinde
boştur; yükleyici açılışta flash'tan 16 kB ağırlığı TCM'e kopyalar.

---

## Ek: Slayt sayısı ve süre özeti

| Bölüm | Slayt | Süre |
|---|---:|---:|
| 1. Kapak | 1 | 0:30 |
| 2. Sistem mimarisi | 2 | 2:00 |
| 3. İşlemci + Spike | 1 | 1:30 |
| 4. Çevre birimleri | 4 | 3:00 |
| 5. NPU | 2 | 2:30 |
| 6. Bus | 1 | 1:00 |
| 7. Bellek | 1 | 1:00 |
| 8. Boot | 1 | 1:00 |
| 9. Doğrulama | 2 | 2:00 |
| 10. ASIC akışı | 2 | 2:30 |
| 11. FPGA demosu | 1 | 1:30 |
| 12. Kapanış | 1 | 0:30 |
| **Toplam** | **19** | **~19 dk** |

15 dakikaya sığdırmak için: 6, 7 ve 8. bölümleri tek slayta birleştirin
(bus + bellek + boot), 4. bölümü ikiye indirin.
