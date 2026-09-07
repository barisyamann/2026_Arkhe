# NPU SRAM Entegrasyonu — Sonuç Raporu

**Tarih:** 23 Ağustos 2026
**Dal:** `npu-sram-entegrasyon` (main tabanlı, 5 commit)
**Konu:** `talha-npu-sram-test` çalışmasının entegrasyonu, doğrulanması ve ASIC akışının koşulması

---

## 1. Özet

FC ağırlıklarını kombinasyonel ROM'dan TCM/SRAM'e taşıma çalışması main'e entegre edildi, bağımsız olarak doğrulandı ve tam ASIC akışı koşuldu.

**Ana sonuç: hipotez doğrulandı.** ASIC fiziksel akışı artık yönlendirmede tıkanmıyor ve GDSII üretiliyor. Ama yeni bir sorun ortaya çıktı: SRAM okuma yolu kritik yol oldu ve zamanlama ihlalleri yaratıyor.

Entegrasyon sırasında raporun kapsamı dışında bırakılan asıl eksik de tamamlandı: **gerçek çipte ağırlıkları flash'tan belleğe yükleyen boot mekanizması yazıldı.** O olmadan üretilen çipte NPU her sese aynı cevabı verirdi.

---

## 2. Çalışmanın doğrulanması

### Paketleme doğru

`fc_weights_packed32.mem`, Google'ın `micro_speech_quantized.tflite` dosyasındaki `final_fc_weights` tensörüyle karşılaştırıldı:

    16.000 değerin TAMAMI birebir aynı, 0 uyuşmazlık

Paketleme betiğinin sınıf-major varsayımı (0..3999 Silence, 4000..7999 Unknown, ...) bağımsız olarak doğrulandı.

### RTL doğru

`fc_weights0..3` çağrılarının hepsi kalkmış (kalan tek eşleşme yorum satırı). Dört sınıf da `fc_weight_word` üzerinden besleniyor.

### Çevrim maliyeti tam olarak ölçüldü

Rapor 80.583 ile 964.071'in karşılaştırılamayacağını söylüyor. Aslında güncel main ile **birebir karşılaştırılabilir**:

    80.583 − 72.583 = 8.000 çevrim = 2 × 4000 FC yinelemesi

Yani maliyet tam olarak SRAM okuma gecikmesi. Matematik değişmemiş. (964.071 sayısı DTR'den; ondan sonra R4 optimizasyonlarıyla 72.583'e inilmişti.)

---

## 3. Entegrasyonda bulunan sorunlar

### 3.1 Testbench adres haritası çakışması

Entegrasyondan sonra `npu_dogruluk` testi 7 vektörün 3'ünde düştü. **Belirti aldatıcıydı:** sınıf kararları DOĞRUYDU, yalnızca logit/olasılık değerleri kayıyordu — ilk bakışta yuvarlama farkı gibi göründü.

Gerçek sebep:

    tb_npu_audio.sv çıkış bölgesi CIKIS_TABAN = 4096
    FC ağırlıkları                              3584..7583
                                                ^^^^^^^^^^ çıkışlar tam ortasına düşüyor

Her vektör kendi olasılıklarını `fc_idx 512..539`'un ağırlıklarının üzerine yazıyordu. Bozulma vektörden vektöre birikiyordu: v0 temiz ağırlıklarla doğru, sonrakiler bozuk.

`CIKIS_TABAN` 7584'e taşındı, testbench'e üç koşum-anı taşma denetimi eklendi.

**Bu bir RTL hatası değildi** — RTL doğru, testbench'in adres haritası yeni yerleşimle çatışıyordu.

### 3.2 Golden PASS bizim akışımızda geçmiyordu

Rapor `tb_npu_golden` PASS diyor. Regresyon akışımızda düştü çünkü `fc_weights_packed32.mem` çalışma dizinine kopyalanmıyordu. Ağırlıklar sıfır okununca `fc_acc` tam olarak `fc_bias`'a eşit çıktı — teşhis kolay oldu.

`run_regression.py`'ye `weights/` arama yolu ve üç NPU testine dosya eklendi.

---

## 4. Raporun bıraktığı asıl eksik: gerçek çipte ağırlık yok

Rapor bunu §6'da "Bekliyor", §7.4'te "yol haritası" olarak işaretlemiş. Entegrasyonda tamamlandı, çünkü onsuz üretilen çip çalışmıyor.

### Sorun

