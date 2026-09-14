# Demo A — iki koşum, ikisi de geçerli (14 Eylül 2026)

Resmi TEKNOFEST demo aracıyla (`demo_harness.py` 1.0.1) Nexys A7-100T
kartı üzerinde alınmış **iki gerçek donanım koşumu**. İkisi de aynı
bitstream'i (14 Eylül, güncel RTL) kullanır; fark yalnızca firmware'in
UART'a ne yazdırdığıdır.

| | `fpga_demo_20260914_normal` | `fpga_demo_20260914_skorlu` |
|---|---:|---:|
| Örnek / yanıtlanan | 156 / 156 | 156 / 156 |
| **Altın referans uyumu** | **%100,00** | **%100,00** |
| Uyuşmazlık | 0 | 0 |
| Zaman aşımı | **0** | **0** |
| Gecikme (medyan) | **8,02 ms** | 23,96 ms |
| **Ölçülen hızlanma** | **177×** | 59× |
| Skor karşılaştırması | — | **156 örnek** |
| Skor hatası (MAE) | — | **%0,078** |
| Sağlamlık | 9 PASS / 1 FAIL / 1 SKIP | 9 PASS / 1 FAIL / 1 SKIP |

## Neden iki koşum var

Demo aracı çıkarım gecikmesini **ISR dönüşünü bekleyerek** ölçer. Dört
sınıf skorunu UART'tan yazdırmak ISR'yi yaklaşık **16 ms uzatır**; bu
süre NPU'nun çıkarım süresi değil, **UART yazdırma süresidir**. Araç
ikisini ayırt etmez.

Sonuç olarak:

- **Normal firmware** (skor yazdırmaz) → gerçek hızlanmayı ölçer: **177×**
- **Skorlu firmware** → nicemleme doğruluğunu kanıtlar: **MAE %0,078**

İkisi aynı koşumda elde edilemez; bu yüzden ikisi de ayrı ayrı alınmış
ve **ikisi de teslim edilmiştir**.

## Hangi sayı nerede kullanılmalı

**Hızlanma iddiası için `normal` koşum:** 177× (yazılım referansı
1418 ms). Şartnamenin istediği metrik budur.

**Nicemleme doğruluğu için `skorlu` koşum:** Donanımın ürettiği dört
olasılık, altın referans modelin çıkışlarıyla ortalama **%0,078** hatayla
eşleşir. Demo aracının kılavuzu bu değeri *"puanlamada kullanılmaz"*
diye işaretler; ek güven kanıtıdır: argmax doğru olsa bile nicemleme,
taşma veya biriktirici genişliği sorunu olup olmadığını gösterir.

**Altın referans uyumu her ikisinde de %100,00** — asıl ölçüt bu ve
firmware farkından etkilenmez.

## Kartta kalan sürüm

Kartın flash'ında **skorlu** sürüm durmaktadır
(`fpga/nexys_demo_20260908/firmware/build/flash_demo.bin`). Normal
sürüme dönmek için `firmware/src/main.c` içindeki ISR'den skor yazdırma
bloğu çıkarılıp yeniden derlenmelidir.

## Çıktı biçimi farkı

```
normal : [IRQ] Class: 3
skorlu : [IRQ] Class: 3 scores=0,335,111,3648
```

Skorlar **Q0.12** biçimindedir (0..4096). Demo aracı yalnızca 0..1
olasılık veya int8 (−128..127) kabul eder
(`demo_harness.py:169`); Q0.12 değerleri 4096'ya bölünerek
karşılaştırılır — bu dönüşüm ölçülmüş ve altın referansla %0,01–0,09
aralığında eşleştiği doğrulanmıştır.

## `back_to_back` senaryosu

Her iki koşumda da **KALDI** (5 çerçevenin 4'ü yanıtlandı). Kök nedeni
`uart_stream_peripheral.sv` içindeki `pack_cnt_r` sayacının FIFO
temizleme ile sıfırlanmaması olarak tespit edilmiş ve 9 Eylül'de
düzeltilmişti; bu bitstream o düzeltmeyi **içeriyor** ancak senaryo yine
de geçmiyor. Dolayısıyla teşhis doğru ama eksik; **bilinen sınırlama**
olarak kayıtlıdır.
