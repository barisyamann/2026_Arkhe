# ARKHE SoC — Jüri Teknik Özeti

**TEKNOFEST 2026 Çip Tasarımı Yarışması — Mikrodenetleyici Kategorisi**
Hazırlanma tarihi: 5 Eylül 2026

> Bu belgedeki her sayı, depodaki veya sunucudaki bir çıktı dosyasından
> alınmıştır. Kaynak dosya her bölümün altında verilmiştir. Tahmine dayanan
> tek kalem (NPU hızlanma) açıkça işaretlenmiştir.

---

## 1. Tasarım özeti

| Öğe | Değer |
|---|---|
| İşlemci | CV32E40P, RV32IMC (FPU = 0) |
| Veri yolu | AMBA AXI4-Lite, 32 bit |
| Bellek | 23 x `sky130_sram_2kbyte_1rw1r_32x512_8` (NPU TCM 15, I-RAM 4, D-RAM 4) |
| YZ hızlandırıcı | TinyConv: Conv2D -> ReLU -> FC -> Softmax |
| Çevre birimleri | 2xUART, I2C, QSPI, GPIO, Timer, DMA, JTAG |
| Teknoloji | SkyWater 130 nm (sky130A), `sky130_fd_sc_hd` |
| Akış | LibreLane 3.0.6 Classic / OpenROAD |
| Die alanı | 3832,40 x 4249,24 um = 16,28 mm2 |

---

## 2. Zamanlama — teslim edilen koşum (`arkhe25s`)

İmzalama periyodu **29,5 ns**. PnR periyodu 20 ns; şartname Bölüm 6.2
ayrık SDC kullanımına izin verir.

| Köşe | Setup payı | Hold payı |
|---|---|---|
| min_ff_n40C_1v95 | +5,663 ns | +0,062 ns |
| nom_ff_n40C_1v95 | +5,338 ns | **-0,141 ns** |
| max_ff_n40C_1v95 | +4,938 ns | **-0,388 ns** |
| min_tt_025C_1v80 | +4,641 ns | +0,310 ns |
| nom_tt_025C_1v80 | +4,276 ns | +0,052 ns |
| max_tt_025C_1v80 | +3,839 ns | **-0,248 ns** |
| min_ss_100C_1v60 | +1,695 ns | +0,939 ns |
| nom_ss_100C_1v60 | +0,847 ns | +0,945 ns |
| **max_ss_100C_1v60** | **-0,247 ns** | +0,764 ns |

**Ulaşılan frekans:** 29,5 + 0,247 = 29,75 ns -> **33,6 MHz**

Kaynak: `run/arkhe25s/57-openroad-stapostpnr/<köşe>/ws.max.rpt` ve `ws.min.rpt`

### Açıkça belirtilmesi gerekenler

- **`max_ss` köşesinde -0,247 ns setup açığı vardır.** Kritik yol CV32E40P
  çekirdeğinin içindedir; çekirdek zorunlu üçüncü taraf IP olduğu için
  içine müdahale edilmemiştir.
- **Üç köşede hold ihlali vardır** (nom_ff -0,141, max_tt -0,248,
  max_ff -0,388 ns).
- 50 MHz hedefine ulaşılamamıştır. Yapılan çalışma Bölüm 5'tedir.

---

## 3. Fiziksel signoff

| Denetim | Sonuç |
|---|---|
| Netgen LVS | **Passed** |
| KLayout DRC | **0 hata** |
| Magic DRC | 7658 ihlal, tamamı `nwell.4` |
| Anten | **2 net / 2 pin ihlali** |
| Akış | 78 / 78 adım tamamlandı |
| IR drop | %0,14 |

Kaynak: `run/arkhe25s/78-misc-reportmanufacturability`

### Magic `nwell.4` hakkında

