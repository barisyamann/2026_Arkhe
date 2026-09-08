# SRAM Okuma Boru Hattı Yaması — Doğrulama Raporu

**Takım Arkhe — TEKNOFEST 2026 Çip Tasarımı Yarışması**
Tarih: 5 Eylül 2026

---

## 1. Neden bu değişiklik yapıldı

`arkhe25_100mhz` koşumunun `max_ss_100C_1v60` köşesindeki imzalama STA'sı,
1399 setup ihlalinin **tamamının** SRAM okuma çıkışlarından başladığını
gösterdi:

| Yolun kaynağı | İhlal sayısı | En kötü açık |
|---|---|---|
| I-RAM | 881 | −4,513 ns |
| D-RAM | 339 | −3,907 ns |
| NPU + yazmaçlar | 216 | −1,797 ns |

En kötü yol:

```
u_instruction_ram.g_sram[2].u_macro/dout1[14]   (SRAM okuma çıkışı)
   → 3 tampon → 3 seri mux2 (banka seçimi, 4,04 ns)
   → ~15 seviye kombinasyonel mantık
   → _185419_/D  (CPU içi yazmaç)
```

`sram_module.sv` içinde `rdata_hold` yazmacı zaten vardı, ancak yalnızca
yedek yolda kullanılıyordu:

```systemverilog
assign ram_rdata = rd_en_q ? dout_r[rsel_q] : rdata_hold;
```

Aktif okumada (`rd_en_q = 1`) veri doğrudan SRAM çıkışından kombinasyonel
geçiyordu; mevcut yazmaç kritik yolu **kesmiyordu**.

---

## 2. Yapılan değişiklik

Değiştirilen tek dosya: `rtl/Memory/sram_module.sv`

```systemverilog
// önce:
assign ram_rdata = rd_en_q ? dout_r[rsel_q] : rdata_hold;

// sonra:
assign ram_rdata = rdata_hold;     // kombinasyonel bypass yok
```

Buna eşlik eden AXI akış kontrolü (yalnızca `USE_SRAM_MACRO` dalında):

```systemverilog
assign s_axil_arready = rst_n && !macro_read_pending && !s_axil_rvalid;
```

