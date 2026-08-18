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


_start:
    li   t0, QSPI_BASE          # QSPI taban adresi
    li   t1, IRAM_BASE          # hedef: I-RAM yazma isaretcisi
    li   t2, 0                  # kaynak: flash adresi
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

    # Yurutmeyi I-RAM'e devret
    li   t0, IRAM_BASE
    jr   t0
