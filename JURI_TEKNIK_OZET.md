# ARKHE — d45_anten2 jüri teknik özeti

8 Eylül 2026 teslim hazırlığı. Esas fiziksel koşu **d45_anten2**; başka koşunun iyi metrikleriyle birleştirilmemiştir. Sentez kaynakları Git `d800acb` ile eşleşir.

## Mimari

CV32E40P / RV32IMC (FPU kapalı), AXI4-Lite, NPU, iki UART, I2C, QSPI, GPIO, timer, DMA ve JTAG. SKY130A / sky130_fd_sc_hd; 23 adet 2 KiB SRAM makrosu. Die 3832,40 × 4249,24 µm. LibreLane 3.0.6 Classic.

## Fiziksel sonuçlar

PnR 10 ns, özgün signoff 20 ns. **50 MHz temiz kapanış yoktur.** 45,8 MHz sayısı ayrı bir periyotta doğrulanmış STA sonucu değildir ve ulaşılan frekans olarak sunulmaz.

**Ek imzalama analizi (9 Eylül 2026).** Aynı layout, hiçbir fiziksel değişiklik yapılmadan 23 ns (43,5 MHz) periyotla yeniden analiz edildi: setup 9/9 köşede pozitif, 0 ihlalli yol; hold 9/9 köşede pozitif. En kötü köşe `max_ss_100C_1v60` setup WNS +0,0810 ns. Periyot taraması 20/22/22,5/23/24 ns ile yapılmıştır; 22 ns hesapla yeterli görünmesine rağmen ölçümde −0,419 ns vermiştir. Yerleştirme, yönlendirme veya optimizasyon tekrarlanmamıştır; GDS, netlist, DRC, LVS, anten ve slew/kapasite/fanout sonuçları değişmez. Özgün 20 ns raporları `asic/reports/timing/` altında olduğu gibi korunur. Ayrıntı ve yeniden üretme: `asic/reports/timing_23ns/`.

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

## Regresyon ve kod kapsama

9 Eylül 2026 itibarıyla regresyon **16 test / 454 denetim** ile tamamı
geçmektedir. Bütün testler kendi kendini kontrol eder; hata varsa koşum
`$fatal` ile düşer.

| Test | Denetim | Test | Denetim |
|---|---:|---|---:|
| npu_dogruluk | 77 | npu_blok | 27 |
| uart | 42 | jtag_debug | 27 |
| qspi | 40 | sync_fifo | 24 |
| dma | 39 | sistem | 17 |
| i2c | 38 | sistem_gercek_boot | 17 |
| gpio | 37 | npu_hizlanma | 2 |
| timer | 36 | npu_golden | 1 |
| uvm_axi_agent | 29 | cekirdek_izi | 1 |

Kod kapsama **üç ayrı seviyede** ölçülür ve hangi seviyeden söz edildiği
belirtilmelidir:

| Seviye | Statement | Branch |
|---|---:|---:|
| Blok testleri (her modül kendi ortamında) | %93,6 – %97,5 | %70,8 – %92,4 |
| Bizim yazdığımız RTL (sistem seviyesi) | %81,6 | %74,9 |
| Genel rapor (CV32E40P ve paketler dahil) | %62,5 | %44,6 |

Blok testi ölçümleri:

| Blok | Statement | Branch |
|---|---:|---:|
| timer | %97,5 | %74,7 |
| gpio | %96,9 | %92,4 |
| uart | %96,9 | %87,7 |
| sync_fifo | %96,5 | %77,3 |
| npu_blok | %96,4 | %88,0 |
| dma | %96,1 | %82,7 |
| i2c | %95,6 | %79,4 |
| qspi | %94,4 | %73,0 |
| jtag_debug | %93,6 | %70,8 |

