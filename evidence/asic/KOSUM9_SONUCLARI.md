# 9. Koşum Sonuçları

**Takım Arkhe — TEKNOFEST 2026 Çip Tasarım Yarışması**
Koşum: 25 Ağustos 2026, 05:55 → 10:50 (4s 55dk) · 78 adım · `77f4f9c`

---

## 0. Bir cümlede

**Setup problemi çözüldü** — tt köşelerinin üçü de artıda ve şimdiye kadarki
en iyi değerler. Karşılığında **hold kötüleşti** ve **anten geriledi**.

---

## 1. Bu koşumda değişenler

Beşi de tahmine değil, ölçüme dayanıyor.

| Değişiklik | Gerekçe | Commit |
|---|---|---|
| `set_driving_cell` saat portlarına uygulanmıyor | 7. koşumu çökerten modelleme hatası | `58a4c73` |
| `RSZ_CORNERS`'a `nom_ss` geri | Çıkarıldığında ss 11 ns kaybediyordu | `f72a423` |
| `MAX_TRANSITION_CONSTRAINT` 0,75 → 1,0 | 0,75 tt'de 2,2 ns yiyordu | `f72a423` |
| I-RAM / D-RAM 2×2 bloklara toplandı | Gruplar çipin tam genişliğine yayılmıştı | `91f0c96` |
| **`SYNTH_STRATEGY` `AREA 0` → `AREA 3`** | **9 strateji ölçüldü, en iyisi** | `77f4f9c` |

### Sentez stratejisi nasıl seçildi

LibreLane'in `synthesisexploration` akışıyla dokuz strateji koşuldu (sentez +
PnR öncesi STA, aynı SDC ve kısıtlarla):

| Strateji | nom_tt | nom_ss | Hücre |
|---|---|---|---|
| **AREA 3** | **+3,9027** | **−8,3425** | 106 460 |
| AREA 1 | +1,8766 | −9,9979 | 69 023 |
| AREA 0 *(önceki)* | +1,5024 | −9,3385 | 69 337 |
| DELAY 0 | +0,1556 | −14,2930 | 78 204 |
| DELAY 1 | −1,3889 | −15,4865 | ~78 000 |
| AREA 2 | −2,6410 | −12,7225 | 69 423 |

**Eksik ölçüm:** `DELAY 2/3/4` sonuçları alınamadı — keşif dizini bir
otomasyon hatasıyla silindi. `DELAY 0` (+0,16) ve `DELAY 1` (−1,39) `AREA 3`'ün
çok gerisinde kaldığı için DELAY ailesinin öne geçmesi beklenmiyor, **ama bu
bir varsayımdır, ölçüm değildir.**

`AREA 3`'ün adı yanıltıcı; kaynak kodda ORFS betiği çıkıyor:

```
strash / dch / map -B 0.9 / topo / stime -c
buffer -c -N {MAX_FANOUT_CONSTRAINT}
upsize -c / dnsize -c
```

Alan için eşliyor, sonra zamanlamayı **kapı boyutlandırmasıyla** düzeltiyor.
Hem daha büyük hem daha hızlı olmasının sebebi bu.

---

## 2. Dokuz köşe STA

| Köşe | Setup WNS | Karşılığı | Hold WNS | reg→reg hold ihlali |
|---|---|---|---|---|
| `min_ff_n40C_1v95` | +2,770 | 58,0 MHz | −0,226 | 96 |
| `nom_ff_n40C_1v95` | +2,439 | 56,9 MHz | −0,307 | 156 |
| `max_ff_n40C_1v95` | +2,061 | 55,7 MHz | **−0,396** | **306** |
| `min_tt_025C_1v80` | +1,751 | 54,8 MHz | −0,156 | 10 |
| `nom_tt_025C_1v80` | **+1,371** | **53,7 MHz** | −0,252 | 28 |
| `max_tt_025C_1v80` | **+0,915** | **52,4 MHz** | −0,360 | 90 |
| `min_ss_100C_1v60` | −5,281 | 39,6 MHz | −0,837 | 0 |
| `nom_ss_100C_1v60` | −6,665 | 37,5 MHz | −1,492 | 0 |
| `max_ss_100C_1v60` | **−8,026** | **35,7 MHz** | −2,163 | 1 |

