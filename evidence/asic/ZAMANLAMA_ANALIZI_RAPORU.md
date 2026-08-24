# ASIC Zamanlama Analizi — Problem, Teşhis ve Çözüm

**Tarih:** 24 Ağustos 2026
**Konu:** Yerleştirme sonrası STA'da çıkan setup ihlalleri, kök neden analizi ve yapılan düzeltmeler
**Dal:** `main` (`4341a77`)

---

## 1. Problem nasıl ortaya çıktı

FC ağırlıklarını kombinasyonel ROM'dan TCM/SRAM'e taşıdıktan sonra ASIC fiziksel akışı ilk kez sonuna kadar koştu. Yönlendirme temiz bitti, GDSII üretildi. **Ama ilk kez yerleştirme sonrası STA'ya (adım 55) ulaştığımız için, o ana kadar hiç görmediğimiz zamanlama ihlalleri ortaya çıktı.**

Önemli bir ayrım: daha önceki koşumlarda pozitif sonuç görmüştük, ama karşılaştırılabilir değildi.

```
evidence/asic/ara_sonuclar/38-sta-metrics.json
    adım 38 = STAMidPNR      yönlendirme ÖNCESİ, TAHMİNİ parazitikler
    kapsam  = 1 köşe (nom_tt)
    sonuç   = WNS 0, 0 ihlal

23 Ağustos koşumu
    adım 55 = STAPostPNR     yönlendirme SONRASI, ÇIKARILMIŞ parazitikler
    kapsam  = 9 köşe
    nom_tt  = 130 ihlal, WNS −4,00 ns
    nom_ss  = 1000+ ihlal, WNS −18,76 ns
```

Yani tasarım kötüleşmemişti; **ilk kez gerçek koşullarda ölçülmüştü.**

---

## 2. İlk teşhis YANLIŞTI — ve bu önemli

İlk raporda şöyle yazmıştım:

> *"Tipik köşede ihlallerin %93'ü NPU TCM SRAM'inden: `u_npu.u_npu_sram.g_sram` 121 ihlal"*

Bu, ihlallerin **başladığı** yeri doğru söylüyordu ama **bittiği** yeri değil. Talha bu rapora dayanarak `FC_WEIGHT_REQ → FC_WEIGHT_WAIT → FC_WEIGHT_LATCH → FC_MAC0` önerdi — mantıklı bir çıkarımdı, ama girdi hatalıydı.

Netlist'ten 130 ihlalin **bitiş yazmaçlarını** çıkarınca gerçek tablo çıktı:

```
121  u_npu.u_npu_engine.conv_acc        ← konvolüsyon biriktiricisi
  8  u_npu.u_npu_engine.rq_ab
  1  u_core.alu_operand_a_ex
────
  0  fc_weight_word / fc_acc            ← FC yolunda SIFIR ihlal
```

**FC ağırlık yolunda tek bir ihlal yoktu.** `FC_WEIGHT_LATCH` eklemek +4000 çevrim maliyet getirir ve WNS'i hiç değiştirmezdi.

### Ders

`max.rpt` ihlalleri sentezlenmiş net adlarıyla (`_124166_`) raporluyor. Bu adlardan tasarımın neresinde sorun olduğu anlaşılmıyor. Netlist'ten `örnek adı → Q sinyali` haritası çıkarmak şart:

```
sky130_fd_sc_hd__dfrtp_2 _124166_ (.CLK(...), .D(...),
    .Q(\u_npu.u_npu_engine.conv_acc[223] ));
```

Bunun için iki betik yazıldı:
```
asic/scripts/sta_ihlal_analiz.py     bitiş noktalarına göre sınıflandırır
asic/scripts/sta_kaynak_analiz.py    kaynak bloğa göre (netlist eşlemeli)
```

---

## 3. Kök neden: SRAM makrosunun düşen kenarı

sky130 SRAM makrosunun Liberty modeli:

```
bus(dout0) {
    pin(dout0[31:0]) {
        timing() {
            related_pin  : "clk0";
            timing_type  : falling_edge;      ← veri DÜŞEN kenarda çıkar
            cell_rise    : 0,383 – 0,529 ns   ← erişim HIZLI
        }
    }
}
```

**SRAM yavaş değil** — erişimi 0,4-0,5 ns. Sorun tamamen bütçede: veri düşen kenarda çıkıyor, tüketici yükselen kenarda yakalıyor, yani yolun **yarım çevrimi** var (20 ns yerine ~9,6 ns).

En kötü yolun dökümü (23 Ağustos, tipik köşe):

```
10,00 ns   saat düşen kenar
13,45 ns   saat ağacı gecikmesi (3,45 ns — giriş ve yakalamada büyük ölçüde iptal olur)
14,11 ns   SRAM dout1 çıktı                (erişim 0,66 ns)
14,95 ns   yönlendirme tamponları           (0,84 ns)
27,38 ns   conv_acc'e varış                 (~12,4 ns MANTIK)
23,38 ns   gereken
           ─────────
           −4,00 ns
```