**FPGA yolu etkilenmez.** Değişiklik `` `ifdef USE_SRAM_MACRO `` içindedir;
çıkarımsal BRAM yolu (Vivado / Nexys A7) aynen korunmuştur. 26 Ağustos
tarihli fiziksel kart testi kanıtı geçerliliğini sürdürür.

**Bedeli:** okuma başına bir ek çevrim. CV32E40P'de komut ön belleği
bulunmadığından bu CPI'ya doğrudan yansır; frekans kazancıyla takası
ölçülmelidir.

---

## 3. Doğrulama sonuçları

Tüm testler **ASIC kod yolunda** (`USE_SRAM_MACRO` tanımlı) koşuldu.

| Test | Denetim | Sonuç |
|---|---|---|
| uart | 30 | GEÇTİ |
| sync_fifo | 24 | GEÇTİ |
| i2c | 14 | GEÇTİ |
| dma | 39 | GEÇTİ |
| gpio | 31 | GEÇTİ |
| qspi | 22 | GEÇTİ |
| timer | 36 | GEÇTİ |
| jtag_debug | 20 | GEÇTİ |
| npu_blok | 9 | GEÇTİ |
| npu_golden | 1 | GEÇTİ |
| npu_dogruluk | 77 | GEÇTİ — birebir eşitlik, sapma yok |
| sistem | 13 | GEÇTİ |
| sistem_gercek_boot | 13 | GEÇTİ — gerçek QSPI boot |
| **uvm_axi_agent** | **17** | GEÇTİ — AXI4-Lite protokolü temiz |
| **cekirdek_izi** | 1 | GEÇTİ — D-RAM imzası `0xC0DE0001` |
| **TOPLAM** | **347** | **15/15 test, 0 hata** |

### Spike ISS karşılaştırması

```
Spike ham buyruk : 414
RTL   ham buyruk : 145801        (gerçek boot zinciri dahil)
hizalama PC      : 0x01000000
karşılaştırılan  : 409 buyruk
PC uyuşmazlığı   : 0
makine kodu uyuş.: 0
sıkıştırılmış    : 156 (beklenen — gösterim farkı)
```

### Yorum

Yama, ASIC kod yolunda **fonksiyonel olarak şeffaftır**:

- AXI4-Lite el sıkışması bozulmaz (`arready` geri basıncı UVM pasif ajanı
  ve `axil_protocol_checker.sv` tarafından onaylandı)
- NPU çıkarım sonuçları bit düzeyinde değişmez (77 denetim birebir eşitlik)
- Çekirdeğin buyruk akışı Spike ISS ile birebir eşleşir

### npu_hizlanma — sonradan kapatıldı

İlk koşumda bu test makro kipinde elaborasyon hatası veriyordu; testbench
`uut.u_npu.u_npu_sram.ram` dizisine doğrudan erişiyordu. Aynı gün üç
engelin ardından çözüldü:

1. `SIM_MACRO_INIT` tanımı gerekiyor — makro içi `mem` dizisi ancak bu
   tanımla görünür olur (`npu_tcm_sram.sv` içinde `ifdef` ile korunmuş).
2. `g_sram[m].u_macro` yoluna **değişken indisle erişilemiyor**; xelab
   `'u_macro' is not declared under prefix 'g_sram'` ile düşüyor. Aynı
   kısıt `tb_soc_top.sv:390`'da da not edilmiş. Erişimler sabit indisli
   `case` yapısına çevrildi (15 TCM + 4 I-RAM makrosu).
3. Testbench donanım çevrim sayısını **üç yerde `81083` olarak gömülü**
   tutuyordu. Bu değer NPU requantization boru hattı (28 Ağustos,
   `CONV_RQ_MUL`/`FC_RQ_MUL`) eklenmeden önceye aitti; `analiz.py`
   güncellenmiş ama testbench unutulmuştu. Hızlanma oranı bu yüzden
   olduğundan yüksek (874x) çıkıyordu. Sabit `localparam DONANIM_CEVRIM`
   yapılıp üç kullanım da ona bağlandı.

**Ölçüm sonucu (ASIC kod yolu, yamalı RTL):**

| Ölçüm | Değer |
|---|---|
| Yazılım, 50 piksel | 547 845 çevrim |
| Tap başına | 248,1 çevrim |
| Piksel başına | 10 956,9 çevrim |
| Tam çıkarım tahmini | 70 902 259 çevrim (1,42 s @50 MHz) |
| Donanım çıkarımı | 85 587 çevrim (1,71 ms) |
| **Kaba hızlanma** | **828×** |

> **Bu bir tahmindir, doğrudan ölçüm değildir.** Yazılım tarafı 50
> pikselden 4000 piksele ölçeklenmiştir; testbench bunu "kaba alt sınır
> tahmini" olarak etiketler. İki farklı N ölçümüyle model çözen
> `tb/npu_sw_bench/analiz.py` daha güvenilirdir ve **753×** verir.

**Yamanın NPU'ya etkisi yok:** donanım çıkarımı yamalı RTL'de de 85 587
çevrimdir. NPU, TCM'e kendi portundan (`npu_tcm_sram`) erişir; yamalanan
`sram_module` I-RAM ve D-RAM içindir.

---

## 4. Bu çalışmanın ortaya çıkardığı yapısal boşluk

**Regresyon bugüne kadar ASIC kod yolunu hiç doğrulamamıştı.**

`run_regression.py` hiçbir testte `USE_SRAM_MACRO` tanımlamıyordu; 16 test
ve 349 denetimin tamamı SRAM'in **çıkarımsal** dalını (`else`) sınıyordu.
ASIC akışı ise `asic/config.yaml` içinde bu tanımı açar ve **makro** dalını
kullanır. İki yol farklı koddur; biri doğrulanırken diğeri doğrulanmamış
kalıyordu.

Bu koşumda kapatılan dört boşluk:

| # | Dosya | Sorun |
|---|---|---|
| 1 | `scripts/run_regression.py` | `--ek-tanim` seçeneği yoktu; ayrıca `USE_SRAM_MACRO` verilince satıcının davranışsal SRAM modeli kaynak listesine eklenmiyordu (`Module <sky130_sram_2kbyte_1rw1r_32x512_8> not found`) |
| 2 | `tb/tb_soc_top.sv` | `CORE_TEST` kipindeki D-RAM imza okuması `ifdef` korumasızdı; makro kipinde elaborasyon `'ram' is not declared under prefix 'u_data_ram'` ile düşüyordu |
| 3 | `sw_nexys/scripts/gen_flash_image.py` | Makro kipinde `core_test.hex` I-RAM'e doğrudan yüklenemez; gerçek QSPI boot kullanılır ama flash'ta ana uygulama vardı. `flash_core_test.hex` üretimi eklendi |
| 4 | `tb/tb_soc_top.sv` | Sabit 200 µs bekleme gerçek boot için yetmiyordu (ölçülen: **14 868 µs**). İmzayı bekleyen döngüye çevrildi |

---

## 5. Yeniden üretme

```bash
# Flash imajlarını üret (flash_core_test.hex dahil)
python sw_nexys/scripts/gen_flash_image.py

