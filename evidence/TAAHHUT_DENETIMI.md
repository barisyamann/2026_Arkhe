# Taahhut Denetimi - OTR/DTR'de Soylenenler ve Fiilen Yapilanlar

20 Agustos 2026 · Takim Arkhe

Bu belge, On Tasarim Raporu ve Detayli Tasarim Raporu'nda verilen
dogrulama ve tasarim taahhutlerini tek tek ele alir ve her biri icin
**kanit dosyasi** gosterir. Amac, teslimden once kendi iddialarimizi
denetlemektir.

Denetim uc sonuc uretti:

| Sonuc | Adet |
|---|---|
| Taahhut karsilandi, kanit var | 4 |
| Taahhut karsilandi, sayilar guncel degildi -> duzeltildi | 1 |
| **Taahhut karsilanmadi -> geri cekildi** | **1** |

---

## 1. SONRADAN KARSILANDI - Spike ISS karsilastirmasi

**Taahhut** (OTR s.177, WP3): "Spike ISS cekirdek testleri"

**Fiilen ne vardi:** `tb/T2.1_core_trace/compare_trace.py` betigi
"RISC-V Cekirdek Komut Izleri referans model ile %100 uyumludur"
ciktisini uretiyordu. Denetimde ortaya cikti ki:

* **Spike ISS hicbir zaman kurulmadi ve kosturulmadi.** Betigin
  "referans model" dedigi sey kaynak kodun icine elle yazilmis
  20 elemanli sabit bir diziydi:

      reference_trace = ["0x00000004", "0x00000008", "0x0000000c", ...]

* Dizi **guncel bootloader'a da uymuyordu.** `bootloader.S` icinde
  `0x08` ve `0x0a` adreslerindeki `li` buyruklari RV32C ile 2 bayta
  sikistirilmistir; sabit dizi her buyrugu 4 bayt varsayarak `0x0a`
  adresini tamamen atliyordu.

**Ne yapildi:** `compare_trace.py` depodan kaldirildi. Yerine
`tb/T2.1_core_trace/trace_check.py` yazildi. Bu betik referansi
uydurmuyor - dogrudan `bootloader.elf` dosyasinin `objdump` ciktisindan
uretiyor ve iki sey denetliyor:

1. Yurutulen her PC, programda gercekten var olan bir buyruk adresi mi?
2. Ardisik PC cifti mesru bir gecis mi? (`pc + uzunluk` ya da
   disassembly'deki dal hedefi)

Buyruk uzunlugu kodlama alanindan okundugu icin RV32C dogru ele aliniyor.

**Denetleyicinin kendisi dogrulandi.** Uc sentetik iz verildi; biri eski
sabit dizinin ta kendisi ve reddediliyor:

    [2] 0x00000008 (li) -> 0x0000000c  beklenmeyen gecis
    [HATA] 1 tutarsizlik.

**Kapsam siniri acikca yazildi:** yeni denetim kontrol akisini dogrular,
aritmetik sonuc dogrulugunu degil. Onun icin gercek bir ISS gerekir.

### 24 Agustos 2026 - eksik KAPATILDI

Yukaridaki "onun icin gercek bir ISS gerekir" cumlesi artik gecerli degil.
Spike kuruldu (**1.1.1-dev**) ve kosturuldu:

| Olcum | Deger |
|---|---|
| Karsilastirilan buyruk | **409** (eski iddia: 20) |
| PC uyusmazligi | **0** |
| Makine kodu uyusmazligi | **0** |
| Sikistirilmis gosterim farki | 156 (beklenen) |

Karsilastirma icin cevre birimi kullanmayan ayri bir test programi yazildi
(`sw_nexys/src/core_test.c`): RV32I aritmetik/mantik, dallanmalarin her iki
sonucu, jal/jalr, bayt/yarim kelime yukleme-saklama ve RV32M carpma/bolme
kumesini uyarir. Spike bizim SoC'umuzu degil ciplak bir cekirdegi modeller;
`main.c` UART'a yazdigi anda izler platform farkindan ayrisirdi.

Regresyona **`cekirdek_izi`** testi olarak eklendi (RTL izini uretir).

**Kanit:** `evidence/dogrulama/SPIKE_ISS_KARSILASTIRMA.md`

**Onceki kanit:** `tb/T2.1_core_trace/T2.1_test_report.md` bolum 4.1

---

## 2. KARSILANDI - UVM yerine hedefli dogrulama

**Taahhut** (OTR bolum 3.9): OTR bu konuda bastan durustu -

> "Proje takvimi goz onune alinarak tam tesekkullu UVM yerine, AXI veri
> yollarinin guvenilirligini saglamak icin *Hedefli Dogrulama* (Targeted
> Verification) yaklasimi izlenecektir."

Yani **tam UVM ortami hicbir zaman vaat edilmedi.** Vaat edilenler:

| Vaat | Durum | Kanit |
|---|---|---|
| AXI arayuzlerine VIP ajanlari | Karsilandi | `rtl/Memory/axil_protocol_checker.sv`, `tb/tb_soc_top.sv:703` ile `bind` edilmis |
| SystemVerilog Assertions | Karsilandi | Ayni dosya - reset degeri, adres/veri kararliligi, yanit kararliligi |
| Islem seviyesinde denetim | Karsilandi | Kendi kendini kontrol eden testbench'ler, 6 blok testi |
| Code ve Functional Coverage | Karsilandi | Bkz. madde 3 |

**Sonuc: taahhut karsilandi.** Tam UVM ortami eksikligi bir sapma
degildir, planlanmis bir tercihtir ve OTR'de gerekcesiyle yazilmistir.

### 24 Agustos 2026 - taahhudun UZERINE cikildi

Sartname §4.2.2 AXI arayuzlerinin UVM ile dogrulanmasini beklediginden,
OTR'de vaat edilmemis olmasina ragmen gercek bir UVM ortami kuruldu:
`tb/uvm/axil_uvm_pkg.sv` - sequence_item, monitor, scoreboard, agent, env
ve test. Agent **passive**; tasarim zaten gercek trafikle suruluyor ve o
trafik self-checking testlerle dogrulaniyor.

SVA denetleyicisi KALDIRILMADI. Ikisi farkli seviyede calisir: SVA sinyal
ve cevrim duzeyinde, UVM islem duzeyinde. EK-3 de tam bunu oneriyor
("butun veri akisini paketlere bolecegi icin...").

NPU motorunun AXI4-Lite master hattinda tam sistem kosumu sonucu:

| Olcum | Deger |
|---|---|
| Paketlenen islem | **81 032** |
| Protokol ihlali | **0** |
| Monitor'un dusurdugu islem | **0** (bagimsiz capraz kontrol) |

Regresyona **`uvm_axi_agent`** testi olarak eklendi.

**Kanit:** `evidence/dogrulama/UVM_AXI_AGENT.md`

---

## 3. KARSILANDI - Kod ve islevsel kapsama

**Taahhut** (OTR bolum 3.9): "Code ve Functional Coverage metrikleri
toplanarak ... sayisal olarak raporlanacaktir."

**Denetim:** Raporda yazan sayilar XSim'in urettigi kapsama panosuyla
karsilastirildi.

| Metrik | Raporda yazan | XSim panosunda olculen | Uyum |
|---|---|---|---|
| Statement | %46,58 | 46,5879 | tam |
| Branch | %30,14 | 30,1488 | tam |
| Condition | %45,70 | 45,7067 | tam |
| Toggle | %21,50 | 21,5 | tam |

Pano ayrica 54 dosya, 55 modul, 60 ornek kapsandigini gosteriyor.

**Islevsel kapsama covergroup'lari gercekten var:**

    tb/tb_npu_compute_engine.sv:104   covergroup cg_npu_inference
    tb/tb_soc_top.sv:127              covergroup cg_soc_verification
                                      cov_gpio, cov_jtag_tms,
                                      cov_axi_aw/w/ar/r

**Kanit:** `tb/T3.1_jtag_debug/coverage_report/codeCoverageReport/dashboard.html`
(Vivado Simulator Coverage Report 2025.2)

> **Not:** Statement kapsamasinin %46,58'de kalmasi, o kosumda DMA, I2C,
> QSPI gibi bloklarin uyarilmamis olmasindandir. Bu rapor icinde zaten
> aciklanmistir. Blok bazinda kapsamalar %90-100 araligindadir.

---

## 4. DUZELTILDI - Komut seti mimarisi

**Taahhut** (OTR bolum 3.6.2): "CV32E40P ... RV32IM**F**C eklentilerini
desteklemektedir. ... Floating-Point (F) eklentisi hassasiyet isteyen
matematiksel islemlerde dogrudan ivme katar."

**Fiilen:** Cekirdek `FPU = 0` ile yapilandirilmistir. Uygulanan komut
seti **RV32IMC**'dir; donanim kayan nokta birimi yoktur.

**Gerekce olculmustur**, tahmin degildir: `evidence/fpga/fpu_karar_olcumu.md`
FPU=1 ve FPU=0 durumlarinin sentez sonuclarini karsilastirir. NPU tamamen
tamsayi aritmetigiyle calisir ve kayan nokta kullanmaz; FPU'nun kaynak
maliyeti karsiliginda bir kazanc uretmemektedir.

**Ne yapildi:** OTR ve DTR gonderilmis belgelerdir, icerikleri
degistirilemez. Ancak depodaki butun guncel belgeler duzeltildi:

    README.md                        RV32IMC olarak yazildi + gerekce baglantisi
    dtr_hazirlik_ve_yol_haritasi.md  duzeltildi
    asic/environment/versions.txt    "CV32E40P, RV32IMC (FPU = 0)"

---

## 5. DUZELTILDI - Guncel olmayan olcum degerleri

Denetimde, depodaki belgelerin eski bir tasarim surumune ait sayilari
tasidigi gorulmustur. Butun sayilar `evidence/` altindaki rapor
dosyalarindan yeniden okundu.

| Metrik | Belgede yazan (eski) | Olculen (dogru) | Kaynak |
|---|---|---|---|
| LUT | 8.114 | **18.587** | `evidence/fpga/utilization_v9.rpt` |
| Setup payi (WNS) | +1,710 ns | **+1,811 ns** | `evidence/fpga/timing_v8.rpt` |
| Toplam guc | 129 mW | **137 mW** | `evidence/fpga/power_v9.rpt` |

8.114 LUT degeri, NPU agirliklarinin henuz sahte (sabit) oldugu doneme
aitti; gercek agirliklar yuklenince tasarim buyudu.

Ayrica 5 adet gecersiz mutlak yol (`C:/Arkhe_2026`) temizlendi - o dizin
bu makinede mevcut degil, komutlar oldugu gibi calistirilamazdi.

---

## 6. KARSILANDI - SRAM makrosunun korunmasi

**Sartname s.16:** "SRAM makrosu sentez sonucunda optimize edilerek
kaldirilmamali; nihai gate level netlist, DEF ve GDSII ciktilarinda
bulunmalidir."

**Uc cikti dosyasinda ayri ayri sayildi:**

| Cikti | Dosya | Makro |
|---|---|---|
| Sentez netlisti | `results/netlist/soc_top.nl.v` | **23** |
| Yerlesim sonrasi netlist | `results/netlist/soc_top.pnl.v` | **23** |
| DEF | `results/def/soc_top.def` | **23** |
| GDSII | akis devam ediyor | bekleniyor |

DEF'te makrolarin hepsi `+ FIXED` olarak, config.yaml'da verdigimiz
koordinatlarda duruyor:

    - u_data_ram.g_sram[0].u_macro sky130_sram_... + FIXED ( 2899300 2716160 ) N ;
    - u_data_ram.g_sram[1].u_macro sky130_sram_... + FIXED (  250000 3332700 ) N ;
    - u_data_ram.g_sram[2].u_macro sky130_sram_... + FIXED ( 1133100 3332700 ) N ;

DEF birimi nanometredir; 250000 = 250 um, 1133100 = 1133,1 um. Ikisi
arasindaki fark 883,1 um - bu tam olarak makro genisligi (683,1) arti
kanal genisligidir (200). Yerlesim tasarlandigi gibi.

**Sentez optimizasyonu makrolari kaldirmadi.** Sartname sartinin netlist
ve DEF ayaklari karsilandi; GDSII ayagi akis tamamlaninca eklenecek.

---

## 7. Denetimden cikan yan bulgular

Taahhut denetimi sirasinda ortaya cikan, taahhutle dogrudan ilgili
olmayan ama kayda gecmesi gereken iki nokta:

**Saat kapisi:** `cv32e40p_sim_clock_gate.sv` kendi basliginda "ASIC
sentezinde kullanilmamali" yaziyor ve ASIC filelist'inde bulunuyor.
Netlist denetlendi: `SYNTHESIS` dali alinmis, saat dogrudan geciyor,
**latch uretilmemis** (0 adet). 10.855 flip-flop dogrudan `clk_i`'ye
bagli. Islevsel hata yok, guc tasarrufu kaybi var.
Ayrinti: `evidence/asic/OLCUMLER.md` bolum a6.

**Lint uyarilari:** 810 uyarinin %83'u bize ait degil (447 PDK blackbox,
223 satici kodu). Bizim koddaki 140 uyarinin riskli gorunen yedisi tek
tek incelendi, hicbiri islevsel hata cikmadi.
Ayrinti: `evidence/lint/LINT_INCELEMESI.md`

---

## 8. Denetimin kendisi hakkinda

Bu belge, teslim oncesinde kendi iddialarimizi kanit dosyasina karsi
dogrulamak icin hazirlandi. Bir taahhudun karsilanmadigi tespit edildi
ve **gizlenmek yerine geri cekildi**; ilgili betik depodan kaldirildi ve
raporuna gerekcesi yazildi.

Denetlenen alti taahhudun besinde kanit dosyalari iddialari dogruladi.
Kapsama sayilari XSim panosuyla ondalik basamagina kadar tuttu.

Tekrar denetim icin:

    python tb/T2.1_core_trace/trace_check.py     # buyruk izi
    python scripts/run_regression.py             # 6 blok testi
    cd asic && make lint                         # Verilator
