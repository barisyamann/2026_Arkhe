# Doğrulama genişletmesi — 9 Eylül 2026 gecesi

Bu belge, 8–9 Eylül gecesi yapılan doğrulama genişletmesinin ne eklediğini ve
her eklemenin **neyi yakaladığını** kaydeder. Hiçbiri `main`'e push edilmemiştir;
inceleme sonrası karar verilecektir.

## Toplam

| | Önce | Sonra |
|---|---:|---:|
| Test sayısı | 16 | 16 |
| **Toplam denetim** | **374** | **422** |
| Spike ISS karşılaştırılan buyruk | 409 | **927** |

Tam regresyon: 16/16 test geçti. `asic/` dizinine ve sentezlenen RTL'e
dokunulmamıştır; yalnızca testbench'ler, çekirdek test programı ve kanıt
dosyaları değişmiştir.

---

## 1. Spike ISS — 409 → 927 buyruk

Spike 1.1.1-dev sunucuda Nix ile kuruldu (`dtc` 1.7.2 bağımlılığıyla).
`core_test.c` iki turda genişletildi.

### Birinci tur — kenar durumları

Önceki program normal değerleri uyarıyordu. ISS karşılaştırmasının asıl
değeri kenar durumlarındadır: bir çekirdek normalde doğru, sınırda yanlış
olabilir ve bunu ancak referans model yakalar.

| Eklenen | Neyi yakalar |
|---|---|
| `mulhsu` | Dokümanda listeliydi, kodda **yoktu** |
| Bölme kenar durumları | RISC-V spec 7.2: `x/0 = -1`, `x%0 = x`, `INT_MIN/-1 = INT_MIN`, `INT_MIN%-1 = 0`. RISC-V'de bölme istisna **üretmez**; yanlış uygulama normal testlerde görünmez |
| Kaydırma maskeleme | `shamt` yalnızca alt 5 bit; `a<<33` ile `a<<1` aynı olmalı |
| Gerçek `jal`/`jalr` | Önceki sürümde "fonksiyon çağrısı" yorumu vardı ama altındaki satır yalnızca toplama yapıyordu — derleyici hiçbir çağrı buyruğu üretmiyordu. `noinline` fonksiyonlar, iç içe özyineleme (yığın derinliği 6), fonksiyon işaretçisi eklendi |

### İkinci tur — CSR, bit desenleri, dallanma yolları

| Eklenen | Neyi yakalar |
|---|---|
| Salt okunur CSR'lar | `mhartid`, `mvendorid`, `marchid`, `mimpid`, `misa`. `csrr` kod çözümü ve yazmaca yazma yolu daha önce **hiç** uyarılmıyordu. Yazma yok — trap kurulumu iki ortamda farklı olurdu |
| Yürüyen bit desenleri | Yalnız-bir-bit ve yalnız-bir-sıfır. Bir ALU dilimi komşusuna sızdırıyorsa bu desenlerde görünür, rastgele değerlerde görünmeyebilir |
| Ardışık bellek erişimi | Sekiz kelimeye yaz, ters sırada oku. Adres artırma ve yazma-sonra-okuma yolu |
| Dallanmanın **her iki** yolu | Önceki turda koşullar hep doğru çıkıyordu; yanlış yol hiç koşulmamıştı |

**Sonuç: 927 buyrukta PC dizisi birebir eşleşti, 0 uyuşmazlık.**

432 buyrukta makine kodu *gösterimi* farklı: Spike ham 16-bit sıkıştırılmış
kodu, CV32E40P tracer'ı açılmış 32-bit karşılığını raporlar. Aynı buyruk,
farklı gösterim — PC eşitliği sıkıştırmanın doğru çözüldüğünü kanıtlar.

Kanıt: `evidence/spike_20260908/`

---

## 2. UVM — 17 → 29 denetim

### Sinyal düzeyi kararlılık (ARM IHI0022 A3.2.1)

Mevcut denetimler **işlem** düzeyindeydi; bir işlem *tamamlanırken* protokolü
ihlal etse orada görünmezdi. Monitor'e eklendi:

- Master kanalları (AR/AW/W): VALID yükseldikten sonra READY gelene kadar
  düşürülemez, adres/veri/strobe değiştirilemez
- Slave kanalları (R/B): aynı kural
- El sıkışan çevrimlerde X/Z denetimi — sentez sonrası netlistte veya eksik
  reset'te bilinmeyen değer taşınabilir

### İşlem düzeyi denetimler

- Yazmada `WSTRB == 0` (hiçbir bayt yazılmaz)
- Adres `[1:0] != 0` hizasız erişim
- Okuma + yazma sayımının toplamla tutarlılığı

### Fonksiyonel kapsam

- Ardışık okuma serisi — **ölçülen: 40.512 işlemlik kesintisiz seri**, DMA/NPU
  akışının gerçekten seri okuduğunu gösterir
- Adres aralığı taraması — ölçülen: `0x00000000 .. 0x000076bc`
- WSTRB deseni dağılımı

