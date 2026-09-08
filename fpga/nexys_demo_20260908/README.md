# Nexys Pmod UART2 demo — 8 Eylül 2026

Bu sürümün bitstream'i 16:18'de üretilmiştir. 57 ortak SoC kaynağı için depo kökündeki d45_anten2 RTL kullanılır; FPGA üst modülü ve pin dosyası bu dizindedir. 17:43 UART FIFO temizleme düzeltmesi bu bitstream'de ve ASIC GDS'de yoktur. Yeni bir kart koşusu veya yeni bitstream bu paketleme sırasında üretilmedi.

Bağlantı: core UART kartın USB-UART bağlantısı; stream UART 3,3V UART-TTL modülü üzerinden JB1/D14 RX, JB2/F16 TX, ortak GND. COM portları `demo/arkhe_icd.json` içinde makineye göre seçilir. `demo/OKUBENI.md` araç kullanımını açıklar.

`cd demo` ardından `python demo_harness.py validate -c arkhe_icd.json` yapılandırmayı kontrol eder. Fiziksel prova için `python demo_harness.py run -c arkhe_icd.json --only-robustness` kullanılır. Gerekli seri paket: pyserial. Orijinal ICD ve deney sonuçları değiştirilmemiştir; ICD'deki eski yazılım süresi tahminidir, yeni tam CPU ölçümü olarak sunulmamalıdır.

`bitstream/nexys_top.bit` ve `firmware/build/flash_demo.hex` farklı katmanlardır: bitstream FPGA mantığını, flash imajı uygulama ve ağırlıkları taşır. HEX dosyası Verilog bellek sözcük biçimidir; MCS değildir. Var olan flash programlama akışında doğru adrese yerleştirilmelidir; yalnız .bit yüklemek uygulama flash'ını güncellemez. Boot yerleşimi firmware betiklerinde 0x800000 uygulama, 0x802000 ağırlıklardır.

Yönlendirme raporu WNS +1,218 ns, WHS +0,055 ns. Son kayıtlı sağlamlık deneyi 9 PASS, 1 FAIL, 1 SKIP: back_to_back beş çerçveden dördüne yanıt; peripheral_interleave atlanmış. Bu yüzden tüm demo testleri geçti denmez.

Yeniden FPGA derleme betiği `build_fpga.tcl` depo kökündeki d45 RTL ve buradaki wrapper/XDC ile çalışır. `vivado -mode batch -source fpga/nexys_demo_20260908/build_fpga.tcl` depo kökünden çağrılır. Firmware kaynakları bağımsız kopyadır; dizin düzeni nedeniyle burada kopyalanan tarihsel build.py doğrudan çalıştırılmadan kök/weights yolu uyarlanmalıdır. Kaynak içerikleri ve hazır HEX dosyaları korunmuştur.
