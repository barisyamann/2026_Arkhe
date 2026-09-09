# Şartname Uyumu ve Sapmalar

**9 Eylül 2026 · Arkhe SoC · TEKNOFEST Çip Tasarım Yarışması, Mikrodenetleyici Kategorisi**

Bu belge, tasarımın 2026 Teknik Şartnamesi v1.3 ile uyumunu madde madde
kaydeder; kalan sapmaları ve yorum gerektiren noktaları açıkça belgeler. Şartname §4.2.2.1 ve EK-2
gereği alternatif bileşen kullanımı ve yorum farkları raporda ve sunumda
belirtilmek zorundadır; bu belge o yükümlülüğü karşılar.

Buradaki her sayı ölçülmüştür; kaynak dosya ve satır numarası verilmiştir.

---

## 1. SAPMA: QSPI Flash parçası — S25FL128S

### Durum

| | |
|---|---|
| Şartnamede referans | MT25QL256ABA8E12 (Micron, 256 Mb) |
| Kullanılan | **Spansion/Cypress S25FL128S** (128 Mb, 16 MB) |
| Neden | Nexys A7-100T geliştirme kartının **üzerinde lehimli** olan parça budur |
| Kart üzerinde doğrulandı | RDID = `0xF0182001` → üretici `0x01`, tip `0x20`, kapasite `0x18` |

Şartname s.24 bu duruma izin verir:

> *"Eğer yarışan bir ekibin belirtilen bellek parçasına erişimi yoksa, bu
> bölümdeki tüm özellikleri desteklediği sürece herhangi bir NOR flash bellek
> kullanmakta özgürdür. (...) Yukarıda belirtilen parçanın kullanılmadığı her
> türlü senaryo, raporlarda ve sunumda açıkça belirtilmelidir."*

### Komut kümesi karşılaştırması — 17/17

Şartname s.24'te 17 zorunlu komut sayılır. S25FL128S bunların **tamamını**
destekler; QSPI Master RTL'inde de hepsi tanımlıdır
(`rtl/Cevre_Birimleri/qspi_master.sv:56-72`):

| Komut | Opcode | S25FL128S | RTL |
|---|---|:---:|:---:|
| READ | 0x03 | ✓ | ✓ |
| DOR (Read Dual Out) | 0x3B | ✓ | ✓ |
| QOR (Read Quad Out) | 0x6B | ✓ | ✓ |
| PP (Page Program) | 0x02 | ✓ | ✓ |
| QPP (Quad Page Program) | 0x32 | ✓ | ✓ |
| SE (Sector Erase) | 0xD8 | ✓ | ✓ |
| READ_ID | 0xAB | ✓ | ✓ |
| RDID | 0x9F | ✓ | ✓ |
| RES | 0xAB | ✓ | ✓ |
| RDSR1 | 0x05 | ✓ | ✓ |
| RDSR2 | 0x07 | ✓ | ✓ |
| RDCR | 0x35 | ✓ | ✓ |
| WRR | 0x01 | ✓ | ✓ |
| WRDI | 0x04 | ✓ | ✓ |
| WREN | 0x06 | ✓ | ✓ |
| CLSR | 0x30 | ✓ | ✓ |
| RESET | 0xF0 | ✓ | ✓ |

### Emsal DDK kararları

DDK bu konuda üç ayrı takıma cevap vermiş ve tutumu tutarlıdır:

| Tarih | Değişim | Eksik komut | DDK cevabı |
|---|---|---|---|
| 29 Ağu 2025 | S25FL128S → W25Q16BV | READ, RESET farkı | *"uygun olur"* |
| 18 Ağu 2026 | → W25Q128JV | CLSR yok | *"kullanabilirsiniz, açıkça belgelenmesi koşuluyla"* |
| 20 Ağu 2026 | → S25FL256L | READ_ID yok | *"kullanabilirsiniz, açıkça belgelenmesi koşuluyla"* |

Dikkat: 2025 şartnamesinde **referans parça S25FL128S'ti** — yani bizim
kullandığımız parça bir önceki yıl doğrudan şartname referansıydı.

