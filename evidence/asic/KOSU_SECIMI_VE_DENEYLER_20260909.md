# Final ASIC koşusuna nasıl gelindi — ölçümler ve kararlar

**9 Eylül 2026**

Bu belge teslim edilen fiziksel tasarımın (`d45_anten2`) neden seçildiğini,
hangi alternatiflerin denendiğini ve her denemenin **ölçülmüş** sonucunu
kaydeder. Amaç, "neden bu koşu" sorusunun cevabını tahminle değil sayıyla
vermektir.

Denemelerin ham çıktıları (metrics.json, dokuz köşe STA özeti, kullanılan
config) sunucuda `~/deney_ozet_20260909/` ve `~/slew40_ozet/` altında
arşivlenmiştir. Koşu dizinleri disk yeri için silinmiştir; özetler korunur.

---

## 1. Teslim edilen koşu: `d45_anten2`

| Ölçüt | Değer |
|---|---:|
| Yönlendirme DRC | 0 |
| KLayout DRC | 0 |
| Anten ihlali (net / pin) | 0 / 0 |
| LVS (LEF/DEF) | Circuits match uniquely |
| LVS (GDS kaynaklı) | Circuits match uniquely |
| XOR | 0 |
| PDN ihlali | 0 |
| **Hold** | **9/9 köşe pozitif, 0 ihlal** |
| Setup @ 20 ns (özgün) | 115 ihlalli yol, WNS −1,8149 ns |
| **Setup @ 23 ns (ek analiz)** | **9/9 köşe pozitif, 0 ihlal** |
| Slew / kapasite / fanout | 19.341 / 1.888 / 11 |
| Magic DRC | 7.658 (tamamı `nwell.4`) |

Belirleyici ayar: `DRT_ANTENNA_REPAIR_JUMPER_ONLY: false`. Bu, yönlendiricinin
anten onarımında yalnızca jumper değil **diyot** da eklemesine izin verir ve
anten ihlallerini 2.246'dan 0'a indirmiştir. Dört ayrı koşuda doğrulanmıştır.

---

## 2. Denenen alternatifler

Slew ihlallerini (19.341) kapatmak için üç koşu yapıldı. **Üçü de teslim
edilen koşudan daha kötü sonuç verdi** ve bu yüzden kullanılmadı.

### 2.1 `slew40` — periyot 25 ns + gevşetilmiş geçiş eşiği

**Hipotez:** PnR hedefi 20 ns'den 25 ns'ye çıkarılırsa zamanlama baskısı
azalır, sürücüler rahatlar ve slew düşer.

**Değişen:** `CLOCK_PERIOD` 20 → 25 ns, `MAX_TRANSITION_CONSTRAINT` 0,75 → 1,2 ns

**Sonuç:**

| Ölçüt | d45_anten2 | slew40 |
|---|---:|---:|
| Slew ihlali | 19.341 | **23.221** |
| Kapasite ihlali | 1.888 | **2.208** |
| Setup WNS | −1,8149 | **−7,8147** |
| Setup ihlal | 115 | **4.103** |
| Hold ihlal | **0** | **6** |

**Neden başarısız:** Daha gevşek periyot, CTS'i daha yavaş bir saat ağacı
kurmaya itti. En kötü yolda veri varış 38,09 ns, gerekli 30,28 ns; saat
ağacındaki 20 tampon tek başına ~10 ns tüketiyordu. Kazanılan zamanı saat
ağacı yedi ve üstüne çıktı.

### 2.2 `kosuA` — eşik kütüphane sınırına çekildi

**Hipotez:** sky130'un kendi `.lib` dosyasında `default_max_transition: 1.5`
yazıyor. Bizim 0,75 ns eşiğimiz kütüphanenin izin verdiğinin yarısı; gerçek
sınıra çekilirse ihlallerin çoğu kapanmalı.

Bu hipotezi destekleyen ölçüm vardı — 19.341 ihlalin yalnızca **2.902'si**
1,5 ns'yi aşıyordu, geri kalanı kütüphanenin kabul ettiği hücrelerdi.

**Değişen:** yalnızca `MAX_TRANSITION_CONSTRAINT` 0,75 → 1,5. Diğer her ayar
d45_anten2 ile birebir aynı.

**Sonuç:**

| Ölçüt | d45_anten2 | kosuA |
|---|---:|---:|
| Slew ihlali | 19.341 | 19.314 |
| **Ortalama slew** | **1,10 ns** | **1,95 ns** |
| Kapasite ihlali | **1.888** | 2.690 |
| Fanout ihlali | **11** | 46 |
| Setup ihlal | **115** | 4.020 |
| Hold ihlal | **0** | **35** |

**Neden başarısız — bu deneyin asıl öğrettiği şey:** Eşik yalnızca bir *ölçüt*
değil, aynı zamanda `repair_design`'ın *hedefidir*. Gevşetince onarıcı "1,5 ns
yeterli" diye daha zayıf sürücüler bıraktı; gerçek slew değerleri 1,10'dan
1,95 ns'ye **çıktı**. İhlal sayısı neredeyse aynı kaldı çünkü tasarım da
eşikle birlikte kötüleşti.

### 2.3 `kosuC` — eşik 1,5 + agresif DRV onarımı

**Hipotez:** Eşik gevşetmesi tek başına yetmiyorsa, onarıcıyı daha çok tampon
eklemeye zorlamak gerekir.

