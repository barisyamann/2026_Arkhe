# UVM doğrulamasında daha ne yapılabilir?

**Tarih:** 13 Eylül 2026
**Yöntem:** Mevcut UVM altyapısının **ölçülen** çıktısı incelenerek,
neyin kapalı neyin açık olduğu tespit edildi.

---

## 1. Şu an ne var — ölçülmüş durum

`tb/uvm/axil_uvm_pkg.sv` — 1283 satır, yedi sınıf:

| Sınıf | Rol | Durum |
|---|---|---|
| `axil_islem` | `uvm_sequence_item` | ✅ |
| `axil_monitor` | `uvm_monitor` | ✅ |
| `axil_scoreboard` | `uvm_scoreboard` | ✅ |
| `soc_kapsam` | `uvm_subscriber` | ✅ |
| `axil_agent` | `uvm_agent` (**pasif**) | ✅ |
| `axil_env` | `uvm_env` | ✅ |
| `axil_passive_test` | `uvm_test` | ✅ |
| **`uvm_sequencer`** | uyarıcı sıralayıcı | ❌ **yok** |
| **`uvm_driver`** | arayüz sürücüsü | ❌ **yok** |
| **`uvm_sequence`** | senaryo tanımı | ❌ **yok** |

**Sonuç:** UVM'in *gözlem* yarısı tam, *uyarım* yarısı yok.
İki agent da **pasif** — mevcut trafiği izliyor, kendisi üretmiyor.

### Ölçülen işlem hacmi

    NPU motoru -> TCM  : 162.064 islem
    SoC ana yolu       : 239.665 islem
    TOPLAM             : 401.729 islem

Ham sinyal çapraz kontrolü **birebir tutuyor**:

    R el sikismasi : 382.691   monitor okuma : 382.691
    B el sikismasi :  19.038   monitor yazma :  19.038
    [OK] monitor hicbir islemi kacirmadi

### Denetlenen protokol kuralları (hepsi geçiyor)

