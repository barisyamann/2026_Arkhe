# ARKHE — üç doğrulama başlığının ölçüm paketi

Makine tarafından denetlenen güncel sonuç: `closure_report.json`. Her koşunun geçme/kalma durumu ayrı JSON dosyasındadır; yalnızca bir log içinde PASS sözcüğü bulunması yeterli değildir. Nihai sonuç özeti `python closure_20260905/summarize.py` ile üretilir.

**Tamamlanan sonuç (5 Eylül 2026):** doğruluk farkı 0 yüzde puan; tam iş yükünde 800,0517× hızlanma; 23/23 AXI-Lite bağlantısında sıfır protokol hatası. Yazılabilir 20 bağlantıda hem okuma hem yazma, salt okunur üç komut bağlantısında okuma görüldü. Dört kasıtlı protokol ihlalini yakalayan denetleyici öztesti geçti. Aday RTL dosyalarının kaynak özetleri değişmedi. Bu sonuçların kapsam koşulları aşağıdadır; özellikle yeni startup dosyasının final uygulamasına dahil edilmesi gereği korunmalıdır.

## 1. Etiketli veriyle doğruluk

TensorFlow'un [mini Speech Commands veri kümesi](https://www.tensorflow.org/tutorials/audio/simple_audio) içinden model sonuçlarına bakılmadan sabit tohumla 25 YES, 25 NO ve diğer altı kelimeden toplam 25 UNKNOWN örneği seçildi. Bunlara ayrı bir değerlendirme grubu olarak 25 sentetik sessizlik/düşük seviyeli gürültü eklendi. Dosya seçimleri `selection.json` içinde; kaynak dosya, giriş tensörü ve model SHA256 değerleri `accuracy_dataset.json` içindedir. Hiçbir yanlış sınıflandırılan örnek elenmedi.

Her 1960 INT8 girdi aynı şekilde resmî LiteRT/TFLite yorumlayıcısına, tamsayı Python referansına ve gerçek NPU hesaplama motorunun RTL simülasyonuna verildi. RTL'nin sınıfı ve dört Q0.12 çıktısı tamsayı referansla karşılaştırıldı. **Accuracy**, modelin tahmin ettiği sınıfa göre değil, ses dosyasının bağımsız etiketine göre hesaplandı. Ayrıca benchmark için kullanılan bir etiketsiz golden girdi işlendi; bu girdi accuracy paydasına katılmadı.

Ölçülen sonuç: konuşma grubunda iki model de **61/75 (%81,33)**, sentetik sessizlik grubunda iki model de **20/25 (%80)**, birleşik grupta iki model de **81/100 (%81)** doğru. Sınıf kararları 101 girdinin tamamında aynı; 100 etiketli girdide doğruluk farkı **0 yüzde puan**. Karışıklık matrisleri `accuracy_report.json` içinde; satırlar gerçek, sütunlar tahmin edilen sınıf, sıra SILENCE/UNKNOWN/YES/NO.

Sınırlar: Bu çalışma bütün resmî test kümesi değildir; modelin eğitim örnekleriyle örtüşme durumu bilinmiyor. Ön işleme mevcut kayan noktalı host frontend'idir ve resmî sabit noktalı microfrontend ile bit eşitliği iddiası yoktur. İki sınıflandırıcıya aynı tensör verildiğinden bu ölçüm hızlandırıcı–yazılım karşılaştırmasıdır. Sentetik sessizlik, bağımsız 25 doğal kayıt gibi sunulmamalıdır. Şartnamenin %10 penceresi bu ölçülen kümede sağlanır; tüm olası veriler için garanti oluşturmaz.

## 2. Tam iş yükünde hızlanma

`bench_full.c`, 4.000 evrişim çıktısının tamamını, ReLU, FC bias/MAC, son kuantizasyon ve softmax işlemlerini gerçek CV32E40P RTL'sinde çalıştırır. ASIC SRAM makro modelleri kullanılır. Süre timer sayacından okunur; sonucu bildiren yazmalar ölçüm bittikten sonra yapılır. Çıktılar **[0, 225, 326, 3543]** olarak denetlenmeden ölçüm geçmiş sayılmaz.

CPU: **68.474.022 çevrim**. Aynı girdi için NPU hesaplama motoru: **85.587 çevrim**. Oran **800,0517×**. 50 MHz karşılaştırma saatinde sırasıyla **1,36948044 s** ve **1,71174 ms**. Bu sayı kısmi piksel sayısından ölçeklenmemiştir; tam çıkarım çalıştırılmıştır.