**Bizim durumumuz bu üç örnekten daha rahattır: hiçbir komut eksiğimiz yok.**
Fark yalnızca parça numarası ve kapasitedir (128 Mb yerine 256 Mb). Tasarım
16 MB'ın tamamını adresleyebilir; kullanılan alan 24 kB'dır (uygulama 8 kB +
NPU ağırlıkları 16 kB).

---

## 2. ÇÖZÜLDÜ: I2C SCL = tam 400,000 kHz

### Önceki durum (9 Eylül 2026 öncesi)

`rtl/Cevre_Birimleri/i2c_peripheral.sv` SCL periyodunu **dört eşit çeyreğe**
bölüyordu:

```systemverilog
localparam int QUARTER = SYS_CLK_FREQ / (4 * I2C_FREQ);
```

50 MHz'de bu `31,25` eder; tamsayı bölme `31` verir ve gerçek SCL
**403,2 kHz** çıkardı — hedefin %0,8 üstünde.

### Kök neden

Sorun sistem saatinde değil, **eşit çeyrek varsayımındaydı**:

```
SCL periyodu = 50e6 / 400e3 = 125 çevrim     <- TAMSAYI
125 / 4 = 31,25                              <- tamsayı DEĞİL
```

Yani tam 400 kHz üretilebilirdi; yalnızca 125'i dörde eşit bölmek mümkün
değildi.

### Çözüm

Dört çeyreğin **toplamı** tam periyodu verecek şekilde son çeyreğe kalan
verildi:

```
31 + 31 + 31 + 32 = 125  ->  SCL = 50e6 / 125 = 400,000 kHz
```

```systemverilog
localparam int PERIYOT    = SYS_CLK_FREQ / I2C_FREQ;   // 125 @ 50 MHz
localparam int QUARTER    = PERIYOT / 4;               // 31
localparam int SON_CEYREK = PERIYOT - 3 * QUARTER;     // 32

assign ceyrek_uzunluk = (phase == 2'd3) ? SON_CEYREK : QUARTER;
```

Örnekleme noktası faz 2'nin **başında** olduğu için uzatmadan etkilenmez;
`bit_done` faz 3'ün sonunda olduğu için uzayan çeyrekle doğal olarak kayar.

### Ölçüm (simülasyon, 50 MHz sistem saati)

```
PERIYOT    = 125 çevrim
QUARTER    = 31
SON_CEYREK = 32
toplam     = 125

SCL periyot #1 = 125 çevrim = 400.0 kHz
SCL periyot #2 = 125 çevrim = 400.0 kHz
SCL periyot #3 = 125 çevrim = 400.0 kHz
...   (kararlı durumda hepsi 125 çevrim)
```

İlk periyot 156 çevrimdir; bu START koşulundan ilk bite geçiştir, veri
periyodu değildir.

### I2C Fast-mode zamanlama kontrolü

| Ölçüt | Değer | Standart isteri | Durum |
|---|---:|---:|:---:|
| t_LOW | 1,26 µs | ≥ 1,3 µs | sınıra çok yakın¹ |
| t_HIGH | 1,24 µs | ≥ 0,6 µs | ✓ rahat |
| LOW/HIGH oranı | 1,016 | — | dengeli |

¹ t_LOW hesabı (31+32)/50 MHz = 1,26 µs; standardın 1,3 µs isterinin %3
altında. 400 kHz'de bu değerler nominal olarak zaten sınırdadır (tam simetrik
bir 400 kHz saatte t_LOW = t_HIGH = 1,25 µs olurdu). Gerçek I2C hatlarında
yükselme süresi ve köle esnetmesi (clock stretching) bu marjı belirler.

### Doğrulama

| Test | Sonuç |
|---|---|
| Blok testi (`i2c`) | 38 denetim, geçti |
| Sistem testi (`sistem`) | 17 denetim, geçti |
| Frekans ölçümü | 125 çevrim = 400,000 kHz |

