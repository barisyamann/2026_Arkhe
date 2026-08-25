# 7. Koşum: Saat Sürücü Modeli Hatası ve Sonuçları

**Takım Arkhe — TEKNOFEST 2026 Çip Tasarım Yarışması**
Tarih: 25 Ağustos 2026 · Koşum: 7 (24 Ağu 19:42 → 25 Ağu 00:33, 4s 51dk)

---

## 0. Özet

7. koşum **ilk kez baştan sona tamamlandı** — 117 adımın tamamı koştu, GDS
üretildi, LVS geçti.

Fiziksel kalite belirgin şekilde iyileşti. **Zamanlama ise ciddi biçimde
geriledi** ve sebebi bir modelleme hatasıydı: `set_driving_cell` saat
portlarına da uygulanmıştı.

| | 6. koşum | 7. koşum |
|---|---|---|
| Anten ihlali | 23 ağ / 33 pin | **6 ağ / 6 pin** ✅ |
| Netgen LVS | geçti | **geçti** ✅ |
| KLayout DRC | 0 | **0** ✅ |
| Yönlendirme DRC | 0 | **0** ✅ |
| Magic DRC (`nwell.4`) | 7659 | 7659 |
| **nom_tt setup WNS** | **+0,947** | **−0,763** ❌ |
| **max_ss setup WNS** | −6,314 | **−17,081** ❌ |
| max_ff hold reg→reg | 8 | **70** ❌ |

---

## 1. Kök neden: saat portuna sürücü modeli verilmesi

### Yapılan hata

6. koşum analizinde `design.sdc`'de `set_driving_cell` bulunmadığı tespit
edilmiş ve şu satır eklenmişti:

```tcl
set_driving_cell -lib_cell sky130_fd_sc_hd__inv_2 -pin Y [all_inputs]
```

`[all_inputs]` **saat portlarını da içerir.** `clk_i` ve `jtag_tck` bu
modelle sürüldü.

### Neden yanlış

`sky130_fd_sc_hd__inv_2` küçük, iç kullanım için tasarlanmış bir evirici.
Saat giriş ağı 0,562 pF yük taşıyor. Bu yükü `inv_2` ile sürmek gerçekçi
olmayan bir kenar üretiyor:

| Nokta | 6. koşum | 7. koşum |
|---|---|---|
| `clkbuf_0_clk_i/A` (nom_tt) | 1,61 ns | **2,99 ns** |
| `clkbuf_0_clk_i/A` (nom_ss) | — | **4,24 ns** |

Gerçekte saat, harici bir osilatörden ya da güçlü bir pad sürücüsünden
gelir; küçük bir iç evirici gibi davranmaz.

### Nasıl yayıldı

Bozukluk yalnızca raporu etkilemedi. **CTS saat ağacını bu modele göre
kurdu.** Yavaş kök kenarı ağaç boyunca birikti ve saat çarpıklığı (skew)
büyüdü:

| Köşe | 6. koşum skew | 7. koşum skew | Değişim |
|---|---|---|---|
| nom_ff | −0,884 | −0,972 | +%10 |
| nom_tt | −1,179 | **−1,663** | **+%41** |
| nom_ss | −1,823 | **−3,012** | **+%65** |
| max_ss | −1,945 | **−3,146** | **+%62** |

**Bozulmanın köşeye göre dağılımı teşhisi kanıtlıyor:** ff köşesinde saat
hızlı, kenar zaten keskin, etki az (%10). ss köşesinde saat yavaş, kenar
4,24 ns'ye çıkıyor, etki büyük (%65). Sebep-sonuç ilişkisi bu örüntüde
açıkça görünüyor.

Skew arttıkça hem setup hem hold birlikte bozulur — 7. koşumda ikisi de
bozuldu.

### Düzeltme

```tcl
set veri_girisleri [all_inputs]
foreach saat_portu [list $clk_port jtag_tck] {
    set idx [lsearch $veri_girisleri [get_ports $saat_portu]]
    if {$idx >= 0} { set veri_girisleri [lreplace $veri_girisleri $idx $idx] }
}

set_driving_cell -lib_cell sky130_fd_sc_hd__inv_2 -pin Y $veri_girisleri
set_input_transition 0.15 [get_ports $clk_port]
set_input_transition 0.15 [get_ports jtag_tck]
```

Veri girişleri sürücü modelini korur; saat girişlerine doğrudan geçiş
süresi bildirilir. `0,15 ns` değeri yukarıdaki `set_clock_transition` ile
aynı tutulmuştur.

Commit: `58a4c73`.

---

## 2. Aynı koşumda doğrulanan kazanç: SDC tasarım kuralı kısıtları

Saat hatası zamanlamayı bozarken, **6. koşumda tespit edilen SDC eksikliği
düzeltmesi çalıştı ve etkisi büyük.**

Karşılaştırmayı **aynı sınırla** yapmak şart. 6. koşumda tasarım düzeyi
`max_transition` kısıtı yoktu; STA kütüphanenin kendi sınırını (**1,5 ns**)
kullanıyordu. 7. koşumda `set_max_transition 0,75` geçerli — LibreLane'in
sky130 varsayılanı, kütüphane sınırından iki kat sıkı.

