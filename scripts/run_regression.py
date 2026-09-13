#!/usr/bin/env python3
"""
Arkhe SoC - Tam regresyon kosumu

Sartname s.297: "Gerceklestirilen dogrulama calismalarinda, 'regression' ve
'coverage' sonuclarinin raporlanmasi degerlendirme puanini yukseltecektir."

Sartname s.615: Testler manuel inceleme gerektirmeden kendi kendini kontrol
etmelidir. Buradaki tum testler hata durumunda $fatal ile biter; bu betik
de sifir olmayan cikis koduyla doner.

Kullanim:
    python scripts/run_regression.py
    python scripts/run_regression.py --vivado "C:/AMDDesignTools/2025.2/Vivado/bin"

Cikis kodu: 0 = hepsi gecti, 1 = en az bir test basarisiz
"""

import argparse
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
WORK = ROOT / "build" / "regression"
RTL  = ROOT / "rtl"
TB   = ROOT / "tb"

VARSAYILAN_VIVADO = r"C:/AMDDesignTools/2025.2/Vivado/bin"

CEV = RTL / "Cevre_Birimleri"
F1  = CEV / "files_1"
MEM = RTL / "Memory"
NPU = RTL / "npu"

# -----------------------------------------------------------------------------
# Test tanimlari
#
# Her test: ad, ust modul, kaynak dosyalar, gereken .mem dosyalari
# -----------------------------------------------------------------------------
TESTLER = [
    # -------------------------------------------------------------------------
    # SARTNAME UYUM TESTLERI  (9 Eylul 2026)
    #
    # Diger blok testleri "tasarim dogru calisiyor mu" sorusunu sorar.
    # Bunlar farkli bir soru sorar: "SARTNAMEDE YAZAN CUMLE ne diyorsa
    # TAM OLARAK o mu oluyor?"
    #
    # Her denetim sartnamenin ilgili cumlesini yorum olarak tasir ve o
    # cumlenin dogrudan karsiligini olcer. Juri "su maddeyi sagliyor
    # musunuz" diye sordugunda cevap tek bir test ciktisidir.
    #
    # QSPI testi ozellikle onemlidir: sartname 4-bayt adresleme ister ama
    # secim mekanizmasi tanimlamaz. Test, CCR[24]=1 iken kontrolcunun
    # GERCEKTEN dort bayt adres bastigini SCK kenarlarini sayarak kanitlar
    # (3 bayt -> 40 kenar, 4 bayt -> 48 kenar).
    # -------------------------------------------------------------------------
    dict(
        ad="sartname_timer",
        top="tb_sartname_timer",
        kaynak=[CEV/"timer_peripheral.sv",
                TB/"sartname"/"tb_sartname_timer.sv"],
        mem=[],
    ),
    dict(
        ad="sartname_gpio",
        top="tb_sartname_gpio",
        kaynak=[CEV/"gpio_peripheral.sv",
                TB/"sartname"/"tb_sartname_gpio.sv"],
        mem=[],
    ),
    dict(
        ad="sartname_uart",
        top="tb_sartname_uart",
        kaynak=[F1/"uart_pkg.sv", F1/"uart_tx.sv", F1/"uart_rx.sv",
                F1/"uart_peripheral.sv",
                TB/"sartname"/"tb_sartname_uart.sv"],
        mem=[],
    ),
    dict(
        ad="sartname_uart_stream",
        top="tb_sartname_uart_stream",
        kaynak=[F1/"uart_pkg.sv", F1/"uart_tx.sv", F1/"uart_rx.sv",
                F1/"sync_fifo.sv", F1/"uart_stream_peripheral.sv",
                TB/"sartname"/"tb_sartname_uart_stream.sv"],
        mem=[],
    ),
    dict(
        ad="sartname_qspi",
        top="tb_sartname_qspi",
        kaynak=[CEV/"qspi_master.sv",
                TB/"sartname"/"tb_sartname_qspi.sv"],
        mem=[],
    ),

    # -------------------------------------------------------------------------
    # SINIR DURUM TESTLERI  (10 Eylul 2026)
    #
    # Dis bir denetim iki islevsel hata buldu; ikisi de mevcut 21 testin ve
    # %100 islevsel kapsamanin DISINDA kalmisti. Kapsama, TANIMLANAN
    # noktalarin kapsandigini gosterir; tum RTL durumlarinin dogrulandigini
    # GOSTERMEZ. Bu iki test o boslugu kapatir.
    # -------------------------------------------------------------------------
    dict(
        # sram_module, W el sikismasinda WDATA/WSTRB kaydetmiyordu; fiziksel
        # yazma canli sinyalleri ornekliyordu. AW gec gelirse master veriyi
        # degistirmekte AXI'ye gore serbest oldugundan YANLIS veri yaziliyordu.
        # Duzeltme geri alindiginda testin basarisiz oldugu dogrulandi.
        ad="sram_w_yakalama",
        top="tb_sram_w_yakalama",
        kaynak=[MEM/"sram_module.sv",
                TB/"tb_sram_w_yakalama.sv"],
        mem=[],
    ),
    # -------------------------------------------------------------------------
    # SRAM AXI-LITE TAM ISLEM TESTI
    #
    # 13 Eylul 2026'da regresyona EKLENDI. Testbench daha onceden
    # yazilmisti (tb/tb_sram_registered.sv) ama regresyonda kayitli
    # DEGILDI - yani her kosumda atlaniyordu.
    #
    # sram_module teslim edilen tasarimin parcasidir: asic/filelist.f
    # satir 23'te kayitli, soc_top ve npu_tcm_sram tarafindan
    # kullanilir. Dolayisiyla testinin kosmasi gerekir.
    #
    # Test AXI-Lite protokol kurallarini dogrular:
    #   - kayitli (registered) okuma yolu
    #   - istek/yanit eslesmesi (outstanding == 1 disinda yanit FATAL)
    #   - bayt-secmeli yazma (wstrb) ve altin model karsilastirmasi
    # -------------------------------------------------------------------------
    dict(
        ad="sram_registered",
        top="tb_sram_registered",
        kaynak=[MEM/"sram_module.sv",
                TB/"tb_sram_registered.sv"],
        mem=[],
    ),
    # -------------------------------------------------------------------------
    # WSTRB KISMI YAZMA TESTI
    #
    # 12 Eylul 2026'da eklendi. UVM kapsam genisletmesi su acigi gosterdi:
    #   "[OK] yazmalar tek genislikte (tam=16 bayt=0 yarim=0)"
    # 162.064 islemlik sistem regresyonunda TEK BIR kismi yazma yoktu;
    # sram_module.sv:319-322'deki bayt-secmeli yazma mantigi HIC
    # dogrulanmamisti. Strb biti yanlis dilime bagli olsaydi mevcut
    # testlerin hicbiri yakalamazdi. Bu test o boslugu kapatir.
    # -------------------------------------------------------------------------
    dict(
        ad="wstrb_kismi_yazma",
        top="tb_wstrb_kismi_yazma",
        kaynak=[MEM/"sram_module.sv",
                TB/"tb_wstrb_kismi_yazma.sv"],
        mem=[],
    ),
    dict(
        # qspi_master tam periyodu (prescaler+1) alti bitte hesapliyordu;
        # presc=63 icin 64 sifira sariyor ve SCK kenari hic uretilmiyordu.
        # Aritmetik yedi bite cikarildi.
        ad="qspi_presc_sinir",
        top="tb_qspi_presc_sinir",
        kaynak=[TB/"tb_qspi_presc_sinir.sv"],
        mem=[],
    ),
    # -------------------------------------------------------------------------
    # QSPI SCK OLCUMU - GERCEK DUT
    #
    # 12 Eylul 2026'da eklendi. Hata enjeksiyonu (scripts/hata_enjeksiyon.py)
    # sunu gosterdi:
    #   MUTASYON qspi_presc_bit (7 bit -> 6 bit)  -> test KACIRDI
    # Cunku tb_qspi_presc_sinir DUT'u HIC ornekleMIYOR; kendi formulunu
    # dogruluyor (tautoloji). Bu test gercek qspi_master'i ornekler ve
    # URETILEN SCK KENARLARINI SAYAR.
    # -------------------------------------------------------------------------
    dict(
        ad="qspi_sck_olcum",
        top="tb_qspi_sck_olcum",
        kaynak=[CEV/"qspi_master.sv",
                TB/"tb_qspi_sck_olcum.sv"],
        mem=[],
    ),
    dict(
        # Ayni W-yakalama hatasi uart_peripheral ve
        # uart_stream_peripheral'da da vardi (tarama ile bulundu,
        # sonda ile olculdu: 0xAB yerine 0xFFFFFFFF yaziliyordu).
        # Bu test duzeltmenin geri gelmedigini garanti eder.
        ad="axi_w_yakalama",
        top="tb_axi_w_yakalama",
        kaynak=[F1/"uart_pkg.sv", F1/"uart_tx.sv", F1/"uart_rx.sv",
                F1/"sync_fifo.sv", F1/"uart_peripheral.sv",
                F1/"uart_stream_peripheral.sv",
                TB/"tb_axi_w_yakalama.sv"],
        mem=[],
    ),
    dict(
        # AXI4-Lite'in SERBEST biraktigi ama testlerimizin hic
        # denemedigi davranislar: B/R kanali geri basinci. Mevcut
        # testler BREADY/RREADY'yi hep yuksek tutuyordu.
        ad="axi_protokol",
        top="tb_axi_protokol",
        kaynak=[MEM/"sram_module.sv",
                TB/"tb_axi_protokol.sv"],
        mem=[],
    ),
    # -------------------------------------------------------------------------
    # INTERCONNECT ADRES COZME TESTI
    #
    # 12 Eylul 2026'da eklendi. axi_lite_interconnect.sv 616 satirla EN
    # BUYUK test edilmemis moduldu; yalnizca sistem testi icinde DOLAYLI
    # calisiyordu. Sistem testi yalnizca FIILEN KULLANILAN adresleri
    # dokunur - bir slave'in sinir adresi yanlis cozulse fark edilmezdi.
    #
    # Bu test 13 slave'in ALT ve UST sinirlarini, bolge bosluklarini
    # (DECERR) ve yazma/okuma yollarinin AYNI cozumu yaptigini dogrular.
    # Her sahte slave KIMLIGINI dondurur; yanlis cozme yanlis kimlik verir.
    # -------------------------------------------------------------------------
    dict(
        ad="interconnect_adres",
        top="tb_interconnect_adres",
        kaynak=[MEM/"axi_lite_interconnect.sv",
                TB/"tb_interconnect_adres.sv"],
        mem=[],
    ),
    dict(
        # Dar alanlarda yapilan aritmetigin sinir degerlerde tasip
        # tasmadigini tarar (QSPI presc=63 hatasinin sinifi).
        ad="sinir_degerleri",
        top="tb_sinir_degerleri",
        kaynak=[TB/"tb_sinir_degerleri.sv"],
        mem=[],
    ),

    dict(
        ad="uart",
        top="uart_tb",
        kaynak=[F1/"uart_pkg.sv", F1/"uart_tx.sv", F1/"uart_rx.sv",
                F1/"sync_fifo.sv", F1/"uart_peripheral.sv",
                F1/"uart_stream_peripheral.sv", F1/"uart_tb.sv"],
        mem=[],
    ),
    # -------------------------------------------------------------------------
    # SYNC_FIFO BLOK TESTI
    #
    # 9. ASIC kosumunda ss kosesinin en kotu yolu bu FIFO'nun icindeydi:
    #     u_uart2.u_rx_fifo.rd_ptr_r[0] -> u_uart2.u_rx_fifo.mem[25][0]
    #     98 hucre, -8,026 ns
    # En kotu SEKIZ bitis noktasinin tamami ayni FIFO'nun mem[...] hucreleriydi.
    #
    # Kok neden: o_full kombinasyonel olarak (wr_ptr - rd_ptr) cikarmasindan
    # geliyor, sonra 256x8 = 2048 flip-flop'un yazma iznini besliyordu.
    # Duzeltme: dolu/bos tespiti cikaricidan ayrildi ve bayraklar yazmaclandi.
    #
    # Zamanlama duzeltmesi islevi bozarsa kazanim anlamsizdir. Bu test
    # FIFO'nun davranis sozlesmesini dogrudan sinar: reset, tek yaz/oku,
    # fill-to-full, drain-to-empty, wraparound, es zamanli R/W, full+read,
    # empty+write. Sistem testleri FIFO'yu dolayli kullanir; bu test sinir
    # kosullarini acikca zorlar.
    # -------------------------------------------------------------------------
    dict(
        ad="sync_fifo",
        top="tb_sync_fifo",
        kaynak=[RTL/"Cevre_Birimleri"/"files_1"/"sync_fifo.sv",
                TB/"tb_sync_fifo.sv"],
        mem=[],
    ),
    dict(
        ad="i2c",
        top="i2c_peripheral_tb",
        kaynak=[CEV/"i2c_peripheral.sv", CEV/"i2c_peripheral_tb.sv"],
        mem=[],
    ),
    # -------------------------------------------------------------------------
    # I2C SCL FREKANS TESTI - iki hedef
    #
    # 11 Eylul 2026'da eklendi. soc_top.sv'de cevre birimi bolucileri
    # SYS_CLK_HZ parametresine baglandi (onceden uc yerde 50 MHz sabit
    # kodluydu). Bu test, parametrenin dogru verildiginde HER IKI hedefte
    # de sartname EK-2'nin "SCL 400 kHz sabit" isterinin karsilandigini
    # dogrular:
    #     FPGA 50,0 MHz -> 50e6/125 = 400.000 Hz TAM
    #     ASIC 43,2 MHz -> 43,2e6/108 = 400.000 Hz TAM
    # -------------------------------------------------------------------------
    # -------------------------------------------------------------------------
    # I2C SCL PERIYOT OLCUMU - GERCEK DALGA FORMU
    #
    # 12 Eylul 2026'da eklendi. Hata enjeksiyonu sunu gosterdi:
    #   MUTASYON i2c_bolen (PERIYOT - 1)  -> i2c blok testi KACIRDI
    # Mevcut i2c_peripheral_tb yazmac/ACK akisini dogruluyor ama SCL'in
    # FREKANSINI hic olcmuyor. Bu test uretilen SCL darbelerinin suresini
    # simulasyon zamaniyla OLCER.
    #
    # tb_i2c_scl_frekans (11 Eylul) bolen HESABINI dogrular;
    # bu test URETILEN DALGAYI olcer. Farkli seyleri kapsarlar.
    # -------------------------------------------------------------------------
    dict(
        ad="i2c_scl_periyot",
        top="tb_i2c_scl_periyot",
        kaynak=[CEV/"i2c_peripheral.sv",
                TB/"tb_i2c_scl_periyot.sv"],
        mem=[],
    ),
    # -------------------------------------------------------------------------
    # I2C SAAT GERME (CLOCK STRETCHING) TESTI
    #
    # 12 Eylul 2026'da eklendi. Port taramasi sunu buldu:
    #     i2c_peripheral : scl_i -> sadece port tanimi, HIC OKUNMUYOR
    #
    #   I2C acik drenajdir: scl_oe=0 "hatti birak" demektir, "hat yuksek"
    #   demek DEGILDIR. Yavas bir slave SCL'i asagi cekerek bekleme ister
    #   (UM10204 3.1.9). Germeyi gormeyen master zamanlamayi yurutmeye
    #   devam eder; slave bitleri kaciririr ve veri SESSIZCE bozulur.
    #
    # Duzeltme scl_i'yi iki kademeli senkronizatorden gecirir ve hat
    # birakilmis ama hala asagidaysa ceyrek sayacini dondurur.
    #
    # Bu test sahte bir slave ile SCL'i 5 us tutar ve SCL-yuksek
    # suresinin gercekten uzadigini, germe bitince islemin devam
    # ettigini (kilitlenme olmadigini) dogrular.
    # -------------------------------------------------------------------------
    dict(
        ad="i2c_saat_germe",
        top="tb_i2c_saat_germe",
        kaynak=[CEV/"i2c_peripheral.sv",
                TB/"tb_i2c_saat_germe.sv"],
        mem=[],
    ),
    dict(
        ad="i2c_scl_frekans",
        top="tb_i2c_scl_frekans",
        kaynak=[TB/"tb_i2c_scl_frekans.sv"],
        mem=[],
    ),
    # -------------------------------------------------------------------------
    # GPIO BLOK TESTI
    #
    # 22 Agustos 2026'da eklendi. GPIO'nun HIC blok testi yoktu; sistem testi
    # yalnizca cikis yazmacini kullaniyordu. Kesme mekanizmasinin dort modu -
    # yukselen kenar, dusen kenar, seviye-yuksek, seviye-dusuk - hicbir testte
    # calismamisti.
    # -------------------------------------------------------------------------
    # -------------------------------------------------------------------------
    # DMA BLOK TESTI
    #
    # 22 Agustos 2026'da eklendi. DMA'nin HIC blok testi yoktu; yalnizca
    # sistem testinde dolayli calisiyordu (%41,1 statement).
    #
    # EN ONEMLI KISIM: testbench'teki bellek modeli AW ve W'yi KASITLI
    # OLARAK farkli cevrimlerde kabul eder. Bu, veriyolu incelemesindeki
    # bulgu V1'in duzeltmesini dogrular. Duzeltme geri alinip kosuldugunda
    # test 20 hatayla duser ve AW islem sayisi 8 yerine 1 cikar.
    # -------------------------------------------------------------------------
    dict(
        ad="dma",
        top="tb_dma_controller",
        kaynak=[CEV/"dma_controller.sv", TB/"dma"/"tb_dma_controller.sv"],
        mem=[],
    ),
    dict(
        ad="gpio",
        top="tb_gpio_peripheral",
        kaynak=[CEV/"gpio_peripheral.sv", TB/"gpio"/"tb_gpio_peripheral.sv"],
        mem=[],
    ),
    dict(
        ad="qspi",
        top="tb_qspi_mock",
        kaynak=[CEV/"qspi_master.sv", TB/"spi_flash_model.sv",
                CEV/"tb_qspi_mock.sv"],
        mem=["qspi_test_pattern.hex"],
    ),
    # -------------------------------------------------------------------------
    # TIMER BLOK TESTI
    #
    # 22 Agustos 2026 dogrulama denetiminde cikti: Timer, 23 RTL modulu
    # icinde HICBIR denetimi olmayan tek moduldu. Sistem testi onu hic
    # kullanmiyor, npu_hizlanma yalnizca ALET olarak kullaniyordu.
    #
    # Sartname EK-2'nin sekiz yazmacini da kapsar: prescaler orani, yukari
    # ve asagi sayma, auto-reload, event uretimi, kesme, TIM_CLR davranisi
    # ve salt-okunur yazmaclarin yazmaya direnci.
    # -------------------------------------------------------------------------
    dict(
        ad="timer",
        top="tb_timer_peripheral",
        kaynak=[CEV/"timer_peripheral.sv", TB/"timer"/"tb_timer_peripheral.sv"],
        mem=[],
    ),
    dict(
        ad="jtag_debug",
        top="tb_jtag_debug",
        kaynak=[CEV/"jtag_debug.sv", TB/"T3.1_jtag_debug"/"tb_jtag_debug.sv"],
        mem=[],
    ),
    # -------------------------------------------------------------------------
    # JTAG SAAT ALANI GECISI (CDC) TESTI
    #
    # 12 Eylul 2026'da eklendi. Akis arastirmasi sunu buldu:
    #   Tasarimda IKI ASENKRON saat alani var (clk_i, jtag_tck) ve SDC
    #   bunlari set_clock_groups -asynchronous ile ayiriyor. Ama mevcut
    #   tb_jtag_debug TCK'yi #100 ile ELLE darbeliyordu: periyot 200 ns,
    #   clk 20 ns - TAM 10 KATI, yani her zaman HIZALI.
    #
    #   jtag_debug.sv iki kademeli senkronizator kullanir (satir 246-265)
    #   ve veri MCP kalibiyla gecirilir. Kalip DOGRU yazilmis ama
    #   asenkron iliski HIC test edilmemisti.
    #
    # Bu test TCK'yi clk ile tam sayi orani OLMAYAN periyotlarda
    # (33/47/71/103/23 ns) ve kaymali fazlarda surer.
    # -------------------------------------------------------------------------
    dict(
        ad="jtag_cdc",
        top="tb_jtag_cdc",
        kaynak=[CEV/"jtag_debug.sv",
                TB/"tb_jtag_cdc.sv"],
        mem=[],
    ),
    # -------------------------------------------------------------------------
    # JTAG AXI YANIT KODU DENETIMI
    #
    # 12 Eylul 2026'da eklendi. Port taramasi sunu buldu:
    #     jtag_debug : m_axi_rresp  -> sadece port tanimi, HIC OKUNMUYOR
    #     jtag_debug : m_axi_bresp  -> sadece port tanimi, HIC OKUNMUYOR
    #
    #   JTAG debug master interconnect uzerinden TUM slave'lere erisir.
    #   Tanimsiz bir adres okunursa interconnect DECERR (2'b11) ve
    #   0xDEADBEEF dondurur. Yanit kodu okunmadigi icin JTAG bu cop
    #   veriyi GECERLI saniyordu - debug oturumunda sessiz yanlis okuma.
    #
    # Duzeltme yanit kodunu iki yoldan bildirir:
    #   REG_DBG_STATUS[3]   = hata bayragi
    #   REG_DBG_STATUS[5:4] = son AXI yanit kodu
    #   IR_MEM_READ DR alt 32 biti = 0 (OKAY) veya hata imzasi
    #
    # Bu test sahte slave ile OKAY/SLVERR/DECERR yanitlarini ZORLAR ve
    # bayragin dogru kalktigini, yeni islemde temizlendigini dogrular.
    # Yazma yolu (bresp) de ayrica denetlenir.
    # -------------------------------------------------------------------------
    dict(
        ad="jtag_yanit_kodu",
        top="tb_jtag_yanit_kodu",
        kaynak=[CEV/"jtag_debug.sv",
                TB/"tb_jtag_yanit_kodu.sv"],
        mem=[],
    ),
    dict(
        ad="npu_blok",
        top="tb_npu_compute_engine",
        # npu_weights_pkg.sv modulden ONCE gelmeli - agirliklar artik
        # RTL'e gomulu, $readmemh ile dosyadan okunmuyor.
        kaynak=[NPU/"npu_weights_pkg.sv", NPU/"npu_compute_engine.sv",
                TB/"tb_npu_compute_engine.sv"],
        mem=["fc_weights_packed32.mem"],
    ),
    # -------------------------------------------------------------------------
    # NPU ACCELERATOR SARMALAYICI TESTI
    #
    # 12 Eylul 2026'da eklendi. Kapsam analizi sunu gosterdi:
    #     npu_accelerator   stmt %0,0   <- hicbir blok testinde YOK
    # NPU testleri yalniz npu_compute_engine'i ornekliyordu; sarmalayici
    # katman (CSR + TCM + AXI denetleyici + motor baglantisi) yalnizca
    # sistem testinde DOLAYLI calisiyordu.
    #
    # Kritik kod orada: satir 204-209 AXI ile motor arasindaki TCM
    # port A hakemligini yapar. Oncelik yanlis olsa DMA ile yuklenen
    # girdi bozulur veya motorun cikisi kaybolurdu.
    # -------------------------------------------------------------------------
    dict(
        ad="npu_accelerator",
        top="tb_npu_accelerator",
        kaynak=[NPU/"npu_weights_pkg.sv", NPU/"npu_csr.sv",
                NPU/"npu_axi_controller.sv", NPU/"npu_tcm_sram.sv",
                NPU/"npu_compute_engine.sv", NPU/"npu_tcm_axi_slave.sv",
                NPU/"npu_engine_axi_master.sv", NPU/"npu_accelerator.sv",
                TB/"tb_npu_accelerator.sv"],
        mem=[],
    ),
    dict(
        ad="npu_golden",
        top="tb_npu_golden",
        kaynak=[NPU/"npu_weights_pkg.sv", NPU/"npu_compute_engine.sv",
                TB/"npu_golden"/"tb_npu_golden.sv"],
        # Agirliklar gomulu; test_input_pattern.mem testin GIRDISIDIR,
        # agirlik degildir - kopyalanmaya devam ediyor.
        mem=["test_input_pattern.mem", "fc_weights_packed32.mem"],
    ),
    # -------------------------------------------------------------------------
    # NPU COK-VEKTORLU DOGRULUK TESTI
    #
    # Sartname EK-1 hizlandiricinin yazilim modeliyle %10 pencerede uyumlu
    # olmasini ister. npu_golden TEK vektor kosuyordu ve yalnizca NO sinifini
    # uyariyordu; SILENCE / UNKNOWN / YES dallari hic calismiyordu.
    #
    # Bu test dort sinifi da kapsayan vektorlerle kosar ve RTL ciktisini
    # yazilim referans modeliyle BIREBIR karsilastirir.
    #
    # Vektorler uretilmistir: python tb/npu_audio/gen_vectors.py
    # -------------------------------------------------------------------------
    dict(
        ad="npu_dogruluk",
        top="tb_npu_audio",
        kaynak=[NPU/"npu_weights_pkg.sv", NPU/"npu_compute_engine.sv",
                TB/"npu_audio"/"tb_npu_audio.sv"],
        mem=["vectors.mem", "fc_weights_packed32.mem"],
    ),
    # -------------------------------------------------------------------------
    # YAZILIM / DONANIM HIZLANMA OLCUMU
    #
    # Sartname EK-1: "YZ hizlandiricisi ... RISC-V cekirdegi uzerinde calisan
    # yazilim gerceklemesine kiyasla HIZLANMA elde etmelidir."
    # Bolum 4.2.2.1: performans "veri/saat dongusu bazinda" olculmelidir.
    #
    # CPU, ayni modeli C ile kosar (agirliklar TCM'de - 16 kB FC agirligi
    # 8 kB D-RAM'e sigmaz). Test, yazilimin donanimdan en az 100x yavas
    # oldugunu dogrular. Kesin oran icin: python tb/npu_sw_bench/analiz.py
    # -------------------------------------------------------------------------
    dict(
        ad="npu_hizlanma",
        top="tb_npu_sw_bench",
        kaynak=None,
        ek_kaynak=[TB/"npu_sw_bench"/"tb_npu_sw_bench.sv"],
        tanim=["BENCH_N50"],
        mem=["tcm_image.mem", "bench_50.hex"],
    ),
    # -------------------------------------------------------------------------
    # TAM SISTEM TESTI
    #
    # 21 Agustos 2026'da fark edildi: regresyon YALNIZCA blok testlerini
    # kapsiyordu, tb_soc_top hic kosmuyordu. Yani bootloader'in calistigi,
    # QSPI -> I-RAM aktariminin dogrulugu ve uctan uca akis regresyonla
    # dogrulanmiyordu. Blok testleri gectigi icin "dogrulandi" saniliyordu.
    #
    # Kaynak listesi asic/filelist.f'ten okunur (bkz. filelist_rtl).
    # -------------------------------------------------------------------------
    dict(
        ad="sistem",
        top="tb_soc_top",
        kaynak=None,                      # filelist_rtl() ile doldurulur
        # axil_protocol_checker asic/filelist.f'te YOKTUR - yalnizca SVA
        # denetleyicisidir, sentezlenmez. tb_soc_top onu bind ile
        # bagliyor, bu yuzden simulasyon kaynagi olarak eklenmeli.
        ek_kaynak=[MEM/"axil_protocol_checker.sv",
                   TB/"spi_flash_model.sv", TB/"tb_soc_top.sv"],
        mem=["app.hex", "app_sim.hex", "boot.hex", "flash.hex",
             "flash_sim.hex", "fc_weights_packed32.mem"],
        mem_zorunlu=False,                # bulunamazsa test atlanir, cokmez
    ),
    # -------------------------------------------------------------------------
    # GERCEK IKI ASAMALI BOOT TESTI
    #
    # Sartname Bolum 5.2 (odul icin asgari basari kriteri):
    #   "En azindan bir adet self-checking test ile BOOT AKISI, bir cevre
    #    birimi programlamasi ve cevre birimi calismasinin dogrulanmasi."
    #
    # Yukaridaki 'sistem' testi HIZLI ACILIS kullanir: I-RAM dogrudan
    # doldurulur ve cekirdegin boot_addr_i girisi zorlanir. Yani yukleyici,
    # QSPI okumasi ve shadowing zinciri HIC KOSMUYOR. Blok testleri gectigi
    # icin "boot dogrulandi" saniliyordu.
    #
    # Bu test -d REAL_BOOT ile gercek zinciri kosar:
    #   Boot ROM -> QSPI Master -> flash -> I-RAM -> jalr -> uygulama
    # -------------------------------------------------------------------------
    # -------------------------------------------------------------------------
    # CEKIRDEK TESTI - Spike ISS karsilastirmasi icin iz uretir
    #
    # Sartname s.569: "CV32E40P ... dogrulanmasinin bir buyruk kumesi
    # benzetim araci (ISS) ile (Orn. Spike ISS) yapilmasi beklenmektedir."
    #
    # Bu test core_test.hex'i kosar ve cv32e40p_tracer ile komut izini
    # trace_core_00000000.log dosyasina yazar. Kendi kendini denetler:
    # D-RAM imzasi 0xC0DE0001 programin bastan sona kostugunu gosterir.
    #
    # Spike ile karsilastirma AYRI bir adimdir (spike Linux gerektirir):
    #     python3 scripts/spike_iz_al.py
    #     python  scripts/spike_karsilastir.py
    # -------------------------------------------------------------------------
    dict(
        ad="cekirdek_izi",
        top="tb_soc_top",
        kaynak=None,
        ek_kaynak=[MEM/"axil_protocol_checker.sv",
                   TB/"spi_flash_model.sv", TB/"tb_soc_top.sv",
                   ROOT/"rtl"/"cv32e40p-master"/"bhv"/"include"/"cv32e40p_tracer_pkg.sv",
                   ROOT/"rtl"/"cv32e40p-master"/"bhv"/"cv32e40p_tracer.sv"],
        tanim=["CORE_TEST", "CV32E40P_TRACE_EXECUTION"],
        mem=["core_test.hex", "app.hex", "app_sim.hex", "boot.hex",
             "flash.hex", "flash_sim.hex", "flash_core_test.hex",
             "fc_weights_packed32.mem"],
        mem_zorunlu=False,
        ek_bayrak=["-L", "uvm",
                   "-i", str(ROOT/"rtl"/"cv32e40p-master"/"bhv"/"include"),
                   "-i", str(ROOT/"rtl"/"cv32e40p-master"/"rtl"/"include")],
        elab_bayrak=["-L", "uvm"],
    ),
    # -------------------------------------------------------------------------
    # UVM AXI4-Lite PASSIVE AGENT
    #
    # Sartname Bolum 4.2.2:
    #   "...cevre birimlerinin ve YZ hizlandiricinin {AXI veya AXI-Lite}
    #    arayuzlerinin SystemVerilog HDL ve Universal Verification
    #    Methodology (UVM) kullanilarak dogrulanmasi beklenecektir."
    #
    # Sartname Bolum 5.2 (odul icin asgari basari kriteri):
    #   "...AXI arayuzlerinin en azindan protocol check duzeyinde AXI
    #    agent'lariyla dogrulanmasi."
    #
    # 'sistem' testiyle AYNI uyaranlari kosar; farki, NPU motorunun AXI4-Lite
    # master hattina bir UVM passive agent baglanmasidir. Agent ham sinyalleri
    # ISLEM nesnelerine cevirir ve islem duzeyinde denetler:
    #   - her AR'ye tam bir R, her AW+W'ye tam bir B yaniti
    #   - yanit kodu gecerli (AXI4-Lite'ta EXOKAY olamaz)
    #   - asili kalmis islem yok
    #
    # Testbench ayrica ham el sikismalarini bagimsiz sayar ve monitor
    # sayaclariyla karsilastirir; boylece agent'in islem DUSURMEDIGI de
    # kanitlanir.
    #
    # NOT: -d UVM_AXI olmadan bu dosyalar hic derlenmez, diger 14 test
    # uvm kutuphanesine baglanmak zorunda kalmaz.
    # -------------------------------------------------------------------------
    dict(
        ad="uvm_axi_agent",
        top="tb_soc_top",
        kaynak=None,
        ek_kaynak=[TB/"uvm"/"axil_if.sv", TB/"uvm"/"axil_uvm_pkg.sv",
                   MEM/"axil_protocol_checker.sv",
                   TB/"spi_flash_model.sv", TB/"tb_soc_top.sv"],
        tanim=["UVM_AXI"],
        mem=["app.hex", "app_sim.hex", "boot.hex", "flash.hex",
             "flash_sim.hex", "fc_weights_packed32.mem"],
        mem_zorunlu=False,
        ek_bayrak=["-L", "uvm"],
        elab_bayrak=["-L", "uvm"],
    ),
    # -------------------------------------------------------------------------
    # AKTIF UVM TESTI  (13 Eylul 2026)
    #
    # uvm_axi_agent PASIF izler: gercek NPU trafigi yalnizca tam-word
    # erisim ve OKAY yanit urettigi icin strb (tek_bayt/yarim) ve yanit
    # (SLVERR/DECERR) bin'leri UYARILAMIYORDU - islevsel kapsam %52,1'de
    # takiliyordu.
    #
    # Bu test agent'lari UVM_ACTIVE kurar ve sequence kosar:
    #   axil_wstrb_seq    - kismi yazma desenlerini hedefler
    #   axil_yanit_seq    - SLVERR/DECERR uretir
    #   axil_rastgele_seq - kisitli-rastgele trafik
    #   axil_sanal_seq    - iki arayuz eszamanli (hakemlik baskisi)
    #
    # Kaynak listesi uvm_axi_agent ile AYNIDIR; fark yalnizca
    # +UVM_TESTNAME plusarg'idir.
    # -------------------------------------------------------------------------
    dict(
        ad="uvm_aktif",
        top="tb_soc_top",
        kaynak=None,
        ek_kaynak=[TB/"uvm"/"axil_if.sv", TB/"uvm"/"axil_uvm_pkg.sv",
                   MEM/"axil_protocol_checker.sv",
                   TB/"spi_flash_model.sv", TB/"tb_soc_top.sv"],
        tanim=["UVM_AXI", "UVM_AKTIF"],
        mem=["app.hex", "app_sim.hex", "boot.hex", "flash.hex",
             "flash_sim.hex", "fc_weights_packed32.mem"],
        mem_zorunlu=False,
        ek_bayrak=["-L", "uvm"],
        elab_bayrak=["-L", "uvm"],
    ),
    dict(
        ad="sistem_gercek_boot",
        top="tb_soc_top",
        kaynak=None,
        ek_kaynak=[MEM/"axil_protocol_checker.sv",
                   TB/"spi_flash_model.sv", TB/"tb_soc_top.sv"],
        tanim=["REAL_BOOT"],
        mem=["app.hex", "app_sim.hex", "boot.hex", "flash.hex",
             "flash_sim.hex", "fc_weights_packed32.mem"],
        mem_zorunlu=False,
    ),
]