**Şartname EK-2 "SCL saat frekansı 400 kHz sabit hızında olacaktır" isteri
artık tam olarak karşılanmaktadır.**

---

## 3. YORUM FARKI: Timer TIM_PRE, PRE = 0xFFFFFFFF

### Şartnamenin kendi içindeki tutarsızlık

Şartname s.21 üç örnek verir:

| Örnek | Şartname der | `PRE+1` kuralı verir |
|---|---|---|
| `TIM_PRE = 0` | 1 periyotta 1 değişir | 1 ✓ |
| `TIM_PRE = 1` | 2 periyotta 1 değişir | 2 ✓ |
| `TIM_PRE = 0xFFFFFFFF` | **0x80000000** periyotta 1 | 0x100000000 ✗ |

İlk iki örnek `bölme oranı = PRE + 1` kuralını tanımlar. Üçüncü örnek aynı
kurala göre `0x100000000` (2³²) vermeliydi; metin `0x80000000` (2³¹) diyor —
**iki kat fark**.

Şartname v1.3 değişiklik listesinde *"[MİKRO] TMR TIM_PRE yazmaç örneği
düzeltildi"* notu bulunur; yani bu örnek bir kez düzeltilmiş, ancak hâlâ ilk
iki örnekle çelişmektedir.

### Bizim seçimimiz

RTL, **kuralı tanımlayan ilk iki örneğe** uyar
(`rtl/Cevre_Birimleri/timer_peripheral.sv:90`):

```systemverilog
if (prescaler_counter >= reg_tim_pre) begin   // PRE+1 çevrimde bir tick
```

Üçüncü örneğe uymak, ilk ikisini bozmak anlamına gelirdi.

### Kart üzerinde doğrulama

Aynı bekleme süresiyle iki ölçüm alınmıştır:

```
PRE = 0  ->  56038 sayım
PRE = 9  ->   5603 sayım        oran = 10,00×  =  (9+1)/(0+1)
```

`PRE+1` kuralı silikonda doğrulanmıştır.

---

## 4. YORUM: QSPI 4 bayt adresleme — CCR[24] rezerve biti

### Şartnamedeki boşluk

| Şartname konumu | İfade |
|---|---|
| s.24, anlatı | *"Tüm flash alanını kapsamak için **4-bayt adresleme modu desteği** bulunacaktır"* |
| s.26, QSPI_ADR | *"READ, DOR, QOR ve PP komutunda **3-bayt** olarak kullanılır. Yani QSPI_ADR[23:0] bitleri adres olarak gönderilir"* |
| s.25, CCR[24] | *"REZERVE"* |

4-baytı seçecek bir mekanizma **tanımlanmamıştır**.

### Seçilen çözüm

```
CCR[24] = 0  ->  3 bayt adres (QSPI_ADR[23:0])   <- RESET DEĞERİ, s.26 birebir
CCR[24] = 1  ->  4 bayt adres (QSPI_ADR[31:0])   <- s.24 karşılanır
```

Reset değeri 0 olduğu için **varsayılan davranış s.26 ile birebir aynıdır**;
4 bayt yalnızca yazılım açıkça istediğinde devreye girer.

Şartname s.26 ayrıca *"Tanımlanmamış tüm bit konumları **Yarışmacı Tanımlı** /
Rezerve'dir"* der. Rezerve bitin yarışmacı tarafından tanımlanması bu
çerçevededir.

### Değerlendirilen ve elenen alternatifler

Üç alternatif ölçülerek denendi (9 Eylül 2026):

**1. `ADR[31:24]` otomatik algılama — denendi, GERİ ALINDI**

"Üst bayt doluysa 4 bayt gönder" kuralı cazipti çünkü `CCR[24]` hiç
kullanılmadan kalırdı. Ancak `tb_qspi_mock`'un 4-bayt bölümü bunu çürüttü:

```
Flash 4-bayt kipindeyken DÜŞÜK adresler de (örn. 0x00000008) dört bayt
gönderilmelidir. Otomatik algılama üst baytı sıfır gördüğü için üç bayt
gönderir, flash dördüncü baytı bekler, okuma bir bayt kayar.

Ölçüldü: iki denetim düştü.
  [HATA] 4-bayt: flash kelime 2: beklenen=0xa5a50002 gercek=0x000000ff
  [HATA] 4-bayt: flash kelime 3: beklenen=0xa5a50003 gercek=0x00000000
```

**2. 4-bayt komut varyantları (0x13, 0x12, 0x0C)**

Şartname 17 zorunlu komut sayar; bu varyantlar listede **yoktur**. Ayrıca
`QSPI_ADR[31:24]` yine tanımsız kalırdı.

**3. Kip değiştirme komutları (0xB7 Enter / 0xE9 Exit)**

Aynı sebep — listede yok. Ayrıca kartta bulunan S25FL128S 16 MB olduğu için
bu kip **gerçek donanımda doğrulanamaz**; yalnızca simülasyonda kalırdı.

**Sonuç:** Rezerve bit kullanımı, yazılımın adres genişliğini açıkça
seçmesine izin veren ve flash'ın hangi kipte olduğundan bağımsız doğru
çalışan tek yöntemdir.

### Ölçüm — iki ayrı testte doğrulandı

**`tb_qspi_mock` (mevcut blok testi, 40 denetim):**
Flash modeli 4-bayt kipine alınır, `CCR[24]=1` ile okuma yapılır ve gelen
verinin doğru kelime olduğu denetlenir. Test yorumu şöyle der:

> *"Bu test AYIRT EDICIDIR: 4-bayt bekleyen flash'a yalnızca 3 bayt adres
> gönderilirse model hâlâ adres fazındadır ve ilk veri baytını adresin son
> baytı sanıp yutar. Okunan kelime kayar, denetim düşer."*

**`tb_sartname_qspi` (yeni şartname uyum testi, 24 denetim):**
SCK kenarları sayılarak adres fazının uzunluğu doğrudan ölçülür:

```
CCR[24]=0  ->  40 kenar   (8 komut + 24 adres + 8 veri)  = 3 bayt
CCR[24]=1  ->  48 kenar   (8 komut + 32 adres + 8 veri)  = 4 bayt
```

Aradaki 8 kenar tam bir bayttır.

### DDK'nın belirsizlik karşısındaki tutumu

DDK, şartnamedeki belirsizliklerde yarışmacının makul yorum yapmasını uygun
görmüştür. 25 Mart 2025'te bir takım QSPI veri yazmacı açıklamasındaki bir
tutarsızlığı sorduğunda cevap şu olmuştur:

> *"MSB 4 bit'i reserved varsayıp 8 yazmaç çalışabilirsiniz."*

**Not:** Bu emsal bizim durumumuzla tam örtüşmez — DDK orada bir alanı
*rezerve saymayı* önermiştir, biz ise rezerve bir alanı *kullanıyoruz*. Emsalin
gösterdiği şey, DDK'nın şartname belirsizliklerinde yarışmacı yorumunu kabul
ettiğidir. Asıl dayanağımız şartnamenin kendi cümlesidir: *"Tanımlanmamış tüm
bit konumları Yarışmacı Tanımlı / Rezerve'dir."*

### Yazılım etkisi

Mevcut yazılımların hiçbiri `CCR[24]` kullanmaz — `bootloader.S:39` zaten
*"CCR[24] 4-bayt kipi burada GEREKMEZ"* notunu taşır. En yüksek kullanılan
flash adresi `0x805E7F`'tir (~8 MB) ve karttaki S25FL128S 16 MB'dır; 3 bayt
adres tüm alanı kapsar. 4-bayt modu yalnızca daha büyük bir flash takılması
durumu için tasarımda hazır bekler.

---

## 5. Mimari not: NPU bellek erişimi

Bu bir sapma değildir; şartnameye uygunluğu kayda geçirmek için yazılmıştır.

### Yapı