Genel rapordaki %62,5 / %44,6 rakamı **üç farklı şeyi birlikte sayar**:
bizim yazdığımız RTL, üçüncü taraf CV32E40P çekirdeği ve çalıştırılabilir
kod içermeyen SystemVerilog paket dosyaları. Paketler yalnızca tip ve sabit
tanımı içerir; kapsama metriği bunları %0 sayarak ortalamayı düşürür.
CV32E40P PULP Platform tarafından ayrıca doğrulanmış bir çekirdektir ve
bizim test kapsamımızın hedefi değildir. Ayrıştırma
`scripts/kapsam_analiz.py` ile yeniden üretilebilir; çıktı
`evidence/dogrulama/KAPSAMA_ANALIZ_20260909.txt` altındadır.

Kapsama, şartname EK-3'te **"Opsiyonel***"** olarak işaretlidir.

8 Eylül 16:18 FPGA bitstream'inin yönlendirme sonrası WNS +1,218 ns, hold +0,055 ns; tüm tanımlı zamanlama kısıtları sağlanmıştır.

8 Eylül 17:31'de yarışma paketiyle gelen `demo_harness.py` aracı, public dataset'in tamamıyla kart üzerinde koşulmuştur. Ham çıktılar `fpga/demo_teknofest/sonuclar/` altındadır.

| Metrik | Değer |
|---|---:|
| Gönderilen örnek | 156 |
| Golden referansı olan | 156 |
| **Golden ile uyum** | **%100,00 (156/156)** |
| Uyuşmazlık | 0 |
| Zaman aşımı | 0 |
| Gecikme (medyan / p95 / maks) | 7,74 / 8,78 / 21,58 ms |
| Ölçülen hızlanma | 183,3× |
| Sağlamlık senaryoları | 9/10 (+1 opsiyonel atlandı) |

Uyum matrisi tamamen köşegendir (silence 6, unknown 16, yes 50, no 84); köşegen dışı hücre yoktur. Donanım doğruluğu ve golden model doğruluğu %72,44 ile aynıdır, fark 0,00 puandır; bu oran veri setinin zorluğudur ve puanlamada kullanılmaz.

Başarısız tek senaryo `back_to_back`'tir: tam sırada koşulduğunda aralıksız beş çerçevenin dördüne yanıt gelmiştir. Tek başına koşulduğunda üç bağımsız tekrarda 5/5 geçmiştir; fark, kendinden önceki senaryodan devreden geçiş etkisidir. Kök nedeni `uart_stream_peripheral.sv` içindeki toplayıcı sayacının (`pack_cnt_r`) `UARTS_FIFO_CLR` ile sıfırlanmamasıdır. Düzeltmesi hazırdır ancak bu teslim yamasız RTL'e SHA-256 ile bağlı olduğu için **dahil edilmemiştir**; ayrı bir fiziksel koşumla girecektir. `peripheral_interleave` senaryosu şartname gereği opsiyoneldir ve `hooks.interleave_core_hex` tanımlanmadığı için ATLANDI olarak raporlanır.

Demo imajı DEMO_MODE ile derlenir. Normal kart imajından iki farkı vardır: çıkarımlar arası 3 saniyelik bekleme yoktur ve `UART_RDR` bayt yolu doğrulama bloğu atlanır. O blok çerçeve başına 1960 değil 1964 bayt tüketir; araç tam 1960 bayt gönderdiği için fazladan istenen 4 bayt bir sonraki çerçevenin başından karşılanır ve o çerçeve kaymış işlenirdi. Normal ve simülasyon imajları bloğu hâlâ koşar, kapsama kaybı yoktur. Ayrıntı: `fpga/demo_teknofest/OKUBENI.md`.

5 Eylül tek USB jüri provası ayrı bir firmware/wrapper sürümüdür.

Fonksiyonel doğrulama Vivado xsim 2025.2 (`xvlog`/`xelab`/`xsim`) ile yapılmıştır; DSim kullanılmamıştır.

## Teslimin kullanımı

Zorunlu raporlar `asic/reports`, nihai görünümler/netlistler/SDC/SPEF/GDS-SPICE/config/metrikler `asic/results` altındadır. `asic/run` teslimde boştur. Büyük dosyalar Release delivery arşivinden indirilir; `make asic_verify` bütünlüğü denetler. Kurulum ve `make asic_run` açıklaması `asic/README.md` içindedir.
