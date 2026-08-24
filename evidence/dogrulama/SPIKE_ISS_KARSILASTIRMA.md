# Spike ISS ile CV32E40P Komut İzi Karşılaştırması

**Takım Arkhe — TEKNOFEST 2026 Çip Tasarım Yarışması**
Tarih: 24 Ağustos 2026

---

## 1. Şartname Gerekçesi

**Şartname s.569:**
> "CV32E40P RISC-V işlemci çekirdeğinin doğrulanmasının bir buyruk kümesi
> benzetim aracı (ISS) ile (Örn. Spike ISS) yapılması **beklenmektedir**."

**EK-3, Çekirdek Testleri:**
> "Çekirdeğin doğruluğunu sağlamak için komut izlerinin (instruction trace)
> **tür ve sıra** bakımından eşleşip eşleşmediğini görmek adına Spike ISS ve
> yazılım testleri (C/assembly) kullanılarak yapılan CV32E40P çekirdeğinin
> **bireysel** testleri. Bu testler kendi kendini kontrol eden (self-checking)
> yapıda olmalı..."

---

## 2. Önceki Durumun Düzeltilmesi

DTR'de şu ifade yer alıyordu:

> "İlk 20 buyruk Spike ile 20/20 eşleşti, %100 uyum"

**Bu iddia gerçek bir Spike koşumuna dayanmıyordu.** Karşılaştırma, elle
yazılmış bir PC listesine karşı yapılmıştı. Spike hiç kurulmamış ve hiç
çalıştırılmamıştı.

Bu belge o boşluğu gerçek ölçümle kapatır. Sayı da değişti: 20 değil **409**
buyruk karşılaştırıldı.

---

## 3. Neden Ayrı Bir Test Programı

Spike bizim SoC'umuzu değil, **çıplak bir RISC-V çekirdeğini** modeller.
UART, GPIO, NPU, DMA, QSPI gibi çevre birimleri Spike'ta **yoktur**.

`main.c` ilk birkaç yüz buyrukta UART'a yazmaya başlar; Spike orada ya trap
atar ya da farklı davranır ve izler ayrışır. Bu bir çekirdek hatası değil,
**platform farkıdır**.

Bu yüzden `sw_nexys/src/core_test.c` yazıldı. Yalnızca çekirdek ve belleği
kullanır:

- hiçbir çevre birimi adresine erişim yok
- hiçbir CSR yazımı yok (kesme/trap kurulumu yok)
- sonsuz döngü yok; düz akış, sonda kendini durdurur

### Uyarılan buyruk sınıfları

| Küme | Kapsanan buyruklar |
|---|---|
| RV32I aritmetik/mantık | `add sub and or xor sll srl sra slt sltu`, `lui auipc` |
| RV32I dallanma | `beq bne blt bge bltu bgeu` (her kolun her iki sonucu) |
| RV32I atlama | `jal jalr` (fonksiyon çağrısı ve dönüş) |
| RV32I bellek | `lb lh lw lbu lhu sb sh sw` (işaretli/işaretsiz genişletme dahil) |
| RV32M | `mul mulh mulhsu mulhu div divu rem remu` |
| RV32C | derleyici `-Os` ile sıkıştırılmış biçimleri üretir |

Sonuçlar D-RAM'de `0x20001000` tabanına yazılır; `s[31] = 0xC0DE0001` imzası
programın baştan sona koştuğunu gösterir (self-checking).

---

## 4. Yol Boyunca Bulunan İki Tuzak

Bunlar kayda değer çünkü ikisi de **sessizce yanlış sonuç** üretiyordu.

### 4.1 Spike izi stdout'a değil, STDERR'e yazar

İlk denemede komut `2>/dev/null` içeriyordu ve iz **tamamen kayboldu**.
Betik boş çıktı üretti ama hata vermedi. `scripts/spike_iz_al.py` artık
`stderr=subprocess.PIPE` kullanır ve bu tuzak dosyanın başında belgelenmiştir.

### 4.2 `.data` bölümü sahte ayrışma üretti

`core_test.c`'nin ilk sürümünde tohum değerleri `static volatile` globaldi.
Bu, değerlerin `.data` bölümünde durması ve **crt0 tarafından I-RAM'den
D-RAM'e kopyalanması** demekti.

- Spike ELF'i doğrudan yüklediği için değerler onda baştan hazırdı
- RTL'de ise kopyalama zincirine bağlıydı

Sonuç: karşılaştırmada **dallanma sonuçları ayrışıyordu**. Bu bir çekirdek
hatası değil, **ortam farkıydı** — ama izde tam olarak çekirdek hatası gibi
görünüyordu.

