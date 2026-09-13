# Hold ihlali — kök neden analizi ve çözümü

**Tarih:** 12–13 Eylül 2026
**Koşular:** `S_final` (sorunlu) → `S_cts` (CTS düzeltmesi, yetersiz)
→ `S_hold` (marj 1,2, sıkıştı) → **`S_hold2` (çözüm)**

Bu belge iki aşamalı bir teşhisi anlatır. Birinci aşamada saat ağacı
asimetrisi bulundu ve düzeltildi; **yetmedi**. İkinci aşamada asıl
kısıtın hold onarım marjı olduğu ölçülerek bulundu. Süreç boyunca
iki yanlış teşhis yapıldı ve ikisi de ölçümle düzeltildi — bunlar
son bölümde açıkça listelenmiştir.

---

## Belirti

`S_final` koşusunda imzalama STA'sı (23,148 ns, dokuz köşe) şunu verdi:

| Köşe | Hold WNS | Hold TNS | İhlal |
|---|---:|---:|---:|
| nom_tt_025C_1v80 | **−0,2580** | −3,91 | 42 |
| nom_ss_100C_1v60 | +0,2364 | 0,00 | 0 |
| nom_ff_n40C_1v95 | **−0,3066** | −12,12 | 77 |
| min_tt_025C_1v80 | **−0,0363** | −0,04 | 1 |
| min_ss_100C_1v60 | +0,4659 | 0,00 | 0 |
| min_ff_n40C_1v95 | **−0,1302** | −1,52 | 29 |
| max_tt_025C_1v80 | **−0,4805** | −19,33 | 79 |
| max_ss_100C_1v60 | +0,0009 | 0,00 | 0 |
| max_ff_n40C_1v95 | **−0,5005** | −34,01 | 151 |

**Setup tarafı sorunsuzdu:** 9/9 pozitif, TNS sıfır, en kötü +0,3188 ns.
Route DRC 0, bağlantısız kritik pin 0.

Önceki `S_saat` koşusu aynı köşelerde hold'u **9/9 pozitif**
kapatmıştı (en kötü +0,1857).

---

## Elenen açıklamalar

Sonuca atlamadan önce şunlar ölçülerek elendi:

### 1. Yanlış SDC periyodu — DEĞİL

İlk bakışta ana logda yalnızca `design.sdc: clk_period = 14 ns`
satırları görünüyordu ve imzalamanın yanlış periyotla koştuğu
sanıldı. **Bu yanlıştı.** Köşe başına loglar kontrol edildiğinde:

    56-openroad-stapostpnr/max_ff_n40C_1v95/sta.log:
      Reading design constraints file at 'constraints/signoff_50mhz_hedef.sdc'
      signoff.sdc: clk_period = 23.148 ns

İmzalama SDC'si **doğru periyotla** uygulanmıştı. İki-SDC tasarımı
çalışıyordu; ölçümler geçerliydi.

### 2. Hold onarımının eksik çalışması — DEĞİL

İki koşu da aynı komutu, aynı marjlarla çalıştırdı:

    repair_timing -verbose -hold -setup_margin 0.025 -hold_margin 0.6
                  -max_buffer_percent 50

| | S_saat | S_final |
|---|---:|---:|
| Bulunan hold endpoint | 12.514 | 12.574 |
| Eklenen hold tamponu | 18 | 17 |
| "Unable to repair all" uyarısı | var | var |

Davranış **özdeş**. Hold marjını artırmak bu tabloyu değiştirmezdi;
onarıcı zaten mevcut marj içinde onaramadığını bildiriyordu.

### 3. RTL düzeltmelerinin yapısal etkisi — DEĞİL

| | S_saat | S_final |
|---|---:|---:|
| Hücre sayısı | — | 102.621 |
| Alan (µm²) | — | 975.864,68 |
| SRAM makrosu | 23 | 23 |
| Die alanı (µm) | 3832,4 × 4249,24 | 3832,4 × 4249,24 |

Ara aşamalarda hold **pozitifti**:

| Adım | S_saat | S_final |
|---|---:|---:|
| 38 post-CTS | +0,2002 | **+0,2452** |
| 44 post-GRT | +0,4239 | **+0,3801** |
| İmzalama (RCX) | +0,4200 | **−0,2580** |

S_final post-CTS'te **daha iyi** marja sahipti. Ayrışma yalnızca
parazitik çıkarımdan sonra ortaya çıktı.

---

## Gerçek kök neden — saat ağacı asimetrisi

En kötü hold yolu (`max_ff_n40C_1v95`, slack −0,5005) incelendi:

    Startpoint: _180177_  (yükselen kenar FF, clk_i)
    Endpoint:   u_npu.u_npu_sram.g_sram[14].u_macro  (SRAM MAKROSU)

İki saat yolunun gecikmesi:

| Yol | Dal | Varış |
|---|---|---:|
| Veri (launch) | `clkbuf_regs_0_clk_i` → … | **2,700 ns** |
| Yakalama (capture) | `clkbuf_0_clk_i` → … | **4,113 ns** |
| | **ASİMETRİ** | **1,41 ns** |

Suçlu satır:

    23   1.394076   1.529639   0.757423   2.222158 ^ clkbuf_1_1_1_clk_i/X
         ^fanout    ^cap(pF)   ^slew      ^gecikme

**CTS 23 SRAM makrosunun tamamını tek bir saat tamponuna yığmıştı.**
1,394 pF yük ve 3,12 ns slew üretiyor; bu da yakalama saatini
1,41 ns geciktiriyor. Hold kontrolünde geç gelen yakalama saati
doğrudan negatif slack demektir.

Karşılaştırma: `S_saat` koşusunda en kötü hold yolu **FF → FF**
(`_190803_`) idi ve **+0,1857 MET** çıkmıştı. Yani o koşuda CTS
makroları tek dala yığmamıştı.

### Neden engellenememişti

`resolved.json` incelendiğinde makro kümeleme sınırlarının
tanımsız olduğu görüldü:

    CTS_MACRO_CLUSTERING_SIZE           None
    CTS_MACRO_CLUSTERING_MAX_DIAMETER   None
    CTS_MAX_CAP                         None

Sınır olmadığı için 23 makronun tek dala binmesine engel yoktu.
Bu bir **CTS varyansıdır**: aynı yapılandırma bir koşuda dengeli,
diğerinde dengesiz ağaç üretebiliyor.

---

## Düzeltme

`config_S_cts.yaml` (orijinal `config_S_saat.yaml` **değiştirilmedi**,
kopyalandı):

| Anahtar | Önce | Sonra | Gerekçe |
|---|---|---|---|
| `CTS_MACRO_CLUSTERING_SIZE` | null | **4** | 23 makro en fazla 4'lük kümelere bölünür |
| `CTS_MACRO_CLUSTERING_MAX_DIAMETER` | null | **200** | Uzak makrolar aynı dala binmez (µm) |
| `CTS_MAX_CAP` | null | **0,3** | Ölçülen ihlal 1,394 pF idi; sınır bunu böler |

**Tasarım hedefleri değişmedi:** `CLOCK_PERIOD 14`,
`SYS_CLK_HZ=43200000`, `SIGNOFF_SDC_FILE` 23,148 ns, 57 kaynak,
`MAX_FANOUT_CONSTRAINT 16` — hepsi aynı.

Sentez sonucu bunu doğruladı: `S_cts` koşusunda hücre sayısı
(102.621) ve alan (975.864,68 µm²) `S_final` ile **birebir aynı**
çıktı. Yani tek değişken saat ağacıdır; karşılaştırma adildir.

---

## Birinci aşamanın sonucu

Saat ağacı asimetrisi gerçekti ve düzeltilmesi gerekiyordu: makro
kapasitansı 1,394 → 0,328 pF düştü, en kötü hold yolu FF→SRAM'den
FF→FF'e döndü.

**Ancak bu tek başına zamanlamayı kapatmadı** — `S_cts` imzalaması
7/9 köşede negatif çıktı. Teşhis doğruydu ama eksikti. Devamı
aşağıdaki "SONUÇ" bölümündedir.

### Bu aşamada alınan ders

Bir koşunun setup'ı temiz, route DRC'si sıfır olabilir ama hold
ihlali taşıyabilir. Hold, frekans düşürülerek düzeltilemediği için
setup'tan daha ciddi kabul edilir.

Doğru teşhis, `min.rpt` içindeki **iki saat yolunun gecikmesini
yan yana okumakla** kondu — tek başına slack sayısına bakmak
yeterli değildi.


---

# SONUÇ — S_hold2 koşusu (13 Eylül 2026)

## Çözüm: hold onarım marjının ölçülerek ayarlanması

CTS düzeltmesi tek başına **yetmedi**. `S_cts` koşusunda makro
kapasitansı 1,394 → 0,328 pF düştü ve en kötü hold yolu FF→SRAM'den
FF→FF'e döndü, ama imzalama hâlâ 7/9 köşede negatif çıktı.

Asıl kısıt hold onarıcısının **marj eşiğiydi**. Üç koşuluk ölçüme
dayalı arama doğru değeri buldu:

| Marj | Eklenen tampon (post-CTS) | Sonuç |
|---|---:|---|
| 0,6 (`S_cts`) | **17** | Onarıcı devreye girmiyor; hold −0,58 |
| 1,2 (`S_hold`) | **12.828** | `GRT-0232 Routing congestion too high`, koşu rc=2 ile durdu |
| **0,8 (`S_hold2`)** | **6.803** | **Dengeli — zamanlama kapandı** |

