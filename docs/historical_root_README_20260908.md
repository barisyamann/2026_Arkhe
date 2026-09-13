# ARKHE — d45_anten2 final teslimi

Teslim sürümü **d45_anten2**. ASIC sentezindeki 57 RTL dosyası `d800acb` commit'i ile byte düzeyinde eşleşir. Sonradan yapılan UART FIFO düzeltmesi veya `slew40` denemesi bu GDS'nin kaynağı olarak sunulmaz.

**Dosya teslimi ve temiz signoff farklıdır:** hold ve anten geçmiştir; setup, Magic DRC, slew, kapasite ve fanout ihlalleri sürer. Ek GDS kaynaklı LVS “Circuits match uniquely” sonucunu vermiştir; SRAM içi abstract/blackbox kapsamındadır. [ASIC teslim açıklaması](asic/README.md) ve [jüri özeti](JURI_TEKNIK_OZET.md).

## Tam teslimi indirme

[d45-anten2-20260908 Release](https://github.com/barisyamann/2026_Arkhe/releases/tag/d45-anten2-20260908) içindeki **delivery** arşivini indirin. Kaynaklar ve küçük raporlar Git'tedir; büyük fiziksel çıktılar Release arşivinden tamamlanır. Yalnız GitHub Source code.zip indirmek bütün fiziksel çıktıları vermez.

Temiz klonda Python 3.11.8+ ile:

```bash
python3 tools/restore_release.py --delivery
cd asic
make asic_verify
```

Arşiv elle açılırsa `package/` dizini tam teslim köküdür. Final belgesinin 20. sayfası gereği `asic/run/` yalnız `.gitkeep` içerir. **16 GB ham koşu final teslimine dahil değildir.**

## Kaynak ve demo düzeni

- `rtl/`, `sw_nexys/`, `tb/`, `scripts/`: d45 çalışma alanının kaynak ve test girdileri.
- `asic/config.yaml`, `filelist.f`, `constraints/`, `macros/`, `environment/`: yeniden üretim girdileri.
- `asic/reports/`, `asic/results/`: zorunlu raporlar ve nihai dosyalar.
- `fpga/nexys_demo_20260908/`: Pmod UART2 demo wrapper'ı, bitstream, firmware, raporlar ve test sınırları.
- `fpga/JURI_FPGA_TESTI/`: 5 Eylül tek USB tanılama sürümü ve kart kanıtları; farklı firmware/wrapper kullanır.
- `provenance/`: kaynak eşlemesi, gereksinim listesi ve checksum kayıtları.

FPGA demo sürümleri ASIC fiziksel kapanışının kanıtı değildir. 8 Eylül 16:18 bitstream'i 17:43 UART düzeltmesini içermez; son kayıtlı demo sağlamlık testinde 9 PASS, 1 FAIL, 1 SKIP vardır. Bu sınırlamalar FPGA README'sinde açıklanır.