- VALID kararlılığı, AR/AW/W/R/B — ARM IHI0022 **A3.2.1**
- Reset'te VALID yüksek olmamalı — **A3.1.2**
- EXOKAY (2'b01) yasağı — **A3.4.4** (`illegal_bins` ile de yakalanır)
- El sıkışmada X/Z yok
- Adres 4 bayta hizalı
- Yazmalarda `WSTRB != 0`
- Asılı kalan işlem yok (>10 µs)

---

## 2. Ölçülen kapsam boşlukları

```
NPU agent : tur %100.0   bolge %75.0   strb %33.3   yanit %33.3   TOPLAM %52.1
SoC agent : tur %100.0   bolge %100.0  strb %66.7   yanit %100.0  TOPLAM %91.0
```

### Boşluklar neden var

**`strb %33.3`** — üç bin tanımlı (`tam_kelime`, `tek_bayt`, `yarim`),
yalnızca biri dolmuş. Log doğruluyor:

    WSTRB desenleri - strb=0xf : 16 yazma
    kismi yazma = 0

NPU motoru TCM'e **her zaman tam kelime** yazar. Bayt-seçmeli yazma
bu arayüzde hiç oluşmaz.

**`yanit %33.3`** — üç bin (`okay`, `slverr`, `decerr`), yalnızca
`okay` görülmüş. NPU'nun TCM'i her zaman OKAY döner.

**`bolge %75.0`** — dört TCM bölgesinden üçü uyarılmış.

**Kritik nokta:** Bu boşluklar **pasif izlemeyle kapatılamaz**.
Trafik ne ise o görülür; görülmeyen bir senaryoyu monitör
uyduramaz. Kapatmanın tek yolu **aktif uyarımdır**.

---

## 3. Yapılabilecekler — değer/maliyet sıralı

### U1. Aktif agent: sequencer + driver + sequence ⭐ en yüksek değer

**Ne:** `axil_agent`'a `UVM_ACTIVE` modu eklemek; `axil_driver` AXI4-Lite
sinyallerini sürsün, `axil_sequencer` işlemleri dağıtsın.

**Neden değerli:** Yukarıdaki üç kapsam boşluğunun **hepsini** kapatır,
çünkü artık ne göreceğimize biz karar veririz.

**Nasıl:** Altyapının çoğu hazır — `axil_islem` zaten
`uvm_sequence_item`. Eklenecekler:

```systemverilog
class axil_driver extends uvm_driver #(axil_islem);
    // seq_item_port.get_next_item() -> vif sinyallerini sur -> item_done()
endclass

class axil_sequencer extends uvm_sequencer #(axil_islem);
endclass
```

`axil_agent::build_phase` içinde `if (get_is_active() == UVM_ACTIVE)`
ile koşullu oluşturma.

**Maliyet:** ~1 gün. **Kazanç:** U2–U5'in tamamının önkoşulu.

---

### U2. Kısıtlı-rastgele sequence

**Ne:** `axil_islem`'e kısıt ekleyip rastgele işlem üretmek:

```systemverilog
class axil_rastgele_seq extends uvm_sequence #(axil_islem);
    rand int unsigned adet;
    constraint c_adet { adet inside {[100:1000]}; }
    // islem icinde: adres hizali, strb != 0, tur dagilimi
endclass
```

**Neden değerli:** Elle yazılmış senaryoların gözden kaçırdığı
kombinasyonları bulur. **Protokol denetleyicileri zaten yerinde**
olduğu için bir ihlal anında yakalanır — yani rastgele trafik
"serbest" hata avıdır.

**Maliyet:** U1'den sonra ~yarım gün.

---

### U3. Yönlendirilmiş sequence'lerle kapsam boşluklarını kapatmak

Ölçülen boşluklara **doğrudan** nişan alan senaryolar:

| Boşluk | Sequence |
|---|---|
| `strb` tek_bayt | Her bayt konumuna tek tek yazma (4 desen) |
| `strb` yarım | `4'b0011` ve `4'b1100` ile yarım kelime |
| `yanit` SLVERR/DECERR | Tanımsız adrese erişim (interconnect DECERR döner) |
| `bolge` eksik dördüncü | O adres aralığına kasıtlı erişim |

**Kazanç:** Kapsam %52,1 → **%100'e yakın** çıkar ve bu **gerçek**
bir artıştır (bin'ler fiilen uyarılır, sayı oynanmaz).

**Maliyet:** U1'den sonra ~yarım gün.

---

### U4. Sanal sequence — iki arayüzü eşzamanlı sürmek

**Ne:** NPU TCM arayüzü ile SoC ana yolunu **aynı anda** sürmek.

**Neden değerli:** `npu_accelerator` hakemliği tam olarak bu durumda
zorlanır — CPU ve motor aynı anda TCM'e gitmek isterse. A1 testi bunu
blok düzeyinde yaptı; sanal sequence sistem düzeyinde ve **rastgele
zamanlamayla** yapardı.

**Maliyet:** U1 + U2'den sonra ~yarım gün.

---

### U5. Scoreboard'a referans model (şu an yok)

**Ne:** Şu anki scoreboard **protokol** doğruluyor ama **veri
doğruluğu** doğrulamıyor — yazılan değerin geri okunduğunu
kontrol etmiyor.

**Nasıl:** Basit bir ilişkisel dizi referans belleği:

```systemverilog
bit [31:0] ref_mem [bit [31:0]];
// yazma -> ref_mem[adres] = veri (wstrb'ye gore bayt birlestirme)
// okuma -> ref_mem varsa karsilastir
```

**Neden değerli:** Hakemlik hatası, adres çözme hatası veya WSTRB
hatası **veri düzeyinde** yakalanır. Şu an bunlar ancak ayrı blok
testleriyle yakalanıyor.

**Maliyet:** ~yarım gün, U1 gerektirmez — **pasif modda da
çalışır**. Değer/maliyet oranı en iyi ikinci madde.

---

### U6. Kapsam raporunu netleştirmek (küçük ama faydalı)

Mevcut özet kafa karıştırıcı:

```
okuma islemi : 382691      <- IKI monitorun TOPLAMI (static sayac)
yazma islemi :  19038      <- IKI monitorun TOPLAMI
toplam islem : 162064      <- YALNIZCA NPU scoreboard
```

Sayaçlar `static` olduğu için iki monitör örneği aynı değişkeni
paylaşıyor. Aritmetik doğru
(162.064 + 239.665 = 401.729 = 382.691 + 19.038) ama **sunum
yanıltıcı**.

**Ne:** Özeti agent başına ayırmak.
**Maliyet:** ~1 saat. **Kazanç:** Rapor okunabilirliği.

---

## 4. Önerilen sıra

| Öncelik | Madde | Maliyet | Kazanç |
|---|---|---|---|
| 1 | **U6** rapor netleştirme | 1 saat | Yanıltıcı sunum düzelir |
| 2 | **U5** referans model | yarım gün | Veri doğruluğu denetlenir (pasif modda da çalışır) |
| 3 | **U1** aktif agent | 1 gün | U2–U4'ün önkoşulu |
| 4 | **U3** yönlendirilmiş seq | yarım gün | Kapsam %52 → ~%100 |
| 5 | **U2** rastgele seq | yarım gün | Bilinmeyen hata avı |
| 6 | **U4** sanal sequence | yarım gün | Hakemlik sistem düzeyinde zorlanır |

**Zaman kısıtlıysa U6 + U5**: bir günden az sürer, raporu düzeltir
ve doğrulamaya gerçek bir denetim boyutu (veri doğruluğu) ekler.

---

## 5. Şartname açısından durum

EK-3 **protokol kontrolünü zorunlu** tutuyor ve bu **karşılanmış
durumda**: iki agent, 401.729 işlem, 37 denetim, ARM IHI0022
kurallarına göre doğrulama, ham sinyal çapraz kontrolü.

Yukarıdaki maddelerin **hiçbiri şartname gereği değildir**.
Hepsi, mevcut altyapının üzerine eklenebilecek iyileştirmelerdir.

Kapsam boşlukları (`strb %33`, `yanit %33`) bir **eksiklik değil**,
pasif izlemenin doğal sınırıdır: NPU motoru TCM'e her zaman tam
kelime yazar ve TCM her zaman OKAY döner — o trafikte başka bir
şey **yoktur**. Bu, `UVM_KAPSAM_ARASTIRMASI.md` içinde de
ölçülerek açıklanmıştır.
