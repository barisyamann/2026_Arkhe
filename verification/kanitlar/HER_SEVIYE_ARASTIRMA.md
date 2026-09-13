# Her seviyede araştırma: RTL, makro, akış ayarları
# (11 Eylül 2026, K_diyot üzerinde ölçüldü)

Kullanıcı isteği: "RTL, makro, koşu configleri — her şeyi değiştir ve
ne yapılabilir araştır, bir yere odaklanma."

Kısıt: **Şartname 46 KB bellek dayatıyor** (NPU 30 KB + I-RAM 8 KB +
D-RAM 8 KB). Makro sayısı azaltılamaz.

# 1. ELENEN YOLLAR (ölçüldü veya kısıtla çelişiyor)

## 1.1 Saat hızını düşürmek — ÖLÇÜLDÜ, ÇÖZMÜYOR

K_diyot layout'unda yalnız imza periyodu değiştirildi:

    23 ns (43,5 MHz) -> 3.336 slew ihlali
    50 ns (20 MHz)   -> 3.336
    100 ns (10 MHz)  -> 3.336

Periyot dört katına çıktı, ihlal **hiç değişmedi**. Slew/cap/fanout
zamanlama değil, elektriksel yük kısıtıdır.

## 1.2 Makro sayısını azaltmak — ŞARTNAME ENGELLİYOR

TCM yerleşimi ölçüldü:

    0    ..  489   girdi tensörü      490 kelime
    490  .. 3583   SERBEST           3094 kelime  (%40 boş)
    3584 .. 7583   FC ağırlıkları    4000 kelime
    7596 .. 7599   çıkış                4 kelime

Gerçek kullanım 4.494 kelime; 7.680'in %40'ı boş. Ağırlıklar 490'dan
başlasa 9 makro yeterdi (15 yerine) — 6 makro tasarrufu.

**ANCAK** şartname 30 KB NPU belleği şart koşuyor. 7.680 kelime x
32 bit = 30.720 bayt = 30 KB. Boşluk şartname gereğidir, israf değil.
Bu yol KAPALI.

## 1.3 Farklı makro kullanmak — SEÇENEK YOK

`asic/macros/` ve PDK tarandı: yalnızca
`sky130_sram_2kbyte_1rw1r_32x512_8` mevcut. Alternatif SRAM makrosu
bulunmuyor.

## 1.4 Makro max_transition'ı SDC ile büyütmek — GEÇERSİZ

Liberty karakterizasyon aralığı:

    index_1 (geçiş) : "0.00125, 0.005, 0.04"
    index_2 (yük)   : "0.00172, 0.00689, 0.02756"

0,04 ns ve 0,0276 pF **modelin geçerlilik sınırıdır**. Ötesine
ekstrapolasyon güvenilmez sayı üretir. Daha önce denendi ve geri
alındı.

# 2. YENİ BULGU: MUX ZİNCİRİ SÜRÜCÜ GÜCÜ