Bu kural KLayout kural setinde bulunmamaktadır; aynı GDS üzerinde KLayout
0 hata verir. Tap hücrelerinin mevcut ve yoğun olduğu ölçülmüştür (13 um
hedefe karşı ~9 um aralık). GDS üzerinden doğrulama denenmiş, bellek
tükenmesi nedeniyle tamamlanamamıştır.
Ayrıntı: `evidence/asic/KOSUM6_BULGU_ANALIZI.md`

**Bu ihlaller "araç hatası" olarak sunulmamaktadır**; tek tanık Magic ve
kesin teşhis tamamlanmamıştır.

---

## 4. Doğrulama

### Regresyon — ASIC kod yolu (`USE_SRAM_MACRO`)

16 test, **349 denetim, 0 hata**.

| Test | Denetim | Test | Denetim |
|---|---|---|---|
| uart | 30 | npu_blok | 9 |
| sync_fifo | 24 | npu_golden | 1 |
| i2c | 14 | npu_dogruluk | 77 |
| dma | 39 | npu_hizlanma | 2 |
| gpio | 31 | sistem | 13 |
| qspi | 22 | sistem_gercek_boot | 13 |
| timer | 36 | **uvm_axi_agent** | **17** |
| jtag_debug | 20 | cekirdek_izi | 1 |

Yeniden üretim: `python scripts/run_regression.py --ek-tanim USE_SRAM_MACRO`

> **Not:** `--ek-tanim USE_SRAM_MACRO` verilmezse testler SRAM modülünün
> çıkarımsal dalını sınar. ASIC akışının kullandığı makro dalını doğrulamak
> için bu tanım gereklidir.

### Spike ISS karşılaştırması

```
karşılaştırılan buyruk : 409
PC uyuşmazlığı         : 0
makine kodu uyuşmazlığı: 0
```

**Sınırları:** 156 sıkıştırılmış buyrukta makine kodu karşılaştırması
atlanmaktadır (Spike ham 16-bit, CV32E40P tracer açılmış 32-bit raporlar).
Yazmaç sonuçları karşılaştırılmamaktadır. Bu **tam ISA doğrulaması
değildir**; komut izlerinin tür ve sıra bakımından eşleştiğini gösterir.
Ayrıntı: `evidence/dogrulama/SPIKE_ISS_KARSILASTIRMA.md`

### UVM AXI4-Lite

Pasif agent ve 5 SVA bağlama noktası; 17 denetim geçti. Kapsam NPU motoru
ile bellek arayüzüdür, bütün çevre birimi AXI arayüzlerini kapsamaz.
Ayrıntı: `evidence/dogrulama/UVM_AXI_AGENT.md`

### Kod kapsama

| | Statement | Branch | Condition | Toggle |
|---|---|---|---|---|
| Tam SoC | %62,46 | %44,53 | %55,77 | %31,48 |

Blok testleri, her test kendi veritabanından:

| Test | Line | Test | Line |
|---|---|---|---|
| timer | %97,5 | i2c | %94,0 |
| sync_fifo | %96,5 | uart | %92,7 |
| npu_blok | %96,3 | qspi | %91,7 |
| dma | %96,1 | gpio | %88,2 |
| | | jtag_debug | %85,5 |

> Birleşik blok raporu **yanıltıcıdır**: xcrg, parametre farkı nedeniyle
> beş modülün verisini birleştiremeyip düşürmektedir. Yukarıdaki değerler
> her testin kendi veritabanından ayrı üretilmiştir.

**Fonksiyonel kapsama ölçülmemiştir.**

### NPU hızlanma

| Ölçüm | Değer |
|---|---|
| Yazılım, 50 piksel (ölçülen) | 547 845 çevrim |
| Tam çıkarım (**tahmin**) | 70 902 259 çevrim |
| Donanım (ölçülen) | 85 587 çevrim |
| **Hızlanma** | **753x - 828x** |

> **Bu bir tahmindir.** Yazılım tarafı 50 pikselden 4000 piksele
> ölçeklenmiştir; tam yazılım koşumu doğrudan ölçülmemiştir. İki farklı N
> ölçümüyle model çözen `analiz.py` 753x, tek ölçümlü kaba tahmin 828x
> vermektedir.