**Okuma notu:** ss köşelerindeki büyük hold sayıları (−1,49 / −2,16)
kütükler arası **değildir** — `summary.rpt`'ın *"of which reg to reg"*
sütunu ss için 0 gösteriyor. Onlar giriş/çıkış yollarında ve SDC'deki I/O
gecikme modelimizden geliyor. Gerçek iç hold sorunu **ff köşelerinde**:
558 reg→reg ihlal (96 + 156 + 306).

---

## 3. Koşum karşılaştırması

| | 6. koşum | 8. koşum | **9. koşum** |
|---|---|---|---|
| **Setup nom_tt** | +0,947 | −1,300 | **+1,371** |
| **Setup max_tt** | +0,362 | −1,875 | **+0,915** |
| Setup nom_ss | −5,454 | −16,367 | −6,665 |
| Setup max_ss | −6,314 | −17,105 | −8,026 |
| **Hold reg→reg ihlal** | 12 | 109 | **687** |
| **Anten** | 23 ağ / 33 pin | **3 / 5** | 9 / 11 |
| Netgen LVS | geçti | geçti | **geçti** |
| KLayout DRC | 0 | 0 | **0** |
| XOR farkı | 0 | 0 | **0** |
| Yönlendirme DRC | 0 | 0 | **0** |
| Magic DRC | 7659 | 7659 | 7658 |
| Standart hücre | 204 730 | 215 958 | 244 104 |
| `repair_design` tamponu | — | 13 955 | **7 782** |
| Tel uzunluğu | 7,28 m | 8,04 m | 8,22 m |
| GRT ekstra iterasyon | — | 21/50 | 31/50 |
| Güç (tahmini) | 119,6 mW | 120,7 mW | 120,6 mW |

**Max slew / cap karşılaştırılamaz:** 8. koşum 0,75 ns sınırıyla 39 173
ihlal, 9. koşum 1,0 ns sınırıyla 22 667. Farklı ölçü birimleri. Kütüphanenin
kendi `max_transition` değeri 1,5 ns.

---

## 4. Hold neden kötüleşti

Mekanik ve öngörülebilirdi. `AREA 3`'ün `upsize -c` adımı kritik yollardaki
kapıları büyütüyor → veri **daha erken** varıyor → setup düzeliyor, **hold
bozuluyor**. Klasik takas.

İhlallerin köşelere dağılımı bunu doğruluyor: ff köşelerinde 558, ss'te 1.
Çip en hızlı olduğunda hold en zor.

Büyüklükler küçük (−0,25 … −0,40 ns), yani tampon eklemeyle kapatılabilir.
Ama hold **frekansla düzelmez** — çip soğukta ve yüksek gerilimde yanlış
değer yakalayabilir. Bırakılamaz.

---

## 5. ss'in en kötü yolu değişti — NPU değil, UART FIFO

8. koşumda ss'in en kötü yolu NPU'nun 32×32 requantization çarpmasıydı
(`d_out[0] → rq_ab[63]`, 152 hücre). **9. koşumda değil.**

```
Startpoint: _199485_  ->  u_uart2.u_rx_fifo.rd_ptr_r[0]
Endpoint:   _194461_  ->  u_uart2.u_rx_fifo.mem[25][0]
98 hücre, slack -8,026 ns
```

**En kötü sekiz bitiş noktasının tamamı** bu FIFO'nun `mem[...]` hücreleri:

```
-8.025902  _194461_   u_uart2.u_rx_fifo.mem[25][0]
-8.023651  _194466_   u_uart2.u_rx_fifo.mem[25][5]
-7.922544  _194850_   u_uart2.u_rx_fifo.mem[69][5]
-7.902925  _194846_
-7.899663  _194851_
-7.877558  _194462_
-7.874622  _194468_
-7.871174  _194847_
```

### Kök neden

`rtl/Cevre_Birimleri/files_1/sync_fifo.sv`:

```systemverilog
assign o_level = wr_ptr_r - rd_ptr_r;          // 9 bit cikarma
assign o_full  = (o_level == DEPTH[PTR_W:0]);  // 9 bit karsilastirma

always_ff @(posedge clk) begin
    if (i_wr_en && !o_full) begin              // <-- o_full burada
        mem[wr_ptr_r[PTR_W-1:0]] <= i_wr_data;
    end
end
```

Zincir: `rd_ptr_r` → çıkarma → karşılaştırma → `o_full` → **256×8 = 2048
flip-flop'un yazma izni**. FIFO derinliği 256 olduğu için bu, ASIC'te 2048
flop'luk bir dizinin enable ağacı demek.

