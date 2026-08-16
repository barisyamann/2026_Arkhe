# FPGA Olcum Gecmisi - Nexys A7-100T (xc7a100tcsg324-1)

Vivado 2025.2, 50 MHz hedef (20 ns periyot)

| Surum | WNS (ns) | WHS (ns) | LUT    | FF    | BRAM | DSP | Not |
|-------|----------|----------|--------|-------|------|-----|-----|
| v2    | -14,199  | +0,033   | 17.240 | 4.975 | 13,5 | 13  | Gercek agirliklar, boru hatti yok |
| v3    | + 1,649  | +0,034   | 16.805 | 5.136 | 13,5 |  9  | NPU FC boru hattina ayrildi |
| v4    | + 2,530  | +0,036   | 16.835 | 5.169 | 13,0 |  9  | softmax LUT projeye eklendi, iki asamali boot, QSPI 9-bit sayaclar |

## Yorum

v2 -> v3: NPU FC hesaplama yolu iki turda boru hattina ayrildi.
Kritik yol 34,1 ns'den 18,4 ns'ye indi. DSP 13 -> 9 (dort paralel
FC MAC seri hale getirildi). Hesaplama sonucu bit duzeyinde
degismedi, cevrim maliyeti %2,9 (964.071 -> 992.083).

v3 -> v4: softmax_exp_lut.mem Vivado projesinin hicbir kumesinde
tanimli degildi; $readmemh dosyayi bulamadigi icin LUT bos
kaliyordu. Eklendikten sonra Vivado ilklendirilmis ROM olarak
cikarabildi: BRAM 13,5 -> 13,0 ve WNS 0,88 ns iyilesti.

## Gecerli referans

WNS +2,530 ns · WHS +0,036 ns
16.835 LUT (%26,55) · 5.169 FF (%4,08) · 13 BRAM (%9,63) · 9 DSP (%3,75)

NOT: README'de yazan 8.114 LUT / %12,80 degeri sahte agirliklar
donemine aittir ve gecersizdir.