Marj 0,6 iken onarıcı ihlalleri kapsam dışı görüyordu; 1,2 iken tüm
tasarıma tampon serpip yönlendirmeyi boğdu. Ölçülen en kötü ihlal
0,583 ns olduğu için 0,8 marj, ihlalli yolları hedefleyip gerisine
dokunmuyor.

### Yardımcı ayarlar

| Anahtar | Değer | İşlev |
|---|---|---|
| `*_RESIZER_HOLD_MAX_BUFFER_PCT` | 50 → **30** | Tampon bütçesi; post-GRT'de yalnızca 21 tampon eklenmesini sağlayıp sıkışıklığı önledi |
| `*_RESIZER_HOLD_REPAIR_TNS_PCT` | yok → **85** | Onarım TNS'in tamamını değil kritiğini hedefler |
| `*_RESIZER_HOLD_MAX_UTIL_PCT` | yok → **85** | Yoğunluk tavanı |
| `*_RESIZER_FIX_HOLD_FIRST` | False → **True** | Hold'a setup'tan önce öncelik |

CTS düzeltmeleri (`CTS_MACRO_CLUSTERING_SIZE 4`,
`CTS_MACRO_CLUSTERING_MAX_DIAMETER 200`, `CTS_MAX_CAP 0.3`) korundu.

**Tasarım hedefleri hiç değişmedi:** `CLOCK_PERIOD 14`,
`SYS_CLK_HZ=43200000`, signoff 23,148 ns, 57 kaynak. Sentez sonucu
üç koşuda da birebir aynı (102.621 hücre, 975.864,68 µm²), yani
karşılaştırmalar adildir.

---

## İmzalama sonucu — dokuz köşe (23,148 ns)

| Köşe | Hold WNS | Setup WNS | Hold TNS | Setup TNS |
|---|---:|---:|---:|---:|
| nom_tt_025C_1v80 | **+0,4936** | +2,8271 | 0 | 0 |
| nom_ss_100C_1v60 | **+1,0878** | +0,8350 | 0 | 0 |
| nom_ff_n40C_1v95 | **+0,2625** | +3,6716 | 0 | 0 |
| min_tt_025C_1v80 | **+0,4891** | +3,2330 | 0 | 0 |
| min_ss_100C_1v60 | **+1,0749** | +1,3439 | 0 | 0 |
| min_ff_n40C_1v95 | **+0,2730** | +4,0363 | 0 | 0 |
| max_tt_025C_1v80 | **+0,4966** | +2,3327 | 0 | 0 |
| max_ss_100C_1v60 | **+0,7100** | +0,2782 | 0 | 0 |
| max_ff_n40C_1v95 | **+0,0380** | +3,2157 | 0 | 0 |

**Setup 9/9 pozitif, hold 9/9 pozitif, her iki TNS sıfır, ihlal
sayısı sıfır.**

### Önceki teslim adayıyla karşılaştırma

`S_saat` koşusu da hold'u 9/9 pozitif kapatmıştı. `S_hold2` dokuz
köşenin **yedisinde ondan daha iyi** marja sahiptir:

| Köşe | S_saat | S_hold2 | Fark |
|---|---:|---:|---|
| nom_tt | +0,4200 | +0,4936 | ↑ |
| nom_ss | +0,9450 | +1,0878 | ↑ |
| nom_ff | +0,2318 | +0,2625 | ↑ |
| min_tt | +0,4179 | +0,4891 | ↑ |
| min_ss | +0,9412 | +1,0749 | ↑ |
| min_ff | +0,2303 | +0,2730 | ↑ |
| max_tt | +0,4226 | +0,4966 | ↑ |
| max_ss | +0,9494 | +0,7100 | ↓ |
| max_ff | +0,1857 | +0,0380 | ↓ |

`max_ff` köşesinde pay dardır (+0,038 ns) ancak pozitiftir ve TNS
sıfırdır.

**Belirleyici üstünlük:** `S_hold2`, 12 Eylül'de bulunan iki
işlevsel eksikliğin düzeltmelerini (JTAG AXI yanıt kodu denetimi ve
I2C saat germe) **içerir**; `S_saat` içermiyordu.

---

## Yanılgılar ve düzeltilmeleri

Bu analiz boyunca iki kez yanlış yola sapıldı; ikisi de ölçümle
düzeltildi:

1. **"İmzalama yanlış periyotla koştu"** — ana logda yalnızca
   `design.sdc: clk_period = 14 ns` görünüyordu. Köşe başına
   `sta.log` dosyaları kontrol edildiğinde imzalamanın
   **23,148 ns** ile koştuğu doğrulandı. İki-SDC tasarımı
   çalışıyordu.

2. **"CTS makro kümeleme sorunu çözer"** — kısmen doğruydu
   (kapasitans düzeldi) ama yeterli değildi. Asıl kısıt onarım
   marjıydı. Kök neden analizinde bir mekanizmanın doğrulanması,
   onun **tek** mekanizma olduğunu göstermez.
