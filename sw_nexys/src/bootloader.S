# =============================================================================
# Arkhe SoC - Iki Asamali Boot: 1. Asama Yukleyici
#
# Sartname s.16: "Bootloader kodu kucuk bir ROM icerisinde degistirilemeyecek
# bir kod parcasi olarak bulunacaktir. Bu kod parcasi QSPI Master arayuzu
# uzerinden flash bellekten calistirilacak olan programi okuyacak ve buyruk
# bellegine yazacaktir. Sonrasinda yurutmeyi buyruk bellegine devredecektir."
#
# Bu kod Boot ROM'da (0x00000000) calisir, uygulamayi QSPI flash'tan okuyup
# I-RAM'e (0x01000000) yazar ve oraya atlar.
# =============================================================================

.section .text.start
.global _start

.equ QSPI_BASE,       0x40050000
.equ QSPI_CCR,        0x00
.equ QSPI_ADR,        0x04
.equ QSPI_DR,         0x08
.equ QSPI_STA,        0x0C

.equ IRAM_BASE,       0x01000000

# -----------------------------------------------------------------------------
# UYGULAMANIN FLASH ICINDEKI YERI  (F2 karari, 23 Agustos 2026)
#
# Kart ustu Spansion S25FL128S'in BASINDA FPGA BITSTREAM'I DURUR.
# XC7A100T bitstream'i yaklasik 3,7 MB'dir. Uygulamayi adres 0'dan
# okumak, bitstream baytlarini buyruk sanip calistirmak demektir.
#
# Bu yuzden uygulama 8 MB sinirina konuluyor: bitstream'in cok
# uzerinde, 16 MB'lik flash'in ortasinda.
#
# Uygulamayi flash'a yazarken AYNI ofset kullanilmalidir:
#     Vivado > Add Configuration Memory Device > s25fl128sxxxxxx0-spi-x1_x2_x4
#     app.bin dosyasi 0x800000 ofsetine programlanir.
#
# 3 baytlik adresleme 16 MB'i tamamen kapsar (0xFFFFFF), bu yuzden
# CCR[24] 4-bayt kipi burada GEREKMEZ.
# -----------------------------------------------------------------------------
.equ APP_FLASH_OFS,   0x800000

# QSPI islem basina en fazla 256 bayt okunabilir (CCR[23:16] 8 bit).
# 8 kB uygulama icin 32 islem gerekir.
.equ CHUNK_COUNT,     8
.equ WORDS_PER_CHUNK, 64
.equ CHUNK_BYTES,     256

# CCR degeri:
#   bit 31    = 1     islemi baslat (ve durum bayraklarini temizle)
#   [23:16]   = 0xFF  veri boyutu - 1  -> 256 bayt
#   bit 10    = 0     okuma
#   [9:8]     = 00    tek hat modu
#   [15:11]   = 0     dummy cevrim yok (CMD_READ 0x03 icin gerekmez)
#   [7:0]     = 0x03  CMD_READ
# [30:25] = 4 -> prescaler. sck yarim periyodu 5 cevrim olur.
# Prescaler 0 iken sck her cevrim degisiyor ve master'in yazmacli
# kenar tespiti (sck_edge_fall bir cevrim gecikmeli) veriyi
# zamaninda guncelleyemiyor; flash bir bit kaymis okuyor.
.equ CCR_READ_256,    0x88FF0103

# =============================================================================
#  NPU FC AGIRLIKLARININ FLASH'TAN TCM'E YUKLENMESI  (23 Agustos 2026)
#
#  NEDEN GEREKLI
#
#    FC agirliklari artik kombinasyonel ROM'da DEGIL, NPU'nun TCM/SRAM'inde
#    (bkz. npu_compute_engine.sv, FC_WEIGHT_BASE = 3584). Bu degisiklik
#    ASIC fiziksel akisini acti - 16 kB'lik ROM netlistten kalkti.
#
#    Ama SRAM UCUCUDUR. Uretilmis cipte guc verildiginde TCM BOSTUR.
#    Simulasyonda testbench $readmemh ile dolduruyor; gercek cipte bunu
#    yapacak kimse yok. Agirliklarin kalici kaynagi flash olmali ve
#    acilista TCM'e kopyalanmalidir.
#
#    Yuklenmezse motor sifir agirlikla kosar: fc_acc yalnizca bias'a esit
#    olur ve NPU HER SESE AYNI CEVABI verir. Sessiz, yaniltici bir hata.
#
#  FLASH YERLESIMI
#
#    0x000000   FPGA bitstream (yalnizca FPGA'de; ASIC'te yok)
#    0x800000   uygulama            8 kB ayrildi
#    0x802000   FC agirliklari     16 kB (4000 x 32-bit)
#
#  BLOK BOYUTU SECIMI
#
#    4000 kelime = 16.000 bayt. 256'ya TAM BOLUNMEZ (62,5 blok).
#    Bu yuzden 50 kelimelik (200 bayt) bloklar kullaniliyor:
#        80 blok x 200 bayt = 16.000 bayt, tam.
#    CCR boyut alani = 200 - 1 = 199 = 0xC7.
# =============================================================================
.equ WEIGHT_FLASH_OFS,  0x802000
.equ NPU_TCM_BASE,      0x20010000
# FC agirliklari TCM'de 3584. kelimeden baslar -> bayt ofseti 3584*4 = 0x3800
.equ WEIGHT_TCM_ADDR,   0x20013800
.equ W_CHUNK_COUNT,     80
.equ W_WORDS_PER_CHUNK, 50
.equ W_CHUNK_BYTES,     200
.equ CCR_READ_200,      0x88C70103

