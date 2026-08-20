# FPGA Olcum Gecmisi - Nexys A7-100T (xc7a100tcsg324-1)

Vivado 2025.2, 50 MHz hedef (20 ns periyot)

| Surum | WNS (ns) | WHS (ns) | LUT    | FF    | BRAM | DSP | Not |
|-------|----------|----------|--------|-------|------|-----|-----|
| v2    | -14,199  | +0,033   | 17.240 | 4.975 | 13,5 | 13  | Gercek agirliklar, boru hatti yok |
| v3    | + 1,649  | +0,034   | 16.805 | 5.136 | 13,5 |  9  | NPU FC boru hattina ayrildi |
| v4    | + 2,530  | +0,036   | 16.835 | 5.169 | 13,0 |  9  | softmax LUT projeye eklendi, iki asamali boot, QSPI 9-bit sayaclar |
| v5    | + 2,431  | +0,035   | 16.856 | 5.207 | 13,0 |  9  | Kesme zinciri (NPU/Timer/DMA), UART-stream paketleyici, DMA sabit adres kipi |
| v6    | + 2,147  | +0,053   | 17.441 | 5.232 | 13,0 |  9  | Veri yolu hata kesmesi (R8), WSTRB 9/9, TCM tek yazan port (B2), tri-state ayrimi |
| v7    | + 0,529  | +0,046   | 18.571 | 5.470 | 13,0 |  9  | R4 (13,7x NPU) + R10 kombinasyonel adres fazi -- R10 GERI ALINDI |
| v8    | + 1,811  | +0,060   | 18.596 | 5.478 | 13,0 |  9  | R4 (13,7x NPU), R3 kapsama + I2C oz testi |

## Yorum

v2 -> v3: NPU FC hesaplama yolu iki turda boru hattina ayrildi.
Kritik yol 34,1 ns'den 18,4 ns'ye indi. DSP 13 -> 9 (dort paralel
FC MAC seri hale getirildi). Hesaplama sonucu bit duzeyinde
degismedi, cevrim maliyeti %2,9 (964.071 -> 992.083).

v3 -> v4: softmax_exp_lut.mem Vivado projesinin hicbir kumesinde
tanimli degildi; $readmemh dosyayi bulamadigi icin LUT bos
kaliyordu. Eklendikten sonra Vivado ilklendirilmis ROM olarak
cikarabildi: BRAM 13,5 -> 13,0 ve WNS 0,88 ns iyilesti.

v4 -> v5: G05 kesme zinciri (NPU/Timer/DMA) ve G06 UART-stream veri
yolu eklendi. Maliyet sasirtici derecede kucuk: +21 LUT, +38 FF, BRAM
ve DSP degismedi. WNS 0,099 ns eridi - paketleyici kayitlari ve DMA'nin
sabit adres coklayicilari kritik yolu kil payi uzatti. Marj hala 2,4 ns.

Bu geri gidis gizlenmemeli: ozellik eklemenin bir bedeli oldugunu,
bedelin olculdugunu ve marjin yeterli kaldigini gosteriyor.

v5 -> v6: Veri yolu hata kesmesi (R8), 9 cevre biriminde WSTRB destegi,
TCM tek yazan porta indirildi (B2) ve tri-state ayrildi. Maliyet +585 LUT
(neredeyse tamami WSTRB maskeleme mantigi), +25 FF. WNS 0,284 ns eridi.

### Tasarim artik YONLENDIRME-SINIRLI

Kritik yol karsilastirmasi (ikisi de ayni yol ailesi - NPU FC birikimi):

    v3 : -5,848 ns | mantik 17,953 ns (%69,7) | yonlendirme  7,792 ns (%30,3)
    v6 : +2,147 ns | mantik  6,659 ns (%37,2) | yonlendirme 11,251 ns (%62,8)

Boru hatti calismasi mantik gecikmesini %63 azaltti (17,95 -> 6,66 ns).
Ancak yolun artik %63'u TEL gecikmesidir.

Iki sonucu var:

  1. v6'daki 0,284 ns'lik dususun sebebi yeni mantik DEGIL, sikisikliktir.
     585 LUT eklenince yerlesim/yonlendirme bir miktar bozuldu. Ilk
     tahminim "TCM Port A cokluyucusu kritik yola girdi" idi; kritik yol
     raporu bunu YANLISLADI - yol hala NPU FC birikimi.

  2. Daha fazla boru hatti bolmesi azalan getiri saglar. Mantik zaten
     6,66 ns; kalan gecikme tellerde. Marj daralirsa cozum floorplan /
     yerlesim kisitlari olmali, ek kayit degil.

v6 -> v8: R4 (NPU 13,7x hizlanma), R3 kapsama genisletmesi ve I2C oz
testi. R10 denendi ve GERI ALINDI.

### R4'un bedeli sasirtici derecede dusuk

    +1.155 LUT (17.441 -> 18.596),  +246 FF
    DSP DEGISMEDI (9)  <- sekiz paralel carpici LUT'a esleşti,
                          9 bit x 8 bit oldugu icin DSP'ye gerek kalmadi
    WNS 2,147 -> 1,811  (-0,336 ns)

WNS dususu yeni mantiktan degil SIKISIKLIKTAN: kritik yol hala ayni
NPU FC zinciri (fc_idx_reg -> fc_acc_reg), yalnizca +1.155 LUT
yerlesimi bir miktar zorlastirdi. Yol %63 yonlendirme gecikmesi
oldugu icin sikisikliga duyarli.

13,7x hizlanma icin 0,336 ns cok iyi bir takas.

### R10 iki kez denendi, ikisi de reddedildi

    v7 : ST_IDLE'da kombinasyonel adres fazi
         Calisti ama buyruk koprusunde
         ALU -> instr_addr -> kopru -> ara baglanti -> bellek -> IF
         zinciri kritik yol oldu. WNS 0,529 ns.
         %1,7 hiz icin marjin %75'i - kotu takas.

    (2) Islem sonunda ST_IDLE'a ugramadan gecis
         YANLIS: CV32E40P yanit beklerken req'i yuksek tutabiliyor,
         ustelik eski adresle. Ayni islem ikinci kez baslatiliyor.
         Simulasyon 10 hata verdi. ST_IDLE'daki cevrim bosa gitmiyor;
         CPU'nun req/addr guncellemesi icin gereken ayrim noktasi.

R10 acik birakildi (denetimde "Risk" seviyesi, engelleyici degil).

## Gecerli referans

WNS +1,811 ns · WHS +0,060 ns
18.587 LUT (%29,32) · 5.478 FF (%4,32) · 13 BRAM (%9,63) · 9 DSP (%3,75)

Hedef periyot 20 ns (50 MHz) -> %9,1 zamanlama marji.
NPU cikarimi: 1,45 ms (72.583 cevrim) - 689 cikarim/saniye.

NOT: README'de bir donem 8.114 LUT / %12,80 yaziyordu. O deger sahte
agirliklar donemine aitti ve gecersizdi; 20 Agustos 2026'da README
yukaridaki olculmus degerlerle duzeltildi.