MEM_KAYNAKLARI = [
    ROOT/"weights",
    ROOT/"sw_nexys"/"build",
    TB,
    ROOT/"vivado"/"vivado_nexys_project"/"Arkhe_SoC_Nexys.ip_user_files"/"mem_init_files",
    TB/"npu_golden",
    TB/"npu_audio",
    TB/"npu_sw_bench",
    NPU,
]


def mem_bul(ad):
    for d in MEM_KAYNAKLARI:
        p = d / ad
        if p.is_file():
            return p
    return None


def komut(args, cwd, log_yolu):
    """Komutu calistir, ciktiyi loga yaz, (rc, cikti) dondur."""
    with open(log_yolu, "w", encoding="utf-8", errors="replace") as fh:
        p = subprocess.run(args, cwd=str(cwd), stdout=subprocess.PIPE,
                           stderr=subprocess.STDOUT, text=True,
                           encoding="utf-8", errors="replace")
        fh.write(p.stdout or "")
    return p.returncode, (p.stdout or "")


# -----------------------------------------------------------------------------
# Tam sistem testi icin RTL listesi
#
# TEK DOGRULUK KAYNAGI asic/filelist.f'tir. Listeyi elle tekrarlamak yerine
# oradan okuyoruz; boylece ASIC akisi ile regresyon AYNI kaynaklari kullanir
# ve biri degisince digeri geride kalmaz.
#
# filelist.f yollari asic/ dizinine goredir (../rtl/...), burada cozuluyor.
# -----------------------------------------------------------------------------
def filelist_rtl():
    fl = ROOT / "asic" / "filelist.f"
    if not fl.is_file():
        return None
    kaynaklar = []
    for satir in fl.read_text(encoding="utf-8", errors="replace").splitlines():
        satir = satir.split("//")[0].split("#")[0].strip()
        if not satir or satir.startswith("+") or satir.startswith("-"):
            continue
        for taban in (ROOT / "asic", ROOT):
            yol = (taban / satir).resolve()
            if yol.is_file():
                kaynaklar.append(yol)
                break
    return kaynaklar or None


