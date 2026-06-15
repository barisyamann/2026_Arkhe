# Arkhe SoC - DTR Raporu Yazım Rehberi ve Test Faaliyetleri El Kitabı

Bu kılavuz, **Arkhe SoC** projesinin doğrulama, simülasyon ve FPGA üzerinde fiziksel test süreçlerini DTR (Dizayn Teknoloji Raporu) formatına uygun şekilde belgelemek için hazırlanmıştır. Bu belgedeki bölümler, doğrudan DTR raporuna kopyalanıp düzenlenebilecek şekilde yapılandırılmıştır.

---

## 📋 1. DTR Raporlama Planı ve Dosya Konumları

DTR Raporunda kullanılacak tüm test sonuçları, loglar ve resmi raporlar projenin `tb/` (Testbench) dizini altında düzenli bir yapıda arşivlenmiştir. Ekip arkadaşlarımızın raporu yazarken referans vereceği dosya yolları şunlardır:

*   **Ana DTR Raporu Taslağı (Markdown):** [DTR_Verification_and_Testing_Report.md](file:///c:/Arkhe_2026/tb/DTR_Verification_and_Testing_Report.md)
*   **Ana DTR Raporu (PDF):** [DTR_Verification_and_Testing_Report.pdf](file:///c:/Arkhe_2026/tb/DTR_Verification_and_Testing_Report.pdf) *(Son testlerle derlenmiş Calibiri formatlı çıktı)*
*   **NPU Blok Seviyesi Test Raporu (T1.1):** [T1.1_test_report.md](file:///c:/Arkhe_2026/tb/T1.1_npu_block_level/T1.1_test_report.md)
*   **SoC Sistem Seviyesi Test Raporu (T1.2):** [T1.2_test_report.md](file:///c:/Arkhe_2026/tb/T1.2_soc_system_level/T1.2_test_report.md)
*   **AXI Protokol Kontrolleri Raporu (T1.3):** [T1.3_test_report.md](file:///c:/Arkhe_2026/tb/T1.3_axil_protocol/T1.3_test_report.md)
*   **Çekirdek Komut İzleme Raporu (T2.1):** [T2.1_test_report.md](file:///c:/Arkhe_2026/tb/T2.1_core_trace/T2.1_test_report.md)
*   **JTAG Debug Doğrulama Raporu (T3.1):** [T3.1_test_report.md](file:///c:/Arkhe_2026/tb/T3.1_jtag_debug/T3.1_test_report.md)
*   **FPGA Sentez/Uygulama Raporları:** [utilization_report.rpt](file:///c:/Arkhe_2026/tb/FPGA_Reports/utilization_report.rpt), [timing_report.rpt](file:///c:/Arkhe_2026/tb/FPGA_Reports/timing_report.rpt), [power_report.rpt](file:///c:/Arkhe_2026/tb/FPGA_Reports/power_report.rpt)

---

## 🛠️ 2. Testler Hakkında Neler Yaptık ve Nasıl Yaptık?

Doğrulama stratejimiz **"Sayısal Metrik Takibi" (Code & Functional Coverage)** ve **"Kendi Kendini Kontrol Eden" (Self-checking) testbench** altyapılarına dayanmaktadır. Yapılan testlerin özeti ve metodolojisi aşağıda listelenmiştir:

### A. Blok Seviyesi Testler (T1.1 NPU Compute Engine)
*   **Nasıl Yapıldı:** `tb_npu_compute_engine.sv` testbench'i ile NPU, SoC'den izole şekilde simüle edildi. Kod içindeki mock fonksiyonlar yerine, gerçek bir TinyConv/TFLite modeline ait evrişim ve tam bağlantılı (Fully Connected) katmanı ağırlık ve bias verileri, sentezlenebilir ROM dosyalarından (`$readmemh` yardımıyla) donanıma yüklendi.
*   **Nasıl Çalışıyor:** Harici test girdileri (YES, NO, SILENCE spektrogram kelimeleri) NPU TCM SRAM'ine yazıldı. Donanımsal Softmax (Q0.12 formatı) ve Argmax karar verici mekanizması çalıştırılarak olasılık çıktılarının doğruluğu test edildi.
*   **Test Sonucu:** YES girdisi `%60.67` olasılıkla Class 2 (YES), NO girdisi `%69.78` olasılıkla Class 3 (NO) olarak başarıyla sınıflandırıldı.

### B. Sistem Seviyesi Entegrasyon Testleri (T1.2 SoC)
*   **Nasıl Yapıldı:** `tb_soc_top.sv` testbench'i ile CPU, AXI Interconnect, NPU, TCM SRAM ve GPIO çevre birimlerinin uçtan uca etkileşimi doğrulandı.
*   **Nasıl Çalışıyor:** CPU, QSPI Shadowing aşamasıyla bootloader yardımıyla ayağa kalkar, I-RAM'e kopyalanan AI yazılımını yürütür, MMIO üzerinden NPU CSR registers'ı (START, RESET) kurar, TCM SRAM'e spektrogram girdisini basar ve çıkarım bitene kadar NPU kesme hattını (`done_sticky`) polling yöntemiyle takip eder. Çıkarım bittiğinde NPU done kesmesini yakalayan CPU, sınıf sonucunu okur ve GPIO ODR yazmacına `16'h5555` başarısını basar.
*   **Test Sonucu:** Sistem simülasyonu toplam **19,29 ms (~964,828 saat çevrimi)** sürmüş ve sıfır hata ile tamamlanmıştır.

### C. AXI4-Lite Protokol Denetimleri (T1.3 SVA)
*   **Nasıl Yapıldı:** `axil_protocol_checker.sv` SystemVerilog Assertion (SVA) tabanlı pasif VIP modülü, AXI Interconnect ve NPU denetleyicisi arasındaki el sıkışma hatlarına bağlandı.
*   **Nasıl Çalışıyor:** Reset durum değerleri (`assert_reset_val`), adres kararlılığı (`assert_awaddr_stable`, `assert_araddr_stable`), veri kararlılığı (`assert_wdata_stable`, `assert_rdata_stable`) ve cevap kararlılığı (`assert_bresp_stable`) kuralları simülasyon boyunca denetlendi.
*   **Test Sonucu:** 960.000+ saat çevrimlik simülasyon süresince **sıfır protokol ihlali** (0 failure) raporlanmıştır.

### D. Spike ISS Trace Karşılaştırması (T2.1 Çekirdek Uyum)
*   **Nasıl Yapıldı:** CV32E40P işlemci çekirdeğinin simülasyon boyunca yürüttüğü buyruklar (PC adresleri, yazmaç güncellemeleri ve komut mnemonikleri) anlık olarak kaydedildi ve `compare_trace.py` otomatik analiz aracıyla Spike ISS (Instruction Set Simulator) referans modeliyle karşılaştırıldı.
*   **Test Sonucu:** İlk 20 komut adımı boyunca donanım komut izleri referans model ile **%100 uyumlu** çalışmıştır.

### E. JTAG Hata Ayıklama (T3.1 JTAG)
*   **Nasıl Yapıldı:** IEEE 1149.1 standartlarına uyumlu 16 durumlu TAP FSM denetim yapısı doğrulandı.
*   **Nasıl Çalışıyor:** JTAG portu üzerinden TAP durum geçişleri tetiklenerek sırasıyla; IDCODE okuma (`32'h41524b48` - "ARKH"), CPU Halt (durdurma), JTAG üzerinden TCM SRAM bellek adresine AXI Master aracılığıyla veri yazma/okuma (`32'hDEADBEEF`) ve CPU Resume (devam ettirme) test edildi.
*   **Test Sonucu:** JTAG testleri sıfır hata ile başarıyla sonuçlanmıştır.

---

## 📈 3. Kod ve İşlevsel Kapsama (Coverage) Sonuçları

DTR'de jüriye sunulacak en önemli metriklerden biri kapsama (coverage) verileridir:

### A. Kod Kapsaması (Code Coverage - XSim Raporu)
Tüm SoC genelinde Vivado Simulator ile toplanan kapsamalar:
*   **Statement (Satır) Coverage:** `%46.58`
*   **Branch (Dallanma) Coverage:** `%30.14`
*   **Condition (Koşul) Coverage:** `%45.70`
*   **Toggle (Geçiş) Coverage:** `%21.50`
> 💡 **Rapor Savunma Notu:** Genel SoC düzeyinde Statement Coverage'ın %46.58 olmasının nedeni, sistemde bulunan ve bu testlerde kullanılmayan büyük donanım bloklarının (DMA, I2C, SPI, UART, FPU vb.) aktif uyarılmamasıdır. Ancak test edilen `jtag_debug`, `npu_axi_controller`, `npu_csr` ve `npu_compute_engine` modüllerinin kendi içindeki kapsama oranları **%90 - %100** aralığında gerçekleşmiştir.

### B. İşlevsel Kapsama (Functional Coverage)
SystemVerilog `covergroup` yapıları ile doğrulanan durumlar:
*   **`cg_npu_inference` (NPU Sınıf Çıktıları Kapsaması):** NPU sınıf çıktılarının (`class_o`) YES, NO ve SILENCE durumları simülasyonda tetiklenerek %100 kapsanmıştır.
*   **`cg_soc_verification` (SoC AXI & JTAG Kapsaması):** GPIO karar çıkışları (`16'h0000`, `16'h5555`), JTAG TMS durum geçişleri ve AXI-Lite okuma/yazma el sıkışmalarının tamamı en az bir kez tetiklenerek %100 işlevsel kapsama elde edilmiştir.

---

## 🚀 4. FPGA Prototipleme ve Fiziksel Doğrulama Detayları

Tasarımın fiziksel olarak **Nexys 4 DDR / Nexys A7 (Artix-7 XC7A100T-1CSG324C)** FPGA geliştirme kartı üzerinde doğrulanması süreci ve elde edilen sonuçlar aşağıda detaylandırılmıştır.

### A. FPGA'da İşlemci Üzerinde Yazılım Koşturuldu mu?
**Evet.** RV32IMFC komut setine sahip CV32E40P işlemcisi üzerinde otonom test yazılımı çalıştırılmıştır. İşlemci, Boot ROM'da yer alan programı yürüterek NPU hızlandırıcısını yönetmiş, girdi verilerini TCM belleğe aktarmış ve çevre birimlerini kontrol etmiştir.

### B. Yazılımlarla Çevre Birimleri Test Edildi mi?
**Evet.** Yazılım tarafından MMIO (Memory Mapped I/O) kullanılarak şu çevre birimleri doğrudan test edilmiştir:
1.  **UART1 (Universal Asynchronous Receiver-Transmitter):** 115200 Baud hızında ilklendirilmiş, başlangıçta terminale `*** ARKHE FPGA TEST ***` başlığı ve test döngülerinde anlık NPU durum logları (`Run`, `Clear TCM`, `Class: 2/3`, `Wait 3s`) basılarak doğrulanmıştır.
2.  **GPIO (General Purpose I/O):** NPU'dan dönen çıkarım sonucuna göre (Class 2 veya Class 3) kart üzerindeki 16 adet fiziksel LED kontrol edilmiştir.
3.  **NPU CSR & TCM SRAM:** NPU'nun durum saklayıcıları (START, done_sticky) ve TCM bellek alanı yazılım ile yönetilmiştir.

### C. Karşılaşılan Zorluklar ve Çözümleri
FPGA prototipleme sürecinde karşılaşılan kritik problemler ve uyguladığımız çözümler DTR'de savunma amaçlı şu şekilde yer almalıdır:

#### 1. QSPI Flash Shadowing ve Reset Kilitlenmesi
*   **Zorluk:** Simülasyonda testbench Boot ROM'a doğrudan yazılım force ederken, gerçek kartta varsayılan bootloader QSPI Flash'tan veri kopyalamaya çalışıyordu. Ancak FPGA kartında QSPI pinleri bağlı olmadığı/veri olmadığı için CPU AXI veriyolundan `DEADBEEF` okuyor ve sonsuz bir reset loop'una girerek kilitleniyordu. UART veya LED'lerde hiçbir tepki alınamıyordu.
*   **Çözüm:** QSPI shadowing kopyalama mantığını devreden çıkararak, otonom bir test yazılımını doğrudan Boot ROM (`boot.hex`) içerisine gömdük. Bu yazılım CPU açılır açılmaz otonom olarak NPU çıkarım döngüsünü başlatır hale getirilerek kilitlenme çözülmüştür.

#### 2. .sdata Bölümü ve RAM Kopyalama Hatası
*   **Zorluk:** C kodunda global `uart` pointer'ı tanımlandığında, derleyici bu değişkeni `.sdata` (small data) bölümüne yerleştiriyordu. Boot ROM'daki startup kodu `.sdata` bölümünü RAM'e kopyalamadığı için pointer RAM'de NULL kalıyor ve CPU UART'a erişmeye çalıştığı anda çöküyordu.
*   **Çözüm:** Global pointer yapısını iptal ederek UART adresine makro ile doğrudan eriştik: `#define UART ((volatile uart_regspace *) UART_BASE_ADDR)`. Bu sayede `.data` ve `.bss` bölümlerinin boyutu sıfıra indirilerek bellek kopyalama ihtiyacı tamamen ortadan kaldırıldı.

#### 3. Saat Kayması (Clock Skew) ve Metastability
*   **Zorluk:** Kart üzerindeki 100 MHz osilatör saati doğrudan SoC sistemine verildiğinde zamanlama ihlalleri oluşuyordu. Ayrıca harici reset butonundan gelen asenkron sinyal CPU'nun kararsız (metastable) başlamasına neden olabiliyordu.
*   **Çözüm:** Donanımsal bir frekans bölücü ve **`BUFG`** (Global Clock Buffer) kullanılarak sistem saati 50 MHz'e düşürüldü. Asenkron reset sinyali ise **iki aşamalı bir reset senkronizasyonu** (`rst_n_sync`) filtresinden geçirilerek sisteme dağıtıldı.

### D. FPGA Sentez ve Uygulama (Implementation) Sonuçları
Vivado 2025.2 ortamında tamamlanan sentez ve yerleştirme metrikleri:
*   **Kaynak Kullanımı:** Slice LUTs: `8,118` (%12.80), Slice Registers: `4,839` (%3.82), BRAM Tile: `13.0` (%9.63), DSPs: `5` (%2.08). *(Tasarım Artix-7 kapasitesinin çok altında kalarak yüksek verimlilik sunmuştur)*
*   **Zamanlama Analizi (Timing Summary):**
    *   Setup Payı (WNS): **`+1.710 ns`** (İhlal Yok, MET)
    *   Hold Payı (WHS): **`+0.034 ns`** (İhlal Yok, MET)
*   **Güç Analizi:** Toplam güç tüketimi **`0.129 W` (129 mW)** olarak ölçülmüştür. NPU dinamik gücün %51.6'sını, CPU ise %22.5'ini tüketmektedir.

---

## 🔮 5. Nereler Daha Geliştirilebilir? (Gelecek Çalışmalar)

DTR raporunun sonuna "Gelecekte Yapılacak Geliştirmeler ve İyileştirmeler" başlığı altında yazılması gereken maddeler:

1.  **Online Co-Simulation Altyapısı:** Spike ISS ile yapılan trace karşılaştırması şu an simülasyon bittikten sonra log dosyaları üzerinden (offline) yürütülmektedir. Gelecek çalışmalarda, simülasyon esnasında her çevrimde donanım yazmaçlarını Spike ile canlı olarak kıyaslayan ve hata anında simülasyonu durduran bir *online co-simulation* yapısı kurulabilir.
2.  **SoC Kapsama (Coverage) Artırımı:** Kullanılmayan çevre birimleri (DMA, I2C, SPI, FPU) pasifize edildiği için genel SoC satır kapsaması %46.58'dir. Bu modüller için de hedefli test senaryoları yazılarak genel kapsama oranı %90'ın üzerine taşınabilir.
3.  **UVM (Universal Verification Methodology) Entegrasyonu:** Hedefli el yazımı testbench'ler yerine, tüm SoC ve AXI veriyolları için SystemVerilog UVM mimarisinde reusable (yeniden kullanılabilir) test suite'ler ve scoreboard'lar geliştirilebilir.

---

## 🖼️ 6. DTR Raporuna Eklenecek Görseller Hakkında Yönlendirme

DTR'de jüriye sunulmak üzere mutlaka eklenmesi gereken ekran görüntüleri ve şemalar (Dosyalar proje dizinindedir):

1.  **SoC Blok Diyagramı:** Ön raporda sunulan mimari şemanın güncellenmiş hali (AXI-Lite interconnect, Boot ROM, TCM SRAM ve NPU bağlantılarını gösteren blok şema).
2.  **Sistem Simülasyonu Zaman Diyagramı (Mermaid/Gantt):** DTR raporunda `4. Sistem Seviyesi Doğrulama` altındaki reset, shadowing, NPU busy ve done durumlarının sürelerini gösteren şema görselleştirilerek rapora konulmalıdır.
3.  **Spike ISS Trace Ekran Görüntüsü:** `compare_trace.py` betiğinin çalıştırılma anında terminale bastığı yeşil renkli `UYUMLU` / `SUCCESS` loglarının ekran görüntüsü.
4.  **FPGA Donanım Testi Logları:** Bilgisayara bağlı terminal (PuTTY/TeraTerm) ekranından alınan, otonom döngüde `Class: 2 (YES)` ve `Class: 3 (NO)` yazan anlık UART loglarının ekran görüntüsü.
5.  **FPGA Kart Fotoğrafı:** Nexys kartı programlandıktan sonra YES durumunda LED'lerin `0x5555`, NO durumunda ise `0xAAAA` şeklinde yandığını gösteren fiziksel kart fotoğrafları.

---

*Başarılar dileriz, rapor yazım süreci şimdiden kolay gelsin!*