# NPU kontrol yazmaci - agirliklar hazir bayragi (npu_csr.sv REG_CTRL bit 4)
.equ NPU_CSR_CTRL,      0x40060000
.equ NPU_WEIGHTS_READY, 0x10


_start:
    li   t0, QSPI_BASE          # QSPI taban adresi
    li   t1, IRAM_BASE          # hedef: I-RAM yazma isaretcisi
    li   t2, APP_FLASH_OFS      # kaynak: flash adresi (bitstream'in USTUNDE)
    li   t3, CHUNK_COUNT        # kalan blok sayisi

chunk_loop:
    sw   t2, QSPI_ADR(t0)       # okunacak flash adresini yaz
    li   t5, CCR_READ_256
    sw   t5, QSPI_CCR(t0)       # islemi baslat

    li   t4, WORDS_PER_CHUNK    # bu blokta okunacak kelime sayisi

word_loop:
    # RX FIFO'da veri olusana kadar bekle (STA bit 5 = rx_empty)
wait_data:
    lw   t5, QSPI_STA(t0)
    andi t5, t5, 0x20
    bnez t5, wait_data

    lw   t5, QSPI_DR(t0)        # FIFO'dan bir kelime cek
    sw   t5, 0(t1)              # I-RAM'e yaz
    addi t1, t1, 4
    addi t4, t4, -1
    bnez t4, word_loop

    addi t2, t2, CHUNK_BYTES    # sonraki flash blogu
    addi t3, t3, -1
    bnez t3, chunk_loop

    # -------------------------------------------------------------------------
    # FC agirliklarini flash'tan NPU TCM'ine kopyala
    #
    # Uygulamaya atlamadan ONCE yapilir: uygulama basladiginda NPU
    # kullanilabilir durumda olmalidir.
    # -------------------------------------------------------------------------
    li   t0, QSPI_BASE
    li   t1, WEIGHT_TCM_ADDR    # hedef: TCM icindeki agirlik bolgesi
    li   t2, WEIGHT_FLASH_OFS   # kaynak: flash'taki agirlik bolgesi
    li   t3, W_CHUNK_COUNT

w_chunk_loop:
    sw   t2, QSPI_ADR(t0)
    li   t5, CCR_READ_200
    sw   t5, QSPI_CCR(t0)

    li   t4, W_WORDS_PER_CHUNK

w_word_loop:
w_wait_data:
    lw   t5, QSPI_STA(t0)
    andi t5, t5, 0x20           # STA bit 5 = rx_empty
    bnez t5, w_wait_data

    lw   t5, QSPI_DR(t0)
    sw   t5, 0(t1)              # TCM'e yaz
    addi t1, t1, 4
    addi t4, t4, -1
    bnez t4, w_word_loop

    addi t2, t2, W_CHUNK_BYTES
    addi t3, t3, -1
    bnez t3, w_chunk_loop

    # -------------------------------------------------------------------------
    # Agirliklar yerinde: NPU'ya haber ver.
    #
    # Bu bayrak kurulmadan npu_csr START'i KABUL ETMEZ (start_o kapisi).
    # Boylece "agirliksiz kosma" sessiz bir yanlis sonuc yerine acik bir
    # davranisa donusur.
    # -------------------------------------------------------------------------
    li   t0, NPU_CSR_CTRL
    li   t1, NPU_WEIGHTS_READY
    sw   t1, 0(t0)

    # Yurutmeyi I-RAM'e devret
    li   t0, IRAM_BASE
    jr   t0