Sınırlar: CPU tarafı `-Os`, RV32IMC ile derlenen özel tamsayı C gerçeklemesidir; resmî TFLite Micro programının çalıştırıldığı iddiası yoktur. Tek girdide ölçüldü. NPU tarafı senkron TCM modeliyle hesaplama motorunun süresidir. Boot, UART girdi taşıma, DMA hazırlama ve ISR/UART çıktı süreleri hızlanma hesabında bulunmaz. 50 MHz referans saatidir; ASIC fiziksel zamanlama kapanışının kanıtı değildir. Ayrıntılar `speed_report.json` içindedir.

## 3. Bütün AXI-Lite bağlantılarında protokol kontrolü

`axi_inventory.json`, 23 ayrı bağlantıyı listeler: CPU veri, DMA ve JTAG master'ları, ortak arbiter çıkışı, 13 slave bağlantısı, ROM/I-RAM arbiter çıkışları, NPU motoru, CPU komut ve iki komut belleği kolu. Aynı elektriksel bağlantının modülün iki ucundaki isimleri ayrıca iki arayüz sayılmaz.

Her bağlantıda ayrı pasif UVM agent ve monitor vardır. Monitor AW, W ve AR kuyruklarını bağımsız tutar; yanıt eşleşmesini, EXOKAY yasağını, geçerli sinyallerde X/Z bulunmamasını ve backpressure sırasında VALID/payload kararlılığını denetler. Gerçek read/write el sıkışmaları ayrıca testbench tarafından sayılıp monitor sayılarıyla karşılaştırılır. ROM'a bilerek yapılan yazmanın SLVERR yanıtı geçerli bir hata yanıtıdır; protokol ihlali sayılmaz.

`tb_monitor_test.sv` doğru ve ayrık AW/W trafiğini kabul etmeyi; sahipsiz R, EXOKAY, stall sırasında adres değişimi ve X verisi olmak üzere dört kasıtlı ihlali yakalamayı sınar. Bu **negatif denetleyici testinde** dört UVM_ERROR beklenir. Gerçek SoC koşusunda UVM_ERROR/UVM_FATAL kabul edilmez.

İlk genişletilmiş koşuda aynı DRAM okumasındaki bilinmeyen veri CPU/arbiter/DRAM monitor'larında görüldü. `baseline_uninitialized_dram.log` saklandı. Yeni test başlangıcı `crt0_deterministic.S` ile bütün 8 KB data SRAM'i **CPU üzerinden gerçek yazmalarla** sıfırlar; ayrıca kullanılan linker script `.sbss/.sdata` bölümlerini kapsar. RAM modeline zorla sıfır basılmaz ve X denetimi kapatılmaz. Son geçme sonucu bu tanımlı RAM başlangıcı ve yeni doğrulama firmware'i için geçerlidir. Bu başlangıç koşulu finalde seçilecek uygulamanın startup dosyasında da korunmalıdır; eski firmware'in aynı şekilde geçtiği iddia edilmemelidir.

GPIO, timer ve DMA'nın eksik kalan okuma yönleri JTAG master üzerinden self-checking register okumalarıyla uyarılır. Başarı için bütün bağlantılarda okuma, yazılabilir bağlantılarda ayrıca yazma tamamlanmalıdır. Kesintisiz komut getirme nedeniyle test sonundaki kısa süreli outstanding işlemler raporlanır; 5 ms liveness sınırı uygulanır. Bu sınır AXI standardının evrensel timeout şartı değil, bu testin kontrol sınırıdır. Zincir üzerindeki bağlantı sayaçları aynı mantıksal işlemi birden fazla sayabileceği için sayaçlar toplanıp benzersiz işlem sayısı diye sunulmaz.

## Yeniden çalıştırma ve dosya kapsamı

Komutlar `work_50mhz/verification_20260905` dizininden çalıştırılır:

```powershell
python closure_20260905/build_full_cpu.py
python closure_20260905/run_full_cpu.py
python closure_20260905/prepare_accuracy.py
python closure_20260905/run_accuracy.py
python closure_20260905/build_defined_app.py
python closure_20260905/run_monitor_test.py
python closure_20260905/run_all_axi.py
python closure_20260905/summarize.py
```

Tam CPU simülasyonu bu bilgisayarda yaklaşık 49 dakika sürdü. Xsim/Vivado ve RISC-V GCC konumları derleme betiklerinde görülebilir; bunlar yerel ölçüm betikleridir, taşınabilir ASIC teslim otomasyonu yerine geçmez. Veri hazırlama için numpy ve ai-edge-litert, yerel `mini_speech_commands.zip` arşivi gerekir.

Bu paket ASIC RTL'sini veya kartta geçen `JURI_FPGA_TESTI` dosyalarını değiştirmez. Buradaki `flash_sim.hex` doğrulama için üretilmiştir; kartın USB demo MCS dosyasının yerine doğrudan yüklenmemelidir. Son ASIC DRC/LVS/STA ve final çıktı toplama bu üç ölçümden ayrı işlerdir.
