# Doğrulama ve Testler

Şartname EK-3'ün istediği doğrulama çıktıları ve bunların ötesine
geçen ek çalışmalar.

---

## 1. `raporlar/`

| Dosya | İçerik |
|---|---|
| `DOGRULAMA_VE_TEST_PLANI.md` | **Doğrulama planı** — hedefler, tamamlanma ölçütleri, seviyeler, EK-3 karşılığı |
| `regresyon_sonuc.txt` | Tam regresyon çıktısı — 36 test, test başına denetim sayısı ve süre |
| `hata_enjeksiyonu_sonuc.txt` | 7 mutasyonun tamamının yakalandığının kanıtı |

### Hata enjeksiyonu nedir, neden önemli

Regresyonda tüm testlerin geçmesi tek başına "testler iyi" demek
DEĞİLDİR — hiçbir şey denetlemeyen bir test de geçer.

`betikler/hata_enjeksiyon.py` RTL'e **kasıtlı hata** sokar ve ilgili
testin kırmızıya döndüğünü gösterir. Dönmüyorsa o test dekoratiftir.

Bu kampanya 12 Eylül 2026'da **iki dekoratif test buldu**:
  - QSPI testi DUT'u hiç örneklemiyordu (kendi formülünü doğruluyordu)
  - I2C testi SCL frekansını hiç ölçmüyordu

İkisi için de gerçek ölçüm yapan testler yazıldı.

Kampanya 12 Eylül'de **üçüncü bir dekoratif test** daha yakaladı:
yeni yazılan I2C saat germe testi `scl` telini ölçüyordu, ama o teli
5 µs boyunca testbench'in kendisi çekiyordu — germe tamamen kapalıyken
bile geçiyordu. DUT'un iç sayacını izleyecek şekilde düzeltildi.

Şu an **9/9 mutasyon** yakalanıyor ve kampanya sonrası 57/57 RTL
dosyası birebir korunuyor.

---

## 2. `testler/` — 36 testbench

    Şartname testleri     sartname_timer, sartname_gpio, sartname_uart,
                          sartname_uart_stream, sartname_qspi
    Blok testleri         uart, i2c, gpio, qspi, timer, dma, sync_fifo,
                          jtag_debug, npu_blok, npu_golden, npu_dogruluk,
                          npu_accelerator, interconnect_adres
    Hata testleri         sram_w_yakalama, axi_w_yakalama,
                          qspi_presc_sinir, qspi_sck_olcum,
                          wstrb_kismi_yazma, sinir_degerleri
    Frekans testleri      i2c_scl_frekans, i2c_scl_periyot
    CDC testi             jtag_cdc
    Yanıt kodu            jtag_yanit_kodu
    Saat germe            i2c_saat_germe
    Protokol              axi_protokol, uvm/ (iki agent)
    Sistem                sistem, sistem_gercek_boot, npu_hizlanma,
                          cekirdek_izi, uvm_axi_agent

### UVM agent yapısı (`testler/uvm/`)

**İki pasif agent:**

| Agent | Bağlantı | Kapsam |
|---|---|---|
| `agent` | NPU motoru iç AXI arayüzü | TCM bölgeleri %75 |
| `soc_agent` | SoC ana yolu (`merged_m_*`) | **13 SoC bölgesi %100** |

Toplam 401.729 işlem izlendi, 37 denetim.