Düzeltme: tohumlar **yerel `volatile`** yapıldı. Değerler artık buyruktan
gelir (`li` / `lui+addi`), belleğe hiç dokunulmaz, iki ortam birebir aynı
başlar. `volatile` yine şart — kaldırılırsa derleyici sabit katlama yapar ve
hiçbir aritmetik buyruk koşmaz, test boşalır.

### 4.3 Sıkıştırılmış buyruk tespiti uzunlukla yapılamaz

Spike ham 16-bit sıkıştırılmış kodu raporlar (örn. `4601`).
CV32E40P tracer'ı ise **açılmış** 32-bit karşılığını yazar (`00000613`).

İlk sürümde ayrım uzunluk karşılaştırmasıyla yapılıyordu. Açılmış biçimin
baştaki sıfırları kırpıldığı için `00000613 -> "613"`, sıkıştırılmış
`"4601"`den **kısa** görünüyordu ve 5 buyruk yanlışlıkla uyuşmazlık
sayılıyordu.

Düzeltme: RISC-V kodlama kuralı kullanıldı — **bir buyruk 32-bit ise alt iki
biti `11`'dir**. Alt iki bit `11` değilse buyruk sıkıştırılmıştır.

```python
if (int(sk, 16) & 3) != 3:   # alt iki bit '11' degil -> sikistirilmis
    sikistirilmis += 1
    continue
```

---

## 5. Ortam

| Öğe | Değer |
|---|---|
| ISS | Spike RISC-V ISA Simulator **1.1.1-dev** |
| ISA dizgesi | `rv32imc_zicsr` |
| Bellek haritası | `-m0x1000000:0x100000,0x20000000:0x10000` |
| Test ELF | `sw_nexys/build/core_test/core_test.elf` (9 224 bayt) |
| RTL izi | `cv32e40p_tracer` (`+define+CV32E40P_TRACE_EXECUTION`) |
| Benzetici | Vivado xsim 2025.2 |
| Hizalama PC | `0x01000000` (uygulamanın giriş noktası, `_start`) |

**Hizalama neden gerekli:** Spike reset vektöründen (`0x1000`) başlar ve kendi
ön yükleyicisini koşar. RTL izi ise çekirdeğin ilk retire ettiği buyruktan
başlar; testbench `boot_addr_i`'yi `0x01000000`'a zorlar. Karşılaştırma
uygulamanın giriş noktasından başlatılır; öncesi platform farkıdır, çekirdek
doğruluğu değildir.

---

## 6. Sonuç

```
Spike ham buyruk : 414
RTL   ham buyruk : 1457
hizalama PC      : 0x01000000
Spike (hizali)   : 409
RTL   (hizali)   : 409

==================================================================
KARSILASTIRMA
==================================================================
  karsilastirilan buyruk : 409
  PC uyusmazligi         : 0
  makine kodu uyusmazligi: 0
  sikistirilmis (beklenen): 156

SONUC: 409 buyrukta PC dizisi BIREBIR ESLESTI.
       Spike ISS ile RTL izleri TUR ve SIRA bakimindan ayni.
```

| Ölçüm | Değer |
|---|---|
| Karşılaştırılan buyruk | **409** |
| PC uyuşmazlığı | **0** |
| Makine kodu uyuşmazlığı | **0** |
| Sıkıştırılmış gösterim farkı | 156 (beklenen — §4.3) |

**RTL ham izi 1457 buyruk** çünkü simülasyon crt0'ın sonsuz döngüsünde
beklemeye devam eder. Her iki iz de döngüye girildiği noktada kesilir
(`donguyu_kes`), bu yüzden hizalı uzunluklar birebir eşittir: **409 = 409**.

EK-3'ün istediği ölçüt — komut izlerinin **tür ve sıra** bakımından eşleşmesi
— sağlanmıştır.

---

## 7. Yeniden Üretim

```bash
# 1) Test programini derle
python sw_nexys/scripts/build.py

# 2) RTL izini uret (regresyonun 'cekirdek_izi' testi)
python scripts/run_regression.py --test cekirdek_izi
#    -> build/coretest/trace_core_00000000.log

# 3) Spike izini al  (Linux / WSL gerektirir)
python3 scripts/spike_iz_al.py
#    -> build/spike/spike_iz.txt

# 4) Karsilastir
python scripts/spike_karsilastir.py
```

---

## 8. İlgili Dosyalar

| Dosya | Rol |
|---|---|
| `sw_nexys/src/core_test.c` | Çevre birimi kullanmayan çekirdek test programı |
| `scripts/spike_iz_al.py` | Spike'ı koşar, izi normalize eder, döngüyü keser |
| `scripts/spike_karsilastir.py` | İki izi tür ve sıra bakımından karşılaştırır |
| `scripts/run_regression.py` | `cekirdek_izi` testi — RTL izini üretir |
| `tb/tb_soc_top.sv` | `CORE_TEST` ve `CV32E40P_TRACE_EXECUTION` desteği |
