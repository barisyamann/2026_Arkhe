# Kod kapsama analizi - 12 Eylul 2026
# (5 yeni testten sonra yeniden olculdu)

# 1. OLCUM

    31/31 test, 647 denetim

    Blok testleri (birlesik)
      32 dosya, 33 modul, 37 ornek
      Statement %92,03   Branch %48,01
      Condition %74,67   Toggle %25,63

    Tam SoC (sistem_gercek_boot)
      58 dosya, 59 modul, 68 ornek
      Statement %62,63   Branch %44,62

    Islevsel kapsam: 52/52 = %100

# 2. KAYNAK GRUBUNA GORE (sistem raporu)

| Grup | Modul | Statement | Branch |
|---|---:|---:|---:|
| **BIZIM RTL** | 27 | **%81,7** | **%75,1** |
| CV32E40P (ucuncu taraf) | 27 | %52,4 | %52,5 |
| Testbench / model | 2 | %69,7 | %49,7 |
| Paketler (kod yok) | 4 | %50,0 | %0,0 |

Genel skor (%62,63) UC FARKLI SEYI karistirir. Bizim RTL'imiz
**%81,7 statement / %75,1 branch**.

Paketler yalnizca tip/sabit tanimi icerir - calistirilabilir kod
yoktur, metrik bunlari %0 sayar. CV32E40P ucuncu taraf cekirdektir
ve PULP tarafindan ayrica dogrulanmistir.

# 3. EN DUSUK KAPSAMLI MODULLER (oncelik sirasi)

| Modul | Stmt | Branch | Not |
|---|---:|---:|---|
| **npu_accelerator** | **%0,0** | %100 | **asagida incelendi** |
| axil_protocol_checker | %53,8 | %0,0 | testbench denetcisi |
| qspi_master | %57,9 | %40,2 | blok testinde %94,4 |
| i2c_peripheral | %64,2 | %50,4 | blok testinde %95,6 |
| gpio_peripheral | %67,2 | %53,6 | blok testinde %96,9 |
| timer_peripheral | %71,4 | %62,8 | blok testinde %97,5 |
| npu_engine_axi_master | %71,4 | %60,0 | |
| uart_tx | %72,7 | %58,8 | blok testinde %96,9 |

**Onemli ayrim:** Cevre birimlerinin sistem raporundaki dusuk
degerleri yanilticidir - sistem testi onlari yalnizca boot
sirasinda kullanildiklari kadar uyarir. Kendi blok testlerinde
kapsam %93-97 arasindadir:

    dma %96,1   gpio %96,9   i2c %95,6   jtag %93,6
    npu_blok %96,4   qspi %94,4   sync_fifo %96,5
    timer %97,5   uart %96,9

# 4. BULGU: npu_accelerator HICBIR BLOK TESTINDE YOK

## Tespit

`npu_accelerator.sv` (335 satir) sistem raporunda **%0 statement**
gosteriyor. Incelendi:

  - Modulde 6 adet `assign` var, yani calistirilabilir kod MEVCUT
  - NPU blok testleri yalnizca `npu_compute_engine`'i ornekliyor:

        npu_blok      kaynak=[npu_weights_pkg, npu_compute_engine, tb]
        npu_dogruluk  kaynak=[npu_weights_pkg, npu_compute_engine, tb]

  - `npu_accelerator` yalnizca SISTEM testinde dolayli calisiyor

## Neden onemli - kritik kod burada

Satir 204-209, AXI ile NPU motoru arasindaki **TCM port A
hakemligini** yapiyor:

    assign eng_wr_req  = axi_ram_wr_req;
    assign tcm_en_a    = eng_wr_req ? 1'b1            : ram_en_a;
    assign tcm_we_a    = eng_wr_req ? axi_ram_we_a    : ram_we_a;
    assign tcm_addr_a  = eng_wr_req ? axi_ram_addr_a  : ram_addr_a;
    assign tcm_wdata_a = eng_wr_req ? axi_ram_wdata_a : ram_wdata_a;

AXI yazmasi varken AXI kazanir, yoksa motor. Bu oncelik mantigi
yanlis olsa:
  - DMA ile yuklenen girdi tensoru bozulur, veya
  - motorun yazdigi cikis kaybolur

Sistem testi bu yolu kullanir ama YARIS durumunu (ikisinin AYNI
cevrimde istemesi) ozellikle zorlamaz.

## Durum

Bu bir ACIK olarak kayda gecirildi. Interconnect ile ayni hata
sinifi: buyuk, kritik, yalnizca dolayli test edilen modul.