**Değişen:** `MAX_TRANSITION_CONSTRAINT` 1,5 · `DESIGN_REPAIR_MAX_SLEW_PCT`
20 → 40 · `DESIGN_REPAIR_MAX_CAP_PCT` 20 → 40 ·
`GRT_DESIGN_REPAIR_MAX_SLEW_PCT` 10 → 30 · `GRT_DESIGN_REPAIR_MAX_CAP_PCT`
10 → 30

**Sonuç:**

| Ölçüt | d45_anten2 | kosuC |
|---|---:|---:|
| Slew ihlali | 19.341 | **7.414** |
| **Ortalama slew** | **1,10 ns** | **1,99 ns** |
| Kapasite ihlali | **1.888** | 2.270 |
| Setup ihlal | **115** | 4.512 |
| Hold ihlal | **0** | **51** |
| Yönlendirme DRC | 0 | 0 |
| Anten ihlali | 0 | 0 |

**Neden başarısız:** Slew ihlal *sayısı* 7.414'e düştü ama bu yanıltıcıdır —
ortalama slew 1,99 ns, yani gerçek geçiş süreleri d45_anten2'den **daha
kötü**. Sayı düştü çünkü ölçüt gevşedi, tasarım iyileşmedi. Ayrıca eklenen
tamponlar hold'u bozdu: 9/9 temizlik kayboldu, 51 ihlal çıktı.

---

## 3. Karar

`d45_anten2` **üç ölçütte birden üstün**: en düşük ortalama slew (1,10 ns),
en az kapasite ve fanout ihlali, ve tek temiz hold (9/9, 0 ihlal).

Hold temizliği belirleyici oldu. Hold ihlali silikonda **düzeltilemez** bir
hatadır — çip yanlış çalışır ve yazılımla telafi edilemez. Setup ihlali ise
saati yavaşlatarak aşılabilir. Bu yüzden 19.341 slew ihlaliyle yaşamayı,
hold'u riske atmaya tercih ettik.

---

## 4. Slew hakkında ölçülen gerçekler

Kapatılamamış olması bir eksiktir; ancak nedenleri ölçülmüştür.

**Eşik kütüphane sınırının yarısı.** sky130 `.lib` içinde
`default_max_transition: 1.5`; bizim SDC 0,75 ns dayatıyor. İhlallerin
dağılımı:

| Gerçek slew | Adet |
|---|---:|
| Toplam (0,75 eşiğiyle) | 19.341 |
| > 1,0 ns | 7.679 |
| > 1,5 ns (kütüphane sınırı) | 2.902 |

**Şiddet düşük.** 13.464 ihlal (%70) sınırın yalnızca 0–0,25 ns üstünde;
sadece 56 tanesi 2 ns'den fazla aşıyor.

**Köşeye bağımlı.** max_ss'de 19.341, ff köşesinde 3.048 — 6 kat fark.
Yapısal bir bozukluk olsaydı her köşede benzer çıkardı.

**%20'si anten diyotu.** 6.380 diyotun 3.806'sı ihlal listesinde. Anten
ihlallerini 2.246'dan 0'a indiren çözüm, her diyot nete kapasite eklediği
için slew'i kötüleştirdi. Bu bilinçli bir **takastır**, hata değil.

**2.245'i SRAM makro pinlerinde.** SRAM'in kendi `.lib` dosyasında
`max_transition: 0.5` yazar; bu sınır SDC'den değiştirilemez, makronun
karakterizasyonundan gelir.

---

## 5. İmzalama periyodu

Özgün koşu 20 ns hedefiyle imzalandı ve üç SS köşesinde 115 ihlalli yol
verdi. Bu raporlar `asic/reports/timing/` altında **değiştirilmeden**
korunmaktadır.

Layout'a hiç dokunmadan, aynı netlist ve parazitiklerle periyot taraması
yapıldı:

| Periyot | Setup WNS (max_ss) | İhlalli yol |
|---:|---:|---:|
| 20,0 ns | −1,8149 ns | 115 |
| 22,0 ns | −0,4190 ns | 3 |
| 22,5 ns | −0,1691 ns | 1 |
| **23,0 ns** | **+0,0810 ns** | **0** |
| 24,0 ns | +0,5809 ns | 0 |

23 ns (43,5 MHz) periyotta setup 9/9 köşede pozitif, hold 9/9 pozitif.

Tarama gerekliydi: WNS −1,8149 olduğu için 22 ns hesapla yeterli
*görünüyordu*, ancak ölçüm −0,419 verdi. En kötü yolun kayması tek başına
belirleyici değildir; ara yollar da hesaba girer. Tahminle yetinilmedi.

Ayrıntı: `asic/reports/timing_23ns/`

---

## 6. Arşivlenen ham veriler

Sunucuda korunan özetler:

```
~/deney_ozet_20260909/kosuA/   metrics.json, summary.rpt, config_A_libsinir.yaml
~/deney_ozet_20260909/kosuC/   metrics.json, summary.rpt, config_C_agresif.yaml
~/slew40_ozet/                 summary.rpt, drt_ihlal.txt, config_slew40.yaml
```

Her koşunun dokuz köşe STA özeti ve kullanılan tam yapılandırması bu
dizinlerdedir. Koşu ağaçları (her biri 11–16 GB) disk yeri için silinmiş,
karar için gereken tüm sayılar korunmuştur.
