# Kod Kapsama (Code Coverage) Raporu

Tarih : 22 Agustos 2026
Arac  : Vivado Simulator 2025.2 (`xelab --cc_type sbct` + `xcrg`)
Uretim: `python scripts/run_regression.py --coverage`

## Neden

Sartname **EK-3**, Code Coverage'i **Opsiyonel\*\*\*** olarak isaretler ve
dipnotu su:

> "\*\*\*Opsiyonel: Dogrulama aktivitelerinden **tam puan alimini**
> saglayacak unsurlar."

Yani puanlanan bir kalemdir. Onceden yalnizca **tek bir modulun**
(JTAG, `tb/T3.1_jtag_debug/coverage_report/`) kapsama raporu vardi ve
elle uretilmisti; sistem geneli olculmemisti.

---

## Sonuclar

Butun regresyon (13 test, 293 denetim) kapsama toplayarak kosuldu.

### Blok testlerinin birlesigi

`evidence/coverage/codeCoverageReport/dashboard.html`

| Metrik | Ilk olcum | **Testler eklendikten sonra** |
|---|---|---|
| Statement | %77,50 | **%87,11** |
| Branch | %40,35 | %43,01 |
| Condition | %64,20 | **%74,35** |
| Toggle | %22,19 | %26,68 |

22 dosya, 22 modul, 28 ornek.

#### Modul bazinda (blok raporu)

| Modul | Statement | Branch | Condition |
|---|---|---|---|
| `dma_controller` | **%97,9** | **%89,7** | %100 |
| `timer_peripheral` | %97,1 | %50,0 | %100 |
| `npu_compute_engine` | %96,6 | %45,3 | %88,6 |
| `i2c_peripheral` | %93,5 | %33,6 | %88,9 |
| `qspi_master` | %80,9 | %45,2 | %75,4 |
| `gpio_peripheral` | %77,8 | %7,4 | %100 |
| `jtag_debug` | **%75,2** | %39,6 | %75,7 |
| `uart_peripheral` | %48,7 (bkz. asagi) | %40,0 | %50,0 |

### DIKKAT - PARAMETRELI MODULLERDE BIRLESIK RAPOR YANILTIR

`uart_peripheral` yukarida %48,7 gorunuyor ama **bu blok testinin sayisi
DEGILDIR.** xcrg birlestirme gunlugu:

    CCI-MERGE2 : Cannot merge module uart_peripheral(DEFAULT_BAUD=1000000)
                 from DB .../covdb/xsim.codeCov/uart/xsim.CCInfo
    CCI-MERGE12 : Cannot merge File uart_peripheral.sv ... into Merged DB

Blok testi modulu **parametre override ile** ornekliyor
(`DEFAULT_BAUD = 1000000`), sistem testi ise varsayilanla. xcrg ikisini
birlestiremiyor ve **blok testinin verisini atiyor**; raporda kalan sayi
sistem testinin gorunumu.

Tek basina uretilen rapor gercek degeri veriyor:

    xcrg -cov_db_dir build/regression/covdb -cov_db_name uart          -report_dir build/uart_cov -report_format html

| Modul | Statement | Branch | Condition |
|---|---|---|---|
| `uart_peripheral(DEFAULT_BAUD=1000000)` | **%100,0** | **%92,1** | %83,3 |
| `uart_rx` | %91,5 | %80,0 | %93,8 |
| `uart_tx` | %72,7 | %58,8 | %71,4 |

**Genel kural:** parametreli bir modulun gercek blok kapsamasi icin o
testin veritabanindan AYRI rapor uretilmelidir. Birlesik rapor yalnizca
parametresiz modullerde dogrudan okunabilir.

Artis, 22 Agustos'ta eklenen testlerden geliyor:

| Test | Denetim | Durum |
|---|---|---|
| `dma` | 39 | **yeni** - modulun hic testi yoktu (%41,1 -> %97,9) |
| `timer` | 36 | **yeni** - modulun hic testi yoktu |
| `gpio` | 31 | **yeni** - modulun hic testi yoktu |
| `qspi` | 6 -> 16 | yazma/silme/durum komutlari (%58,4 -> %80,9) |
| `jtag_debug` | 14 -> 20 | TAP seri protokolu (%54,9 -> %75,2) |
| `uart` | 21 -> 26 | AXI hata dallari, RO denetimi (%100 blok raporunda) |
| `i2c` | 7 -> 14 | NBY kirpma, adres maskeleme, RO denetimi |

`dma` testinin bellek modeli AW ve W'yi **kasitli olarak farkli
cevrimlerde** kabul eder. V1 duzeltmesi gecici geri alinip kosuldugunda
test **20 hatayla duser** ve AW islem sayisi 8 yerine 1 cikar - yani
test gercekten ayirt edicidir.

`qspi_master` testleri **iki gercek RTL hatasi** ortaya cikardi;
bkz. `evidence/qspi_yazma_hatalari.md`.