# ASIC kod yolunda tam regresyon
python scripts/run_regression.py --ek-tanim USE_SRAM_MACRO

# Tek test
python scripts/run_regression.py --test uvm_axi_agent --ek-tanim USE_SRAM_MACRO

# Spike ISS karşılaştırması
python scripts/run_regression.py --test cekirdek_izi --ek-tanim USE_SRAM_MACRO
python scripts/spike_karsilastir.py
```

Çıkarımsal yolu (FPGA davranışı) sınamak için `--ek-tanim` verilmez:

```bash
python scripts/run_regression.py
```

---

## 6. Fiziksel tasarım — yoğunluk deneyleri

Yama fonksiyonel olarak doğrulandıktan sonra PnR denendi ve **yönlendirme
sıkışıklığı** engeliyle karşılaşıldı. Yamanın kritik yolu kesmesi
zamanlama optimizasyonunu serbest bıraktı; resizer daha çok tampon ekledi
ve met1/met2 katmanlarında yerel yığılma oluştu.

`PL_TARGET_DENSITY_PCT` dışında hiçbir ayar değiştirilmeden dört koşum
yapıldı. Hepsi aynı önbellek durumundan devam etti
(`--from OpenROAD.GlobalPlacement --with-initial-state`), yani tek değişken
yoğunluktur.

| Yoğunluk | Toplam taşma | met1 | met2 | Tel uzunluğu | `nom_tt` payı | Sonuç |
|---|---|---|---|---|---|---|
| ~%57,4 (dinamik) | 9789 | 2308 | 6069 | 11 516 µm | −0,2226 ns | GRT-0116 |
| %52 | 5673 | 1367 | 3235 | 11 403 µm | −0,2296 ns | GRT-0116 |
| %48 | 193 | 51 | 48 | 11 542 µm | −0,2208 ns | GRT-0116 |
| **%45** | **0** | **0** | **0** | **11 025 µm** | **−0,1601 ns** | **geçti** |

### Yorum

**Taşma-yoğunluk ilişkisi doğrusal değil, eşik davranışı gösteriyor.**
%57,4 → %52 taşmayı yarıya indirdi; %52 → %48 yirmi dokuz kata böldü;
%48 → %45 sıfırladı.

**Tel uzunluğu artmadı, azaldı.** Yoğunluk düşünce hücreler yayılır ve
tellerin uzaması beklenirdi; ölçüm bunun tersini gösterdi (11 542 →
11 025 µm). Hücreler daha rahat yerleşince yönlendirici daha kısa yollar
buluyor.

**Zamanlama da iyileşti.** `nom_tt` payı −0,2208'den −0,1601 ns'ye çıktı.
Yani seyreltmenin zamanlama maliyeti yok; aksine kritik yoldaki teller
kısaldığı için küçük bir kazanç var.

### Yanlış çıkan ilk teşhis

İlk değerlendirmede `GRT_ADJUSTMENT`'ın 0,18 olduğu ve **artırılmasının**
yönlendiriciye kapasite kazandıracağı öne sürülmüştü. İkisi de yanlıştır:

- Bu koşumda `GRT_ADJUSTMENT` **0,30**'dur (`resolved.json` ile
  doğrulandı); 0,18 değeri `arkhe_t50_12` tarafındaki ayrı bir
  yapılandırmaya aitti.
- OpenROAD'da bu ayar yönlendirme kapasitesini **azaltır**; 0,30 = "%30
  azalt". Artırmak kapasite kazandırmaz.

Ayrıca `GRT_LAYER_ADJUSTMENTS = [0.99, 0, 0, 0, 0, 0]` olduğu görüldü:
`li1` katmanı %99 kısılmış, yani yönlendirmeye neredeyse hiç katılmıyor.
Taşmanın %81'inin met1+met2'de toplanması bunun doğrudan sonucudur.

## 7. Açık kalan sorular

1. **Zamanlama kazancı henüz ölçülmedi.** PnR koşumu
   (`~/arkhe_exp/experiments/sramreg_20260905`) devam ediyor; 9 köşe
   imzalama STA'sı sonuçlanmadan 50 MHz'in kapanıp kapanmadığı bilinemez.
2. **CPI bedeli ölçülmedi.** I-RAM'e eklenen çevrimin uygulama başarımına
   etkisi sayısallaştırılmalıdır.
3. **Diğer cepheler açık.** NPU yolları (−1,797 ns) ve CPU operand →
   komut adresi yolu (−1,557 ns) bu yamadan etkilenmez; 50 MHz için
   onların da kapanması gerekir.
