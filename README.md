# Arkhe SoC & Yapay Zeka Hızlandırıcı (NPU) Projesi

Bu depo, TEKNOFEST Çip Tasarım Yarışması Mikrodenetleyici Tasarımı Kategorisi için geliştirilmiş, RISC-V tabanlı **Arkhe SoC** ve tümleşik Yapay Zeka Hızlandırıcısının (NPU) tüm RTL tasarımını, doğrulama (testbench) ortamını ve FPGA prototipleme dosyalarını barındırmaktadır.

---

## 📂 Proje Dizin Yapısı (Neyin Nerede Olduğu)

Projemiz, jüri değerlendirmesini ve geliştirme takibini kolaylaştırmak amacıyla aşağıdaki şekilde modüler olarak yapılandırılmıştır:

```text
2026_Arkhe/
├── rtl/                          # Donanım (RTL) Kaynak Dosyaları
│   ├── CPU/                      # CV32E40P RISC-V İşlemci Çekirdeği
│   ├── Memory/                   # AXI Interconnect, Bellek Kontrolcüsü ve nexys_top.sv
│   ├── npu/                      # YZ Hızlandırıcı (NPU) Modülleri
│   │   ├── npu_accelerator.sv    # NPU Üst Seviye Sarmalayıcı Modülü
│   │   ├── npu_compute_engine.sv # Çıkarım Motoru (Evrişim, Softmax, Argmax vb.)
│   │   ├── npu_axi_controller.sv # Senkron AXI-Lite TCM Bellek Denetleyicisi [YENİ]
│   │   ├── npu_csr.sv            # Kontrol ve Durum Yazmaçları (Control/Status Registers)
│   │   └── npu_tcm_sram.sv       # Sınır Güvenlikli TCM Bellek (30 kB)
│   └── boot/                     # Boot ROM Bellek Resmi (boot.hex)
│
├── tb/                           # Doğrulama, Simülasyon ve Test Ortamı
│   ├── T1.1_npu_block_level/     # NPU Blok Seviyesi Testbench ve Sonuç Raporu
│   ├── T1.2_soc_system_level/    # SoC Entegrasyon Testbench ve Sonuç Raporu
│   ├── T1.3_axil_protocol/       # AXI4-Lite SVA (Assertion) Protokol Denetimleri Raporu
│   ├── T2.1_core_trace/          # Çekirdek Komut İzleme ve Spike ISS Karşılaştırma Betiği
│   ├── T3.1_jtag_debug/          # JTAG Hata Ayıklama Testleri ve Kod Kapsama (Coverage) Raporu
│   ├── FPGA_Reports/             # Sentez, Zamanlama ve Güç Raporları (.rpt)
│   ├── DTR_Verification_and_Testing_Report.md  # DTR Doğrulama Bölümü Taslağı
│   └── DTR_Verification_and_Testing_Report.pdf  # Calibri Formatlı Resmi PDF Raporu
│
├── sw/                           # Temel C ve Assembly RISC-V Yazılımları
├── sw_nexys/                     # FPGA Fiziksel Test Yazılımı
│   ├── src/                      # Otonom Test C Kodları (main.c, crt0.S)
│   └── scripts/                  # Boot ROM için boot.hex Üreten Derleme Betiği
│
├── dtr_demo/                     # Jüri Değerlendirmesi İçin Temizlenmiş İzole Demo Projesi
│   ├── scripts/                  # Vivado Projesini Otomatik Kuran Scriptler
│   └── src/                      # Demo Kaynak Kodları
│
├── teknotest/                    # TEKNOTEST Çevre Birimi (UART/GPIO) Kabul Testi Ortamı
├── scripts/                      # Vivado Proje Kurulum ve Bitstream Derleme Scriptleri
├── weights/                      # Yapay Zeka Modeli Ağırlık ve Bias ROM Dosyaları (.mem)
│   └── generate_weights.py       # Ağırlık Haritasını Üreten Python Betiği
│
├── README.md                     # Bu Açıklama Dokümanı
└── dtr_hazirlik_ve_yol_haritasi.md # Raporu Yazacak Ekip İçin Kılavuz Dokümanı
```

---

## 🚀 Başlangıç ve Vivado Kurulumu

### A. Simülasyon Projesini Oluşturma
Vivado TCL konsolu üzerinden ana simülasyon projesini kurmak için:
1. Vivado'yu açın.
2. TCL konsoluna şu komutları yazın:
   ```tcl
   cd <depo_koku>
   source ./scripts/create_project.tcl
   ```
Bu komut, tüm tasarım dosyalarını ve testbench'leri içeren ana Vivado projesini otomatik olarak kuracaktır.

### B. DTR Demo Projesini Çalıştırma
Jüri değerlendirme kuralları çerçevesinde izole edilen demo projesini koşturmak için:
```tcl
cd <depo_koku>/dtr_demo
source ./scripts/create_vivado_proj.tcl
launch_simulation
run -all
```
Bu komut sonucunda, CPU'nun otonom UART ve NPU el sıkışma simülasyonu çalışarak testi başarıyla sonlandıracaktır.

---