### FPGA — fiziksel kart

Nexys A7-100T üzerinde 26 Ağustos 2026 tarihli canlı UART kaydı: **8
ardışık çıkarım, global reset olmadan**, sınıflandırmalar doğru
(NO / SILENCE / YES). Timer, bus-fault (SLVERR), I2C, DMA, GPIO ve NPU IRQ
zinciri doğrulanmıştır.
Kanıt: `evidence/fpga/kart_testi_20260826.log`

> **Sürüm notu:** Bu bitstream 24 Ağustos tarihlidir. Sonraki RTL
> değişiklikleri (NPU requantization boru hattı) bu bitstream içinde
> değildir.

---

## 5. 50 MHz hedefi — yapılan çalışma ve sonucu

Hedef **ulaşılamamıştır.**

### Teşhis

`max_ss` köşesindeki 1399 setup ihlalinin kaynak dağılımı:

| Kaynak | İhlal | En kötü açık |
|---|---|---|
| I-RAM | 881 | -4,513 ns |
| D-RAM | 339 | -3,907 ns |
| NPU | 84 | -1,797 ns |
| CPU yazmaçları | 132 | -1,557 ns |

En kötü yol: SRAM okuma çıkışı -> 3 seri mux2 (banka seçimi, 4,04 ns) ->
~15 seviye kombinasyonel mantık -> CPU yazmacı.

**Bu yol yarım çevrimdir:** SRAM veriyi düşen kenarda çıkarır, CPU yükselen
kenarda yakalar. 50 MHz hedefinde bu yolun bütçesi 20 ns değil **10 ns**.

### Denenen çözüm

`sram_module.sv` içinde SRAM okuma çıkışı yazmaçlandı; kombinasyonel bypass
kaldırıldı. Değişiklik yalnızca `USE_SRAM_MACRO` dalındadır, FPGA davranışı
değişmemiştir.

**Fonksiyonel olarak doğrulanmıştır:** 349 denetim, Spike 409/0, UVM 17
denetim.

**Fiziksel tasarımda iki engel çıkmıştır:**

1. Yönlendirme sıkışıklığı — yerleştirme yoğunluğu deneyleriyle çözüldü:

| Yoğunluk | Toplam taşma |
|---|---|
| ~%57 | 9789 |
| %52 | 5673 |
| %48 | 193 |
| **%45** | **0** |

2. Pin erişimi — %45 yoğunlukta `DRT-1231`: D-RAM makrosunun bir veri
   pinine yönlendirici ulaşamadı. Makro halo artırılarak yeniden
   denenmektedir.

**Sonuç:** Yama fonksiyonel olarak doğrudur ancak bu tasarımda fiziksel
kapanış henüz sağlanamamıştır. Teslim edilen paket **yamasız** sürümdür.

---

## 6. ÖTR/DTR'den farklar

| Konu | Rapordaki | Güncel | Gerekçe |
|---|---|---|---|
| ISA | RV32IMFC | RV32IMC (FPU=0) | `evidence/fpga/fpu_karar_olcumu.md` |
| NPU veri yolu | AXI4 burst | AXI4-Lite | Şartname izin veriyor |
| NPU sonuç iletimi | Polling | Kesme + ISR | Şartname kesme istiyor |
| NPU / DMA IRQ | 21 / 23 | 22 / 24 | RTL güncel |
| Ağırlık saklama | ROM | QSPI flash -> TCM | Mimari değişikliği |
| Spike | "20/20 eşleşti" | 409 buyruk, gerçek ISS | İlk beyan gerçek koşuma dayanmıyordu |

---

## 7. Yeniden üretim

```bash
# Doğrulama
python scripts/run_regression.py --ek-tanim USE_SRAM_MACRO
python scripts/spike_karsilastir.py

# ASIC akışı
nix develop ./environment
cd asic && make asic_run && make asic_verify
```

Araç sürümleri: `asic/environment/versions.txt`
Bağımlılık sabitlemesi: `asic/environment/flake.lock`