def test_kos(t, vivado_bin, kapsam=False, ek_tanim=None):
    # Kaynak listesi gec baglanan testler (tam sistem) icin
    if t.get("kaynak") is None:
        rtl = filelist_rtl()
        if rtl is None:
            return dict(ad=t["ad"], durum="ATLANDI", denetim=0,
                        not_="asic/filelist.f okunamadi")
        t = dict(t, kaynak=rtl + list(t.get("ek_kaynak", [])))

    d = WORK / t["ad"]
    if d.exists():
        shutil.rmtree(d, ignore_errors=True)
    d.mkdir(parents=True, exist_ok=True)

    for m in t["mem"]:
        kaynak = mem_bul(m)
        if kaynak is None:
            if not t.get("mem_zorunlu", True):
                continue
            return dict(ad=t["ad"], durum="ATLANDI", denetim=0,
                        not_=f"{m} bulunamadi")
        shutil.copy2(kaynak, d / m)

    xvlog = str(Path(vivado_bin) / "xvlog.bat")
    xelab = str(Path(vivado_bin) / "xelab.bat")
    xsim  = str(Path(vivado_bin) / "xsim.bat")

    tanim_arg = []
    for tn in t.get("tanim", []):
        tanim_arg += ["-d", tn]

    # -------------------------------------------------------------------------
    # 5 Eylul 2026'da EKLENDI: --ek-tanim
    #
    # Regresyon simdiye kadar HIC USE_SRAM_MACRO tanimlamiyordu; yani butun
    # testler SRAM'in CIKARIMSAL yolunu (`else` dali) dogruluyordu. ASIC
    # akisi ise `asic/config.yaml` icinde bu tanimi acar ve MAKRO yolunu
    # kullanir. Iki yol farkli kodtur - biri dogrulanirken digeri
    # dogrulanmamis kaliyordu.
    #
    # sram_module.sv'ye eklenen okuma boru hattu (macro_read_pending,
    # kombinasyonel bypass'in kaldirilmasi) YALNIZCA makro dalindadir.
    # Bu tanim verilmeden kosulan regresyon o degisikligi HIC test etmez.
    # -------------------------------------------------------------------------
    for tn in (ek_tanim or []):
        if tn not in t.get("tanim", []):
            tanim_arg += ["-d", tn]

    # ek_bayrak: teste ozel derleyici bayraklari (orn. -L uvm, -i <dizin>)
    # cekirdek izi testi cv32e40p_tracer'i kullanir; o da uvm_pkg import
    # eder ve bhv/include dizinindeki basliklara ihtiyac duyar.
    ek_bayrak = [str(x) for x in t.get("ek_bayrak", [])]

    # USE_SRAM_MACRO acikken RTL, saticinin davranissal SRAM modelini
    # ornekler; o dosya normal kaynak listesinde YOKTUR (yalnizca ASIC
    # akisinin filelist.f'inde). Eklenmezse elaborasyon
    # "Module <sky130_sram_2kbyte_1rw1r_32x512_8> not found" ile duser.
    kaynaklar = [str(k) for k in t["kaynak"]]
    if "USE_SRAM_MACRO" in (ek_tanim or []):
        sram_model = (ROOT / "asic" / "macros" /
                      "sky130_sram_2kbyte_1rw1r_32x512_8" / "verilog" /
                      "sky130_sram_2kbyte_1rw1r_32x512_8.v")
        if sram_model.is_file():
            kaynaklar.insert(0, str(sram_model))

    rc, out = komut([xvlog, "-sv"] + tanim_arg + ek_bayrak +
                    kaynaklar +
                    ["-log", "vlog.log"], d, d / "vlog.log")
    if rc != 0:
        return dict(ad=t["ad"], durum="DERLEME HATASI", denetim=0,
                    not_=ilk_hata(out))

    # ---------------------------------------------------------------------
    # KOD KAPSAMA (Sartname EK-3)
    #
    #   "Code Coverage ... Opsiyonel***" ve
    #   "***Opsiyonel: Dogrulama aktivitelerinden TAM PUAN alimini
    #    saglayacak unsurlar."
    #
    # sbct = (s)tatement (b)ranch (c)ondition (t)oggle
    # Her testin veritabani ayri isimle yazilir; sonunda xcrg ile
    # birlestirilip tek rapor uretilir.
    # ---------------------------------------------------------------------
    kapsam_arg = []
    if kapsam:
        # Yol POSIX bicimde verilmeli. Windows'ta str(Path) ters bolu
        # uretir ve xelab uretilen C dosyasini derleyemez:
        #     ERROR: [XSIM 43-3409] Failed to compile generated C file
        # Bayraklarin kendisi sorunsuz; yalnizca ayrac sorunuydu.
        # -------------------------------------------------------------
        # 9 Eylul 2026: FUNCTIONAL COVERAGE eklendi.
        #
        # Onceden yalnizca sbct (statement/branch/condition/toggle) yani
        # KOD kapsamasi toplaniyordu. Sartname EK-3 ayrica "Functional
        # Coverage" maddesi tanimlar ve "tanimlanan islevsel coverage
        # noktalariyla her zaman %100'u hedeflemelidir" der.
        #
        # tb_soc_top icinde covergroup'lar zaten tanimliydi (GPIO, JTAG,
        # AXI el sikismalari, kesme hatlari, DMA durumlari) ama
        # toplanmiyordu. -covergroup bayragi bunlari veritabanina yazar.
        # -------------------------------------------------------------
        kapsam_arg = ["--cc_type", "sbct",
                      "--cov_db_dir", (WORK / "covdb").as_posix(),
                      "--cov_db_name", t["ad"]]

    # elab_bayrak: teste ozel elaborate bayraklari (orn. -L uvm)
    elab_bayrak = [str(x) for x in t.get("elab_bayrak", [])]

    rc, out = komut([xelab, "-debug", "typical", "-timescale", "1ns/1ps"] +
                    kapsam_arg + elab_bayrak +
                    [t["top"], "-s", "snap", "-log", "elab.log"],
                    d, d / "elab.log")
    if rc != 0:
        return dict(ad=t["ad"], durum="ELAB HATASI", denetim=0,
                    not_=ilk_hata(out))

    (d / "run.tcl").write_text("run all\nquit\n", encoding="ascii")

    t0 = time.time()
    # xsim'in kendi logu ayri dosyaya; stdout'u sim.log'a aliyoruz.
    # Ikisi ayni dosya olursa her satir IKI KEZ yazilir ve denetim sayilari
    # iki katina cikar - ilk surumde tam olarak bu oldu.
    # -------------------------------------------------------------------
    # plusarg (13 Eylul 2026)
    #
    # DIKKAT: Windows'ta xsim.bat sarmalayicisi "-testplusarg AD=DEGER"
    # icindeki '=' isaretinde arguman bolyor ve xsim yardim ekrani
    # basiyor ("Expected a switch but found a"). Bu yuzden UVM testi
    # plusarg ile DEGIL, derleme zamani makrosuyla secilir
    # (tanim=["UVM_AXI","UVM_AKTIF"] -> tb_soc_top icindeki `ifdef).
    #
    # Alan yine de duruyor: '=' icermeyen plusarg'lar sorunsuz gecer.
    # -------------------------------------------------------------------
    plusarg = []
    for pa in t.get("plusarg", []):
        plusarg += ["-testplusarg", str(pa)]

    # NOT: xsim arguman ayristirmasi hassastir. Snapshot adi ("snap")
    # ILK sirada, plusarg'lar EN SONDA olmalidir. Yanlis sirada
    # "Expected a switch but found a" hatasiyla YARDIM EKRANI basar ve
    # simulasyon hic kosmaz (belirti: "DENETIM YOK").
    rc, out = komut([xsim, "snap", "-tclbatch", "run.tcl",
                     "-log", "xsim.log"] + plusarg,
                    d, d / "sim.log")
    sure = time.time() - t0

    metin = (d / "sim.log").read_text(encoding="utf-8", errors="replace")

    # $fatal cagrildi mi?
    fatal = ("Fatal:" in metin) or ("FATAL_ERROR" in metin)

    ok   = len(re.findall(r"\[OK\]|\[PASS\]", metin))
    hata = len(re.findall(r"\[HATA\]|\[FAIL\]", metin))

    # npu_golden farkli bicim kullaniyor: satir basinda "PASS:" / "FAIL:"
    ok   += len(re.findall(r"^PASS:", metin, re.M))
    hata += len(re.findall(r"^FAIL:", metin, re.M))

    if fatal or hata > 0:
        durum = "BASARISIZ"
    elif ok == 0:
        durum = "DENETIM YOK"
    else:
        durum = "GECTI"

    return dict(ad=t["ad"], durum=durum, denetim=ok, hata=hata,
                sure=sure, not_="")


