# UVM AXI4-Lite Passive Agent

**Takım Arkhe — TEKNOFEST 2026 Çip Tasarım Yarışması**
Tarih: 24 Ağustos 2026

---

## 1. Şartname Gerekçesi

**Şartname §4.2.2:**
> "...çevre birimlerinin ve YZ hızlandırıcının {AXI veya AXI-Lite}
> arayüzlerinin SystemVerilog HDL ve **Universal Verification Methodology
> (UVM)** kullanılarak doğrulanması beklenecektir."

**Şartname §5.2 (ödül için asgari başarı kriteri):**
> "...AXI arayüzlerinin **en azından protocol check düzeyinde** AXI
> agent'larıyla doğrulanması."

**EK-3:**
> "**Tam teşekküllü** bir UVM tabanlı sistem doğrulama ortamına sahip
> olunması **beklenmemektedir**. Ancak protokol kontrolü amacıyla tüm AXI
> arayüzlerine entegre edilmiş agent'lar halihazırda bütün veri akışını
> **paketlere böleceğinden** ötürü yarışmacıların, isterlerse UVM-tabanlı
> olası scoreboarding faaliyetleri gerçeklemeleri çok daha kolay olacaktır."

Şartname iki farklı eşik koyar: §5.2 **protocol check** düzeyini ödül için
zorunlu tutar, EK-3 ise tam UVM ortamını açıkça beklemediğini söyler. Bizim
konumumuz ikisinin arasında ve §5.2'nin üstündedir: **gerçek bir UVM ortamı
(env / agent / monitor / scoreboard / sequence_item) var, ama sürücü yok.**

---

## 2. Neden "Passive" — Sürücü Neden Yok

Agent yalnızca **dinler**. Sebebi tasarım kararıdır, eksiklik değil:

1. **Tasarım zaten gerçek trafikle sürülüyor.** NPU motorunun AXI4-Lite
   master hattında, tam bir çıkarım koşumu boyunca 81 bin işlem akıyor.
   Bu, sentetik bir sürücünün üretebileceğinden hem daha fazla hem daha
   gerçekçi bir uyaran kümesidir.
2. **O trafik zaten self-checking testlerle doğrulanıyor.** NPU çıkışı
   Google'ın resmî TFLite modeline karşı bit düzeyinde kıyaslanıyor
   (7 vektör, maks. 0,15 puan sapma). Buraya bir sürücü eklemek mevcut
   testleri tekrar etmek olurdu.
3. Agent'ın **kattığı** şey uyaran değil, **gözlem düzeyi**: ham sinyalleri
   işlem (transaction) nesnelerine çevirmek, protokol kurallarını işlem
   düzeyinde denetlemek ve sayısal özet vermek. EK-3'ün "bütün veri akışını
   paketlere böler" dediği şey tam olarak budur.

---

## 3. Mevcut SVA ile İlişki — İkisi Farklı Seviyede Denetler

`rtl/Memory/axil_protocol_checker.sv` **korunur** ve çalışmaya devam eder.
UVM onun yerini almaz:

| Katman | Seviye | Ne denetler |
|---|---|---|
| SVA (`axil_protocol_checker`) | sinyal / çevrim | valid düşmemeli, adres değişmemeli, ready öncesi kararlılık |
| UVM agent | işlem | her adrese tam bir yanıt, yanıt kodu geçerli, yarım kalmış işlem yok |

Bir SVA "bu çevrimde valid düştü" der; UVM "bu adrese hiç yanıt gelmedi" der.
İkisi birbirinin yerine geçmez.

SVA denetleyicileri `bind soc_top` ile beş AXI master/slave hattına bağlı.
UVM agent'ı ise şartnamenin özellikle andığı yere — **YZ hızlandırıcının AXI
master arayüzüne** — bağlıdır.

---

## 4. Ortamın Yapısı

```
uvm_test_top  (axil_passive_test)
└── env       (axil_env)
    ├── agent (axil_agent, UVM_PASSIVE)
    │   └── mon (axil_monitor)  --analysis_port-->  sb
    └── sb    (axil_scoreboard)
```

