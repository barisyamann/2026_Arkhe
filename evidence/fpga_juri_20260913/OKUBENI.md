# Kart uzeri tam SoC testi - 13 Eylul 2026

Nexys A7-100T karti uzerinde `run_jury.py` ile alinmis **gercek donanim**
kosumudur. Demo A (TEKNOFEST resmi araci) siniflandirma dogrulugunu
olcer; bu kosum ise **SoC'un tamamini** sinar.

## Kurulum

| | |
|---|---|
| Kart | Digilent Nexys A7-100T |
| Bitstream | `fpga/JURI_FPGA_TESTI/nexys_usb_top.bit` |
| Flash imaji | `flash_jury.bin` @ `0x00800000` (MCS ile) |
| Baglanti | Tek USB (COM16) - Pmod gerekmez |
| Tur sayisi | 3 |
| Tohum | 20260905 |

## Komut

```
python run_jury.py --port COM16
```

Elle kontroller **atlanmadi** (`--skip-manual` kullanilmadi).

## Sonuc

```
GECTI: 2 x 83 oztest kontrolu, 21 NPU sonucu, UART bayt testleri
GPIO: PASS: 16 anahtar, yukselen/dusen kenar IRQ, dort LED deseni
```

| Alan | Deger |
|---|---|
| `passed` | **true** |
| `physical_board_test` | **true** |
| Oztest turu | 2 x 83 kontrol |
| NPU cikarimi | **21** (7 vektor x 3 tur) |
| `manual_gpio` | **PASS** (16 anahtar + kenar IRQ + 4 LED deseni) |

### NPU cikarim tutarliligi

Yedi referans vektorun ucu de ayni sinifi verdi; dort sinifin tamami
kapsandi:

| Vektor | Tur 1/2/3 | Sinif |
|---|---|---|
| `rastgele_sinif0_silence` | 0, 0, 0 | SILENCE |
| `rastgele_sinif1_unknown` | 1, 1, 1 | UNKNOWN |
| `rastgele_sinif2_yes` | 2, 2, 2 | YES |
| `ses_yes` | 2, 2, 2 | YES |
| `rastgele_sinif3_no` | 3, 3, 3 | NO |
| `ses_no` | 3, 3, 3 | NO |
| `deterministik_golden` | 3, 3, 3 | NO |

Referans ile uyusmazlik: **0**.

## Kapsanan asamalar

Flash -> CPU acilisi (FNV ozeti) · CPU aritmetik/mantik/carpma-bolme ve
uc durumlar · D-RAM desen testleri · NPU TCM (15 banka) · GPIO yazmaclari ·
Timer (3 kesme, ISR sayisi) · DMA (banka siniri, koruma kelimeleri) ·
Bus fault (ROM'a yazma reddi) · I2C · UART2 tum bayt degerleri ·
NPU uctan uca (UART2 -> DMA -> cikarim -> ISR) · Kullanici anahtar/LED.

## Kapsam disinda kalanlar (rapordan)

- I2C: harici slave yok; yalnizca bos hat islem tamamlanmasi
- QSPI: boot okuma; flash yazma/silme ve tum opcode modlari yok
- D-RAM: 1 KB test alani; calisan stack ve tum 8 KB hucreler yok
- JTAG debug/halt/resume, CPU tum ISA ve ASIC zamanlama kapsami yok
- NPU: 7 referans vektorun tekrari; yeni ses/veri dogrulugu iddiasi yok

Bu sonuc yalnizca yukaridaki kapsami dogrular.