## ⚡ FPGA Prototipleme ve Fiziksel Test (Nexys 4 DDR)

Tasarımın fiziksel donanım üzerinde doğrulanması için **50 MHz** sistem saati ve asenkron reset senkronizasyonu tasarlanmıştır.

### 1. Bitstream Üretimi:
FPGA projesini kurmak ve sentezi başlatmak için Vivado TCL konsolunda:
```tcl
cd <depo_koku>
source ./scripts/create_nexys_project.tcl
source ./scripts/build_nexys.tcl
```
Bu adımlar sonucunda `vivado_nexys_project` altında bitstream (`.bit`) dosyası üretilecektir.

### 2. Otonom Yazılım Akışı (Boot ROM):
FPGA üzerinde koşan [sw_nexys](sw_nexys/) yazılımı:
*   İşlemci uyandığı anda UART1'i 115200 Baud formatında ilklendirir.
*   Terminale `*** ARKHE FPGA TEST ***` çıktısını basar.
*   TCM SRAM bellek alanına otonom döngüde 3 saniyede bir YES (`0x55555555`) ve NO (`0xAAAAAAAA`) spektrogram verilerini basarak NPU çıkarımını tetikler.
*   Çıkarım sonucuna göre (Class 2 / Class 3) kart üzerindeki 16 LED'i sırasıyla `0x5555` ve `0xAAAA` desenlerinde yakıp söndürür.

---

## 📊 Özet Doğrulama Metrikleri

> Aşağıdaki bütün sayılar `evidence/` altındaki rapor dosyalarından
> alınmıştır. Her satırın kaynağı belirtilmiştir.

### FPGA — Nexys 4 DDR (xc7a100t), 50 MHz

| Metrik | Değer | Kaynak |
|---|---|---|
| Setup payı (WNS) | **+1,811 ns** | `evidence/fpga/timing_v8.rpt` |
| Hold payı (WHS) | **+0,060 ns** | aynı |
| LUT | **18.587** (%29,32) | `evidence/fpga/utilization_v9.rpt` |
| Flip-flop | 5.478 (%4,32) | aynı |
| Block RAM | 13 (%9,63) | aynı |
| DSP | 9 (%3,75) | aynı |
| Toplam güç | **137 mW** (39 dinamik + 98 statik) | `evidence/fpga/power_v9.rpt` |

Hedef periyot 20 ns → **%9,1 zamanlama marjı**.

### ASIC — SKY130A, LibreLane Classic, 50 MHz

| Metrik | Değer |
|---|---|
| Standart hücre | 47.926 |
| SRAM makrosu | **23** (30 kB TCM + 8 kB I-RAM + 8 kB D-RAM) |
| Flip-flop | 10.908 |
| Setup payı (yönlendirme sonrası) | **+2,719 ns** |
| Hold payı (yönlendirme sonrası) | **+0,246 ns** |
| Zamanlama ihlali | **0** |
| Yönlendirme overflow | **0** (tüm katmanlar, %14,4 kullanım) |
| Toplam tel uzunluğu | 7.260.490 µm |
| Toplam güç | 104,8 mW (%61,5'i SRAM makroları) |

Ayrıntı: `evidence/asic/OLCUMLER.md`

### Doğrulama

| Kontrol | Sonuç |
|---|---|
| AXI4-Lite protokol denetleyicisi (SVA) | 0 ihlal — `axil_protocol_checker.sv`, `tb_soc_top.sv:703` ile `bind` edilmiş |
| Blok testleri | 6 test, 0 hata — `scripts/run_regression.py` |
| Tam sistem regresyonu | 77 denetim, 0 hata |
| Buyruk izi (kontrol akışı) | Derlenmiş programın disassembly'si ile tutarlı — `tb/T2.1_core_trace/trace_check.py` |

**Kapsam notu:** Buyruk izi denetimi kontrol akışını doğrular. ÖTR'de
taahhüt edilen **Spike ISS karşılaştırması yapılmamıştır**; ayrıntı ve
gerekçe `tb/T2.1_core_trace/T2.1_test_report.md` bölüm 4.1'dedir.

### YZ hızlandırıcı başarımı

| | Öncesi | Sonrası |
|---|---|---|
| Çıkarım süresi | 19,84 ms | **1,45 ms** |
| Çevrim | 992.083 | **72.583** |
| Hızlanma | — | **13,7×** |
| DSP maliyeti | 9 | **9** (değişmedi) |

Kanal paylaşımı (8 paralel biriktirici) ve okuma boru hattı ile elde
edildi. Saniyede 689 çıkarım.

**Komut seti:** Uygulama `RV32IMC`'dir. CV32E40P `FPU=0` ile
yapılandırılmıştır; ÖTR/DTR'de `RV32IMFC` yazmaktadır. Ölçüme dayalı
sapma gerekçesi: `evidence/fpga/fpu_karar_olcumu.md`.

---

*Detaylı doğrulama verileri ve rapor yazım yönergeleri için [dtr_hazirlik_ve_yol_haritasi.md](dtr_hazirlik_ve_yol_haritasi.md) kılavuzunu inceleyebilirsiniz.*