nom_tt'nin en kötü yolu ise farklı: `u_instruction_ram.g_sram[2].u_macro →
u_core.id_stage_i.register_file_i.mem[851]` (82 hücre) — komut getirme yolu.

---

## 6. Üretilebilirlik

```
* Antenna
Failed  -  Pin violations: 11,  Net violations: 9

* LVS
Passed

* DRC
Failed  -  KLayout DRC errors: 0,  Magic DRC errors: 7658
```

**Magic DRC 7658:** üç koşumda tıpatıp 7659 iken bu koşumda bir azaldı.
Tamamen sabit olsaydı "tasarımdan bağımsız" derdik; bir birim oynaması
ihlallerin yerleşime **hafifçe** bağlı olduğunu gösteriyor. Yine de 106 bin
hücreli tamamen farklı bir sentez, farklı yerleştirme ve farklı yönlendirme
sonucunda sayının 7659 → 7658 gitmesi, gerçek bir geometri kusurundan çok
sistematik bir modelleme durumuna işaret ediyor.

**Kesinleştirme testi hâlâ yapılmadı:** `MAGIC_DRC_USE_GDS: true` ile DRC'yi
final GDS üzerinde koşmak. Şu an DEF görünümü üzerinden koşuyor (bkz.
`asic/README.md` §9.8).

**Anten 3/5 → 9/11 geriledi.** Sebebi muhtemelen +%13 hücre ve +%2 tel.
Yine de 6. koşumun 23/33'ünden belirgin iyi.

---

## 7. Kabul edilmeyen iddialar

Bu koşumla ilgili **söylenemeyecek** şeyler:

| İddia | Durum |
|---|---|
| "Tüm PVT köşelerinde zamanlama temiz" | **Hayır** — ss setup ve ff hold ihlalleri var |
| "DRC tamamen temiz" | **Hayır** — `manufacturability.rpt` FAIL diyor (Magic 7658) |
| "Anten temiz" | **Hayır** — 9 ağ / 11 pin |
| "Production-ready GDS" | **Hayır** — signoff açıkları var |
| "Güç 120,6 mW ölçüldü" | **Hayır** — VCD/SAIF kullanılmadı, tahmini değer |
| "50 MHz her koşulda sağlanıyor" | **Hayır** — tt ve ff'de sağlanıyor, ss'te 35,7 MHz |

Söylenebilecekler:

| İddia | Durum |
|---|---|
| RTL → GDS otomatik akış çalışıyor | Evet, `make asic_run` |
| 23 SRAM makrosu fiziksel olarak entegre | Evet |
| Netgen LVS temiz | Evet |
| KLayout GDS DRC temiz | Evet, 0 |
| XOR temiz | Evet, 0 |
| Yönlendirme DRC temiz | Evet, 0 |
| **50 MHz tipik köşede kapanıyor** | **Evet, +1,371 ns payla** |

---

## 8. Metodolojik sınır: SRAM Liberty modeli

Kullandığımız SRAM makrosunun PDK'da yalnızca **TT / 1,80 V / 25 °C** Liberty
modeli var. Aynı model ss ve ff analizlerinde de kullanılıyor.

Sonuç: standart hücreler üç gerçek PVT köşesiyle analiz edilirken **SRAM
gecikmesi ss'te iyimser, ff'te kötümser** modellenmiş oluyor.

Final raporda bu açıkça yazılmalı:

> Standart hücreler üç PVT köşesiyle analiz edilmiştir. Kullanılan SRAM
> makrosu için PDK'da yalnızca TT Liberty modeli bulunduğundan, SRAM
> zamanlaması diğer köşelerde TT modeli üzerinden değerlendirilmiştir.

Ayrıntı: `asic/README.md` §9.2.

---

## 9. Arşivlenen dosyalar

| Dosya | İçerik |
|---|---|
| `summary.rpt` | 9 köşe setup/hold/DRV özeti |
| `metrics.json` | Tüm akış metrikleri |
| `manufacturability.rpt` | Anten / LVS / DRC sonucu |
| `anten_ozeti.rpt` | İhlalli anten ağları |
| `kritik_yol_nom_tt.rpt` | En kötü 30 setup yolu (tipik köşe) |
| `kritik_yol_max_ss.rpt` | En kötü 30 setup yolu (en yavaş köşe) |
| `hold_yollari_max_ff.rpt` | En kötü 30 hold yolu (en hızlı köşe) |

Yol raporları en kötü 30 yola kırpıldı (ham hâlleri 13–17 MB idi).
