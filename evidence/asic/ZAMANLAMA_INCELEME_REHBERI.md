# Zamanlama Sonuçlarını Bağımsız İnceleme Rehberi

**Takım Arkhe — TEKNOFEST 2026 Çip Tasarımı Yarışması**
Hazırlanma tarihi: 5 Eylül 2026

Bu belge, `arkhe25` tasarımının zamanlama sonuçlarını **üçüncü bir kişinin
kendi başına doğrulayabilmesi** için yazılmıştır. Hiçbir rakam bu belgeye
elle girilmemiştir; her biri aşağıdaki komutlarla üretilir.

---

## 0. Özet tablo (doğrulanacak iddialar)

| Koşum | PnR periyodu | İmzalama periyodu | max_ss setup payı | Kapandığı periyot | Frekans |
|---|---|---|---|---|---|
| `arkhe25s` | 20,0 ns | 29,5 ns | −0,247 ns | 29,75 ns | 33,6 MHz |
| `arkhe25_100mhz` | 10,0 ns | 20,0 ns | −4,513 ns | 29,03 ns | **34,45 MHz** |

Kritik nokta: **PnR periyodu ile imzalama periyodu farklı olabilir.**
Şartname Bölüm 6.2 bunu açıkça izin verir. PnR periyodu araca uygulanan
optimizasyon baskısıdır; imzalama periyodu ise sonucun ölçüldüğü noktadır.
10 ns'lik PnR hedefi ulaşılabilir değildir, amaç ulaşmak değil aracı
daha agresif optimizasyona zorlamaktır — ölçülen sonuç bunun işe
yaradığını gösteriyor, ancak kazanç mütevazıdır (33,6 → 34,45 MHz).

> **DÜZELTME (5 Eylül 2026).** Bu belgenin ilk sürümünde kapanan periyot
> `20,0 − (−4,513) = 24,51 ns → 40,8 MHz` diye hesaplanmıştı. **Bu yanlıştı.**
> En kötü yol TAM ÇEVRİM değil, YARIM ÇEVRİM yoludur: SRAM veriyi DÜŞEN
> kenarda çıkarır, CPU YÜKSELEN kenarda yakalar. Doğrulaması `max.rpt`
> içindedir:
>
> ```
> Startpoint: u_instruction_ram.g_sram[2].u_macro
>             (falling edge-triggered flip-flop clocked by clk_i)
> Endpoint:   _185419_ (rising edge-triggered flip-flop clocked by clk_i)
>                       10.000000   clock clk_i (fall edge)    <- launch
>                       20.000000   clock clk_i (rise edge)    <- capture
> ```
>
> 50 MHz'te bu yolun bütçesi 20 ns değil **10 ns**'dir. Doğru hesap:
>
> ```
> gereken yarım çevrim = 10 + 4,513 = 14,513 ns
> gereken periyot      = 2 × 14,513 = 29,03 ns
> frekans              = 1000 / 29,03 ≈ 34,45 MHz
> ```
>
> Bu, kritik yoldan çıkarılan YAKLAŞIK sınırdır; o periyotta yeniden STA
> koşulmuş ve bütün denetimlerin geçtiği anlamına GELMEZ.

---

## 1. Sunucuya erişim

```bash
ssh -i ~/.ssh/arkhe_asic tatua7806@<VM_IP>
```

> Dış IP efemeraldir, VM yeniden başlatılınca değişir.
> Güncel adres: GCP Konsolu → VM instances → `arkhe-asic` → External IP.

Koşum dizinleri:

```
~/arkhe_exp/asic/run/arkhe25s/          # 29,5 ns imzalama (temel)
~/arkhe_exp/asic/run/arkhe25_100mhz/    # 10 ns PnR, 20 ns imzalama (deney)
```

---

## 2. Dokuz köşenin setup/hold payını okuma

LibreLane her köşe için ayrı bir alt dizin yazar. Ham rapor dosyaları:

| Dosya | İçerik |
|---|---|
| `ws.max.rpt` | Worst Slack (setup) — **gerçek pay, pozitif olabilir** |
| `wns.max.rpt` | Worst *Negative* Slack — ihlal yoksa 0,0 yazar |
| `tns.max.rpt` | Total Negative Slack — tüm ihlallerin toplamı |
| `ws.min.rpt` | Worst Slack (hold) |
| `violator_list.rpt` | İhlal eden her yolun listesi |
| `max.rpt` | Kritik yolun tam dökümü (hücre hücre) |

