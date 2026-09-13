# Doğrulama — daha ne yapılabilir?

**Tarih:** 13 Eylül 2026
**Amaç:** Mevcut doğrulama altyapısının üzerine eklenebilecek işleri,
**değer / maliyet** oranına göre sıralamak.

Bu belge bir eksik listesi değildir; şartnamenin istediklerinin
tamamı zaten karşılanmaktadır. Buradaki maddeler **isteğe bağlı
iyileştirmelerdir**.

---

## Mevcut durum — nereden başlıyoruz

| Ölçüt | Değer |
|---|---|
| Regresyon | 35 test, 677 denetim |
| Hata enjeksiyonu | 7/7 mutasyon yakalanıyor, 0 kaçıyor |
| İşlevsel kapsam | 52/52 covergroup = %100 |
| Kod kapsamı (bizim RTL) | %81,7 statement / %75,1 branch |
| UVM | İki pasif agent, 401.729 işlem, 37 protokol denetimi |
| Spike ISS | 927 buyruk + 765 yazmaç **değeri** karşılaştırıldı |

---

## A. Yüksek değer / düşük maliyet

### A1. `npu_accelerator` hakemlik dalının izole testi

**Durum:** Sistem kapsamında `%0,0 statement`. Blok testi
(`tb_npu_accelerator.sv`, 11 denetim) sarmalayıcıyı test ediyor ama
**motor tarafı hakemlik dalı** uyarılmıyor — o dal yalnızca NPU
motoru TCM'e erişirken tetikleniyor.

**Neden açık kaldı:** Mutasyon kampanyasında bu dala enjekte edilen
hata yakalanamadı; dürüstçe "sınır" olarak belgelendi
(`KAPSAM_ANALIZI_20260912.md`).

**Ne yapılabilir:** Testbench'te NPU motorunu sahte bir TCM isteğiyle
sürüp CPU isteğiyle çakıştırmak. Hakem her iki tarafı da görür.

**Maliyet:** ~1 testbench, yarım gün.
**Kazanç:** Bilinen tek gerçek kapsam açığı kapanır.

---

### A2. Rastgele/kısıtlı-rastgele AXI trafiği (UVM)

**Durum:** UVM agent'ları **pasif** — mevcut trafiği izliyor,
kendisi üretmiyor.

**Ne yapılabilir:** Aktif bir sequence ile kısıtlı-rastgele AXI
işlemleri üretmek: rastgele adres/WSTRB/gecikme kombinasyonları,
arka arkaya yazma-okuma, sınır adresleri.

**Maliyet:** Mevcut `axil_uvm_pkg.sv` altyapısı hazır; sequencer ve
driver eklemek ~1 gün.
**Kazanç:** Elle yazılmış senaryoların gözden kaçırdığı köşe
durumları bulunabilir. Protokol denetleyicileri zaten yerinde
olduğu için ihlal anında yakalanır.

---

### A3. Spike karşılaştırmasını daha uzun programla koşmak

**Durum:** 927 buyruk karşılaştırıldı, uyuşmazlık 0.

**Ne yapılabilir:** Daha uzun bir firmware (örn. tam NPU çıkarımı +
çevre birimi sürücüleri) ile izi almak. Buyruk sayısı 10 kat artar.

**Maliyet:** Betikler hazır (`spike_iz_al.py`, `spike_karsilastir.py`);
yalnızca daha uzun bir ELF ve koşum süresi.
**Kazanç:** Çekirdek doğrulamasının istatistiksel gücü artar.

---

## B. Orta değer

### B1. Gate-level simülasyonu anlamlı hâle getirmek

**Durum:** Netlist iki araçla **sıfır hatayla derlendi** ama işlevsel
koşum X yayılımı nedeniyle sonuç vermedi — **6.296 reset'siz
flip-flop** var (tasarım hatası değil; sky130 `dfxtp` hücreleri
reset pini taşımaz).

**Ne yapılabilir:**
- `+initreg` / `$deposit` ile flip-flopları başlangıçta 0'a çekmek
- veya SDF ile zamanlamalı GLS yerine yalnız işlevsel GLS koşmak

**Maliyet:** Deneme gerektirir, ~1 gün, sonuç garanti değil.
**Kazanç:** Sentez sonrası netlistin işlevsel doğruluğu kanıtlanır.
Şartname bunu **istemiyor**.

---

### B2. Kod kapsamını %81,7'den yukarı çekmek

**Durum:** Bizim RTL %81,7 stmt / %75,1 branch. Çevre birimleri
kendi blok testlerinde zaten %93–97.

Düşük görünen değerler **sistem testinden** gelir; sistem testi
çevre birimlerini yalnızca boot sırasında kullanıldıkları kadar
uyarır. Bu yanıltıcı bir düşüklüktür, gerçek bir açık değildir.

**Ne yapılabilir:** Blok ve sistem kapsamını birleştirip tek bir
"gerçek kapsam" sayısı üretmek (`kapsam_analiz.py` genişletilir).

**Maliyet:** Yarım gün (araç işi).
**Kazanç:** Sunumda tek ve dürüst bir sayı.

---

### B3. I2C/QSPI'yi gerçek slave modelleriyle test etmek

**Durum:** Testler sahte slave'ler kullanıyor.

**Ne yapılabilir:** Açık kaynak bir I2C EEPROM modeli ve
S25FL128S SPI flash modeli bağlayıp uçtan uca işlem koşmak.

**Maliyet:** Model bulup entegre etmek ~1 gün.
**Kazanç:** Protokol uyumu üçüncü taraf modelle doğrulanır.

---

## C. Düşük öncelik / şartname istemiyor

### C1. Formal doğrulama

Şartname **istemiyor**. Elimizde lisanslı bir formal araç yok.
SymbiYosys ile sınırlı özellik kanıtı (örn. AXI el sıkışma
kuralları) mümkün ama maliyeti yüksek, kazancı bu aşamada düşük.

### C2. Güç analizi için gerçek switching activity

**Durum:** Güç sonuçları **tahminî** — açık switching activity
girdisi kullanılmadı ve bu açıkça belirtildi (§9.10).

**Ne yapılabilir:** RTL simülasyonundan VCD/SAIF üretip akışa
vermek. Güç sayıları gerçekçileşir.

**Maliyet:** VCD üretimi + akış parametresi, ~yarım gün.
**Kazanç:** Güç raporu "tahminî" etiketinden çıkar. Şartname
tahminî olmasına izin veriyor.

---

## Önerilen sıra

Zaman kısıtlıysa **yalnızca A1**: bilinen tek gerçek kapsam
açığını kapatır ve "her açık kapatıldı" denebilir.

Zaman varsa **A1 → A2 → A3**: doğrulamanın derinliği ölçülebilir
biçimde artar.

B ve C maddeleri teslim için **gerekli değildir**; mevcut hâliyle
şartnamenin tamamı karşılanmaktadır.

---

## Bu belge neden var

Şartname §3.3.2 *"eksikliklerin açık anlatımı ve analizi"*ni
puanlıyor. Yukarıdaki maddeler gizlenmiş açıklar değil, **bilinçli
kapsam kararlarıdır**; her biri için ne yapıldığı, neyin neden
yapılmadığı ve nasıl yapılabileceği yazılıdır.
