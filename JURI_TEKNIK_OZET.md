# ARKHE — d45_anten2 jüri teknik özeti

8 Eylül 2026 teslim hazırlığı. Esas fiziksel koşu **d45_anten2**; başka koşunun iyi metrikleriyle birleştirilmemiştir. Sentez kaynakları Git `d800acb` ile eşleşir.

## Mimari

CV32E40P / RV32IMC (FPU kapalı), AXI4-Lite, NPU, iki UART, I2C, QSPI, GPIO, timer, DMA ve JTAG. SKY130A / sky130_fd_sc_hd; 23 adet 2 KiB SRAM makrosu. Die 3832,40 × 4249,24 µm. LibreLane 3.0.6 Classic.

## Fiziksel sonuçlar

PnR 10 ns, signoff 20 ns. **50 MHz temiz kapanış yoktur.** 45,8 MHz sayısı ayrı bir periyotta doğrulanmış STA sonucu değildir ve ulaşılan frekans olarak sunulmaz.

| Köşe | Setup slack ns | Hold slack ns |
|---|---:|---:|
| nom_tt_025C_1v80 | +1,3803 | +0,3204 |
| nom_ss_100C_1v60 | −1,2962 | +0,7504 |
| nom_ff_n40C_1v95 | +2,4939 | +0,1648 |
| min_tt_025C_1v80 | +1,7364 | +0,3196 |
| min_ss_100C_1v60 | −0,8395 | +0,7484 |
| min_ff_n40C_1v95 | +2,8082 | +0,1642 |
| max_tt_025C_1v80 | +0,9267 | +0,3195 |
| max_ss_100C_1v60 | −1,8149 | +0,7506 |
| max_ff_n40C_1v95 | +2,0799 | +0,1643 |

Kaynak: `asic/reports/timing/summary.rpt`; ayrıntılı WNS/TNS ve yollar ilgili köşe dizinlerindedir. SRAM'in yalnız TT modeli vardır; FF/SS için de bu model kullanılmıştır.

| Kontrol | Sonuç |
|---|---:|
| Hold | 9/9 köşede pozitif; 0 ihlalli yol |
| Setup | 115 ihlalli yol |
| Anten net/pin | 0 / 0 |
| Detailed route / KLayout DRC | 0 / 0 |
| Magic DRC, özgün LEF/DEF kontrolü | 7.658 |
| Özgün LEF/DEF LVS | Circuits match uniquely |
| Ek GDS kaynaklı LVS | Circuits match uniquely; SRAM içi kapsam dışında |
| XOR / PDN ihlali | 0 / 0 |
| Slew / kapasite / fanout | 19.341 / 1.888 / 11 |
| Lint hata / uyarı / latch | 0 / 818 / 0 |
| Bağlantısız / kritik bağlantısız pin | 257 / 0 |

## Magic DRC değerlendirmesi

7.658 nwell.4 bulgusu LEF/DEF soyut görünümündeki tap geometrisiyle ilişkilidir. Ayrı küçük hücre deneylerinde gerçek tap GDS/MAG temiz, aynı tap MAGLEF görünümü ihlalli bulunmuştur. Tam GDS incelemeleri ayrıca SRAM bit hücresinde tekrar üretilebilen farklı katman/kural bulguları göstermiştir. Dolayısıyla bütün Magic bulguları çözülmüş veya resmi waiver alınmış kabul edilmez. KLayout 0 ve XOR 0 tek başına Magic'in bütün kural kapsamını doğrulamaz. Kaynak: `evidence/asic/MAGIC_KOK_NEDEN_DENEYLERI_20260908.md`.

## İşlevsel doğrulama ve FPGA

Tarihsel aday logları ve test kaynakları pakette korunmuştur. 5–6 Eylül NPU doğrulamasında 1.400 girdide sınıf uyuşmazlığı 0; 1.300 etiketli girdide TFLite/RTL doğruluğu %84,15. 100 stres girdisi doğruluk paydasına katılmaz. Tam CPU iş yükünde 68.474.022 çevrim ve NPU motorunda 85.587 çevrim yaklaşık 800,05× hesaplama oranı verir; veri aktarımı ve boot dahil değildir. Bu ölçümler son d45 RTL'sinin yeniden çalıştırılmış tam regresyonu olarak sunulmaz.

8 Eylül QSPI testinde yeni FIFO negatif senaryolarıyla 30 kontrol geçmiştir. Kaynak/test kayıtlarının tarih ve kapsamları `evidence/` altında tutulur. Son UVM veya kod kapsamı için tamamlanmamış loglar başarı kabul edilmez.

8 Eylül 16:18 FPGA bitstream'inin yönlendirme sonrası WNS +1,218 ns, hold +0,055 ns; tüm tanımlı zamanlama kısıtları sağlanmıştır. 17:31 kart/demo testinde 9 PASS, 1 FAIL, 1 SKIP vardır: aralıksız beş çerçevenin dördüne yanıt gelmiştir. Bu sürüm sonradan eklenen UART FIFO toplayıcısı sıfırlama düzeltmesini içermez. 5 Eylül tek USB jüri provası ayrı bir firmware/wrapper sürümüdür.

## Teslimin kullanımı

Zorunlu raporlar `asic/reports`, nihai görünümler/netlistler/SDC/SPEF/GDS-SPICE/config/metrikler `asic/results` altındadır. `asic/run` teslimde boştur. Büyük dosyalar Release delivery arşivinden indirilir; `make asic_verify` bütünlüğü denetler. Kurulum ve `make asic_run` açıklaması `asic/README.md` içindedir.