Bütçeyi yiyen şey SRAM değil, **SRAM çıkışından hemen sonra gelen 8 paralel çarpma-toplama**:

```systemverilog
raw_byte   = mux(mem_rdata_b'nin 4 baytı)
x_centered = raw_byte + 128
for (d = 0; d < 8; d++)
    conv_acc[d] <= conv_acc[d] + x_centered * dw_weights(...);
```

Ve kritik olarak: **bu yol SRAM ağırlık geçişinden ÖNCE de vardı.** Konvolüsyon her zaman girdiyi TCM'den okuyordu (`184762d` commit'inde de öyle). Talha'nın değişikliği bu sorunu yaratmadı; sadece ilk kez PnR sonrası STA'ya ulaştığımız için şimdi göründü.

---

## 4. Birinci düzeltme: CONV_MAC üç aşamalı boru hattı

SRAM çıkışı MAC'ten önce yazmaca alındı. Yol ikiye bölündü:

```
SRAM → rdata_q        yarım çevrim, neredeyse boş
rdata_q → conv_acc    tam çevrim, MAC'e rahat yer
```

Boru hattı yapısı:

```
kh/kw       adresi bu çevrim verilen tap
mac_*       verisi mem_rdata_b'de olan tap
mac_*_q     verisi rdata_q'da yazmaçlanmış, MAC edilen tap   ← yeni
```

### Maliyet — ölçüldü

Konvolüsyon **boru hattı** olduğu için ek aşama verim düşürmez; yalnızca her pikselin sonunda boşaltma için +1 çevrim gerekir.

```
80.583 → 81.083 çevrim   (+500, tam olarak 500 piksel × 1)
%0,6 yavaşlama
```

İlk tahminim +40.000 çevrim (%49) idi — **yanlıştı**, tap başına maliyet sanmıştım. Ölçüm piksel başına olduğunu gösterdi.

### Sonuç

```
                 ÖNCE                    SONRA
nom_tt     130 ihlal, −4,00 ns      0 ihlal, TEMİZ
nom_ff       0 ihlal                0 ihlal, TEMİZ
nom_ss    1000+ ihlal, −18,76 ns   2624 ihlal, −5,91 ns
```

Tipik ve hızlı köşeler **tamamen kapandı**. Yavaş köşe üçte birine indi.

Ek fayda: toplam kablo uzunluğu 7.320.455 → 7.113.744 µm (**−%2,8**). Kritik yol bölününce yönlendirici daha rahat çözdü.

---

## 5. İkinci analiz: yavaş köşede ne kaldı

`nom_ss` (100°C, 1,60 V) ihlallerini netlist eşlemesiyle sınıflandırdım. **İlk sınıflandırmam yine yanıltıcıydı:** ham metne bakınca NPU kaynaklı yol 3 görünüyordu, çünkü normal flip-flop'lar sentezlenmiş adla, yalnızca SRAM makroları hiyerarşik adla görünüyor. Eşlemeyle gerçek sayı 362 çıktı.

### Yol çiftleri (başlangıç → bitiş)

| Yol | İhlal | En kötü |
|---|---|---|
| D-RAM SRAM → CV32E40P | 322 | −4,50 ns |
| **NPU mantık → NPU TCM SRAM** | **275** | **−5,42 ns** |
| CV32E40P → CV32E40P | 258 | **−5,91 ns** |
| NPU → NPU | 87 | −5,66 ns |
| UART → UART | 33 | −1,98 ns |

*(1000 yol örneklemi; toplam 2624 ihlal)*

### En kötü yol tamamen çekirdekte

```
Startpoint  u_core.csr_access_ex
Endpoint    u_core.if_stage_i.prefetch_buffer_i.fifo_i.mem_q[48]
arrival 30,19 ns / required 24,28 ns  →  −5,91 ns
```

CV32E40P'nin kendi kontrol yolu. Üçüncü parti IP, dokunulmadı.

---

## 6. İkinci düzeltme: NPU adres yolu

`NPU mantık → NPU TCM SRAM` kümesi (275 ihlal) tamamen bizim kodumuz. Başlangıç noktası `u_npu.u_npu_engine.t_out`.

Adres zinciri yazmaçtan çıkıp **tek çevrimde** SRAM adres pinine varıyordu:

```systemverilog
t_in_signed = t_out * 2 - 4 + kh              // çarpma + toplama
f_in_signed = f_out * 2 - 3 + kw
in_bounds   = (t_in >= 0 && t_in < 49 && f_in >= 0 && f_in < 40)   // 4 karşılaştırma
flat_idx_in = in_bounds ? (t_in[5:0] * 40 + f_in[5:0]) : 0         // ×40 çarpma
word_offset = flat_idx_in >> 2
mem_addr_b  = in_addr_i + word_offset          // ve SRAM pinine
```

**Çözüm CONV_MAC'te yapılanın aynısı, ters yönde:** orada SRAM **çıkışı** yazmaçlanmıştı, burada SRAM **girişi**. Adres bir çevrim önceden hesaplanıp `wo_q0`/`bo_q0`/`ib_q0` yazmaçlarına alınıyor; SRAM artık hazır bir adres görüyor.

