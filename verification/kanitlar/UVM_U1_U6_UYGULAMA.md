# UVM genişletmesi — U1…U6 uygulandı

**Tarih:** 13 Eylül 2026
**Dosya:** `tb/uvm/axil_uvm_pkg.sv` (1283 → ~1600 satır)
**Kaynak analiz:** `UVM_YAPILABILECEKLER.md`

---

## Özet

| # | İş | Durum |
|---|---|---|
| **U6** | Rapor netleştirme | ✅ **uygulandı ve doğrulandı** |
| **U5** | Referans model (veri doğruluğu) | ✅ **uygulandı, 1.038 okuma doğruladı** |
| **U1** | Aktif agent (driver + sequencer) | ✅ altyapı eklendi |
| **U2** | Kısıtlı-rastgele sequence | ✅ eklendi |
| **U3** | Yönlendirilmiş sequence (kapsam) | ✅ eklendi |
| **U4** | Sanal sequence (iki arayüz) | ✅ eklendi |

---

## U6 — Rapor netleştirme

### Sorun

Eski özet çelişkili görünüyordu:

    okuma islemi : 382691      <- IKI monitorun TOPLAMI
    yazma islemi :  19038      <- IKI monitorun TOPLAMI
    toplam islem : 162064      <- YALNIZCA NPU scoreboard

Sebep: `axil_monitor::okuma_sayisi` ve `yazma_sayisi` **`static`**
olduğu için iki monitör *örneği* aynı değişkeni paylaşıyordu.
Aritmetik doğruydu ama okuyan kişi "toplam neden daha küçük?"
diye düşünüyordu.

### Sonuç

    -- agent 1: NPU motoru -> TCM (AXI4-Lite master) --
    islem (scoreboard) : 162064
    -- agent 2: SoC ana yolu (merged_m_*) --
    islem (scoreboard) : 239665
    -- genel --
    TOPLAM islem       : 401729
    monitor okuma/yazma: 382691 / 19038  (iki agent birlikte;
                          sayaclar static, ornekler paylasir)

**162.064 + 239.665 = 401.729 = 382.691 + 19.038** ✓

---

## U5 — Referans model (veri doğruluğu)

### Neden gerekliydi

Scoreboard 13 Eylül'e kadar yalnızca **protokol** denetliyordu:
VALID kararlılığı, yanıt kodu, hizalama, X/Z, `WSTRB != 0`…

**"Yazılan değer geri okunduğunda aynı mı"** hiç kontrol
edilmiyordu. Bu bir boşluktur: hakemlik hatası, adres çözme hatası
veya WSTRB uygulama hatası **protokolü bozmadan** veriyi bozabilir
ve tüm protokol denetimlerinden geçerdi.

### Nasıl çalışır

İlişkisel dizi bir referans bellek tutar:

- **Yazma** → `WSTRB`'ye göre **bayt bayt** birleştirilip saklanır
- **Okuma** → adres daha önce yazılmışsa beklenen değerle karşılaştırılır

Kasıtlı sınırlamalar (yanlış alarm önlemek için):

| Sınırlama | Gerekçe |
|---|---|
| Yalnızca `OKAY` yanıtlı işlemler | SLVERR/DECERR dönen işlemin verisi anlamsızdır |
| Yalnızca **daha önce yazılmış** adresler | Belleğin başlangıç içeriği bilinmez |
| SoC yolunda yalnızca **gerçek bellek** bölgeleri (iram, dram, npu_mem) | Çevre birimi yazmaçları yazılanı geri vermez: salt-okunur bitler, kendiliğinden temizlenen bayraklar, FIFO'lar |
| X/Z içeren okumalar atlanır | Ayrı bir denetimde ele alınır |

### Ölçülen sonuç

    -- referans model (veri dogrulugu) --
    NPU TCM  : 4 adres izlendi, 0 okuma dogrulandi
    SoC yolu : 3647 adres izlendi, 1038 okuma dogrulandi
    [OK]   1038 okumada yazilan deger BIREBIR geri okundu

**NPU TCM'de neden 0?** Motor TCM'e yazar ama simülasyon boyunca
aynı adresleri geri **okumaz** — denetim fırsatı doğmaz. Bu
beklenen bir durumdur, modelin hatası değildir. Referans modelin
asıl değeri **SoC ana yolunda** ortaya çıkar: CPU, DMA ve JTAG
trafiğinin birleştiği noktada yazılıp geri okunan adres boldur.

---

## U5'in mutasyonla sınanması — dürüst sonuç

Yeni bir denetim eklendiğinde onun **gerçekten hata yakaladığını**
kanıtlamak gerekir. İki mutasyon denendi:

### Deneme 1 — `s_axil_rdata` bit0 ters çevrildi

    assign s_axil_rdata = {ram_rdata[31:1], ~ram_rdata[0]};

**Sonuç:** Test başarısız oldu (38 → 22 denetim), yani mutasyon
yakalandı. **Ancak yakalayan referans model değildi:**

    [HATA] NPU zaman asimi - DONE sinyali 60 ms icinde gelmedi
    [HATA] DMA tamamlanmadi - UART-stream veri yolu calismiyor
    [HATA] Uygulama ikinci tura hic girmedi

