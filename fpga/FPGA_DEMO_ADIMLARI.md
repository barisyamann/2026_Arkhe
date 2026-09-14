# FPGA Demo — adım adım uygulama kılavuzu

**Hedef:** Nexys A7-100T kartına Arkhe SoC'u yükleyip TEKNOFEST'in resmi
demo aracıyla uçtan uca çalıştırmak.

Bu belge, demoyu **kendiniz yapmanız** için yazılmıştır. Her adımda ne
göreceğiniz ve ters giderse ne yapacağınız yazılıdır.

## Üç demo var — hangisi ne işe yarar

| Demo | Ne ölçer | Ek donanım | Bölüm |
|---|---|---|---|
| **A** | TEKNOFEST'in resmi aracı; sınıflandırma doğruluğu ve arayüz uyumu | Pmod JB'ye 3,3 V UART-TTL modülü | aşağıda |
| **B** | SoC'un tamamı: CPU, bellek, çevre birimleri, NPU | yok (tek USB) | aşağıda |
| **C** | **B'nin üst kümesi** + harici ESP32 ile **gerçek I2C** | ESP32 (Pmod JA) | aşağıda |

> **Demo C, Demo B'yi kapsar.** C'yi koşarsanız B'yi ayrıca koşmanıza
> gerek yoktur; C tüm B denetimlerini ve üzerine 3 I2C denetimini içerir.
>
> **Jüri demosu için asıl olan A'dır** — resmi araç odur. B ve C kendi
> doğrulama kanıtlarımızdır.

Her üç bitstream de **14 Eylül 2026'da güncel RTL'den** üretilmiştir;
ASIC teslimiyle aynı kaynak.

---

## Gerekenler

| | |
|---|---|
| Kart | Digilent **Nexys A7-100T** |
| Kablo | USB (kart ↔ bilgisayar) — programlama ve UART aynı kablodan |
| Yazılım | Vivado (Hardware Manager yeterli) · Python 3.9+ |
| Python paketi | `pyserial` (GUI için ayrıca `tkinter`) |

    python -m pip install pyserial

---

## Adım 1 — Kartı bağla ve COM portunu bul

1. Kartı USB ile bağlayın, güç anahtarını **ON** yapın.
2. Windows: **Aygıt Yöneticisi → Bağlantı Noktaları (COM ve LPT)**
   Orada `USB Serial Port (COMxx)` göreceksiniz. **COM numarasını not edin.**

> Kart görünmüyorsa Digilent USB sürücüleri kurulu değildir; Vivado ile
> birlikte gelen "Install Cable Drivers" adımını çalıştırın.

---

## Adım 2 — Bitstream'i karta yükle

**Vivado Hardware Manager ile:**

1. Vivado'yu açın → **Open Hardware Manager**
2. **Open target → Auto Connect** (kart `xc7a100t_0` olarak görünür)
3. **Program device** → bitstream dosyasını seçin:

```
fpga/nexys_demo_20260908/bitstream/nexys_top.bit
```

4. **Program**

**Ne göreceksiniz:** Kart üzerindeki `DONE` LED'i yanar. Programlama
birkaç saniye sürer.

> **Dikkat:** `JURI_FPGA_TESTI/nexys_usb_top.bit` **farklı bir sürümdür**
> (tek USB üzerinden çalışan tanılama firmware'i). Demo için yukarıdaki
> `nexys_demo/bitstream/nexys_top.bit` kullanılmalıdır — pin haritaları
> ve firmware farklıdır, karıştırmayın.

---

## Demo A — TEKNOFEST'in resmi aracı (`demo_harness.py`)

Bu, jürinin kullanacağı araçtır. Çalışma dizini:

```powershell
cd C:\Users\ybari\2026_Arkhe\fpga\nexys_demo_20260908\demo
```

### A-1. Araç ayakta mı (kart gerekmez)

```powershell
python demo_harness.py --version
python demo_harness.py ports
```

`ports` bağlı COM portlarını listeler. **İki port göreceksiniz** ve ikisi de
lazım (aşağıya bakın).

### A-2. İki portu da belirle

Bu demo **iki ayrı seri hat** kullanır — tek port yetmez:

| Rol | Ne | Nereden | ICD'deki varsayılan |
|---|---|---|---|
| **core** | Kartın durum/sonuç çıktısı | Kart üstü USB-UART (C4/D4) | `COM16` @ 115200 |
| **stream** | NPU'ya veri sürülen hat | **Harici 3,3 V UART-TTL modülü, Pmod JB** | `COM12` @ 1000000 |

**Pmod JB bağlantısı zorunludur** (Demo A için):

| Pmod JB | FPGA pini | Modül tarafı |
|---|---|---|
| JB1 | `D14` | modülün **TX**'i |
| JB2 | `F16` | modülün **RX**'i |
| JB5 veya JB6 | GND | modülün GND'si |

> Modülün TX'i JB1'e, RX'i JB2'ye gider (çapraz). GND'yi bağlamayı unutmayın.

### A-2b. Flash imajını yaz — **bu adım şart**

`nexys_top.bit` yalnızca FPGA mantığını yükler. Uygulama yazılımı ve NPU
ağırlıkları **flash'ta** durur ve `.bit` onu değiştirmez. Demo A'nın
beklediği firmware `flash_demo.bin`'dir (`Stream ready` banner'ını yazan,
`[IRQ] Class: N` döndüren sürüm).

