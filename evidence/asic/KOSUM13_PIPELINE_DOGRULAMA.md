# Koşum 13 NPU pipeline doğrulaması

Tarih: 26 Ağustos 2026

## RTL değişikliği

`npu_compute_engine.sv` içindeki depthwise ve fully-connected
requantization yollarında operand seçimi ile 32x32 signed çarpma ayrı
FSM çevrimlerine bölündü.

- Yeni operand yazmaçları: `rq_x`, `rq_m`
- Yeni durumlar: `CONV_RQ_MUL`, `FC_RQ_MUL`
- Matematik ve yuvarlama sırası değişmedi.
- Her depthwise kanal requantization işlemi ve her FC sınıfı için bir
  çevrim eklendi.
- Amaç: Koşum 11'deki `d_out -> conv_acc mux -> multiplier -> rq_ab`
  kritik yolunu yazmaç sınırında bölmek.

## Doğrulama

Kaynak commit'i: `3d4c001`

Vivado 2025.2 regresyonu:

```text
16/16 test geçti
349/349 denetim geçti
```

Özellikle geçen kontroller:

- NPU blok: 9 denetim
- Deterministik NPU golden: 1 denetim
- Çok vektörlü NPU doğruluk: 77 denetim
- NPU hızlanma: 2 denetim
- Tam SoC: 13 denetim
- UVM AXI agent: 17 denetim
- Gerçek QSPI boot: 13 denetim
- Çekirdek izi: 1 denetim

ASIC `filelist` kontrolü ve LibreLane/Verilator lint temiz geçti.
Koşum 13, önceki fiziksel signoff düzeltmeleri korunarak 50 MHz
(`CLOCK_PERIOD: 20.0`) hedefinde başlatılacaktır.