> **Tuzak:** `wns.max.rpt` ihlal yokken `0.0` yazar. Bu "sıfır pay" demek
> DEĞİLDİR. Gerçek payı görmek için `ws.max.rpt` okunmalıdır.

Dokuz köşeyi birden dökmek için:

```bash
cd ~/arkhe_exp/asic/run/arkhe25_100mhz
D=$(ls -d *stapostpnr* | tail -1)

for c in min_tt_025C_1v80 nom_tt_025C_1v80 max_tt_025C_1v80 \
         min_ss_100C_1v60 nom_ss_100C_1v60 max_ss_100C_1v60 \
         min_ff_n40C_1v95 nom_ff_n40C_1v95 max_ff_n40C_1v95; do
  s=$(tail -1 "$D/$c/ws.max.rpt")
  h=$(tail -1 "$D/$c/ws.min.rpt")
  printf "%-22s setup=%-22s hold=%s\n" "$c" "$s" "$h"
done
```

`arkhe25s` için aynı komutu `run/arkhe25s` dizininde çalıştırın.

---

## 3. Kapanan periyodu hesaplama

**Önce yolun tam çevrim mi yarım çevrim mi olduğuna bakın.** `max.rpt`
başındaki launch/capture kenarları bunu söyler:

```bash
grep -E "edge-triggered|clock clk_i \((rise|fall) edge\)" max.rpt | head -4
```

- Launch ve capture aynı kenar tipindeyse **tam çevrim**:
  `kapanan_periyot = imzalama_periyodu − pay`
- Launch düşen, capture yükselen kenardaysa **yarım çevrim**:
  `gereken_yarim = (imzalama_periyodu / 2) − pay`
  `kapanan_periyot = 2 × gereken_yarim`

`arkhe25_100mhz` yarım çevrimdir (SRAM düşen kenarda çıkarır):

```
(20,0 / 2) − (−4,513) = 14,513 ns
kapanan periyot       = 29,03 ns  →  34,45 MHz
```

İmzalama periyodunun nereden geldiğini doğrulamak için:

```bash
grep -n "clk_period" ~/arkhe_exp/asic/constraints/signoff_50mhz_hedef.sdc
grep -n "^CLOCK_PERIOD:\|^SIGNOFF_SDC_FILE:" ~/arkhe_exp/asic/config_arkhe25_100mhz.yaml
```

> **Tcl tuzağı:** Tcl'de satır sonu `#` yorumu YOKTUR.
> `set clk_period 20.0   # aciklama` yazılırsa `set` komutu fazladan
> argüman alır ve `wrong # args` hatası verir. Bu hata bir kez tüm dokuz
> köşenin STA'sını düşürmüştür. Yorum ayrı satıra yazılmalıdır.

---

## 4. Kritik yolu inceleme

```bash
cd ~/arkhe_exp/asic/run/arkhe25_100mhz/*stapostpnr*/max_ss_100C_1v60
head -80 max.rpt          # en kötü yolun hücre hücre dökümü
tail -12 max.rpt          # slack hesabının özeti
```

Okunacak dört satır (raporun sonunda):

```
data required time      # hedefe kadar izin verilen süre
data arrival time       # verinin gerçekte vardığı an
slack (VIOLATED)        # fark
clock uncertainty       # jitter/belirsizlik bütçesi
```

### İhlallerin dağınık mı yoksa tek noktada mı olduğunu görme

```bash
grep -oE "\] [^ ]+ ->" violator_list.rpt | sort | uniq -c | sort -rn | head
wc -l violator_list.rpt
```

Bu tasarımda 1399 ihlalin tamamı **4-5 SRAM okuma çıkışından** başlar
(`u_instruction_ram.g_sram[2].u_macro/dout1[23]` tek başına 351 yol).
Yani sorun dağınık değil, tek bir yapısal darboğazdır.

### Saat çarpıklığının payı

```bash
cat skew.max.rpt
```

`arkhe25_100mhz` / max_ss çıktısı: −2,689 ns setup skew.