| Bileşen | Dosya | Rol |
|---|---|---|
| `axil_islem` | `tb/uvm/axil_uvm_pkg.sv` | `uvm_sequence_item` — bir AXI işlemi (tür, adres, veri, strb, yanıt, başlangıç/bitiş zamanı) |
| `axil_monitor` | aynı | Ham sinyalleri işlemlere çevirir; AR-R ve AW+W-B eşlemesi |
| `axil_scoreboard` | aynı | İşlem düzeyi denetimler |
| `axil_agent` | aynı | `UVM_PASSIVE` — sürücü ve sequencer oluşturulmaz |
| `axil_env` / `axil_passive_test` | aynı | Standart UVM hiyerarşisi |
| `axil_if` | `tb/uvm/axil_if.sv` | Yalnızca gözlem arayüzü; hiçbir sinyal sürülmez |

**Sanal arayüz (virtual interface)** kullanılır: UVM ortamı tasarım
hiyerarşisinden bağımsızdır, hangi arayüze bağlanacağı testbench tarafında
`uvm_config_db` ile belirlenir.

### Scoreboard'un denetimleri

1. **Yanıt kodu geçerliliği.** AXI4-Lite'ta RESP[1:0] yalnızca `00` (OKAY),
   `10` (SLVERR), `11` (DECERR) olabilir. `01` (EXOKAY) yalnızca AXI4
   exclusive erişimde geçerlidir ve **Lite'ta yoktur** — görülürse
   `uvm_error`.
2. **Asılı kalmış işlem.** Bir işlem 10 mikrosaniyeden uzun sürerse uyarı.
3. **Eşleşmeyen yanıt.** AR olmadan gelen R, ya da AW/W tamamlanmadan gelen B
   → `uvm_error`.

---

## 5. Yol Boyunca Bulunan Üç Hata

Üçü de **sessizce yanlış sonuç** üretiyordu. Kayda değer olmalarının sebebi
budur: hiçbiri derleme hatası vermedi, testler "geçti" dedi.

### 5.1 UVM zaman 0'da bitiyordu — run_phase objection'ı yoktu

İlk sürümde passive test'in `run_phase`'i yoktu. Hiçbir faz objection
tutmadığı için `run_test()` **hemen `$finish` çağırdı**; tasarım hiç koşmadan
simülasyon kapandı.

Belirti: `islem ozeti: okuma=0 yazma=0` — ve UVM `0 errors` raporladı, yani
**yeşil görünüyordu**.

Passive agent sürücü içermez, dolayısıyla kendi başına bitiş koşulu da yoktur.
Objection alınır ve **bırakılmaz**; simülasyonu testbench'in kendi `$finish`'i
sonlandırır. Bu, monitor-only ortamlarda standart yaklaşımdır.

### 5.2 Örtük wire — arayüz saati hiç toggle etmedi

Arayüz örneği şöyle bağlanmıştı:

```systemverilog
axil_if npu_eng_if (.clk(clk_i), .rst_n(rst_ni));   // YANLIS
```

`clk_i` / `rst_ni` isimleri, hemen aşağıdaki `bind soc_top` bloklarından
kopyalanmıştı. Ama **bind blokları SoC kapsamında çalışır**; orada bu
isimler gerçek port isimleridir. Testbench kapsamında sinyaller `clk` ve
`rst_n` adını taşır.

Verilog, tanımsız bir tanıtıcıyı port bağlantısında görünce **örtük wire**
yaratır. Derleme hatası **vermez**. Sonuç: arayüzün saati sürekli `z`,
monitor'ün `@(posedge vif.clk)` beklemesi hiç tetiklenmedi, agent sessizce
sıfır işlem yakaladı.

```systemverilog
axil_if npu_eng_if (.clk(clk), .rst_n(rst_n));      // DOGRU
```

Bu, ölçüm eklenmeden **fark edilemezdi** — ilk özet zaten "0 işlem"
diyordu ve UVM "0 error" diyordu.

### 5.3 Tek slotlu bayrak 2 680 okumayı düşürdü

Monitor'ün ilk sürümü bekleyen okuma adresini tek bir bayrakla tutuyordu.
Bizim AXI4-Lite slave'imiz `arready`'yi **her çevrim** yüksek tutar ve okuma
verisi bir çevrim sonra döner; yani **AR(n+1) ile R(n) aynı çevrimde el
sıkışır**. Tek slot bu durumda yeni adresi eskinin üzerine yazıyordu.

| Ölçüm | Tek slot | Kuyruk |
|---|---|---|
| Ham AR el sıkışması | 81 024 | 81 024 |
| Monitor okuma sayısı | **78 344** | **81 024** |
| Kayıp | **2 680** | 0 |

