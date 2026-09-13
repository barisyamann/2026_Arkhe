# FPGA Demo — adım adım uygulama kılavuzu

**Hedef:** Nexys A7-100T kartına Arkhe SoC'u yükleyip TEKNOFEST'in resmi
demo aracıyla uçtan uca çalıştırmak.

Bu belge, demoyu **kendiniz yapmanız** için yazılmıştır. Her adımda ne
göreceğiniz ve ters giderse ne yapacağınız yazılıdır.

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

## Adım 3 — Demo aracını tanı (donanımsız)

Karta dokunmadan önce aracın çalıştığını görün:

```bash
cd fpga/nexys_demo_20260908/demo
python demo_harness.py --version
```

Sahte cihazla deneme (kart bağlı olmasa da çalışır):

```bash
python demo_harness.py selftest
```

---

## Adım 4 — ICD dosyasını doğrula

ICD (Arayüz Tanım Dokümanı) zaten hazırlanmıştır: `arkhe_icd.json`

```bash
python demo_harness.py validate -i arkhe_icd.json
```

**Beklenen:** doğrulama hatasız geçer. Hata verirse çıktıdaki alan adını
not edip bana iletin — ICD'de düzeltilecek bir alan var demektir.

---

## Adım 5 — Gerçek kartla çalıştır

```bash
python demo_harness.py run -i arkhe_icd.json --port COM7
```

`COM7` yerine **Adım 1'de not ettiğiniz portu** yazın.

**Grafik arayüz tercih ederseniz:**

```bash
python demo_gui.py
```

GUI'de: ICD dosyasını seçin → COM portunu seçin → **Run**.

---

## Adım 6 — Sonucu kontrol et

Araç sonuçları şuraya yazar:

```
demo/results/ARKHE_<tarih>_<saat>/
```

İçinde çerçeve kayıtları, ölçülen süreler ve özet rapor bulunur.

**Referans:** Daha önce alınmış bir koşu `demo/results/ARKHE_20260908_173100`
altında durmaktadır; yeni koşunuzu onunla karşılaştırabilirsiniz.

### Beklenen davranış

| Ne | Beklenen |
|---|---|
| Bağlantı | Araç kartı bulur, el sıkışma başarılı |
| Çerçeveleme | Sağlama toplamı hataları **0** |
| Sonuç | Her çerçeve için sınıflandırma çıktısı döner |
| Altın vektör | `[0, 225, 326, 3543]` |

---

## Adım 7 — Kart üstü kendi testlerimiz (isteğe bağlı ama önerilir)

Demo aracının yanı sıra kendi doğrulama firmware'imiz de vardır:

| Test | Sonuç |
|---|---|
| Çevre birimi testleri | **34/34** |
| NPU testleri | **15/15** |
| Self-checking boot | `sistem_gercek_boot` ile doğrulandı |

Bunları çalıştırmak için `JURI_FPGA_TESTI/` sürümünü yükleyin ve
seri terminalden (115200 8N1) çıktıyı izleyin. Testler otomatik koşar
ve sonucu ekrana basar.

> Bu sürümü yükledikten sonra demo için **Adım 2'yi tekrarlayıp**
> `nexys_top.bit` geri yüklemeyi unutmayın.

---

## Pin haritası

Tam liste: `fpga/nexys_demo_20260908/constraints/nexys4ddr.xdc`
(her pinin gerekçesi yorumlarda yazılıdır).

### Demo için gereken — başka bağlantı yok

Resmi demo aracı kart üzerindeki **USB-UART köprüsünü** kullanır.
PMOD'lara hiçbir şey takmadan çalışır.

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

Harici 3,3 V UART-TTL modülü gerekir. Demo aracı bu hattı
kullanmaz; NPU'ya ayrı bir kanaldan veri sürmek isterseniz.

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