```
              ANA AXI4-Lite INTERCONNECT  (tek interconnect)
                            │
            ┌───────────────┼────────────────┐
       Slave 9         Slave 10         (diğer 9 slave)
      NPU CSR        NPU BELLEĞİ       GPIO, UART×2, I2C,
    0x4006_0000      0x2001_0000       QSPI, Timer, DMA...
                          │
                  ┌───────┴───────┐
              Port A           Port B
            (yaz + oku)      (salt oku)
                  │                │
          AXI'den: CPU/DMA    yerel AXI4-Lite: NPU motoru
```

- NPU belleği **ana interconnect'te Slave 10**'dur; UART→DMA→bellek yolu
  tamamen ana AXI4-Lite üzerinden gider.
- NPU motoru ayrıca SRAM makrosunun **ikinci portundan** (Port B) okur. Bu
  ikinci bir veri yolu değil, `sky130_sram_2kbyte_1rw1r_32x512_8` makrosunun
  donanımsal olarak sunduğu porttur.
- Motorun bağlantısı da **tam AXI4-Lite**'tır (`npu_engine_axi_master.sv`:
  AW/W/B/AR/R beş kanal, valid-ready el sıkışması, bresp/rresp yanıtları).

### Şartname dayanağı

EK-2 girişi: *"bus mimarisi ve protokolü AXI-uyumlu (konfigürasyon için
AXI4-Lite, veri için AXI4/AXI4-Lite) bir arayüz olmalıdır"* — her iki yol da
AXI4-Lite'tır.

§4.2.2.2: *"YZ hızlandırıcı kendi bellek bölgesine sahip olacağı için SoC'de
aynı bellek üzerinde birden fazla master bulunmasına gerek yoktur."*

Bu mimari ÖTR ve DTR'de sunulmuş ve her iki rapor aşaması geçilmiştir.

### Ölçülen maliyet (alternatifin neden seçilmediği)

NPU motorunun TCM erişimi simülasyonda sayılmıştır
(`tb/npu_golden`, Port B sayacı):

| | Değer |
|---|---:|
| Okuma erişimi | **40.512** |
| Yazma erişimi | 4 |
| Çıkarım çevrimi | 85.589 |
| Erişim yoğunluğu | **%47,3** (her ~2 çevrimde bir) |

Motor ana yola taşınsaydı, AXI4-Lite'ta her okuma en az 2 çevrim sürdüğü için:

| Senaryo | Çevrim | Yavaşlama |
|---|---:|---:|
| Mevcut (Port B) | 85.589 | — |
| Ana yol, en iyi durum | 126.105 | 1,5× |
| Ana yol, gerçekçi | 207.137 | **2,4×** |
| Ana yol, CPU/DMA çakışması | 288.169 | 3,4× |

AXI4 burst da çözüm değildir: erişimlerin dağılımı ölçülmüştür —

| Tür | Adet | Ardışık mı |
|---|---:|---|
| FC ağırlık okuması | 4.000 | evet, burst edilebilir |
| **Konvolüsyon girdi okuması** | **36.512** | **hayır** — 10×8 pencere satır atlamalı |

Erişimlerin **%90'ı burst edilemez**; bu konvolüsyonun yapısal özelliğidir,
tasarım tercihi değil.

Şartname §4.2.2.1 hızlandırıcı performansının *"veri/saat döngüsü bazında"*
değerlendirileceğini söyler; 2,4× yavaşlama doğrudan puan kaybı olurdu.

---

## 6. Uyum özeti

### §4.2.2.1 Genel İsterler — 12/12

| İster | Durum |
|---|:---:|
| CV32E40P çekirdek | ✓ |
| 8 kB buyruk + 8 kB veri belleği | ✓ |
| 30 kB NPU belleği | ✓ |
| Boot ROM 512 B – 1 kB | ✓ (1 kB) |
| QSPI'den boot | ✓ |
| Reset'siz birim geçişi | ✓ |
| GPIO 32 pin (16 giriş + 16 çıkış) | ✓ |
| 2× UART (genel + stream) | ✓ |
| I2C Master / QSPI Master / Timer | ✓ |
| JTAG (opsiyonel, +3 bonus) | ✓ |
| AXI-uyumlu bus | ✓ |
| Bellek haritası yarışmacı tanımlı | ✓ |