Düzeltme: hem okuma hem yazma kanalı **kuyruğa** çevrildi, ve çevrim içinde
**önce biten işlem (R / B), sonra yeni gelen (AR / AW / W)** işlenir. Tersi
olursa aynı çevrimde gelen yeni adres, biten işlemin adresi sanılır.

**Bu hata da sessizdi:** 78 344 işlem "hepsi protokole uygun" diye
raporlanıyordu; eksik olduğunu gösteren hiçbir belirti yoktu.

---

## 6. Bağımsız Çapraz Kontrol

5.3'teki hatanın sessizliği, monitor'ün kendi sayacına güvenilemeyeceğini
gösterdi. Bu yüzden testbench, aynı arayüzde **ham el sıkışmaları** bağımsız
olarak sayar ve koşum sonunda monitor sayaçlarıyla karşılaştırır:

```systemverilog
always @(posedge npu_eng_if.clk) begin
    if (npu_eng_if.rvalid && npu_eng_if.rready) ham_r++;
    if (npu_eng_if.bvalid && npu_eng_if.bready) ham_b++;
end
```

Sayımlar tutmuyorsa **test başarısız olur**. Yani agent'ın *eksik yakalaması*
artık sessiz kalamaz.

**Not — report_phase kullanılamaz:** testbench `$finish`'i UVM dışından
çağırır, o yüzden UVM fazları tamamlanmadan simülasyon biter ve
`report_phase` **hiç koşmaz**. Özet ve geçme/kalma kararı SystemVerilog
`final` bloğuna taşınmıştır; `final` `$finish`'te mutlaka koşar. Sayaçlar bu
yüzden `static` tanımlıdır (sınıf kapsamından okunabilsinler diye).

---

## 7. Sonuç

Tam sistem koşumu (iki NPU çıkarımı, DMA akışı, UART, gerçek ağırlıklar):

```
================= UVM AXI4-Lite PASSIVE AGENT =================
  izlenen arayuz     : NPU motoru -> TCM (AXI4-Lite master)
  okuma islemi       : 81024
  yazma islemi       : 8
  toplam islem       : 81032
  hatali yanit       : 0  (SLVERR/DECERR)
  gecersiz yanit kodu: 0  (AXI4-Lite'ta EXOKAY olamaz)
  asili kalmis islem : 0  (>10us)
  [OK]   81032 AXI4-Lite islemi yakalandi ve paketlendi
  [OK]   tum yanit kodlari gecerli (OKAY), protokol ihlali yok
  [OK]   asili kalmis islem yok (hepsi <10us tamamlandi)
==============================================================
  capraz kontrol (ham sinyal sayimi):
    R  el sikismasi  : 81024   monitor okuma : 81024
    B  el sikismasi  : 8       monitor yazma : 8
  [OK]   monitor hicbir islemi kacirmadi (ham sayim tutuyor)
```

| Ölçüm | Değer |
|---|---|
| Paketlenen AXI4-Lite işlemi | **81 032** |
| Protokol ihlali | **0** |
| Hatalı yanıt (SLVERR/DECERR) | **0** |
| Asılı kalmış işlem | **0** |
| Monitor'ün düşürdüğü işlem | **0** (bağımsız çapraz kontrol) |
| UVM_ERROR | **0** |

Simülasyon süresi 78,4 ms benzetim zamanı, 3 dk 11 sn duvar saati.

---

## 8. Yeniden Üretim

```bash
python scripts/run_regression.py --test uvm_axi_agent
```

`-d UVM_AXI` tanımı olmadan UVM dosyaları **hiç derlenmez**; diğer 14 test
uvm kütüphanesine bağlanmak zorunda kalmaz.

---

## 9. İlgili Dosyalar

| Dosya | Rol |
|---|---|
| `tb/uvm/axil_uvm_pkg.sv` | UVM paketi — item, monitor, scoreboard, agent, env, test |
| `tb/uvm/axil_if.sv` | Gözlem arayüzü (sürülmez) |
| `tb/tb_soc_top.sv` | Arayüz bağlantısı, `uvm_config_db` kurulumu, çapraz kontrol, `final` özeti |
| `rtl/Memory/axil_protocol_checker.sv` | SVA denetleyicisi (korunur, tamamlayıcıdır) |
| `scripts/run_regression.py` | `uvm_axi_agent` test girdisi |