> **Belirti:** Flash'ta başka bir imaj varsa (örn. `flash_npu_demo.bin` —
> interaktif NPU demosu) kart çalışır, seri terminale kendi testini
> basar, ama `demo_harness` her örnekte **TIMEOUT** alır. Kart bozuk
> değildir; sadece yanlış uygulama yüklüdür.

**1) MCS üret** — Vivado Tcl konsolunda:

```tcl
cd C:/Users/ybari/2026_Arkhe/fpga/nexys_demo_20260908/firmware/build
write_cfgmem -format mcs -size 16 -interface SPIx4 \
  -loadbit  "up 0x00000000 C:/Users/ybari/2026_Arkhe/fpga/nexys_demo_20260908/bitstream/nexys_top.bit" \
  -loaddata "up 0x00800000 C:/Users/ybari/2026_Arkhe/fpga/nexys_demo_20260908/firmware/build/flash_demo.bin" \
  -file     "C:/Users/ybari/2026_Arkhe/fpga/nexys_demo_20260908/firmware/build/arkhe_stream_demo.mcs" -force
```

**2) Programla** — Hardware Manager:

1. **Add Configuration Memory Device** → `s25fl128s...`
2. **Program Configuration Memory Device** → `arkhe_stream_demo.mcs`
3. Erase + Program + Verify işaretli
4. Bitince kartı yeniden başlat (güç anahtarı veya **PROG** düğmesi)

**3) Doğrula** — banner geliyor mu:

```powershell
python demo_harness.py probe -c arkhe_icd.json --seconds 15
```

`Stream ready` satırını görmelisin. Görmüyorsan flash yazılmamıştır.

> Flash yerleşimi: `0x800000` uygulama, `0x802000` NPU ağırlıkları.

### A-3. ICD'yi kendi portlarınla güncelle

`arkhe_icd.json` içinde iki port alanı var. Kendi COM numaralarını yaz:

```powershell
python -c "import json;p='arkhe_icd.json';d=json.load(open(p,encoding='utf-8'));d['stream']['port']['port']='COM12';d['core']['port']['port']='COM16';json.dump(d,open(p,'w',encoding='utf-8'),ensure_ascii=False,indent=2);print('stream',d['stream']['port']['port'],'core',d['core']['port']['port'])"
```

`COM12` / `COM16` yerine **A-1'de gördüğün gerçek numaraları** yaz.

### A-4. ICD'yi doğrula

```powershell
python demo_harness.py validate -c arkhe_icd.json
```

> Dikkat: bayrak `-c` (veya `--config`), `-i` **değil**.

**Beklenen:** hatasız geçer.

### A-5. Donanımsız prova (isteğe bağlı)

```powershell
python demo_harness.py run -c arkhe_icd.json --dry-run
```

> **Bu adımda her senaryo KALDI/zaman aşımı verir — normaldir.**
> `--dry-run` sahte bir cihaz canlandırmaz; portu açmadan koşar, yani
> yanıt verecek kimse yoktur. Sadece aracın çöküp çökmediğini, ICD'nin
> okunduğunu ve `results/` klasörünün yazıldığını gösterir.
> Gerçek sonuç için A-6'ya geç.