**1,5 ns sınırıyla ölçülen gerçek ihlal sayısı:**

| Köşe | 6. koşum | 7. koşum | Değişim |
|---|---|---|---|
| nom_tt | 1842 | **159** | **−%91** |
| nom_ss | 9183 | **4505** | **−%51** |

Ham sayılardaki artış (11 354 / 36 181) tamamen sınır değişiminden
kaynaklanıyor, tasarımın kötüleşmesinden değil.

**Ders:** iki koşumun tasarım kuralı sayıları, kısıtlar aynı olmadıkça
doğrudan karşılaştırılamaz. Final raporda her iki sınırdaki sayı ayrı ayrı
verilmelidir.

---

## 3. Anten: 23 → 6

Bu koşumun tartışmasız kazancı.

| | 6. koşum | 7. koşum |
|---|---|---|
| İhlalli ağ | 23 | **6** |
| İhlalli pin | 33 | **6** |

Ayrıca `81-odb-diodesonports` adımı devreye girdi ve ayrıntılı yönlendirme
üç anten onarım turu koştu; her turdan sonra yeniden yönlendirme yapıldı ve
**yönlendirme DRC ihlali sıfırda kapandı**.

Anten ayarlarına bu koşumda dokunulmadı — kazanç, fanout gevşetmesinin
sağladığı yönlendirme rahatlığından geliyor.

---

## 4. Fanout gevşetmesi: GRT çöküşünün çözümü

7. koşumun ilk denemesi global yönlendirmede düştü:

```
[GRT-0116] Global routing finished with congestion.
```

50 ekstra iterasyon tükendi. Sebep bizim kendi düzeltmemizdi: SDC kısıtları
`repair_design`'a 1576 fanout ihlali buldurdu ve **18 430 tampon** ekletti.
6. koşumda kısıt yoktu, GRT kullanımı %14,4 / overflow 0 idi.

`MAX_FANOUT_CONSTRAINT` 10 → 20 yapıldı:

| | fanout 10 | fanout 20 |
|---|---|---|
| Fanout ihlali | 1576 | **974** (−%38) |
| Eklenen tampon | 18 430 | **13 955** (−%24) |
| GRT ekstra iterasyon | **50/50 → çöktü** | **21/50 → geçti** |
| Yönlendirme talebi (3D) | 3 846 952 | **3 398 113** (−%12) |

Kazancın esası korundu: `set_max_transition` ve `set_max_capacitance`
değişmedi ve slew/cap'i doğrudan hedeflemeye devam ediyor. 20 sınırı,
sorunun kaynağı olan ~150 yüklü reset dallarına göre hâlâ **7,5 kat**
iyileşme.

---

## 5. `PL_TIMING_DRIVEN` denendi, araç hatası verdi

```
[INFO GPL-0100] Timing-driven iteration 1/2, virtual: false.
[CRITICAL RSZ-2007] buffering pin _061835_/X: wire step options empty
```

OpenROAD boyutlandırıcısının iç hatası. `false`'a alındı; ayrıntı
`asic/README.md` bölüm 9.9.

---

## 6. `nwell.4`: 7659, değişmedi

İki koşumda **tıpatıp aynı sayı**. Bu, hipotezi güçlendiriyor: sorun
tasarıma bağlı değil, **sistematik bir modelleme durumu**. 6. koşum
analizinde ölçülmüştü ki ihlal şeritlerinin %87,3'ünde tap hücresi var.

Belirleyici test hâlâ aynı: `MAGIC_DRC_USE_GDS: true` ile DRC'yi GDS
üzerinde koşmak.

---

## 7. Diğer ölçümler

| | 6. koşum | 7. koşum |
|---|---|---|
| Standart hücre | 204 730 | 215 945 |
| Toplam örnek | 2 080 015 | 2 076 459 |
| Tel uzunluğu | 7 277 840 µm | 8 025 389 µm (+%10) |
| Güç | 119,6 mW | 120,7 mW |
| Yönlendirme DRC | 0 | **0** |

Tel uzunluğundaki %10 artış eklenen tamponlardan; güç neredeyse değişmedi.

---

## 8. 8. koşum

Tek değişiklik: **saat sürücü modeli düzeltmesi** (`58a4c73`).

Tek değişkenle koşulması bilinçli — 7. koşumda birden fazla ayar aynı anda
değişti ve etkileri ayırt etmek için skew örüntüsüne bakmak gerekti.

**Beklenti:** saat çarpıklığı 6. koşum seviyesine dönerse (nom_tt ~−1,18)
setup ve hold da o seviyeye dönmeli; üzerine post-GRT hold onarımı ve SDC
kısıtlarının kazancı eklenmeli.

**Doğrulanacak:**
- nom_tt setup WNS ≥ 0 (6. koşum: +0,947)
- max_ff hold reg→reg ihlal = 0 (6. koşum: 8)
- Anten ≤ 6 ağ
- LVS geçti, KLayout DRC 0
- 1,5 ns sınırında slew ihlali ≤ 159 (nom_tt)