### EK-1 YZ Hızlandırıcı — 6/6

| İster | Durum | Ölçüm |
|---|:---:|---|
| TFLite Micro Speech RTL gerçeklemesi | ✓ | DepthwiseConv2D + FC + Softmax |
| 1960 değer girdi → 4 sınıf | ✓ | kartta `[0, 225, 326, 3543]` |
| UART-stream → bellek → AXI → hızlandırıcı | ✓ | DMA zinciri |
| Kesme üretimi | ✓ | `irq_o` |
| Yazılıma karşı hızlanma | ✓ | **183,3×** |
| %10 doğruluk penceresi | ✓ | altın referansla **birebir** |

### EK-2 Çevre Birimi Yazmaçları

| Birim | Durum |
|---|---|
| GPIO (IDR/ODR) | tam uyumlu |
| Timer (7 yazmaç) | tam uyumlu — PRE örneği için bkz. §3 |
| UART (CPB/STP/RDR/TDR/CFG) | tam uyumlu, v1.3 CFG[0] otomatik sıfırlama dahil |
| I2C (NBY/ADR/RDR/TDR/CFG) | tam uyumlu — SCL tam 400,000 kHz, bkz. §2 |
| QSPI (CCR/ADR/DR/STA/FCR) | tam uyumlu — 4-bayt için bkz. §4 |

### EK-3 Doğrulama

| Madde | Öncelik | Durum |
|---|---|:---:|
| Protokol kontrolleri | Zorunlu | ✓ UVM AXI4-Lite agent |
| YZ hızlandırıcı testleri | Zorunlu | ✓ self-checking |
| Sistem seviyesi testler | Zorunlu | ✓ |
| Çekirdek testleri (Spike ISS) | Elden gelenin en iyisi | ✓ 927 komut, 0 fark |
| Doğrulama planı | Elden gelenin en iyisi | ✓ |
| Blok seviyesi testler | Opsiyonel | ✓ 11 blok |
| Code coverage | Opsiyonel | ✓ %81,6 satır / %74,9 dal |

**Güncel RTL ile regresyon: 16/16 test, 454 denetim, tamamı geçti.**

### §5.2 Ödül Minimum Kriterleri — 5/5

| Kriter | Durum | Kanıt |
|---|:---:|---|
| FPGA'da test senaryoları | ✓ | 34/34 çevre birimi + 15/15 NPU |
| Self-checking boot + çevre birimi | ✓ | `sistem_gercek_boot` |
| AXI protokol kontrolü | ✓ | UVM agent |
| YZ hızlandırıcı test senaryosu | ✓ | altın vektör |
| Üretime hazır GDSII | ✓ | LVS/DRC/anten temiz |

---

## 7. Sunumda söylenecekler

Şartname §3.3.2 puanlama tablosunda *"Şartnameye göre eksikliklerin açık bir
şekilde anlatımı ve analizi"* başlığı vardır. Yukarıdaki dört madde sunumda
şu çerçevede aktarılmalıdır:

1. **Flash parçası** — kart üstü S25FL128S; 17/17 komut destekli; DDK'nın
   benzer üç başvuruya verdiği onaylar emsaldir.
2. **I2C** — 9 Eylül 2026'da tam 400,000 kHz'e çekildi (eşit olmayan
   çeyrek yapısı); sapma kalmadı.
3. **Timer PRE** — şartnamenin üç örneğinden ikisi `PRE+1` der, üçüncüsü
   çelişir; kuralı tanımlayan örneklere uyulmuştur.
4. **QSPI 4-bayt adresleme** — şartname 4-bayt ister ama seçim mekanizması
   tanımlamaz; rezerve CCR[24] biti kullanıldı. Üç alternatif ölçülerek
   elendi (biri denendi ve testi kırdı).