## 2.1 Kritik yol dökümü (max_ss, ölçüldü)

    SRAM dout çıkışı .......... 15,991 ns
    _097713_ mux2_2 ........... +2,100
    _097714_ mux2_2 ........... +2,236
    _097715_ mux2_2 ........... +2,589
    _097723_ mux2_2 ........... +3,184
    _097724_ a22o_2 ........... +0,870
      MUX ZİNCİRİ ............. 10,979 ns  (veri yolunun %91'i)
    hold buffer ............... +1,084
    hedef D girişi ............ 28,054 ns

## 2.2 Slew zincir boyunca BÜYÜYOR

Mux girişlerindeki geçiş süreleri:

    _097713_/A0 : 0,140 ns
    _097714_/A1 : 0,480 ns
    _097715_/A1 : 1,875 ns
    _097723_/A0 : 0,845 ns
    _097724_/B1 : 1,695 ns

Her kademe bir sonrakine daha kötü sinyal veriyor — yük zincirleme
birikiyor.

## 2.3 Tel gecikmesi SUÇLU DEĞİL

NPU'nun 15 makrosu 4x6 ızgarada yayılmış; en uzak iki makro arası
3.231 um. sky130 met3 için ~0,1 ns/mm ile bu **0,32 ns** eder.

10,979 ns'lik zincirin yalnızca %3'ü. Sorun mesafe değil, **mantık
derinliği ve sürücü gücü**.

## 2.4 KULLANILABİLİR AMA KULLANILMAYAN HÜCRELER

Kütüphanede mevcut:

    sky130_fd_sc_hd__mux2_1
    sky130_fd_sc_hd__mux2_2   <- tasarım BUNU kullanıyor
    sky130_fd_sc_hd__mux2_4
    sky130_fd_sc_hd__mux2_8

`no_synth.cells` kontrol edildi: yalnızca `mux2i` (ters çıkışlı)
yasaklı, normal `mux2` serbest. Yani `mux2_4`/`mux2_8` kullanılabilir
ama sentez seçmemiş — çünkü sentez aşamasında gerçek yerleşim yükü
bilinmiyor.

# 3. UYGULANABİLİR ADAYLAR

## A) Mux sürücülerini güçlendirmek  (YENİ, denenmedi)

Kritik yoldaki dört `mux2_2`'yi `mux2_4` veya `mux2_8` yapmak.

Yollar:
  1. **Resizer'a bırakmak:** `RSZ_DONT_TOUCH_RX` boş ve resizer bu
     hücreleri büyütebilir. Ama `RUN_POST_GRT_DESIGN_REPAIR: false`
     yaptığımız için o fırsat kaçıyor olabilir.
  2. **RTL'de açık mux ağacı yazmak:** Sentezin ürettiği yapı yerine
     elle iki kademeli ağaç kurmak (önce 4'lü gruplar, sonra gruplar
     arası). Her kademe daha dar, sürücü seçimi kontrollü.
  3. **Sentez ayarı:** `SYNTH_SIZING` veya buffer/sizing ile ilgili
     ayarlar incelenmeli.

Tahmini kazanç: zincirin %91'ini hedefliyor; kademe başına 2-3 ns'lik
gecikmenin bir kısmı kazanılabilir.

Risk: daha büyük hücreler daha çok alan ve güç. Utilization %49,5
olduğu için alan sorun değil.

## B) N_surucu koşusu  (ŞU AN KOŞUYOR)

    MAX_FANOUT_CONSTRAINT   16 -> 8
    PL_TARGET_DENSITY_PCT   45 -> 40

Adım 12 ölçümü: slew 41.045 -> 22.526. Ama bu SENTEZ aşaması;
imza değeri (adım 56) beklenmelidir. K'da sentez 41.045 iken imza
16.442 olmuştu — aşamalar ters yönde değişiyor.

## C) Anten diyotu sayısını azaltmak

Slew ihlallerinin %55'i (1.844 pin) anten diyotlarında. K_diyot'ta
12.155 diyot var (C_kapanis'te 10.125) — `DIODE_ONLY` stratejisinin
bedeli.

Adaylar: `GRT/DRT_ANTENNA_REPAIR_ITERS` azaltmak, `RT_MAX_LAYER`
gözden geçirmek.

**RİSK YÜKSEK:** Anten ihlalleri şu an 0/0. Diyot azaltmak bunu
bozabilir ve anten ihlali imalat riskidir — slew'den çok daha ciddi.

## D) Saat ağacı cap ihlalleri

En kötü iki cap ihlali saat buffer'larında:

    clkbuf_1_1_1_clk_i/X   limit 0,59  gerçek 1,14
    clkbuf_1_0_1_clk_i/X   limit 0,59  gerçek 1,06

`CTS_SINK_CLUSTERING_SIZE` küçültmek veya `CTS_CLK_BUFFERS`'a daha
büyük buffer eklemek.

Risk: orta. Saat ağacı değişiklikleri skew'i ve dolayısıyla
setup/hold'u etkiler — ikisi de şu an 9/9 pozitif, bozulmamalı.

## E) Makro Liberty'sini yeniden karakterize etmek

En doğru çözüm, gün mertebesinde iş. OpenRAM karakterizasyon akışı
gerektirir.

# 4. KAPATILABILIRLIK ANALİZİ

| İhlal | Makro kaynaklı | Müdahale edilebilir |
|---|---:|---:|
| Slew 3.336 | 506 (%15) | 2.830 (%85) |
| Cap 450 | 139 (%31) | 311 (%69) |
| Fanout 81 | - | 81 (%100) |
| Magic DRC 7.658 | 7.658 (%100) | 0 |

Magic DRC dışındakilerin çoğunluğu teorik olarak müdahale edilebilir.
Ama "müdahale edilebilir" ile "kolayca sıfırlanır" aynı şey değil:
anten diyotları (slew'in %55'i) kendi çözümümüzün bedeli ve
azaltmak başka risk doğuruyor.

# 5. ÖNERİLEN SIRA

1. **N_surucu sonucunu bekle** (koşuyor) — fanout ve density
   ayarlarının imza etkisini ölç.
2. **(A) Mux sürücü güçlendirme** — kritik yolun %91'ini hedefliyor,
   yeni ve denenmemiş. Önce RTL'de açık mux ağacı denemesi yapılabilir;
   NPU testleriyle doğrulanmalı.
3. **(D) Saat ağacı** — dikkatli, setup/hold korunmalı.
4. **(C) Anten** — en son, risk yüksek.
5. **(E) Liberty** — yukarıdakiler yetmezse.

# 6. DÜRÜST ÇERÇEVE

Bu ihlaller **imalatı engellemiyor**. Kritik denetimler temiz:

    LVS ................... Circuits match uniquely
    KLayout imza DRC ...... 0
    Yönlendirme DRC ....... 0
    Anten ................. 0 / 0
    Setup/hold (9 köşe) ... pozitif

Slew/cap/fanout uyarı seviyesi göstergelerdir: "bu pin ideal olandan
yavaş geçiş yapıyor". Zamanlama zaten dokuz köşede karşılandığı için
bu yavaşlık tolere edilmiş durumdadır.

C_kapanis'te de aynı kalemler vardı (17.065 / 1.911 / 66) ve o koşu
teslim edilebilir sayılmıştı. K_diyot slew'de daha iyidir (16.442).

---

# 7. N_surucu SONUCU: BASARISIZ — ölçülmüş ders

    MAX_FANOUT_CONSTRAINT   16 -> 8
    PL_TARGET_DENSITY_PCT   45 -> 40

Koşu adım 39'da `[GRT-0116] Global routing finished with congestion`
ile öldü.

## Ölçülen sebep

| | K_diyot | N_surucu |
|---|---:|---:|
| Yönlendirme kullanımı | %18,72 | **%24,60** |
| Taşma (H/V/toplam) | 0/0/0 | **0/2/8** |
| Hücre sayısı (adım 32) | 238.684 | **245.191** |

Fanout limitini 16'dan 8'e indirmek sentezi **6.507 ek tampon**
koymaya zorladı. Yönlendirme kaynağı %31 arttı ve tıkandı.

Yoğunluğu 45'ten 40'a düşürmek bunu telafi etmedi — iki ayar TERS
yönde çalıştı: biri hücre sayısını artırdı, diğeri yerleştirme
alanını daralttı.

## Ders

Adım 12'de slew 41.045 -> 22.526 görüp "%45 iyileşme" demiştim.
Bu **erken bir yorumdu**: sentez aşamasındaki kazanç yönlendirmeye
taşınmadı, aksine tıkanıklık üretti.

Bir ayarın etkisi TEK BİR AŞAMADA ölçülemez; akışın tamamı
görülmelidir.

## Bundan sonra

`MAX_FANOUT_CONSTRAINT` düşürme yolu KAPALI. Fanout ihlallerini
azaltmak için tampon eklemek, tıkanıklık pahasına geliyor.

Alternatif: fanout ihlallerinin %72'si zaten marjinal (17-19, limit
16). Bunları kapatmaya çalışmanın maliyeti kazancından büyük.

Kalan adaylar (2. bölümdeki A, D, E) hâlâ geçerli ama A (mux sürücü
güçlendirme) artık daha dikkatli kurulmalı: hücre büyütmek de alan
ve yönlendirme baskısı yaratır.