### A-6. Gerçek koşum

```powershell
python demo_harness.py run -c arkhe_icd.json --manifest public_dataset/manifest.csv --data-dir public_dataset
```

> **`--manifest` vermeyi atlama.** Verilmezse araç **sentetik** veri
> üretir (`synthetic_0000`...), bunların altın referansı olmadığı için
> `golden_agreement_pct` **hesaplanamaz** ve çıktıda
> *"veri setinde 'golden' sütunu yok"* uyarısı görürsün. Referans
> koşumumuz (156/156, %100) tam olarak yukarıdaki komutla alınmıştır.

Portları ICD'ye yazmak yerine komut satırından da verebilirsin:

```powershell
python demo_harness.py run -c arkhe_icd.json --stream-port COM12 --core-port COM16
```

Kısa deneme için `-n 20` ekle (20 örnek). Sağlamlık senaryolarını atlamak
için `--no-robustness`.

**Grafik arayüz:**

```powershell
python demo_harness.py gui
```

### A-7. Sonuç

Çıktı: `results/ARKHE_<tarih>_<saat>/` — içinde `summary.json`,
`samples.csv`, `robustness.csv`, `report.md`.

Referans koşumuz `fpga/demo_teknofest/sonuclar/` altındadır. Karşılaştır:

| Ölçüt | Referans değer |
|---|---|
| `total_samples` / `answered` | 156 / 156 |
| `timeouts` | **0** |
| `golden_agreement_pct` | **100.0** |
| `mismatch_count` | **0** |
| Gecikme (medyan) | 8,02 ms |
| Hızlanma | **177×** (yazılım referansı 1418 ms) |
| Sağlamlık | **9 PASS / 1 FAIL / 1 SKIP** — `back_to_back` beş çerçevenin dördüne yanıt verir (bilinen sınırlama, kök nedeni bulundu); `peripheral_interleave` opsiyoneldir ve atlanır |

`golden_agreement_pct = 100.0` ve `timeouts = 0` görüyorsan demo başarılıdır.

---

## Demo B — Bizim kendi tam test firmware'imiz (`run_jury.py`)

Demo A sınıflandırma doğruluğunu ölçer. Demo B **SoC'un tamamını**
sınar: CPU, D-RAM, NPU TCM, GPIO, Timer, DMA, bus fault, I2C, UART2 ve
uçtan uca NPU çıkarımı. Tek USB kablosuyla çalışır, Pmod gerekmez.

Çalışma dizini:

```powershell
cd C:\Users\ybari\2026_Arkhe\fpga\JURI_FPGA_TESTI
```

### B-1. Dosyaları donanımsız doğrula

```powershell
python run_jury.py --validate
```

Karta bağlanmaz, sadece yerel girdi dosyalarını denetler.

### B-2. Flash imajını yaz (bu adım şart)

Demo B'nin test yazılımı **flash'ta** durur; sadece `.bit` yüklemek
yetmez. İki dosya gerekir:

- `nexys_usb_top.bit` — bu klasörde, hazır
- `flash_jury.bin` — bu klasörde, hazır (flash'a `0x00800000` adresine)

**Vivado Hardware Manager:**

1. Open Target → Auto Connect
2. Kartın konfigürasyon belleğini seç (`s25fl128s...`)
3. **Add Configuration Memory Device** → **Program Configuration Memory Device**
4. Dosya olarak `flash_jury.bin`, **başlangıç adresi `0x00800000`**;
   Erase + Program + Verify işaretli
5. Sonra **Program Device** ile `nexys_usb_top.bit`

> **Tek `.mcs` tercih edersen** (depoda yok, türetilmiş dosyadır) Vivado
> Tcl konsolunda üret:
>
> ```tcl
> cd C:/Users/ybari/2026_Arkhe/fpga/JURI_FPGA_TESTI
> write_cfgmem -format mcs -size 16 -interface SPIx4 \
>   -loadbit "up 0x00000000 nexys_usb_top.bit" \
>   -loaddata "up 0x00800000 flash_jury.bin" \
>   -file arkhe_jury.mcs -force
> ```
>
> Sonra tek dosya olarak `arkhe_jury.mcs`'i programla.

> **Karıştırma:** `nexys_usb_top.bit` (Demo B) ile
> `nexys_demo_20260908/bitstream/nexys_top.bit` (Demo A) **farklı
> sürümlerdir** — boot ROM'ları ve pin haritaları ayrıdır.

### B-3. Portu bul

```powershell
python -m serial.tools.list_ports
```

Başka seri terminal açıksa **kapat** — aynı COM iki programda açılamaz.

### B-4. Tam koşum (elle kontroller dahil)

```powershell
python run_jury.py --port COM16
```

`Hazir... CPU RESET...` yazısını görünce **CPU RESET düğmesine bir kez bas.**
Sonra test bitene kadar bir daha resetleme.

**Elle yapacakların** (otomatik bölüm bittikten sonra istenir):

1. 16 anahtarın **hepsini 0** yap → Enter
2. **Hepsini 1** yap → Enter
3. **Tekrar 0** yap → Enter
4. LED desenleri gösterilir: desen doğruysa `e`, yanlışsa `h` yaz

> Anahtarları değiştirirken **CPU RESET'e basma.**
> Geçen sefer koşum `Anahtarlar 0 okunmadi` ile düştü — 1. adımda
> anahtarların gerçekten hepsi aşağıda olduğundan emin ol.

### B-5. Yalnız otomatik bölüm (elle kontrol istemezsen)

```powershell
python run_jury.py --port COM16 --skip-manual
```

Anahtar/LED bölümü rapora **SKIP** yazılır. Jüriye tam kanıt vermek
için **B-4'ü** tercih et.

Daha uzun koşum: `--rounds 20` (yedi örnek 140 kez çalışır).

### B-6. Sonuç

Program `juri_board_<tarih>_<saat>.json` ve aynı adlı `.log` üretir.

**Aranan:** JSON'da `passed = true` ve logun son satırında `GECTI`.

| Aşama | Beklenen |
|---|---|
| Öztestler | her turda 83 kontrol |
| NPU çıkarımı | 7 örnek × tur sayısı, sınıf referansla birebir |
| Çevre birimi | 34/34 |
| NPU testleri | 15/15 |
| `manual_gpio` | `PASS` (B-4) veya `SKIP` (B-5) |

Hata, zaman aşımı veya Ctrl+C durumunda test **geçmiş sayılmaz**;
rapor kısmi sonucu kaydeder.

### B-7. Demo A'ya geri dön

Demo B'nin flash imajı Demo A'nınkini ezer. Demo A'yı tekrar
çalıştıracaksan **Adım 2'yi tekrarla** ve `nexys_top.bit`'i geri yükle.

---

## Demo C — tam SoC testi + harici ESP32 I2C (`DEMO_C_I2C/run_jury.py`)

**Demo B'nin üst kümesidir.** Aynı öztestler, aynı NPU çıkarımları, aynı
anahtar/LED kontrolleri — üzerine **gerçek bir I2C cihazıyla veri
alışverişi** eklenir. Demo B'yi ayrıca koşmaya gerek yoktur.

### Neden var

Demo B'nin kendi raporu I2C'yi eksik ilan ediyordu:

> *"I2C: harici slave yok; yalnızca boş hat işlem tamamlanması"*

Yani sadece "master işlemi başlattı, `TX_DONE` kuruldu" doğrulanıyordu.
Demo C bunu kapatır: kart bir bayt yazar, ESP32 **tersini** döndürür,
kart geri okuyup karşılaştırır.

### C-1. ESP32'yi hazırla

Arduino IDE → `fpga/DEMO_C_I2C/esp32_slave/esp32_slave.ino` → yükle →
Seri Monitor **115200**:

```
ARKHE I2C SLAVE HAZIR (adres 0x42)
  SDA=GPIO21  SCL=GPIO22
```

### C-2. Bağlantı

| Nexys Pmod JA | FPGA pini | ESP32 |
|---|---|---|
| **JA1** | `C17` | **GPIO22** (SCL) |
| **JA2** | `D18` | **GPIO21** (SDA) |
| **JA5** veya **JA6** | GND | **GND** |

> **GND'yi bağlamayı unutma** — iki kartın referansı ortak olmazsa hat
> güvenilmez çalışır.
>
> 400 kHz'de sorun çıkarsa SCL ve SDA'ya 3,3 V'a giden 2,2–4,7 kΩ
> harici direnç ekle. Dahili pull-up'larla da çalışır.

### C-3. Programla

MCS hazır (`arkhe_demo_c.mcs`, bitstream + flash birlikte):

```
Hardware Manager → Add Configuration Memory Device → s25fl128s...
→ Program Configuration Memory Device → arkhe_demo_c.mcs
→ Erase + Program + Verify
→ sonra Program Device ile nexys_usb_top.bit
```

Kendin üretmek istersen: `python build_firmware.py` sonra Vivado Tcl'de
`source gen_mcs.tcl`.

### C-4. Koş

```powershell
cd C:\Users\ybari\2026_Arkhe\fpga\DEMO_C_I2C
python run_jury.py --port COM16
```

`Hazir... CPU RESET` görünce **CPU RESET'e bir kez bas**, sonra dokunma.

**Elle kısım** (otomatik bölüm bitince): 16 anahtar hepsi **0** → Enter,
hepsi **1** → Enter, tekrar **0** → Enter, sonra 4 LED deseni için
`e`/`h`.

### C-5. Beklenen sonuç

```
I2C_ESP_TX_DONE      PASS
I2C_ESP_RX_DONE      PASS
I2C_ESP_YAZILAN 5A -> I2C_ESP_OKUNAN A5
I2C_ESP_YAZILAN A5 -> I2C_ESP_OKUNAN 5A
I2C_ESP_YAZILAN 3C -> I2C_ESP_OKUNAN C3
I2C_ESP_VERI_DOGRU   PASS

GECTI: 2 x 86 oztest kontrolu, 21 NPU sonucu, UART bayt testleri
GPIO: PASS: 16 anahtar, yukselen/dusen kenar IRQ, dort LED deseni
```

ESP32 Seri Monitor'de eşzamanlı: `yazildi: 0x5A  ->  okunacak: 0xA5`

> **ESP32 bağlı değilse test sessizce geçmez.** Yazma yine `TX_DONE`
> verir (master hattı kendisi sürer) ama okuma `0xFF` döner —
> `I2C_ESP_VERI_DOGRU` 0 çıkar ve koşum KALDI der.

### Bilinen davranış: ESP32 sürücü gecikmesi

ESP32'nin `Wire` slave TX yolu bir işlem geriden gelir. Bu yüzden test
her değeri **iki kez** yazıp okur: ilk tur tamponu doldurur, ikinci tur
geri okur. Bu Arkhe SoC'un I2C kontrolcüsünde bir kusur **değildir**;
ölçülmüş ve `evidence/fpga_democ_20260914/OKUBENI.md` içinde
belgelenmiştir.

### Demo A'ya dönüş

Demo C'nin flash imajı Demo A'nınkini ezer. Demo A'yı tekrar
koşacaksan `nexys_demo_20260908/firmware/build/arkhe_stream_demo.mcs`
dosyasını geri yükle.

---

## Pin haritası

Tam liste: `fpga/nexys_demo_20260908/constraints/nexys4ddr.xdc`
(her pinin gerekçesi yorumlarda yazılıdır).

### Hangi demo neyi kullanır

| | Demo A (`demo_harness.py`) | Demo B (`run_jury.py`) |
|---|---|---|
| Kart üstü USB-UART | **evet** (`core`, 115200) | **evet** (tek bağlantı) |
| Pmod JB UART-TTL | **evet** (`stream`, 1 Mbps) — zorunlu | hayır |
| Diğer Pmod'lar | gerekmez | gerekmez |

Demo B tek USB kablosuyla çalışır. **Demo A ayrıca Pmod JB'ye harici
3,3 V UART-TTL modülü ister** (aşağıdaki JB tablosuna bakın).

| Sinyal | FPGA pini | Açıklama |
|---|---|---|
| `UART_TXD_IN` | **C4** | PC → FPGA |
| `UART_RXD_OUT` | **D4** | FPGA → PC |
| `CLK100MHZ` | **E3** | 100 MHz kart osilatörü |
| `CPU_RESETN` | **C12** | CPU reset butonu (aktif düşük) |

`--port COMxx` bu hat üzerinden gider.

### Pmod JA — I2C Master

| Pmod | FPGA pini | Sinyal |
|---|---|---|
| **JA1** | `C17` | `I2C_SCL` |
| **JA2** | `D18` | `I2C_SDA` |
| JA5 / JA6 | — | GND |

İkisinde de dahili pull-up açık (`PULLUP TRUE`, ~50 kΩ). Fonksiyonel
test için yeterlidir; **400 kHz Fast Mode'da harici 2,2–4,7 kΩ
direnç önerilir** (güvenilir yükselme kenarı için).

### Pmod JB — UART-stream (NPU veri akışı)

| Pmod | FPGA pini | Sinyal | Yön |
|---|---|---|---|
| **JB1** | `D14` | `JB_UART_RX` | FPGA **girişi** ← modülün TX'i |
| **JB2** | `F16` | `JB_UART_TX` | FPGA **çıkışı** → modülün RX'i |
| JB5 / JB6 | — | GND | |

Harici 3,3 V UART-TTL modülü gerekir. **Demo A bu hattı kullanır**
(`stream` portu) — bağlantısız Demo A koşamaz. Demo B bu hatta
ihtiyaç duymaz, tek USB ile çalışır.

### Pmod JC — JTAG hata ayıklama (opsiyonel)

| Pmod | FPGA pini | Sinyal | Yön |
|---|---|---|---|
| **JC1** | `K1` | `JTAG_TCK` | giriş (clock-capable pin) |
| **JC2** | `F6` | `JTAG_TMS` | giriş |
| **JC3** | `J2` | `JTAG_TDI` | giriş |
| **JC4** | `G6` | `JTAG_TDO` | çıkış |
| JC5 / JC6 | — | GND | |

### Pmod JD — GPIO çıkış yönü (alt 8 bit)

`tx_en` pad'i FPGA'da dışarıdan gözlenemediği için GPIO'nun alt
8 biti JD'ye verilmiştir.

| Pmod | FPGA pini | Sinyal |
|---|---|---|
| JD1 | `H4` | `GPIO_TXEN[0]` |
| JD2 | `H1` | `GPIO_TXEN[1]` |
| JD3 | `G1` | `GPIO_TXEN[2]` |
| JD4 | `G3` | `GPIO_TXEN[3]` |
| JD7 | `H2` | `GPIO_TXEN[4]` |
| JD8 | `G4` | `GPIO_TXEN[5]` |
| JD9 | `G2` | `GPIO_TXEN[6]` |
| JD10 | `F3` | `GPIO_TXEN[7]` |

### Kart üstü anahtar ve LED'ler

16 anahtar (`SW[15:0]`, `J15`…`V10`) ve 16 LED (`LED[15:0]`,
`H17`…) GPIO'ya bağlıdır; sınıflandırma sonucu LED'lerde görünür.

---

## Sorun giderme

| Belirti | Sebep / çözüm |
|---|---|
| COM portu görünmüyor | Digilent sürücüleri kurulu değil; Vivado "Install Cable Drivers" |
| `Auto Connect` kartı bulamıyor | Kart kapalı veya başka bir program portu tutuyor (Vivado'yu kapatıp açın) |
| Araç bağlanıyor ama veri gelmiyor | Yanlış bitstream yüklü olabilir — Adım 2'deki uyarıya bakın |
| `pyserial` bulunamadı | `python -m pip install pyserial` |
| GUI açılmıyor (Linux) | `sudo apt install python3-tk` |
| Sağlama toplamı hataları | Baud hızı uyuşmazlığı; ICD'deki `baud` alanını kontrol edin |

---

## Saat farkı hakkında (sorulursa)

FPGA hedefi **50 MHz**, ASIC hedefi **43,2 MHz**'dir. Şartname buna izin
verir ("farklı MHz'lerde çalıştırabilirsiniz ama aynı tasarımı istiyoruz").

**RTL kaynağı iki hedefte de AYNIDIR** — `ifdef` ile ayrılmamıştır.
Yalnızca `soc_top.sv`'deki `SYS_CLK_HZ` parametresi farklı verilir:

    FPGA : 50_000_000  -> I2C bölen 125 -> SCL tam 400.000,00 Hz
    ASIC : 43_200_000  -> I2C bölen 108 -> SCL tam 400.000,00 Hz

Her iki hedefte de EK-2'nin "SCL 400 kHz sabit" isteri **tam** karşılanır.

Ayrıntı: `docs/ASIC_SAAT_BAGIMLILIGI.md`