SRAM uçucudur. Üretilmiş çipte güç verildiğinde TCM boştur. Simülasyonda testbench `$readmemh` ile dolduruyor; gerçek çipte bunu yapacak kimse yok.

Yüklenmezse `fc_acc` yalnızca bias'a eşit olur: `[427, −518, −94, 186]`. En büyüğü indeks 0'da, yani **NPU her sese SILENCE der.**

### Yapılanlar

**a) `weights_ready` koruması** (`npu_csr.sv`)

    assign start_o = reg_start && reg_weights_ready;

CTRL bit 4 kurar (yapışkan), STATUS bit 3'ten geri okunur. Bayrak kurulmadan START kabul edilmez. Raporun §7.4'te önerdiği koruma bu.

Not: ilk yazımda `npu_reset` de bayrağı temizliyordu, bu yanlıştı — `npu_reset` motor FSM'ini sıfırlar, TCM içeriğine dokunmaz. Üstelik uygulama her çıkarım öncesi `npu_reset` veriyor, yani START bir daha asla kabul edilmiyordu. Bayrağı artık yalnızca sistem reseti temizliyor.

**b) Yükleyici ağırlıkları kopyalıyor** (`bootloader.S`, 80 → 168 bayt)

Uygulamayı I-RAM'e kopyaladıktan sonra 4000 kelimeyi flash'tan `TCM[3584..7583]`'e kopyalar, sonra bayrağı kurar.

Blok boyutu 50 kelime (200 bayt): 4000 kelime 256'ya tam bölünmez (62,5 blok), 200'e bölünür (80 × 200 = 16.000 bayt).

**c) Birleşik flash imajı** (`scripts/gen_flash_image.py`)

    0x800000  uygulama         2048 kelime (8 kB ayrıldı)
    0x802000  FC ağırlıkları   4000 kelime (16 kB)

Testbench artık ağırlıkları TCM'e ön-yüklemiyor. Simülasyon, üretilmiş çipte olacak şeyin aynısını koşuyor.

**Kanıt:** `sistem_gercek_boot` süresi 109 s → 179 s. Aradaki 70 saniye, 16 kB'ın QSPI üzerinden gerçekten kopyalanması.

---

## 5. Koruma üç gizli hata ortaya çıkardı

`weights_ready` eklenince sistem testleri düştü. Sebebini ararken **üç ayrı yerde ağırlıkları silen kod** bulundu:

| Nerede | Ne yapıyordu |
|---|---|
| `tb_soc_top` hızlı açılış | ağırlıkları hiç yüklemiyordu |
| `tb_npu_compute_engine` `run_scenario` | her senaryoda tüm TCM'yi sıfırlıyordu |
| **`main.c`** | **her çıkarım öncesi 7680 kelimenin tamamını siliyordu** |

Üçü de aynı kör nokta: *"NPU belleğini temizle"* mantığı, belleğin artık **kalıcı veri** de tuttuğunu bilmiyordu. Ağırlıklar ROM'dayken güvenliydi; TCM'e taşınınca sessiz hataya dönüştü.

`main.c` artık yalnızca çalışma bölgesini (0..3583) siliyor.

### Sistem testi de sıkılaştırıldı

Boşluk: GPIO denetimi **üç deseni birden** kabul ediyordu (YES/NO/SILENCE). Yani NPU'nun hangi sınıfı verdiği hiç denetlenmiyordu — sıfır ağırlıkla da geçiyordu.

Artık beklenen sınıf denetleniyor. Girdi UART-stream'den 1960 bayt `0x55`; beklenen sonuç resmi TFLite'a çapalı referans modelden:

    fc_acc = [-985885, 242268, 240758, 387226]
    logits = [-128, 120, 120, 127]
    sinif  = 3 (NO)  ->  GPIO 0xAAAA

Bu denetim eklenir eklenmez kırmızı yandı ve yukarıdaki üç hatayı ortaya çıkardı.

---

## 6. Güncel TCM yerleşimi

    0    ..  489   girdi tensörü (DMA buraya yazar)
    0    ..    3   çıkış olasılıkları (out_addr = 0)
    490  .. 3583   serbest / uygulama tarafından temizlenir
    3584 .. 7583   FC AĞIRLIKLARI — hiçbir yerden silinmez
    7584 .. 7679   serbest

`npu_blok` testinin çıkışı 7596'da, ağırlıkların bitişine **12 kelime** mesafede. `out_addr_i` değiştirilecekse 7583'ün üzerinde kalmalı.

