# QSPI Master - yazma yolunda iki hata

Tarih  : 22 Agustos 2026
Modul  : `rtl/Cevre_Birimleri/qspi_master.sv`
Bulundu: PP (Page Program) testi ilk kez yazildiginda

---

## Nasil ortaya cikti

Kod kapsama olcumunde `qspi_master` **%58,4 statement** ile bizim en dusuk
kapsamli modulumuzdu. Sebep basitti: testler yalnizca **READ (0x03)**
yolunu kosuyordu. Sartname s.24 su komutlari zorunlu tutuyor ve hepsi
RTL'de gerceklenmisti:

    READ  DOR  QOR  PP  QPP  SE  READ_ID  RDID  RES
    RDSR1  RDSR2  RDCR  WRR  WRDI  WREN  CLSR  RESET

Yazma ve silme yollari **hic uyarilmamisti**. Flash modeli de yalnizca
READ destekliyordu, yani test yazilamiyordu.

Model genisletildi (WREN/WRDI/RDSR1/RDID/PP/SE/QOR) ve ilk PP testi
kosuldugunda hata gorundu:

    yazilan  : 0x12345678
    geri okunan: 0x3C1A2B3C

---

## HATA 1 - ilk veri biti bir SCK cevrimi gec cikiyordu

### Belirti

Baytlar bir bit saga kaymis geliyordu:

    0x78 -> 0x3C      0x56 -> 0x2B      0x34 -> 0x1A

### Sebep

`SEND_ADDR` cikis surucusunu **her cevrim** guncelliyor:

    SEND_ADDR: begin
        io_oe     <= 1'b1;
        io_out[0] <= shift_out[7];      // kenar kontrolunun DISINDA
        ...
        if (sck_edge_fall) begin ... end

`WRITE_DATA` ise yalnizca kenarda:

    WRITE_DATA: begin
        io_oe  <= 1'b1;
        if (sck_edge_fall) begin
            case (ccr_data_mode)
                2'b01: begin
                    io_out[0] <= shift_out[7];   // kenar kontrolunun ICINDE
                    ...

Sonuc: `WRITE_DATA`'ya girildigi cevrimde `io0` hala bayat **ADRES**
bitini tasiyor. Ilk veri biti bir SCK cevrimi gec cikiyor ve flash bir
bit kaymis veri yaziyor.

### Neden okuma testleri bunu goremezdi

Butun okuma testleri **adres 0** kullaniyor. Bir bit kaymis sifir yine
sifirdir. Adres fazi da dogru hizalanmis gorunuyordu - 4-bayt testi
adres 8'den dogru kelimeyi okuyabiliyordu, cunku kayma yalnizca
adres -> VERI gecisinde olusuyor.

### Duzeltme

Cikis surucusu kenar kontrolunun disina alindi, `SEND_ADDR` ile ayni
bicime getirildi:

    unique case (ccr_data_mode)
        2'b10:   io_out[1:0] <= shift_out[7:6];
        2'b11:   io_out[3:0] <= shift_out[7:4];
        default: io_out[0]   <= shift_out[7];
    endcase

---

## HATA 2 - her kelimenin dorduncu bayti hic gonderilmiyordu

### Belirti

4 baytlik PP'de son bayt, **ilk baytin tekrariydi**. Flash sunlari aldi:

    0x3C  0x2B  0x1A  0x3C
                      ^^^^ 0x12 olmaliydi, 0x78 tekrarlandi

### Sebep

    if (tx_byte_idx == 2'd3) begin
        if (!tx_empty) begin
            tx_word   <= tx_fifo[...];       // yeni kelime cek
            tx_rd_ptr <= tx_rd_ptr + 1;
        end
        tx_byte_idx <= 2'd0;
        shift_out   <= tx_word[7:0];         // ESKI kelimenin 1. bayti
    end else begin
        case (tx_byte_idx)
            2'd0: shift_out <= tx_word[7:0];
            2'd1: shift_out <= tx_word[15:8];
            2'd2: shift_out <= tx_word[23:16];
            2'd3: shift_out <= tx_word[31:24];   // ULASILAMAZ
        endcase
        tx_byte_idx <= tx_byte_idx + 1;
    end

`tx_byte_idx == 3` durumu her zaman ilk dala giriyor, dolayisiyla
`case` icindeki `2'd3` kolu **hicbir zaman calismiyor**. Yani
`tx_word[31:24]` hic gonderilmiyor.

Bu, 4 bayttan uzun her yazmada veriyi bozar: 256 baytlik bir sayfa
programlamada 64 baytin tamami yanlis olur.

### Duzeltme

Once bayti yukle, SONRA bir sonraki icin kelime cek:

    case (tx_byte_idx)
        2'd0: shift_out <= tx_word[7:0];
        2'd1: shift_out <= tx_word[15:8];
        2'd2: shift_out <= tx_word[23:16];
        2'd3: shift_out <= tx_word[31:24];
    endcase

    if (tx_byte_idx == 2'd3) begin
        if (!tx_empty) begin
            tx_word   <= tx_fifo[...];
            tx_rd_ptr <= tx_rd_ptr + 1;
        end
        tx_byte_idx <= 2'd0;
    end else begin
        tx_byte_idx <= tx_byte_idx + 1;
    end

`shift_out <= tx_word[31:24]` ESKI `tx_word`'u kullanir (bloklamayan
atama), yeni kelime bir sonraki cevrimde gecerli olur - dogru sira.

---

## Etki degerlendirmesi

**Boot yolu etkilenmemisti.** Yukleyici yalnizca READ kullanir; iki hata
da yalnizca YAZMA yolundadir. Bu yuzden sistem testleri gecmeye devam
ediyordu.

**Ama sartname QSPI Master'in PP ve QPP desteklemesini zorunlu tutuyor**
(s.24, "256 baytlik sayfa yazma ve sayfa okumayi destekleyecektir").
Jüri bir yazma senaryosu isteseydi tasarim **yanlis veri yazacakti**.

---

## Dogrulama

`rtl/Cevre_Birimleri/tb_qspi_mock.sv` 6 -> **16 denetime** cikti:

| Denetim | Kapsanan |
|---|---|
| READ x1, 3 bayt adres | temel okuma |
| READ x1, 4 bayt adres | 4-bayt adresleme modu |
| RDID | uretici kimligi |
| WREN -> RDSR1.WEL = 1 | yazma etkinlestirme |
| WRDI -> RDSR1.WEL = 0 | yazma devre disi |
| QOR x4 (2 kelime) | **dortlu hatli okuma** |
| SE -> okuma 0xFF | sektor silme |
| PP -> geri okuma | **sayfa programlama** |
| WEL yokken PP | yazma korumasi |

Kapsama olcumu tekrarlandiginda `qspi_master` istatistigi bu belgeye
eklenecektir.

Ilgili kaynak: `tb/spi_flash_model.sv` (model genisletildi).
