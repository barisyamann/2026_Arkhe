# Devir Notu — ASİK Akışı Durumu

**Takım Arkhe — TEKNOFEST 2026**
Yazıldığı an: 25 Ağustos 2026, 16:17 (sunucu saati)
Teslim: **31 Ağustos 2026, 13:00**

---

## 1. Sunucuya erişim

```bash
ssh -i ~/.ssh/arkhe_asic tatua7806@34.141.105.233
```

| | |
|---|---|
| Özel anahtar | `C:\Users\ybari\.ssh\arkhe_asic` |
| Açık anahtar | `C:\Users\ybari\.ssh\arkhe_asic.pub` |
| Kullanıcı | `tatua7806` |
| Dış IP | `34.141.105.233` |
| Makine | GCP `arkhe-asic`, `c3-highmem-8` (8 vCPU / 64 GB) |
| Depo yolu | `~/arkhe` (GitHub `barisyamann/2026_Arkhe`) |

Açık anahtar GCP Konsolu → VM instances → arkhe-asic → SSH Keys altında ekli.
İş bitince oradan silinirse erişim kapanır.

**Durum betiği:** `~/durum.sh` — aktif koşumu kendi bulur, adım/kaynak/STA
özeti verir. Sürekli izlemek için `watch -n 20 ~/durum.sh`.

**Önemli:** Koşumlar `nohup setsid` ile başlatılıyor, tmux penceresinde
değil. `tmux attach` yapmaya gerek yok.

---

## 2. Şu an ne koşuyor

**11. koşum**, 16:15'te başladı, `run/arkhe11` dizininde.
Kütük: `/tmp/asic_kosum11.log`. Bitiş ~**20:45**.

Başlatma komutu:
```bash
cd ~/arkhe/asic
nohup setsid make asic_run TAG=arkhe11 > /tmp/asic_kosum11.log 2>&1 < /dev/null &
```

**Depo HEAD:** `349201b` (yerel ve uzak aynı, temiz)

---

## 3. Koşum geçmişi ve nerede olduğumuz

| Koşum | nom_tt setup | max_ss setup | hold reg→reg | anten | Not |
|---|---|---|---|---|---|
| 6 | +0,947 | −6,314 | 12 | 23/33 | eski taban |
| 7 | −0,763 | −17,105 | ~100 | 6/6 | saat modeli hatası |
| 8 | −1,300 | −17,105 | 109 | **3/5** | ss optimizasyonu kapalıydı |
| **9** | **+1,371** | **−8,026** | 687 | 9/11 | **en iyi setup** |
| 10 | +1,235 | −17,619 | 1147 | — | hold ayarı yıktı, durduruldu |
| **11** | koşuyor | | | | 9 + FIFO düzeltmesi |

**Geçen denetimler (9. koşum):** Netgen LVS, KLayout DRC 0, XOR 0,
yönlendirme DRC 0. **Açık:** Magic DRC 7658 (`nwell.4`), anten 9/11.

---

## 4. Bugün yapılan değişiklikler

| Commit | Ne |
|---|---|
| `349201b` | 10. koşum hold ayarları **geri alındı** |
| `42ecaea` | UART FIFO kritik yolu kesildi + blok testi |
| `4cce4cf` | 9. koşum sonuçları arşivlendi |
| `77f4f9c` | `SYNTH_STRATEGY` `AREA 0` → **`AREA 3`** (9 strateji ölçüldü) |
| `91f0c96` | Makro yerleşimi gruplara göre toplandı |
| `f72a423` | `RSZ_CORNERS`'a `nom_ss` geri, geçiş süresi 1,0 |

### Aktif config (11. koşum)

```yaml
SYNTH_STRATEGY: "AREA 3"
MAX_FANOUT_CONSTRAINT: 20
MAX_TRANSITION_CONSTRAINT: 1.0
RSZ_CORNERS: [nom_tt, nom_ff, nom_ss]
RUN_POST_GRT_RESIZER_TIMING: true
RUN_POST_GRT_DESIGN_REPAIR: true
GRT_RESIZER_HOLD_SLACK_MARGIN: 0.1
PL_RESIZER_HOLD_SLACK_MARGIN: 0.1
PL_TIMING_DRIVEN: false        # arac hatasi, README 9.9
MAGIC_MACRO_STD_CELL_SOURCE: "PDK"
MAGIC_DRC_USE_GDS: false       # README 9.8
```

---

## 5. Tekrarlanmaması gereken hatalar

Bunlar **yapıldı ve maliyeti ölçüldü**. Aynı yola girilmemeli.

**1. `set_driving_cell` saat portlarına uygulanmaz.**
`[all_inputs]` yazınca `clk_i` de girdi, saat girişi 2,99 ns'ye yavaşladı,
CTS bozuk modele göre ağacı kurdu, 7. koşum çöktü. Saatler için
`set_input_transition` kullanılır. Düzeltildi.

**2. `RSZ_CORNERS`'tan `nom_ss` çıkarılmaz.**
Boyutlandırıcının ss'te dönmesi "boşuna efor" sanılıp çıkarıldı; ss setup
−5,45'ten −16,37'ye düştü. Birikimli etkisi 11 ns'miş. Geri kondu.

