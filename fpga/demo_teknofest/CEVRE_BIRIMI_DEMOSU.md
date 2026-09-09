# Tam çevre birimi demosu — kullanım

**9 Eylül 2026**

Yarışmada jürinin hangi çevre birimini görmek isteyeceğini önceden
bilemiyoruz. Bu demo **yedi çevre birimini tek tek** çalıştırır ve sonucu
core UART'a yazar. Her adım kendi kendini denetler; başarısız olan
`[HATA]` ile işaretlenir ve program devam eder — tek bir hata bütün demoyu
durdurmaz.

## Yükleme

```
Vivado Tcl konsolu:
  source C:/Users/ybari/2026_Arkhe/sw_nexys/build/gen_mcs_fdemo.tcl

Hardware Manager:
  Add Configuration Memory Device -> s25fl128sxxxxxx0-spi-x1_x2_x4
  Program -> sw_nexys/build/arkhe_cevre_demo.mcs

Sonra karttaki PROG butonuna basılır.
```

Çıktı: **core UART (COM16), 115200 baud**

```
python demo_harness.py probe --core-port COM16 --core-baud 115200 --seconds 30
```

veya herhangi bir terminal (PuTTY, TeraTerm).

## Ne gösteriyor

### 1. GPIO
- `ODR` yazma → 16 LED'in hepsi yanar
- `CLEAR` → üst 8 LED söner
- `SET` → dört LED tekrar yanar
- `TOGGLE` → hepsi terslenir
- **Dört pin modu** sırayla uygulanır: giriş / çıkış / açık drenaj-0 / açık drenaj-1.
  Yön sinyali (`tx_en`) **Pmod JD**'ye çıkar — osiloskopla veya LED ile gözlenebilir.
- Anahtar (SW) değerleri okunup yazdırılır

Jüriye gösterilecek: LED'ler adım adım değişir, anahtarları çevirip
tekrar koşturunca okunan değer değişir.

### 2. Timer
- `CLR` sonrası sayaç sıfır
- Sayaç ilerliyor, `ENA=0` ile duruyor
- Otomatik yeniden yükleme → olay bayrağı kuruluyor
- `EVC` bayrağı temizliyor
- **Prescaler** etkisi ölçülüyor (PRE=9 ile sayım yavaşlıyor)

### 3. I2C
- `NBY` kırpma davranışı (0→1, 25→4) — şartname gereği
- `ADR` yalnızca 7 bit tutuyor
- `TDR` tam genişlik korunuyor
- Gerçek işlem başlatılır ve **askıda kalmadan** sonlanır

> Kart üzerinde gerçek bir I2C kölesi yoksa adres NACK alınması
> **beklenen** durumdur; önemli olan motorun doğru sonlanmasıdır.
> Pmod JA'ya bir I2C cihazı (EEPROM, sensör) takılırsa gerçek ACK görülür.

### 4. QSPI
- `CMD_RDID` (0x9F) → **flash kimliği** okunur ve yazdırılır
- `CMD_RDSR1` (0x05) → durum yazmacı
- `CMD_READ` (0x03) → `0x800000` adresinden uygulama verisi okunur
- Hata bayrakları temiz

Bu, kart üzerindeki gerçek Spansion S25FL128S ile konuşulduğunun kanıtıdır —
boot zaten bu yoldan yapılır.

### 5. DMA
- 16 kelime bellekten belleğe taşınır
- Hepsinin doğru taşındığı tek tek denetlenir
- İlk ve son kelime yazdırılır

### 6. UART-stream (UART 2)
- `CPB=50` → 1 Mbps
- Stop bit 1 / 2 ayarları
- FIFO temizleme sonrası boş

Bu, demo aracının 1960 baytlık çıkarım vektörünü aldığı yoldur.

### 7. JTAG hata ayıklama
- `DBG_ADDR` / `DBG_DATA` yazmaç geri okuma
- **Hata ayıklayıcı üzerinden belleğe yazma** — `0x20000300`'e `0xA5A55A5A`
- **Hata ayıklayıcı üzerinden bellekten okuma** — yazılan değer geri alınır
- Hata bayrağı durumu

> **Önemli:** Bu demo JTAG'in **AXI yazmaç arayüzünü** kullanır; harici
> adaptör gerekmez. Aynı birimin TAP tarafı (Pmod JC: TCK=JC1, TMS=JC2,
> TDI=JC3, TDO=JC4) simülasyonda 27 denetimle doğrulanmıştır ve fiziksel
> pinlere çıkarılmıştır, ancak gösterimi için bir JTAG adaptörü gerekir.

## Sonuç göstergesi

Program sonunda:

```
================================================
 SONUC: N gecti, M kaldi
 TUM CEVRE BIRIMLERI CALISIYOR
================================================
```

Ayrıca **LED'ler**: hepsi yanık = tüm denetimler geçti; `0xF00F` deseni =
en az bir denetim başarısız.

## İki imaj arasında geçiş

| İmaj | Ne yapar | MCS |
|---|---|---|
| **Çevre birimi demosu** | Yedi birimi tek tek test eder, rapor yazar | `arkhe_cevre_demo.mcs` |
| **Çıkarım demosu** | Demo aracıyla 156 vektör, sağlamlık senaryoları | `arkhe_demo_flash.mcs` |

İkisi de aynı bitstream'i kullanır, yalnızca firmware farklıdır. Geçiş
yaklaşık 5 dakika (flash programlama + PROG).

**Demo günü önerisi:** Önce çevre birimi demosunu göster (donanımın
tamamının çalıştığını kanıtlar), sonra çıkarım demosuna geç (jürinin resmi
aracıyla 156/156 golden uyumu).

## Kaynak

`sw_nexys/src/fpga_demo.c` — 4640 bayt, 8192 baytlık uygulama alanına sığar.
