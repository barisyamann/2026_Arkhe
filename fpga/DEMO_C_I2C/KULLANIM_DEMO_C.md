# Demo C — ESP32 ile gerçek I2C doğrulaması

Demo B'nin **birebir kopyası**, üzerine tek bir ek: I2C kontrolcüsünün
**gerçek bir harici cihazla** veri alışverişi yaptığı kanıtlanır.

## Neden var

Demo B'nin kendi raporu I2C'yi eksik ilan ediyordu:

> *"I2C: harici slave yok; yalnızca boş hat işlem tamamlanması"*

Yani şimdiye kadar yalnızca "master işlemi başlattı ve `TX_DONE` kuruldu"
doğrulanıyordu. Karşı tarafta kimse olmadığı için gerçek ACK, gerçek veri
iletimi ve okuma yolu sınanmamıştı. Demo C bunu kapatır.

## Test nasıl çalışır

| Adım | Kart (Arkhe SoC) | ESP32 |
|---|---|---|
| 1 | `0x5A` yazar | baytı saklar, tersini (`0xA5`) hazırlar |
| 2 | okuma isteği (`RX_EN`) | `0xA5` döndürür |
| 3 | okunanı `0xA5` ile karşılaştırır | — |

Üç farklı değerle (`0x5A`, `0xA5`, `0x3C`) tekrarlanır.

**Neden "tersi" döndürülüyor?** Sabit bir değer dönseydi, hat sıfıra
çekili kalsa bile test geçebilirdi. Tersini döndürmek, dönen değerin
yazılan değere **bağlı** olmasını zorunlu kılar — bu, gerçek çift yönlü
iletişimin kanıtıdır.

**ACK hakkında dürüst not.** I2C kontrolcüsü ACK/NACK bitini yazılıma
açmaz; `I2C_CFG` yalnızca `TX_EN`/`TX_DONE`/`RX_EN`/`RX_DONE` tutar.
NACK durumunda durum makinesi STOP atar ve veri gelmez
(`rtl/Cevre_Birimleri/i2c_peripheral.sv:659`). Dolayısıyla **doğru
verinin geri okunması, ACK'in alındığının dolaylı ama kesin kanıtıdır.**

## Bağlantı

| Nexys A7-100T | FPGA pini | ESP32 |
|---|---|---|
| **Pmod JA1** | `C17` | **GPIO22** (SCL) |
| **Pmod JA2** | `D18` | **GPIO21** (SDA) |
| **Pmod JA5** veya **JA6** | GND | **GND** |

> **GND'yi bağlamayı unutma.** İki kartın referansı ortak olmazsa hat
> güvenilmez çalışır.
>
> **Pull-up:** FPGA tarafında dahili pull-up açık (~50 kΩ), ESP32'de de
> `Wire` kütüphanesi açar. 400 kHz'de bu zayıf kalabilir; sorun
> yaşarsan SCL ve SDA hatlarına 3,3 V'a giden **2,2–4,7 kΩ harici
> direnç** ekle.

## Adımlar

### 1. ESP32'yi hazırla

Arduino IDE'de `esp32_slave/esp32_slave.ino` dosyasını aç, kartına
yükle, Seri Monitor'ü **115200** baud ile aç.

Görmen gereken:
```
ARKHE I2C SLAVE HAZIR (adres 0x42)
  SDA=GPIO21  SCL=GPIO22
```

### 2. Firmware'i derle

```powershell
cd C:\Users\ybari\2026_Arkhe\fpga\DEMO_C_I2C
python build_firmware.py
```

### 3. MCS üret (Vivado Tcl)

```tcl
cd C:/Users/ybari/2026_Arkhe/fpga/DEMO_C_I2C
write_cfgmem -format mcs -size 16 -interface SPIx4 \
  -loadbit  "up 0x00000000 C:/Users/ybari/2026_Arkhe/fpga/DEMO_C_I2C/nexys_usb_top.bit" \
  -loaddata "up 0x00800000 C:/Users/ybari/2026_Arkhe/fpga/DEMO_C_I2C/flash_jury.bin" \
  -file     "C:/Users/ybari/2026_Arkhe/fpga/DEMO_C_I2C/arkhe_demo_c.mcs" -force
```

### 4. Programla

Hardware Manager → Add Configuration Memory Device (`s25fl128s...`) →
`arkhe_demo_c.mcs` → Erase + Program + Verify → sonra Program Device
ile `nexys_usb_top.bit`.

### 5. Koş

```powershell
python run_jury.py --port COM16
```

`Hazir... CPU RESET` görünce **CPU RESET'e bir kez bas.**

## Beklenen sonuç

Demo B'nin tüm denetimlerine **ek olarak**:

```
I2C_ESP_TX_DONE      1
I2C_ESP_RX_DONE      1
I2C_ESP_YAZILAN      0x0000005A
I2C_ESP_OKUNAN       0x000000A5
I2C_ESP_YAZILAN      0x000000A5
I2C_ESP_OKUNAN       0x0000005A
I2C_ESP_YAZILAN      0x0000003C
I2C_ESP_OKUNAN       0x000000C3
I2C_ESP_VERI_DOGRU   3
```

ESP32 Seri Monitor'de eşzamanlı olarak:
```
yazildi: 0x5A  ->  okunacak: 0xA5
yazildi: 0xA5  ->  okunacak: 0x5A
yazildi: 0x3C  ->  okunacak: 0xC3
```

## ESP32 bağlı değilse ne olur

Test **sessizce geçmez.** Yazma yine `TX_DONE` verir (master hattı
kendisi sürer), ancak okuma `0xFF` döner — hat pull-up ile yüksekte
kalır. `I2C_ESP_VERI_DOGRU` 3 yerine 0 çıkar ve koşum `KALDI` der.

## Demo B ile ilişkisi

Demo C, Demo B'nin **üst kümesidir**: aynı 83 öztest, aynı NPU
çıkarımları, aynı anahtar/LED kontrolleri + ESP32 I2C testi. Demo B'yi
ayrıca koşmaya gerek yoktur; Demo C geçerse Demo B de geçmiş sayılır.

Flash imajları farklıdır — Demo C'yi yükledikten sonra Demo A'ya
dönmek istersen `nexys_demo_20260908` MCS'ini geri yüklemen gerekir.