---

## 7. Regresyon

**13/13 test, 293 denetim — hepsi geçiyor.**

`sistem_gercek_boot` tam zinciri koşuyor: Boot ROM → QSPI flash → ağırlıklar TCM'e → `weights_ready` → uygulama → DMA → NPU → **doğru sınıf**.

---

## 8. ASIC akış sonuçları

### 8.1 Sentez karşılaştırması

Aynı yapılandırmayla iki koşum:

|  | main (kombinasyonel ROM) | SRAM | fark |
|---|---|---|---|
| örnek sayısı | 78.863 | **69.071** | −9.792 (**−%12,4**) |
| alan | 944.248 µm² | **851.902 µm²** | −92.346 µm² (**−%9,8**) |
| lint hatası | 0 | 0 | |
| sentez hatası | 0 | 0 | |

Kazanç beklenenden mütevazı. Sebebi: main'de ROM **zaten dörde bölünmüştü**, kolay kazanç önceden alınmıştı.

Not: FC ağırlıkları `npu_weights_pkg.sv` kaynak dosyasında hâlâ duruyor ama artık referans verilmediği için sentez eliyor. 92.346 µm²'lik düşüş tam olarak bu.

### 8.2 Fiziksel akış — hipotez doğrulandı

**Detailed routing üç geçişte de sıfır ihlalle tamamlandı:**

| Geçiş | İhlal seyri |
|---|---|
| `drt-run-0` | 39076 → 15461 → 13110 → 687 → 16 → **0** |
| `drt-run-1` | 10035 → 695 → 6 → **0** |
| `drt-run-2` | tamamlandı |

    soc_top.drc          0 bayt (yönlendirme DRC ihlali yok)
    Toplam kablo         7.320.455 µm
      met1               2.829.386 µm
      met2               2.622.040 µm
      met3               1.177.171 µm
      met4                 503.822 µm
      met5                  44.647 µm

**GDSII üretildi:**

    soc_top.gds          334 MB (Magic)
    soc_top.klayout.gds  186 MB (KLayout)

**IR drop mükemmel:**

    VPWR en kötü düşüm   1,80 mV  (1,8 V beslemede %0,1)
    VGND en kötü         1,41 mV

Raporun temel tezi — *"16 kB FC weight tablosu fiziksel yerleştirme ve routing tarafını zorlayarak akışın tamamlanmasını engelliyordu"* — **doğrulandı**. Bu adım daha önce bitmiyordu, şimdi 44 dakikada sıfır ihlalle bitti.

### 8.3 Zamanlama — yeni ve ciddi sorun

Saat kısıtı **20 ns (50 MHz)**.

| Köşe | İhlal | WNS |
|---|---|---|
| `nom_ff` (hızlı, −40°C, 1,95 V) | **0** | temiz |
| `nom_tt` (tipik, 25°C, 1,80 V) | 130 | **−4,00 ns** |
| `nom_ss` (yavaş, 100°C, 1,60 V) | 1000+ | **−18,76 ns** |

**Tipik köşede ihlallerin %93'ü NPU TCM SRAM'inden:**

    u_npu.u_npu_sram.g_sram     121 ihlal   en kötü −4,00 ns
    _124359_                      8 ihlal   en kötü −0,92 ns
    u_instruction_ram.g_sram      1 ihlal   en kötü −0,08 ns

**Sebep, yolun kenar yapısında:**

    Startpoint: u_npu.u_npu_sram.g_sram[3].u_macro
                (falling edge-triggered flip-flop clocked by clk_i)
    Endpoint:   _124166_ (rising edge-triggered)

SRAM makrosu **düşen kenarda** veri veriyor, hedef **yükselen kenarda** yakalıyor. Yani bu yolun tam çevrimi değil, **yarım çevrimi** var — 20 ns yerine 10 ns. sky130 SRAM makrosunun okuma erişim süresi bu bütçenin çoğunu yiyor.

    data arrival  27,38 ns
    data required 23,38 ns
    slack         −4,00 ns

**Bu, SRAM'e geçişin doğrudan bedeli.** Ağırlıklar ROM'dayken bu yol yoktu.

### 8.4 FPGA karşılaştırması

Vivado `nexys_top` routed raporu (20 Ağustos):

    WNS  +1,886 ns    TNS 0,000    başarısız uç 0/16874
    WHS  +0,021 ns    THS 0,000    başarısız uç 0/16874
    "All user specified timing constraints are met."