**Kapsam ölçümü bir kör nokta buldu:** yalnızca `strb=0xf` deseni uyarılmış,
kısmi yazma (bayt/yarım kelime) bu arayüzde hiç test edilmemiş. Sayı tek başına
bir şey kanıtlamaz ama neyin hiç uyarılmadığını gösterir.

Ölçülen: 81.032 AXI4-Lite işlemi, dokuz denetimin hepsi geçti.

---

## 3. NPU blok testi — 9 → 27 denetim

Önceki sürüm yalnızca softmax toplamını ve argmax tutarlılığını denetliyordu.
Bu ikisi geçerken de motor yanlış çalışabilir.

| Eklenen | Neyi yakalar |
|---|---|
| Olasılıklar negatif değil | İşaretli/işaretsiz dönüşüm hatası, taşma |
| Üst sınır aşılmıyor | Q0.12 formatı bozulması |
| `class_o` 0..3 aralığında | Geçersiz sınıf çıkışı |
| Kazanan sınıf baskın | **Ağırlıkların sıfır olması** — 6 Eylül 2026'da tam bu belirti gözlenmişti (bias'a eşit çıkış) |
| **FC ağırlık bölgesi ezilmemiş** | Motor TCM 3584..7583'e yazarsa bir *sonraki* çıkarım sessizce bozulur; tek çıkarımlık test bunu hiç görmez |
| Çıkışta X/Z yok | Eksik reset; `int'()` dönüşümü X'i sessizce 0 yapar |

**Bir düzeltme:** İlk denemede SILENCE senaryosu düştü çünkü "kazanan sınıf
baskın olmalı" denetimi eklenmişti. Ancak sessiz girdide dört sınıfın eşit
çıkması (1024/1024/1024/1024) **doğru davranıştır** — model sessizlikte hiçbir
kelimeden emin olmamalıdır. Denetim yanlıştı, motor değil; SILENCE muaf tutuldu.

---

## 4. I2C — 14 → 29 denetim

En zayıf çevre birimi testiydi.

| Eklenen | Neyi yakalar |
|---|---|
| Reset sonrası yazmaç değerleri | Hiçbiri denetlenmiyordu. Bir yazmaç reset'te yanlış kalırsa sonraki testler **üzerine yazdığı** için hatayı maskeler |
| `$isunknown` X/Z denetimi | Güç verildiğinde bilinmeyen durum |
| `I2C_NBY` tam sınır değerleri | 2, 4 (üst sınır), 5 (sınırın hemen üstü), `0xFFFFFFFF` (taşma) |
| `I2C_ADR` üst bit atma | `[6:0]` tutulduğu denetleniyordu ama üst bitlerin **sızmadığı** denetlenmemişti |
| `I2C_TDR` tam genişlik | `0xFFFFFFFF`, `0xA5A55A5A` desenleri |
| Bayrak temizleme | Donanımın **kurduğu** denetleniyordu, yazılımın **temizleyebildiği** denetlenmiyordu |

**Bir düzeltme:** İlk denemede iki denetim düştü çünkü `0x08` ve `0x0C`
adresleri ters yazılmıştı (`0x08` = RDR salt okunur, `0x0C` = TDR). Test doğru
davrandı — salt okunur yazmaca yazınca değer değişmedi.

---

## 5. Sistem testi — 13 → 17 denetim

Blok testleri her çevre birimini **tek başına** doğrular; sistem testi uçtan
uca akışı doğrular. Arada kalan boşluk: **bütün sistem için doğru olması
gereken, hiçbir blok testinin göremeyeceği** değişmezler.

| Eklenen | Neyi yakalar |
|---|---|
| Bellek haritası ayrıklığı | İki çevre birimi aynı adresi decode ederse veri yolunda çatışma olur; hangisinin kazandığı sentez sonrası değişebilir. Blok testleri bunu **asla** göremez |
| QSPI CS boşta pasif | `qspi_cs_n` aktif-düşük; boşta '0' kalırsa flash sürekli seçili kalır |
| I2C açık drenaj kuralı | Hatlar yalnızca **aşağı** çekilebilir; '1' sürmek çok-master veriyolunda kısa devre demektir |
| UART boşta MARK | Boşta '0' kalırsa alıcıda sürekli BREAK görünür, ilk gerçek bayt kaybolur |

---

## Değişen dosyalar

```
sw_nexys/src/core_test.c                    83 satır
sw_nexys/build/core_test.hex               230 satır  (üretilen)
tb/uvm/axil_uvm_pkg.sv                      80 satır
tb/tb_npu_compute_engine.sv                 70 satır
tb/tb_soc_top.sv                            79 satır
evidence/spike_20260908/spike_iz.txt       529 satır  (üretilen)
evidence/spike_20260908/karsilastirma_sonucu.txt  16 satır
rtl/Cevre_Birimleri/i2c_peripheral_tb.sv    85 satır  (önceki commit)
```

`asic/` dizinine, sentezlenen RTL'e ve teslim paketine dokunulmamıştır.