**3. `FIX_HOLD_FIRST: true` kullanılmaz.**
0,30 marjla birlikte **11 749 hold tamponu** ektirdi, ss setup 8,6 ns
çöktü, hold da düzelmedi. 10. koşum bu yüzden durduruldu. Hold'a mutlak
öncelik vermek, ss setup'ı zaten zorda olan bir tasarımda yanlış.

**4. `PL_TIMING_DRIVEN: true` bu OpenROAD sürümünde çöküyor.**
`[CRITICAL RSZ-2007] wire step options empty`. Araç iç hatası. Kapalı.

**5. Zincirli otomasyon gözcüsü kurulmamalı.**
`make asic_clean` içeren bir gözcü, sentez keşfi dizinini sildi ve yanlış
config'le koşum başlattı. Gözcüler yalnız **durum bildirmeli**.

---

## 6. Bilinen teknik gerçekler

**ss'te duvar var, tek kritik yol yok.** 9. koşumun en kötü 1000 yolu
1,66 ns'lik bir bantta (−6,37 … −8,03). `max_ss`'te toplam 2921 ihlalli yol.

**Duvarın modül dağılımı (9. koşum, en kötü 1000 yol):**

| Modül | Yol | En kötü |
|---|---|---|
| `u_uart2` | **818** | −8,026 |
| `u_core` | 148 | −7,378 |
| `u_npu` | 34 | −7,664 |

818'i UART FIFO'suydu ve **düzeltildi** (11. koşum bunu ölçecek).

**Maksimum frekans tavanı:** çekirdeğe dokunmadan **~36,5 MHz**
(`u_core` −7,378 → 27,4 ns periyot). QSPI (−7,873) ve NPU (−7,664)
çekirdeğin önünde; onları düzeltmek 0,65 ns kazandırır.

**Çekirdek değiştirilebilir mi:** Şartname s.282 CV32E40P kullanımını
**zorunlu** kılıyor ama değiştirmeyi yasaklamıyor (Solderpad lisansı izin
verir). Ancak çekirdek duvarın **en iyisi**, en kötüsü değil — düzeltmenin
faydası yok. Ayrıca Spike ISS karşılaştırması (409 buyruk, 0 uyuşmazlık)
geçersizleşir.

---

## 7. Açık işler

### §5.2 ödül eşiği

| Madde | Durum |
|---|---|
| Self-checking boot + çevre birimi testi | ✅ |
| AXI protocol check (UVM agent) | ✅ 81 032 işlem, 0 ihlal |
| Sentez + P&R + STA | ✅ |
| **DRC/LVS signoff** | ⚠️ LVS geçti, Magic DRC ve anten açık |
| **FPGA kart testi** | ❌ **hiç yapılmadı** |

### Teknik

1. **Anten 9/11 → 0** — hedefli diyot/routing onarımı, 11. koşum sonrası
2. **Magic DRC 7658'i kesinleştir** — `MAGIC_DRC_USE_GDS: true` ile tek
   koşum. Şu an DEF görünümü üzerinden koşuyor; KLayout final GDS'te 0
   veriyor. Ölçüm: ihlal şeritlerinin %87,3'ünde tap hücresi VAR, yani
   "tap eksik" hipotezi çürütüldü.
3. **Hold 687 ihlal** — ölçülü marj denemesi (0,1 → 0,15),
   `FIX_HOLD_FIRST`'e dokunmadan
4. **Frekans kararı** — ss 50 MHz'de kapanmıyor. İki seçenek:
   belgelenmiş derating (tt/ff'de 50 MHz, ss'te ~36 MHz) veya ASİK saat
   hedefini düşürmek. Kullanıcı "maksimum MHz'e çıkalım" dedi.

### Belge

1. `asic/README.md` **§11 Signoff Sonuç Özeti hâlâ `(doldurulacak)`**
2. DTR sonrası değişiklik günlüğü — hiç yok
3. Teslim paketi: §5/§6 çıktıları + `checksums/SHA256SUMS`
4. SRAM makrosunun yalnız TT Liberty modeli olduğu final raporda
   belirtilmeli (ss'te iyimser, ff'te kötümser)

---

## 8. Doğrulama durumu

| | |
|---|---|
| Regresyon | **16/16 test, 349 denetim** |
| Spike ISS | 409 buyruk, **0 uyuşmazlık** |
| UVM AXI agent | 81 032 işlem, **0 protokol ihlali** |
| NPU golden | Google TFLite'a karşı 7 vektör, maks. 0,15 puan sapma |
| FPGA bitstream | WNS **+1,216 ns** |

Yeni eklenen: `tb/tb_sync_fifo.sv` — 24 denetim (reset, fill-to-full,
drain-to-empty, wraparound, eş zamanlı R/W, full+read, empty+write).

---

## 9. Söylenebilecekler / söylenemeyecekler

**Söylenebilir:** RTL→GDS otomatik akış çalışıyor · 23 SRAM entegre ·
Netgen LVS temiz · KLayout DRC 0 · XOR 0 · yönlendirme DRC 0 ·
50 MHz tipik köşede kapanıyor (9. koşum +1,371 ns payla)

**Söylenemez:** "Tüm PVT köşelerinde temiz" · "DRC tamamen temiz"
(`manufacturability.rpt` FAIL diyor) · "Anten temiz" · "Production-ready
GDS" · "Güç 120 mW ölçüldü" (VCD/SAIF yok, tahmini)