**Ama bu rapor SRAM değişikliğinden ÖNCEsine ait.** Ayrıca FPGA'de TCM, BRAM olarak sentezleniyor — Xilinx BRAM'i yükselen kenarda ve hızlı okur; sky130 SRAM makrosu düşen kenarda ve yavaş. Aynı RTL iki teknolojide çok farklı davranıyor.

FPGA implementasyonu yeni RTL ile tekrar koşulmalı.

### 8.5 Akışın durumu

Akış `KLayout.Render` adımında bir kez patladı:

    The layout has multiple top cells in Layout.top_cell

Bu kozmetik adım (düzenin PNG görüntüsü) ama LibreLane ölümcül sayıp çıktı. `--skip KLayout.Render` ile devam ettirildi.

**Bu rapor yazılırken:** Magic.WriteLEF → Magic DRC → KLayout DRC → SPICE çıkarımı → Netgen LVS koşuyor. DRC/LVS sonuçları henüz yok.

`multiple top cells` uyarısı ya zararsız (SRAM makro GDS'inin öksüz hücreleri) ya da gerçek bir yapısal sorun. **Ayrımı LVS yapacak.**

---

## 9. Sonuç ve öneri

### Kazanılan

- ASIC fiziksel akışı artık tamamlanıyor, GDSII üretiliyor
- −%12,4 hücre, −%9,8 alan
- Gerçek çipte çalışabilecek ağırlık yükleme zinciri
- Ağırlıksız başlatmaya karşı donanım koruması
- Doğrulama üç gizli hatayı yakalayacak kadar sıkılaştı

### Açık kalan

**1. Zamanlama (öncelikli).** Yavaş köşede tasarım 50 MHz'de çalışmaz. Tipik köşede de marj yok.

Öneri: **FC ağırlık okumasına bir çevrim daha vermek.** `FC_WEIGHT_WAIT` şu an SRAM çıkışını aynı çevrimde yakalıyor; araya bir yazmaç katmanı koymak yolu ikiye böler.

    Maliyet: FC döngüsünde +4000 çevrim (80.583 → 84.583, %5)
    Kazanç : kritik yol yarıya iner

%5 hız kaybı, imzalanabilir bir tasarım için ucuz. Ama RTL değişikliği demek, ASIC akışı bir kez daha koşmalı.

**2. DRC/LVS sonuçları** — akış bitince.

**3. FPGA yeniden implementasyon** — 20 Ağustos raporu artık geçerli değil.

### Talha'ya soru

`FC_WEIGHT_REQ`/`FC_WEIGHT_WAIT` yapısını sen kurdun. Araya üçüncü bir durum eklemek (`FC_WEIGHT_LATCH`) yerine daha zarif bir yol görüyor musun?

Örneğin ağırlık okumasını bir sonraki `fc_idx` için önceden başlatmak (prefetch): FC_MAC0 sırasında bir sonraki adresi vermek, FC_MAC3 bittiğinde veri hazır olsun. O zaman ek çevrim maliyeti olmaz ama FSM karmaşıklaşır ve sınır koşulları (ilk ve son eleman) dikkat ister.

---

## 10. Dosya değişiklikleri

| Dosya | Durum |
|---|---|
| `rtl/npu/npu_csr.sv` | `weights_ready` koruması |
| `rtl/npu/npu_compute_engine.sv` | SRAM okuması (değişmeden alındı) |
| `sw_nexys/src/bootloader.S` | ağırlık yükleme, 80 → 168 bayt |
| `sw_nexys/src/main.c` | TCM temizleme 7680 → 3584 |
| `scripts/gen_flash_image.py` | **yeni** — birleşik flash imajı |
| `tb/tb_soc_top.sv` | sınıf denetimi, flash.hex |
| `tb/npu_audio/tb_npu_audio.sv` | `CIKIS_TABAN` 4096 → 7584 |
| `tb/tb_npu_compute_engine.sv` | ağırlık geri yükleme |
| `scripts/run_regression.py` | `weights/` yolu, .mem dosyaları |
| `asic/scripts/check_filelist.py` | `runs/` dizinlerini atla |

Hepsi `npu-sram-entegrasyon` dalında, 5 commit. `main`'e henüz alınmadı — zamanlama sorunu çözülene kadar bekletiliyor.
