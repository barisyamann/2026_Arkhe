# Demo C — ESP32 ile gerçek I2C doğrulaması (14 Eylül 2026)

Nexys A7-100T kartı üzerinde alınmış **gerçek donanım** koşumudur.
Demo B'nin üst kümesidir: aynı öztestler + NPU çıkarımları + elle
GPIO/LED kontrolleri, üzerine **harici I2C slave ile gerçek veri
alışverişi** eklenmiştir.

## Neden var

Demo B'nin kendi raporu I2C'yi eksik ilan ediyordu:

> *"I2C: harici slave yok; yalnızca boş hat işlem tamamlanması"*

Yani yalnızca "master işlemi başlattı ve `TX_DONE` kuruldu" doğrulanıyordu.
Karşı tarafta kimse olmadığı için gerçek ACK, veri iletimi ve okuma yolu
sınanmamıştı. Bu koşum o boşluğu kapatır.

## Kurulum

| | |
|---|---|
| Kart | Digilent Nexys A7-100T |
| Bitstream | `fpga/DEMO_C_I2C/nexys_usb_top.bit` — **14 Eylül, güncel RTL** |
| Flash imajı | `flash_jury.bin` @ `0x00800000` |
| Harici cihaz | ESP32, I2C slave adresi `0x42` |
| Bağlantı | JA1 `C17` → GPIO22 (SCL) · JA2 `D18` → GPIO21 (SDA) · GND |
| Bağlantı (kart) | Tek USB, COM16 |

## Sonuç

```
GECTI: 2 x 86 oztest kontrolu, 21 NPU sonucu, UART bayt testleri
GPIO: PASS: 16 anahtar, yukselen/dusen kenar IRQ, dort LED deseni
```

| Alan | Değer |
|---|---|
| `passed` | **true** |
| `physical_board_test` | **true** |
| Öztest turu | 2 × **86** kontrol (Demo B'de 83 idi; 3 I2C denetimi eklendi) |
| NPU çıkarımı | **21** (7 vektör × 3 tur), referansla 0 uyuşmazlık |
| `manual_gpio` | **PASS** — elle kontroller atlanmadı |

### I2C gerçek veri alışverişi

```
I2C_ESP_TX_DONE      PASS
I2C_ESP_RX_DONE      PASS
I2C_ESP_YAZILAN 5A -> I2C_ESP_OKUNAN A5
I2C_ESP_YAZILAN A5 -> I2C_ESP_OKUNAN 5A
I2C_ESP_YAZILAN 3C -> I2C_ESP_OKUNAN C3
I2C_ESP_VERI_DOGRU   PASS (3/3)
```

ESP32 karttan gelen baytın **tersini** döndürür. Sabit bir değer dönseydi
hat sıfıra çekili kalsa bile test geçebilirdi; tersini döndürmek dönen
değerin yazılan değere **bağlı** olmasını zorunlu kılar.

### ACK hakkında dürüst not

I2C kontrolcüsü ACK/NACK bitini yazılıma **açmaz**; `I2C_CFG` yalnızca
`TX_EN`/`TX_DONE`/`RX_EN`/`RX_DONE` tutar. NACK durumunda durum makinesi
STOP atar ve veri gelmez
(`rtl/Cevre_Birimleri/i2c_peripheral.sv:659`). Dolayısıyla **doğru
verinin geri okunması, ACK'in alındığının dolaylı ama kesin kanıtıdır.**

### Ölçülen bir davranış: ESP32 sürücü gecikmesi

İlk koşumda okunan değerler bir tur geriden geldi:

```
yazildi 5A -> okundu C3   (= ~3C, bir onceki turun cevabi)
```

ESP32 seri çıktısı cevabı **doğru** hesapladığını gösteriyordu
(`yazildi: 0x5A -> okunacak: 0xA5`). Sorun ESP32'nin `Wire` slave TX
yolunda: `onRequest()` çağrıldığında tampon zaten dolu olmalı. Tamponu
`onReceive` içinde doldurmak ve 2 ms beklemek bunu değiştirmedi.

**Çözüm:** her değer için iki tur yaz-oku. İlk tur tamponu o değerin
cevabıyla doldurur, ikinci tur onu geri okur. Sürücü gecikmesinden
bağımsız olarak gerçek veri alışverişi doğrulanır.

Bu, Arkhe SoC'un I2C kontrolcüsünde bir kusur **değildir**; karşı
taraftaki kütüphanenin davranışıdır ve ölçülerek belgelenmiştir.

## Kapsam dışı kalanlar

- I2C flash programlama/silme komutları ve çoklu-slave hakemliği
- QSPI: boot okuma var; flash yazma/silme ve tüm opcode modları yok
- D-RAM: 1 KB test alanı; çalışan stack ve tüm 8 KB hücreler yok
- JTAG debug halt/resume, CPU tam ISA, ASIC zamanlama kapsamı
- NPU: 7 referans vektörün tekrarı; yeni ses/veri doğruluğu iddiası yok

Bu sonuç yalnızca yukarıdaki kapsamı doğrular.

## Üretim

```powershell
# ESP32: esp32_slave/esp32_slave.ino -> Arduino IDE ile yukle
cd C:\Users\ybari\2026_Arkhe\fpga\DEMO_C_I2C
python run_jury.py --port COM16
```

Ayrıntı: `fpga/DEMO_C_I2C/KULLANIM_DEMO_C.md`