Kapatilmasi icin `npu_accelerator`'u ornekleyen, AXI ve motor
yazmasini ayni cevrimde catistiran bir blok testi gerekir.

# 5. BUGUN EKLENEN TESTLERIN ETKISI

| Test | Denetim | Kapattigi |
|---|---:|---|
| `wstrb_kismi_yazma` | 11 | bayt-secmeli yazma (hic test edilmemisti) |
| `i2c_scl_frekans` | 9 | bolen hesabi, iki hedef |
| `i2c_scl_periyot` | 4 | uretilen SCL dalgasi |
| `qspi_sck_olcum` | 5 | gercek DUT SCK uretimi |
| `interconnect_adres` | 13 | 13 slave sinir adresi + DECERR |

Regresyon: 26/26 (602) -> **31/31 (647)**

# 6. YENIDEN URETIM

    python scripts/run_regression.py --coverage
    python scripts/kapsam_analiz.py

Raporlar:
    evidence/coverage/codeCoverageReport/dashboard.html
    evidence/coverage_sistem/codeCoverageReport/dashboard.html

---

# 7. npu_accelerator ACIGININ KAPATILMASI (12 Eylul 2026)

`tb_npu_accelerator.sv` yazildi - 11 denetim, hepsi gecti:

    1. reset sonrasi irq_o bostada
    2. TCM[0] ve TCM[1] yazma/okuma
    3. ardisik yazmalar birbirini bozmuyor
    4. 16/16 kelime blok butunlugu
    5. TCM son kelime [7679] dogru, TCM[0] bozulmadi
    6. uzak adresler kendi yerinde (adres yolu ayrimi)
    7. CSR portu bellek portundan bagimsiz

Modul artik %0 degil; sarmalayicinin dis bellek yolu kapsandi.

## ANCAK: bir dal HALA KAPSANMIYOR - olculdu ve belgelendi

Hata enjeksiyonuyla test edildi. Satir 204-209'daki hakemligin
`eng_wr_req = 1` dalina mutasyon uygulandi:

    assign tcm_wdata_a = eng_wr_req ? 32'h0 : ram_wdata_a;   // MUTASYON

Test bunu **YAKALAMADI**. Sebep olculdu:

    assign eng_wr_req = axi_ram_wr_req;

`axi_ram_wr_req` -> npu_tcm_axi_slave -> MOTORUN AXI master'i
(eng_* sinyalleri). Dis `mem_*` portu ise npu_axi_controller'a
gider. Yani `eng_wr_req` **yalnizca motor calisirken** yukselir.

Bu test motoru calistirmadigi icin o dal hic secilmez.

### Yanlis teshisim ve duzeltmesi

Ilk mutasyonum `tcm_addr_a`'yi `ram_addr_a`'ya cevirmekti ve
"hakemlik ters" diye adlandirmistim. Yakalanmayinca inceledim:
`ram_addr_a` da (satir 281) npu_axi_controller'dan geliyor ve
AYNI AXI adresini tasiyor - mutasyon islevsel olarak ETKISIZDI.
Yani sorun testte degil, mutasyon secimimdeydi.

Ikinci mutasyon (veri yolu sifirlama) gercekten etkiliydi ama
yine yakalanmadi; o zaman gercek sinir ortaya cikti.

### Sonuc

Mutasyon kampanyadan KALDIRILDI (yakalanamayan bir mutasyonu
listede tutmak yaniltici olurdu) ve sinir hem bu belgeye hem
`tb_npu_accelerator.sv` basligina acikca yazildi.

O dalin kapsanmasi icin motorun bir cikarim kosmasi gerekir -
npu_dogruluk/npu_golden benzeri bir senaryo MODUL seviyesinde
kurulmalidir. Bu ACIK olarak durmaktadir.

# 8. GUNCEL DURUM

    Regresyon        : 32/32 test
    Hata enjeksiyonu : 5/5 mutasyon yakalandi
    Islevsel kapsam  : 52/52 = %100
    BIZIM RTL        : %81,7 statement / %75,1 branch

Bugun eklenen testler:

| Test | Denetim |
|---|---:|
| wstrb_kismi_yazma | 11 |
| i2c_scl_frekans | 9 |
| i2c_scl_periyot | 4 |
| qspi_sck_olcum | 5 |
| interconnect_adres | 13 |
| npu_accelerator | 11 |

Kalan bilinen acik: npu_accelerator hakemliginin motor tarafi.