def _kapsam_ozet(rapor_dizini):
    """xcrg dashboard.html icinden ozet skorlari cikarir."""
    dash = Path(rapor_dizini) / "codeCoverageReport" / "dashboard.html"
    if not dash.is_file():
        return None
    metin = dash.read_text(encoding="utf-8", errors="replace")
    duz = re.sub(r"<[^>]+>", " ", metin)
    duz = re.sub(r"\s+", " ", duz)
    m = re.search(r"Total Files Total Modules Total Instances "
                  r"Statement Coverage Score Branch Coverage Score "
                  r"Condition Coverage Score Toggle Coverage Score "
                  r"([\d.]+) ([\d.]+) ([\d.]+) "
                  r"([\d.]+) ([\d.]+) ([\d.]+) ([\d.]+)", duz)
    if not m:
        return None
    g = m.groups()
    return dict(dosya=int(float(g[0])), modul=int(float(g[1])),
                ornek=int(float(g[2])),
                statement=float(g[3]), branch=float(g[4]),
                condition=float(g[5]), toggle=float(g[6]),
                dashboard=dash)


def _xcrg(vivado_bin, args, log_adi):
    xcrg = str(Path(vivado_bin) / "xcrg.bat")
    rc, _ = komut([xcrg] + args + ["-log", (WORK / log_adi).as_posix()],
                  WORK, WORK / (log_adi + ".stdout"))
    return rc