### Tam SoC

`evidence/coverage_sistem/codeCoverageReport/dashboard.html`

| Metrik | Skor |
|---|---|
| Statement | **%61,81** |
| Branch | %44,14 |
| Condition | %54,09 |
| Toggle | %30,24 |

56 dosya, 57 modul, 65 ornek - CV32E40P cekirdegi dahil.

**Bu sayi CV32E40P tarafindan asagi cekiliyor.** Ayristirildiginda:

| | Statement | Branch | Condition | Toggle |
|---|---|---|---|---|
| Bizim modullerimiz (30) | **%79,1** | **%65,7** | %69,9 | %25,1 |
| CV32E40P (27) | %52,3 | %52,4 | %63,7 | %35,3 |

CV32E40P'de kosulmayan kod agirlikli olarak kullanilmayan ozelliklerdir:
FPU yolu (`FPU = 0`), PULP eklentileri (`COREV_PULP = 0`), donanim
dongusu. Bunlari kapsamak ne mumkun ne anlamlidir.

**NOT:** Tam SoC sayisi ilk olcume gore hafifce dustu (%62,24 -> %61,81).
Sebep kapsama kaybi degil, `qspi_master`'a eklenen yeni kod: hata
duzeltmesi uc dalli bir `unique case` getirdi ve boot yolu yalnizca
birini kullaniyor. Payda buyudu.

Kaynak kosum: `sistem_gercek_boot` (gercek iki asamali boot zinciri).

---

## NEDEN IKI AYRI RAPOR

Ilk denemede tum veritabanlari tek raporda birlestirilmeye calisildi.
**Sonuc yaniltici cikti:** rapor yalnizca 20 dosya gosteriyordu ve
`soc_top`, `axi_lite_interconnect`, arbiter'lar, `boot_rom` gibi sistem
seviyesi moduller RAPORDA HIC GORUNMUYORDU.

Sebep `xcrg.log` icinde acikca yaziyor:

    CCI-MERGE10 : Cannot merge module npu_compute_engine ...
                  as toggle coverage info are different
    CCI-MERGE2  : Cannot merge module i2c_peripheral(SYS_CLK_FREQ=50000000) ...

xcrg, ayni modulun **farkli parametrelerle elaborate edilmis**
surumlerini birlestiremiyor. Blok testleri modulleri kendi test
kosullarinda, sistem testi ise SoC icindeki gercek parametrelerle
elaborate ediyor. Zorla birlestirmek buyuk veritabanlarinin (sistem
kosumlari, her biri 612 kB) sessizce DUSMESINE yol aciyordu.

Bu yuzden iki rapor ayri uretiliyor. Ikisi de gecerli; birlesik tek bir
sayi bu araç zincirinde **elde edilemiyor**.

---

## Sayilarin yorumu

**Statement %62-78 makul.** Kosulmayan kod agirlikli olarak CV32E40P'nin
kullanilmayan ozellikleridir: FPU yolu (`FPU = 0`), PULP eklentileri
(`COREV_PULP = 0`), donanim dongusu, bazi istisna yollari.

**Branch %40-44 dusuk.** Beklenen: cevre birimlerinin hata dallari
(FIFO tasmasi, gecersiz komut, zaman asimi) kasitli olarak
uyarilmiyor. Bunlari uyaran negatif testler yazilirsa yukselir.

**Toggle %22-30 dusuk ve bu YANILTICIDIR.** Toggle kapsamasi her
sinyalin hem 0->1 hem 1->0 gecisini ister. Tasarimda:
- 32 bitlik adres/veri yollarinin ust bitleri hicbir zaman degismez
  (adres haritasi 0x0000_0000 - 0x4008_0FFF araligindadir),
- `fc_weights` gibi sabit tablolar hic toggle etmez,
- kullanilmayan CV32E40P portlari sabit baglidir.

Bu metrigi yukseltmek icin tasarimi degistirmek anlamsizdir; dusuk
olmasi bir kusur degil, adres uzayinin seyrek kullanilmasinin
sonucudur.

---

## Yeniden uretme

    python scripts/run_regression.py --coverage

Betik her testin veritabanini `build/regression/covdb/` altina ayri
isimle yazar, sonra iki raporu uretir. Kapsamasiz normal kosum:

    python scripts/run_regression.py

---

## Fonksiyonel kapsama

**Yoktur.** Tasarimda `covergroup` tanimlanmamistir; `xcrg` bunu
raporda acikca belirtir:

    ERROR : No Functional Coverage Databases have been found

Sartname EK-3 Functional Coverage'i da Opsiyonel\*\*\* sayar. Mevcut
dogrulama, kapsama noktalari yerine **yonlendirilmis self-checking
testler** ve **SVA protokol denetleyicileri** (dort AXI arayuzu)
uzerine kuruludur.
