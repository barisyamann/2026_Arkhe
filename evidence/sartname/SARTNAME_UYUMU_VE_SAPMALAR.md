# Şartname Uyumu ve Sapmalar

**9 Eylül 2026 · Arkhe SoC · TEKNOFEST Çip Tasarım Yarışması, Mikrodenetleyici Kategorisi**

Bu belge, tasarımın 2026 Teknik Şartnamesi v1.3 ile uyumunu madde madde
kaydeder ve **dört sapmayı** açıkça belgeler. Şartname §4.2.2.1 ve EK-2
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

## 2. SAPMA: I2C SCL = 403,2 kHz

### Ölçüm

`rtl/Cevre_Birimleri/i2c_peripheral.sv:99`

```systemverilog
localparam int QUARTER = SYS_CLK_FREQ / (4 * I2C_FREQ);
```

`soc_top.sv:785` ile örneklenir: `SYS_CLK_FREQ = 50_000_000`, `I2C_FREQ = 400_000`

```
50e6 / (4 × 400e3) = 31,25   →   tamsayı bölme   →   QUARTER = 31
gerçek SCL = 50e6 / (4 × 31) = 403,2 kHz        sapma +%0,8
```

### Neden tam 400 kHz üretilemiyor

50 MHz sistem saatiyle 400 kHz **matematiksel olarak** elde edilemez; bölüm
31,25 çıkar ve tamsayı değildir. Ulaşılabilir en yakın iki değer:

| QUARTER | SCL | Hedeften sapma |
|---:|---:|---:|
| 31 (seçilen) | **403,2 kHz** | **+%0,8** |
| 32 | 390,6 kHz | −%2,3 |

Şartname *"400 kHz sabit hızında olacaktır"* der. 31 seçimi hedefe **üç kat
daha yakındır**, bu yüzden tercih edilmiştir.

Tam 400 kHz için iki yol vardır, ikisi de reddedilmiştir:

- **48 MHz sistem saati** — tüm SoC zamanlaması, ASIC imzalaması ve FPGA
  kısıtları değişirdi. Kazanç %0,8, maliyet tüm tasarımın yeniden imzalanması.
- **Kesirli bölücü** — yeni RTL, yeni doğrulama, yeni ASIC koşusu. Aynı
  orantısızlık.

### Etki

I2C Fast-mode cihazları saat toleransını geniş tutar; %0,8 sapma hiçbir
uyumlu köle cihazda sorun çıkarmaz. Kart üzerinde I2C testi 5/5 geçmiştir
(`evidence/fpga/TAM_CEVRE_DEMOSU_20260909.txt`).

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

## 4. YORUM FARKI: QSPI CCR[24] ile 4 bayt adresleme

### Şartnamenin kendi içindeki tutarsızlık

| Şartname konumu | İfade |
|---|---|
| s.24, anlatı | *"Tüm flash alanını kapsamak için **4-bayt adresleme modu desteği** bulunacaktır"* |
| s.26, QSPI_ADR tanımı | *"READ, DOR, QOR ve PP komutunda **3-bayt** olarak kullanılır. Yani QSPI_ADR[23:0] bitleri adres olarak gönderilir"* |
| s.25, CCR[24] | *"REZERVE"* |

3 bayt adres 16 MB kapsar; "tüm flash alanı" için 4 bayt gerekir. İki ifade
aynı anda sağlanamaz.

### Çözümümüz

Rezerve bit adres genişliği seçicisi yapılmıştır
(`rtl/Cevre_Birimleri/qspi_master.sv:274-289`):

```
CCR[24] = 0  ->  3 bayt adres (QSPI_ADR[23:0])   <- RESET DEĞERİ
CCR[24] = 1  ->  4 bayt adres (QSPI_ADR[31:0])
```

**Reset değeri 0 olduğu için varsayılan davranış şartnamenin yazmaç tanımıyla
birebir aynıdır.** 4 bayt yalnızca yazılım açıkça istediğinde devreye girer.
Böylece her iki ifade de karşılanır.

Şartname s.26 ayrıca *"Tanımlanmamış tüm bit konumları Yarışmacı Tanımlı /
Rezerve'dir"* der; rezerve bitin yarışmacı tarafından tanımlanması bu
çerçevededir.

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
| I2C (NBY/ADR/RDR/TDR/CFG) | tam uyumlu — SCL için bkz. §2 |
| QSPI (CCR/ADR/DR/STA/FCR) | tam uyumlu — CCR[24] için bkz. §4 |

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
2. **I2C 403,2 kHz** — 50 MHz'de tam 400 kHz matematiksel olarak
   üretilemez; seçilen değer ulaşılabilir en yakın olandır.
3. **Timer PRE** — şartnamenin üç örneğinden ikisi `PRE+1` der, üçüncüsü
   çelişir; kuralı tanımlayan örneklere uyulmuştur.
4. **QSPI CCR[24]** — şartnamenin anlatısı ile yazmaç tanımı çelişir; rezerve
   bit ile her ikisi de karşılanmıştır, varsayılan davranış değişmemiştir.