> **DİKKAT — bu değer KRİTİK YOLA AİT DEĞİLDİR.** `skew.max.rpt`
> `u_npu.u_npu_sram.g_sram[12] → _189752_` yolunu raporlar; en kötü setup
> yolu ise `u_instruction_ram.g_sram[2] → _185419_`'dur. O yolda saat
> gecikmeleri `max.rpt` içinde şöyledir:
>
> ```
> 15.098744  u_instruction_ram.g_sram[2].u_macro/clk1   (launch, kenar 10 ns)
> 25.859774  _185419_/CLK                               (capture, kenar 20 ns)
> ```
>
> Launch +5,099 ns, capture +5,860 ns — capture **0,761 ns daha geç**
> geliyor ve bu setup'a **YARDIM EDİYOR**. Dolayısıyla "CTS dengelemesiyle
> 2,7 ns kazanılır" çıkarımı geçersizdir; o dalı düzeltmek bu yolda setup'ı
> kötüleştirir.

---

## 5. Bulguların yorumu — 4,5 ns'lik açığın dökümü

| Kalem | Süre | Müdahale edilebilir mi |
|---|---|---|
| SRAM `clk1 → dout1` | 0,61 ns | Hayır (makro içi) |
| 3 seri `mux2` (banka seçimi) | 4,04 ns | **Evet** — boru hattı aşaması |
| ~15 seviye kombinasyonel mantık | ~9 ns | Kısmen |
| Saat çarpıklığı | 2,69 ns | **Evet** — CTS ayarları |
| Saat belirsizliği | 0,25 ns | Kısmen |

Kapatma seçenekleri, maliyet sırasıyla:

1. **İmzalama periyodunu 29,1 ns'e ayarlamak** — sıfır maliyet, 34,45 MHz
   (yaklaşık sınır; o periyotta yeniden STA gerekir).
2. **Fiziksel optimizasyon** — hücre boyutlandırma ve tamponlama. OpenROAD
   bunu destekler, ancak kazanç yeni bir STA raporuyla doğrulanmalıdır.
   (CTS dengeleme ÖNERİLMEZ: yukarıda gösterildiği gibi kritik yolda capture
   saati zaten geç geliyor ve setup'a yardım ediyor.)
3. **I-RAM okuma yoluna boru hattı aşaması** — ~4 ns kazanç, ama RTL
   değişikliği + tüm regresyonun tekrarı gerekir. (NPU'da aynı teknik
   `CONV_RQ_MUL`/`FC_RQ_MUL` ile zaten uygulanmıştır.)

---

## 6. Bu koşumu sıfırdan yeniden üretme

```bash
cd ~/arkhe_exp/asic
nix develop ../environment
librelane config_arkhe25_100mhz.yaml \
  --run-tag <yeni_etiket> --force-run-dir run/<yeni_etiket>
```

`config_arkhe25_100mhz.yaml`, `config_arkhe25s.yaml`'den **yalnızca iki
satırda** ayrılır (doğrulamak için):

```bash
diff <(grep -v '^#' config_arkhe25s.yaml      | grep -v '^$') \
     <(grep -v '^#' config_arkhe25_100mhz.yaml | grep -v '^$')
```

Beklenen fark: `CLOCK_PERIOD` (20,0 → 10,0) ve `SIGNOFF_SDC_FILE`
(`signoff.sdc` → `signoff_50mhz_hedef.sdc`).

### Yalnızca imzalama adımını yeniden koşma

Yerleşim/yönlendirme sonuçları önbellektedir; STA'yı yeniden koşmak için
tüm akışı tekrarlamaya gerek yoktur:

```bash
librelane config_arkhe25_100mhz.yaml --run-tag arkhe25_100mhz \
  --force-run-dir run/arkhe25_100mhz --from OpenROAD.STAPostPNR
```

> `error.log` önceki bir hatadan kalma içerik taşıyorsa yanıltır.
> Yeniden başlatmadan önce `> run/<etiket>/error.log` ile temizleyin.

---

## 7. Bilinen ve belgelenmiş sapmalar

| Konu | Durum |
|---|---|
| `max_ss` setup ihlali | Bilinen. Kritik yol CV32E40P + I-RAM SRAM okuma yolu. Üçüncü taraf IP'ye dokunmama kararı gereği çekirdek içi optimizasyon yapılmamıştır. |
| Magic DRC `nwell.4` (7658) | Bilinen. KLayout DRC aynı tasarımda 0 verir; `nwell.4` KLayout kural setinde yoktur. GDS üzerinden doğrulama denenmiş, bellek tükenmesi nedeniyle tamamlanamamıştır. |
| SRAM makrosu tek köşe | Satıcı modeli yalnızca `TT_1p8V_25C` içerir; ff ve ss köşelerinde de aynı model okunur. |

Bu sapmalar `evidence/asic/` altındaki ilgili belgelerde ayrıntılıdır.