**Denetlenen protokol kuralları (ARM IHI0022):**
  - VALID kararlılığı (AR/AW/W/R/B) — A3.2.1
  - El sıkışmada X/Z (adres, veri, yanıt)
  - **Reset'te VALID yüksek olmamalı** — A3.1.2
  - **EXOKAY (2'b01) yasağı** — A3.4.4
  - Yanıt kodu geçerliliği, adres hizalaması, WSTRB=0 kontrolü

**Fonksiyonel kapsam:** işlem türü, adres bölgesi, WSTRB deseni,
yanıt kodu + çaprazlar. `illegal_bins exokay` ile yasak yanıt
simülatör seviyesinde de yakalanır.

---

## 3. `betikler/`

| Betik | İşlev |
|---|---|
| `run_regression.py` | Tüm testleri koşar, denetim sayar, kapsam toplar |
| `hata_enjeksiyon.py` | Mutasyon kampanyası — testlerin hata yakaladığını kanıtlar |
| `spike_iz_al.py` | Spike ISS izini alır (PC + makine kodu + **yazmaç değeri**) |
| `spike_karsilastir.py` | Spike ile RTL izini karşılaştırır |
| `kapsam_analiz.py` | Kod kapsamını kaynak grubuna göre ayırır |
| `rtl_manifest.py` | 57 RTL dosyasının SHA-256 manifesti |

---

## 4. `kapsam/`

    kod_kapsami_blok/     blok testlerinin birleşik kapsamı
    kod_kapsami_sistem/   tam SoC (sistem_gercek_boot) kapsamı
    islevsel_kapsam/      52/52 covergroup raporu

**Önemli ayrım:** Sistem raporundaki genel skor (%62,63) üç farklı
şeyi karıştırır. Gruplara ayrıldığında:

| Grup | Statement | Branch |
|---|---:|---:|
| **Bizim RTL** | **%81,6** | **%74,9** |
| CV32E40P (üçüncü taraf) | %52,4 | %52,5 |
| Paketler (çalıştırılabilir kod yok) | %50,0 | %0,0 |

Çevre birimlerinin kendi blok testlerinde kapsamı %93–97 arasındadır.

---

## 5. `spike_iss/` — Çekirdek doğrulaması

| Dosya | İçerik |
|---|---|
| `spike_iz.txt` | Spike ISS izi — PC, makine kodu, yazmaç değeri |
| `rtl_iz.log` | CV32E40P tracer çıktısı |
| `karsilastirma_sonuc.txt` | Karşılaştırma sonucu |

**Sonuç:**

    karsilastirilan buyruk  : 927
    PC uyusmazligi          : 0
    makine kodu uyusmazligi : 0
    yazmac karsilastirilan  : 765
    yazmac DEGER uyusmazligi: 0

Şartname EK-3 "tür ve sıra" eşliğini istiyor. Bu karşılaştırma
12 Eylül 2026'da **yazmaç düzeyine** çıkarıldı: her buyruğun yazdığı
yazmaç numarası ve değeri de doğrulanıyor. Yani sadece doğru
buyrukların doğru sırayla koştuğu değil, **sonuçların doğru
hesaplandığı** da kanıtlanıyor.

Üç platform kimlik CSR'ı (`mvendorid`, `marchid`, `misa`) ayrı
sayılır ve raporda listelenir — bunlar çekirdek kimliğidir,
hesaplama hatası değil.

---

## 6. `kanitlar/` — 25 ölçüm belgesi

Öne çıkanlar:

| Belge | Konu |
|---|---|
| `HATA_ENJEKSIYONU.md` | İki dekoratif testin bulunması ve düzeltilmesi |
| `UVM_KAPSAM_GENISLETMESI.md` | Protokol denetimleri ve fonksiyonel kapsam eklenmesi |
| `UVM_KAPSAM_ARASTIRMASI.md` | İkinci agent, yanıltıcı %8,3 kapsamın düzeltilmesi |
| `SPIKE_YAZMAC_DUZEYI.md` | Spike karşılaştırmasının yazmaç düzeyine çıkarılması |
| `KAPSAM_ANALIZI_20260912.md` | Kapsam ölçümü ve `npu_accelerator` açığı |
| `RDATA_X_BULGUSU.md` | Okuma verisinde X — kök neden ve değerlendirme |
| `GATE_LEVEL_SIM.md` | Gate-level simülasyon denemesi ve sınırları |
| `MAGIC_DRC_KOK_NEDEN.md` | 7.658 DRC ihlalinin makro kaynaklı olduğunun kanıtı |
| `SRAM_KOSE_MODELI_OLCUMU.md` | Tek köşe SRAM modelinin marja etkisi (%10) |
| `LIBERTY_EK_ANALIZ.md` | DDK kararı ve Liberty sınırları analizi |
| `S_SAAT_KOSU.md` | Teslim edilen koşunun gerekçesi ve imza düzeltmesi |

---

## Yeniden üretim

    # Tüm testler
    python scripts/run_regression.py

    # Kapsam ile
    python scripts/run_regression.py --coverage
    python scripts/kapsam_analiz.py

    # Testlerin hata yakaladığını kanıtla
    python scripts/hata_enjeksiyon.py
    python scripts/rtl_manifest.py dogrula rtl_manifest.txt

    # Spike ISS (Spike kurulu makinede)
    python scripts/spike_iz_al.py <elf> --cikti build/spike/spike_iz.txt
    python scripts/spike_karsilastir.py
