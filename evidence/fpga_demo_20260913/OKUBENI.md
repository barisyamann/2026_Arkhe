# FPGA demo kosumu - 13 Eylul 2026

Nexys A7-100T karti uzerinde, TEKNOFEST'in resmi `demo_harness.py`
araciyla alinmis **gercek donanim** kosumudur (dry-run degildir).

## Kurulum

| | |
|---|---|
| Kart | Digilent Nexys A7-100T |
| Bitstream | `fpga/nexys_demo_20260908/bitstream/nexys_top.bit` |
| Flash imaji | `firmware/build/flash_demo.bin` @ `0x00800000` |
| Sistem saati | 50 MHz (FPGA hedefi) |
| core UART | COM16, 115200 - kart ustu USB-UART |
| stream UART | COM12, 1 Mbps - harici 3,3 V TTL modul, Pmod JB (D14/F16) |
| Arac surumu | demo_harness 1.0.1 |

## Komut

```
python demo_harness.py run -c arkhe_icd.json \
       --manifest public_dataset/manifest.csv --data-dir public_dataset
```

## Sonuc

| Olcut | Deger |
|---|---|
| Ornek sayisi / yanitlanan | **156 / 156** |
| Zaman asimi | **0** |
| Altin referansla uyum | **%100,00** |
| Uyusmazlik | **0** |
| Saglamlik senaryolari | 9 gecti / 1 opsiyonel atlandi |
| Gecikme (medyan) | 7,87 ms |
| Gecikme (p95) | 11,56 ms |
| Hizlanma | 180,1x (yazilim referansi 1418 ms) |

`golden_agreement_pct = 100,0` sunun kanitidir: kart uzerindeki RTL,
yazilim altin modeliyle **birebir ayni** sinifi uretmektedir.

`accuracy_info_hw_pct = %72,44` modelin veri setindeki dogrulugudur;
yarismanin olctugu deger bu degil, yukaridaki uyum oranidir.

## Onceki kosumla karsilastirma

`fpga/demo_teknofest/sonuclar/` altindaki 8 Eylul kosumu ile ayni:
156/156, %100 uyum, 0 zaman asimi, 9/10 saglamlik. Hizlanma 183,3x
idi; aradaki fark (180,1x) olcum gurultusudur.

## back_to_back senaryosu (bilinen sinirlama - teyit)

Bu kosumda da `back_to_back` 5 cerceveden 4'une yanit verdi; 8 Eylul
kosumuyla **birebir ayni** sonuc. Yani rastgele bir kararsizlik degil,
deterministik ve kok nedeni bilinen bir sinirdir.

**Kok neden** (8 Eylul 2026'da tespit edildi):
`rtl/cevre/uart_stream_peripheral.sv` icindeki toplayici sayaci
`pack_cnt_r`, yalnizca reset ve tam kelime okumasi ile sifirlanir;
`UARTS_FIFO_CLR` komutu ile SIFIRLANMAZ. Bir onceki senaryodan devreden
yarim kelime kalintisi sonraki cerceveyi kaydirir.

**Kanit:** Senaryo TEK BASINA kosuldugunda uc bagimsiz tekrarda 5/5
gecer. Yalnizca tam sirada, kendinden onceki senaryodan devreden gecis
etkisiyle duser.

**Neden duzeltilmedi:** Duzeltmesi hazirdir. Ancak ASIC teslimi yamasiz
RTL'e SHA-256 ile baglidir; bu teslime dahil edilirse teslim edilen
GDS'nin kaynak hash'i tutmaz. Ayri bir fiziksel kosumla girecektir.

Ayrinti: `fpga/demo_teknofest/OKUBENI.md` ve `docs/SUNUM_ICERIGI.md`.