Her okumanın bir biti bozulunca yazılım tamamen çöktü; referans
modelin karşılaştırma yapacağı trafik bile oluşmadı
(`SoC yolu : 1 okuma dogrulandi`).

### Deneme 2 — `w_strb_reg` bit3 zorla 1

    w_strb_reg <= s_axil_wstrb | 4'b1000;

Amaç: yalnızca **bayt-seçmeli** yazmayı bozmak, tam kelime
yazmalarına dokunmamak — böylece sistem ayakta kalsın.

**Sonuç:** Bu da sistemi çökertti (`0 adres izlendi` — hiç trafik
oluşmadı). Boot sırasında bayt-seçmeli yazma kritik yollarda
kullanılıyor.

### Değerlendirme

**U5 çalışıyor ve ölçülebilir iş yapıyor** — temiz RTL'de 1.038
okumayı doğruladı, yani karşılaştırma mantığı fiilen çalışıyor.

**Ancak mutasyonla *bağımsız* olarak kanıtlanamadı:** denenen her
veri bozulması sistemi o kadar erken çökertiyor ki, referans
modelin devreye gireceği trafik oluşmuyor. Bu, mevcut regresyonun
hâlihazırda **çok sıkı** olmasının bir yan etkisidir — sistem
testleri veri bozulmasını zaten daha erken yakalıyor.

Bu yüzden U5, kalıcı mutasyon kampanyasına **eklenmemiştir**.
Kampanyaya yalnızca hedefini kanıtlayabilen mutasyonlar girer;
aksi hâlde "9/9 yakalandı" ifadesi anlamını yitirir.

**U5'in gerçek değeri ileriye dönüktür:** bugün sistem testlerinin
yakaladığı veri hatalarını, yarın *daha ince* bir hata olduğunda
(örneğin yalnızca belirli bir adres aralığında, boot'u etkilemeyen
bir bozulma) **işlem düzeyinde ve tam adresiyle** raporlar.

---

## U1 — Aktif agent altyapısı

Eklenen sınıflar:

```systemverilog
class axil_sequencer extends uvm_sequencer #(axil_islem);
class axil_driver    extends uvm_driver    #(axil_islem);
```

`axil_driver` AXI4-Lite'ı kurallarına uygun sürer:
- **Yazma:** AW ve W kanalları `fork…join` ile **paralel**, sonra B beklenir
- **Okuma:** AR sürülür, R beklenir
- Sürülen işlem sayaçları (`surulen_yazma`, `surulen_okuma`)

`axil_agent` artık koşullu kurulum yapar:

```systemverilog
if (get_is_active() == UVM_ACTIVE) begin
    drv = axil_driver::type_id::create("drv", this);
    sqr = axil_sequencer::type_id::create("sqr", this);
end
```

**Varsayılan PASİF kalır** — teslim edilen koşumun 401.729 işlemlik
gözlem sonucu değişmez.

---

## U2 / U3 / U4 — Sequence kütüphanesi

| Sınıf | Amaç |
|---|---|
| `axil_wstrb_seq` | **U3** — 7 WSTRB deseni: `1111`, dört tek bayt, iki yarım kelime. Her yazmadan sonra geri okur (U5 doğrulasın) |
| `axil_yanit_seq` | **U3** — tanımsız adreslere erişir; interconnect DECERR döndürür |
| `axil_rastgele_seq` | **U2** — kısıtlı-rastgele: hizalı adres, `strb != 0`, 50–200 işlem |
| `axil_sanal_seq` | **U4** — iki sequencer'ı `fork…join` ile **eşzamanlı** sürer; `npu_accelerator` hakemliğine baskı uygular |
| `axil_aktif_test` | Yukarıdakileri sırayla koşturan test |

### Hedeflenen kapsam boşlukları

Ölçülen mevcut durum:

    NPU agent : strb %33,3   yanit %33,3   TOPLAM %52,1
    SoC agent : strb %66,7   yanit %100    TOPLAM %91,0

`axil_wstrb_seq` üç `strb` bin'ini de (tam_kelime / tek_bayt / yarım),
`axil_yanit_seq` ise `decerr` bin'ini uyarır.

---

## Teslim edilen regresyonda ne değişti

| | Önce | Sonra |
|---|---|---|
| `uvm_axi_agent` denetimi | 37 | **38** |
| Referans model | yok | **1.038 okuma doğrulandı** |
| Rapor | çelişkili görünüyordu | agent başına ayrık |
| Aktif agent altyapısı | yok | var (varsayılan pasif) |

**Regresyon pasif testi kullanmaya devam eder.** Aktif test
(`axil_aktif_test`) altyapıyı ve kapsam kapatma yolunu gösterir;
teslim edilen gözlem sonuçlarını değiştirmez.

---

## Şartname açısından

EK-3 protokol kontrolünü zorunlu tutar ve bu **zaten
karşılanıyordu**. U1–U6'nın hiçbiri şartname gereği değildir;
mevcut altyapının üzerine eklenen iyileştirmelerdir.

Kapsam boşlukları (`strb %33`, `yanit %33`) bir eksiklik değil,
pasif izlemenin doğal sınırıdır: NPU motoru TCM'e her zaman tam
kelime yazar ve TCM her zaman OKAY döner — o trafikte başka bir
şey **yoktur**.