def _islevsel_ozet(rapor_dizini):
    """xcrg islevsel kapsama raporundan kapsama noktalarini cikarir.

    grp0.html icindeki her satir bir cover point'tir:
        <ad> <beklenen> <kapsanmayan> <kapsanan> <yuzde> ...
    """
    grp = Path(rapor_dizini) / "functionalCoverageReport" / "grp0.html"
    if not grp.is_file():
        return None
    metin = grp.read_text(encoding="utf-8", errors="replace")
    noktalar = {}
    for satir in re.findall(r"<tr.*?</tr>", metin, re.S):
        h = [re.sub(r"<[^>]+>", "", x).strip()
             for x in re.findall(r"<td.*?</td>", satir, re.S)]
        if len(h) >= 5 and h[0].startswith("cov_"):
            # Ad sutunu "cov_uar ...cov_uart2_fifo" gibi kirpilmis
            # gelebiliyor; son kelime gercek addir.
            ad = h[0].split()[-1]
            try:
                noktalar[ad] = (int(h[1]), int(h[2]), int(h[3]), float(h[4]))
            except ValueError:
                continue
    return noktalar or None


def islevsel_kapsam(vivado_bin):
    """Islevsel kapsamayi TUM testlerin BIRLESIMI olarak raporlar.

    NEDEN BIRLESIM ELLE HESAPLANIYOR
      xcrg'nin -cov_db_dir ile tum veritabanlarini birlestirmesi bu
      projede calismiyor: veritabanlarini listeliyor ama
        "WARNING : No Functional coverage DBs have been found"
        "ERROR   : No Functional Coverage Databases have been found"
      deyip cikiyor (build/regression/xcrg_fcov.log). Tek veritabani
      -cov_db_name ile verildiginde ise sorunsuz rapor uretiyor.

      Bu yuzden her veritabani icin ayri rapor uretip kapsama
      noktalarini burada birlestiriyoruz. Bir nokta HERHANGI bir
      testte kapsandiysa kapsanmis sayilir - kapsama zaten boyle
      tanimlidir.

    NEDEN GEREKLI
      Olcum 10 Eylul 2026'da %92,08'de takilmisti, cunku rapor
      yalnizca sistem_gercek_boot veritabanindan uretiliyordu. Yeni
      kapsanan noktalar (cov_axi_resp/decerr ve dort sinifli
      cov_npu_class) "sistem" testinde uretiliyor. Tek basina
      "sistem" %94,17 veriyor.
    """
    covdb = WORK / "covdb"
    fdb = covdb / "xsim.covdb"
    if not fdb.is_dir():
        return None

    birlesik = {}
    kaynak = {}
    for db in sorted(x.name for x in fdb.iterdir() if x.is_dir()):
        hedef = WORK / "fcov_rapor" / db
        shutil.rmtree(hedef, ignore_errors=True)
        hedef.mkdir(parents=True, exist_ok=True)
        _xcrg(vivado_bin, ["-cov_db_dir", covdb.as_posix(),
                           "-cov_db_name", db,
                           "-report_dir", hedef.as_posix(),
                           "-report_format", "html"], "xcrg_fcov_%s.log" % db)
        noktalar = _islevsel_ozet(hedef)
        if not noktalar:
            continue
        for ad, (bekl, eksik, kaps, yuzde) in noktalar.items():
            onceki = birlesik.get(ad)
            if onceki is None or kaps > onceki[2]:
                birlesik[ad] = (bekl, eksik, kaps, yuzde)
                kaynak[ad] = db

    if not birlesik:
        return None

    top_bekl = sum(v[0] for v in birlesik.values())
    top_kaps = sum(v[2] for v in birlesik.values())
    return dict(noktalar=birlesik, kaynak=kaynak,
                beklenen=top_bekl, kapsanan=top_kaps,
                yuzde=(100.0 * top_kaps / top_bekl) if top_bekl else 0.0)


