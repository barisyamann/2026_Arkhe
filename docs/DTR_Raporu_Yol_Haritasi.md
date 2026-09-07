# Detay Tasarım Raporu (DTR) - Yol Haritası ve Kalan İşler Listesi

Bu doküman, Teknofest 2026 Çip Tasarım Yarışması Mikrodenetleyici Kategorisi kapsamında hazırlayacağımız **Detay Tasarım Raporu (DTR)** için tamamlanmış kısımları, yapılması gerekenleri ve kalan adımları listeler.

---

## 1. Tamamlanan Kısımlar (Rapora Yazılmaya Hazır)

RTL tasarım ve simülasyon aşamalarını başarıyla tamamladığımız için aşağıdaki bölümler doğrudan teknik verileri ve kodlarıyla rapora yazılabilir durumdadır:

* **Sistem Adres Haritası**: `memory_map_pck.sv` dosyasındaki tüm adres alanları ve slave haritalamaları (Tablo halinde sunulacak).
* **Donanımsal Hakemleme (Master Arbiter)**: CPU, JTAG ve DMA master'larını birleştiren round-robin `axil_arbiter_3to1.sv` tasarımı.
* **Tek Kanallı DMA Kontrolcüsü**: `dma_controller.sv` FSM şeması, durum geçişleri ve CSR register tanımları.
* **JTAG Debug Bridge**: `jtag_debug.sv` basitleştirilmiş TAP durum makinesi ve CPU debug kontrol mekanizması.
* **Yapay Zeka Hızlandırıcı (NPU)**: `npu_compute_engine.sv` ve `npu_tcm_sram.sv` dual-port bellek yapısı, 1960 girişli otonom veri akışı ve Softmax/Argmax donanım eşdeğeri sınıflandırıcı FSM tasarımı.
* **Hata Giderme Çalışmaları**: NPU Done sticky bit güncellemesi, I2C IRQ eklenmesi ve testbench QSPI makine kodu düzeltmeleri.
* **Fonksiyonel Simülasyon Doğrulaması**: Boot ROM kopyalama aşamasının, NPU çıkarımının (Class=2) ve GPIO çıkışının `0x5555` olmasının başarıyla doğrulanması.

---

## 2. Kalan İşler ve Yapılacaklar Listesi (DTR Checklist)

DTR raporunun tamamlanması için yapılması gereken donanımsal analizler ve raporlama adımları aşağıda listelenmiştir:

- [ ] **1. Simülasyon Dalga Formu (Waveform) Ekran Görüntülerini Almak**
  * [ ] **Boot Kopyalama**: QSPI arayüzünden verilerin okunup I-RAM'e (`0x0100_0000`) yazıldığı anın dalga formu.
  * [ ] **NPU Çıkarımı**: `start_i` sinyalinin tetiklenmesi, TCM SRAM okumaları ve `done_o` ile `npu_irq` kesmesinin yükseldiği an.
  * [ ] **GPIO ve Karar**: GPIO ODR yazmacına `0x5555` yazılması ve `gpio_o` pinlerinin çıkışlarının değiştiği an.

- [ ] **2. Mantıksal Sentez (Synthesis) ve Kaynak Kullanım Raporu**
  * [ ] Vivado veya Yosys üzerinden tasarımı sentezleyin.
  * [ ] **Utilization Report** (Kaynak kullanımı) tablosunu oluşturun: Toplam LUT, Register (FF), BRAM (Bellek blokları) sayılarını ve bunların modüllere göre dağılımını rapora ekleyin.

- [ ] **3. Fiziksel Tasarım (PnR - OpenLane Akışı)**
  * [ ] RTL kodlarımızı OpenLane akışına (OpenROAD / Yosys) dahil edin.
  * [ ] **Kat Planı (Floorplan)** ve **Yönlendirme (Routing)** görsellerini (çip üstü yerleşim ekran görüntüleri) kaydedin.
  * [ ] **Zamanlama Raporu (Timing)**: WNS (Worst Negative Slack), WHS (Worst Hold Slack) ve çipin maksimum çalışma frekansını (MHz) çıkarın.
  * [ ] **Güç ve Alan Analizi**: Toplam güç tüketimi (mW) ve silikon alanı ($mm^2$) değerlerini rapora yazın.
  * [ ] Nihai **GDSII** tasarım dosyasının görüntüsünü rapora ekleyin.

- [ ] **4. Kod Kapsama (Code Coverage) Analizi**
  * [ ] ModelSim, Questa veya DSim gibi bir simülatörde testbench'i coverage modunda çalıştırın.
  * [ ] **Statement, Branch, Expression ve Toggle Coverage** yüzdelerini raporlayın (Yarışma komitesi genelde %90 üzeri kapsamayı hedefler).

- [ ] **5. Şablon Dokümanının Doldurulması**
  * [ ] `2026_Mikrodenetleyici_Tasarim_DTR_Sablonu_1_w0HlD (1).docx` şablonunu açarak ekibimizin rol dağılımını, kullanılan araçları ve yukarıdaki tüm verileri/şemaları ilgili başlıklara yerleştirin.

---

> [!TIP]
> * **Rapor Görselleri**: Simülasyon ekran görüntülerinde `clk_i`, `rst_ni`, `PC_ID`, `npu_irq`, `gpio_o` ve AXI handshake sinyallerinin görünür olması rapor kalitesini büyük ölçüde artıracaktır.
> * **DMA ve NPU Tabloları**: DMA ve NPU CSR'ları için hazırladığımız tabloları doğrudan DTR'deki register haritaları kısmına ekleyebilirsiniz.