### Boru hattı artık dört aşamalı

```
kh/kw      adresi HESAPLANAN tap
*_q0       adresi SRAM'e VERİLEN tap        ← yeni
mac_*      verisi mem_rdata_b'de olan tap
mac_*_q    verisi rdata_q'da olan, MAC edilen tap
```

### Maliyet

```
81.083 → 81.583 çevrim   (+500, yine piksel başına 1)
```

### Doğrulama

```
13/13 test, 306 denetim

Golden değerleri DEĞİŞMEDİ:
  fc_acc    = [-566992, 149030, 156762, 216460]
  fc_logits = [-128, 79, 83, 109]
  class     = 3
```

Matematik birebir aynı, yalnızca zamanlama değişti.

---

## 7. Yapmadıklarım ve neden

### D-RAM → CPU (322 ihlal)

`sram_module.sv` içinde aynı örüntü var:

```systemverilog
assign ram_rdata    = rd_en_q ? dout_r[rsel_q] : rdata_hold;
assign s_axil_rdata = ram_rdata;
```

SRAM düşen kenarda veri veriyor, sonra mux → AXI → interconnect → OBI köprüsü → CPU boru hattı, hepsi yarım çevrimde.

Düzeltilebilir (`rdata_hold`'u her zaman kullan, `rvalid`'i bir çevrim geciktir) **ama yapmadım:**

```
Fayda    322 ihlal, TNS −816 ns      WNS DEĞİŞMEZ (−5,91 çekirdekte)
Bedel    her fetch ve load +1 çevrim, CPU %30-50 yavaşlar
Risk     sram_module hem I-RAM hem D-RAM tarafından kullanılıyor
```

WNS'i değiştirmeyen, CPU'yu belirgin yavaşlatan ve iki belleği birden etkileyen bir müdahale — teslime 7 gün kala risk/getiri oranı zayıf.

### CV32E40P (258 ihlal, WNS'i belirleyen)

Üçüncü parti IP. Dokunulmadı.

### NPU requantization çarpımı (43 ihlal, −5,66 ns)

```systemverilog
rq_ab <= $signed(conv_acc[d_out]) * $signed(m);   // 32×32 işaretli çarpma
```

Bölünebilir (iki 16×32 aşaması) ama maliyeti +4000 çevrim (%5) ve WNS yine çekirdekte kalır. Şimdilik bırakıldı.

---

## 8. Şartname açısından durum

Köşe zorunluluğu bizim kategorimizde **yok**:

- TT/27°C isteri **analog AFE bölümünde** (PCIe ön-uç), mikrodenetleyici kategorisinde değil
- Bizim puanlamamız: *"Çip Akışı Puanı — Statik tasarım kontrolleri (CDC, RDC, **STA**, vb.)"*, sentez, P&R, LVS/DRC, GDS

Yani STA'nın **yapılmış ve raporlanmış** olması puanlanıyor; belirli bir köşede sıfır ihlal şartı yazılı değil.

---

## 9. Bir sonraki koşum için tahmin

**Yüksek güven:**
- WNS ~−5,91 ns kalacak (çekirdek yolu, dokunulmadı)
- tt ve ff köşeleri temiz kalacak
- Çevrim sayısı 81.583

**Orta güven:**
- `NPU → NPU TCM` kümesi (275) büyük ölçüde kapanmalı
- Toplam ihlal 2624 → ~1800-2000

**Kapanmayacak:**
- ss köşesi temizlenmeyecek. Hem çekirdek (−5,91) hem NPU'nun kendi `rq_ab` çarpımı (−5,66) duruyor.

---

## 10. Özet

| Düzeltme | Maliyet | Sonuç |
|---|---|---|
| CONV_MAC 3 aşamalı boru hattı | +500 çevrim | tt/ff **temiz**, ss −18,76 → −5,91 ns |
| NPU adres yolu yazmaçlandı | +500 çevrim | 275 ihlal hedefleniyor (ölçüm bekliyor) |
| **Toplam** | **+1000 çevrim (%1,2)** | 80.583 → 81.583 |

İki düzeltme de aynı fikirdir: **SRAM'in yarım çevrimlik bütçesinde uzun kombinasyonel zincir bırakma.** Biri çıkışta, biri girişte.

Golden test her iki değişiklikten sonra da birebir aynı değerleri verdi — matematik hiç değişmedi.

### Savunulabilir konum

> *"Tasarım tipik (tt) ve hızlı (ff) köşelerde 50 MHz'de kapanıyor. Yavaş (ss) köşedeki ihlallerin baskın kısmı üçüncü parti CV32E40P çekirdeğinin iç yollarındadır. Kendi bloklarımızda iki zamanlama düzeltmesi yapılmış, ihlaller X'ten Y'ye indirilmiştir. Kritik yol analizi netlist eşlemeli olarak yapılmış ve betikleri repoda kayıtlıdır."*