def kapsam_raporu(vivado_bin):
    """Kod kapsama raporlarini uretir.

    IKI AYRI RAPOR uretilir, cunku xcrg ayni modulun FARKLI PARAMETRELERLE
    elaborate edilmis surumlerini birlestiremiyor:

        CCI-MERGE10 : ... as toggle coverage info are different
        CCI-MERGE2  : Cannot merge module i2c_peripheral(SYS_CLK_FREQ=50000000)

    Blok testleri modulleri kendi test kosullarinda, sistem testi ise SoC
    icindeki gercek parametrelerle elaborate ediyor. Zorla birlestirmek
    sistem seviyesi modullerin RAPORDAN DUSMESINE yol aciyordu - ilk
    kosumda soc_top, interconnect ve arbiter'lar hic gorunmedi.

      evidence/coverage         blok testlerinin birlesigi
      evidence/coverage_sistem  tam SoC (sistem_gercek_boot kosumu)

    Sartname EK-3, Code Coverage'i "Opsiyonel***" isaretler; dipnot
    "***Opsiyonel: Dogrulama aktivitelerinden TAM PUAN alimini saglayacak
    unsurlar" der.
    """
    covdb = WORK / "covdb"
    if not covdb.is_dir():
        print(" Kapsama veritabani bulunamadi - kapsama atlandi.")
        return None

    sonuc = {}

    # --- 1) Blok testlerinin birlesigi ---
    blok = ROOT / "evidence" / "coverage"
    shutil.rmtree(blok, ignore_errors=True)
    blok.mkdir(parents=True, exist_ok=True)
    _xcrg(vivado_bin, ["-cov_db_dir", covdb.as_posix(),
                       "-merge_dir", covdb.as_posix(),
                       "-merge_db_name", "birlesik",
                       "-report_dir", blok.as_posix(),
                       "-report_format", "html"], "xcrg_blok.log")
    o = _kapsam_ozet(blok)
    if o:
        sonuc["Blok testleri (birlesik)"] = o

    # --- 2) Tam SoC: sistem testi tek basina ---
    sis_db = covdb / "xsim.codeCov" / "sistem_gercek_boot"
    if sis_db.is_dir():
        sis = ROOT / "evidence" / "coverage_sistem"
        shutil.rmtree(sis, ignore_errors=True)
        sis.mkdir(parents=True, exist_ok=True)
        _xcrg(vivado_bin, ["-cov_db_dir", covdb.as_posix(),
                           "-cov_db_name", "sistem_gercek_boot",
                           "-report_dir", sis.as_posix(),
                           "-report_format", "html"], "xcrg_sistem.log")
        o = _kapsam_ozet(sis)
        if o:
            sonuc["Tam SoC (sistem_gercek_boot)"] = o

    return sonuc or None


def ilk_hata(cikti):
    for satir in (cikti or "").splitlines():
        if satir.startswith("ERROR"):
            return satir.strip()[:110]
    return "bilinmeyen hata"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--vivado", default=os.environ.get("VIVADO_BIN", VARSAYILAN_VIVADO),
                    help="Vivado bin dizini")
    ap.add_argument("--coverage", action="store_true",
                    help="Kod kapsama (statement/branch/condition/toggle) topla")
    # -------------------------------------------------------------------------
    # 4 Eylul 2026'da EKLENDI: --test ve --list.
    #
    # Teker teker inceleme icin tek test kosmak gerekiyordu; onceden bu
    # secenek yoktu, her seferinde 16 testin tamami (sistem testleri dahil,
    # bazilari 400+ saniye) kosuyordu. --list test adlarini yazar; --test
    # <ad> (birden fazla kez verilebilir) yalnizca o testleri kosar.
    # -------------------------------------------------------------------------
    ap.add_argument("--test", action="append", metavar="AD",
                    help="Yalnizca bu testi kos. Birden fazla kez verilebilir. "
                         "Adlar icin --list")
    ap.add_argument("--list", action="store_true",
                    help="Test adlarini listele ve cik")
    ap.add_argument("--ek-tanim", action="append", metavar="TANIM",
                    dest="ek_tanim",
                    help="Butun testlere ek `define ekle (orn. USE_SRAM_MACRO). "
                         "Birden fazla kez verilebilir.")
    a = ap.parse_args()

    if a.list:
        print("Blok testleri:")
        for t in TESTLER:
            if t.get("kaynak") is not None:
                print(f"  {t['ad']}")
        print("Sistem testleri (bellek dosyalari gerekir):")
        for t in TESTLER:
            if t.get("kaynak") is None:
                print(f"  {t['ad']}")
        return 0

    if a.coverage:
        shutil.rmtree(WORK / "covdb", ignore_errors=True)

    if not Path(a.vivado, "xvlog.bat").is_file():
        print(f"HATA: Vivado araclari bulunamadi: {a.vivado}")
        print("      --vivado ile yol verin veya VIVADO_BIN ortam degiskenini ayarlayin.")
        return 2

    WORK.mkdir(parents=True, exist_ok=True)
    print("=" * 70)
    print(" ARKHE SoC - BLOK SEVIYESI REGRESYON")
    print("=" * 70)

    testler = TESTLER
    if a.test:
        istenen = set(a.test)
        gecerli = {t["ad"] for t in TESTLER}
        bilinmeyen = istenen - gecerli
        if bilinmeyen:
            print(f"HATA: bilinmeyen test adi: {', '.join(sorted(bilinmeyen))}")
            print("      Adlar icin: --list")
            return 2
        testler = [t for t in TESTLER if t["ad"] in istenen]

    sonuclar = []
    for t in testler:
        print(f"  {t['ad']:<12} calisiyor...", end="", flush=True)
        s = test_kos(t, a.vivado, a.coverage, a.ek_tanim)
        sonuclar.append(s)
        if s["durum"] == "GECTI":
            print(f"\r  {t['ad']:<12} GECTI    {s['denetim']:>3} denetim  "
                  f"{s.get('sure',0):5.1f} s")
        else:
            print(f"\r  {t['ad']:<12} {s['durum']}  {s.get('not_','')}")

    print("=" * 70)
    gecen  = sum(1 for s in sonuclar if s["durum"] == "GECTI")
    toplam_denetim = sum(s["denetim"] for s in sonuclar)
    kalan  = [s for s in sonuclar if s["durum"] != "GECTI"]

    print(f" {gecen}/{len(sonuclar)} test gecti, toplam {toplam_denetim} denetim")
    if kalan:
        print(" BASARISIZ:")
        for s in kalan:
            print(f"   - {s['ad']}: {s['durum']} {s.get('not_','')}")
    print("=" * 70)

    if a.coverage:
        print(" Kapsama raporlari uretiliyor...")
        k = kapsam_raporu(a.vivado)
        if k:
            print("=" * 70)
            print(" KOD KAPSAMA")
            for ad, o in k.items():
                print("")
                print(f" {ad}")
                print(f"   {o['dosya']} dosya, {o['modul']} modul, {o['ornek']} ornek")
                print(f"   Statement %{o['statement']:.2f}   Branch    %{o['branch']:.2f}")
                print(f"   Condition %{o['condition']:.2f}   Toggle    %{o['toggle']:.2f}")
                print(f"   {o['dashboard']}")
            print("=" * 70)
        else:
            print(" Kapsama raporu uretilemedi - build/regression/xcrg_*.log")

        f = islevsel_kapsam(a.vivado)
        if f:
            print("")
            print("=" * 70)
            print(" ISLEVSEL KAPSAMA  (tum testlerin birlesimi)")
            print("")
            for ad in sorted(f["noktalar"]):
                bekl, eksik, kaps, _ = f["noktalar"][ad]
                isaret = "  " if eksik == 0 else " <"
                print(f"   {ad:<24} {kaps:>3}/{bekl:<3}"
                      f"  [{f['kaynak'][ad]}]{isaret}")
            print("")
            print(f"   TOPLAM  {f['kapsanan']}/{f['beklenen']}"
                  f"  = %{f['yuzde']:.2f}")
            print("=" * 70)
        else:
            print(" Islevsel kapsama raporu uretilemedi")

    return 1 if kalan else 0


if __name__ == "__main__":
    sys.exit(main())
