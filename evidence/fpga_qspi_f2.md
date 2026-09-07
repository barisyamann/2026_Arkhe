# F2 - QSPI kart ustu flash baglantisi

Tarih : 23 Agustos 2026
Karar : **F2** - harici Pmod modulu ALINMADI, Nexys A7'nin kendi
        16 MB Spansion S25FL128S QSPI flash'i kullaniliyor.

---

## Neden F2

Sartname QSPI Master'in bir NOR flash'a baglanmasini istiyor. Iki secenek
vardi:

| | Yol | Maliyet | Risk |
|---|---|---|---|
| F1 | Harici Pmod SF3 modulu | satin alma + tedarik suresi | Pmod pinleri, ek XDC |
| **F2** | **Kart ustu flash** | **yok** | yapilandirma arayuzu paylasimi |

Teslime 8 gun kala tedarik riski almanin anlami yoktu. F2 secildi.

---

## IKI SESSIZ TUZAK

Bu iki nokta atlanirsa **sentez hata vermez, bitstream uretilir, tasarim
kurulur - ama flash calismaz.** Ikisi de FPGA'ye kadar gorunmez.

### 1. Saat pini STARTUPE2'den gecmek zorunda

7-serisi Artix'te flash saati (CCLK) **normal bir kullanici pini
degildir.** Yapilandirma devresine aittir ve XDC ile pakete atanamaz.
Kullanici mantiginin flash saatini surebilmesinin TEK yolu `STARTUPE2`
ilkel blogunun `USRCCLKO` girisidir.

    STARTUPE2 #(.PROG_USR("FALSE"), .SIM_CCLK_FREQ(0.0)) u_startupe2 (
        ...
        .USRCCLKO  (qspi_sck_w),   // flash saati buradan cikar
        .USRCCLKTS (1'b0),         // 0 = surucu etkin (ters mantik)
        ...
    );

Bkz. `rtl/Memory/nexys_top.sv`.

### 2. Uygulama bitstream'in uzerinde olmali

Kart ustu flash'in **basinda FPGA bitstream'i durur.** XC7A100T icin
yaklasik 3,7 MB. Yukleyici adres 0'dan okursa bitstream baytlarini
buyruk sanip calistirir.

    .equ APP_FLASH_OFS,   0x800000      # 8 MB - bitstream'in cok ustunde

3 baytlik adresleme 16 MB'i tamamen kapsar (0xFFFFFF), bu yuzden
CCR[24] 4-bayt kipi burada **gerekmez**.

Bkz. `sw_nexys/src/bootloader.S`.

---

## Pin atamalari

`rtl/nexys4ddr.xdc`:

| Sinyal | Pin |
|---|---|
| `QSPI_CS_N` | L13 |
| `QSPI_DQ[0]` | K17 |
| `QSPI_DQ[1]` | K18 |
| `QSPI_DQ[2]` | L14 |
| `QSPI_DQ[3]` | M14 |
| saat | **pin YOK** - STARTUPE2/USRCCLKO |

> **DOGRULANMALI:** Bu pinler Digilent Nexys A7 master XDC'siyle
> karsilastirilmalidir. Yerelde kart dosyasi bulunamadi. Yanlissa
> tasarim kurulur ama flash sessizce cevap vermez.

---

## Flash'a programlama yordami

Iki ayri sey programlanir: **bitstream** (adres 0) ve **uygulama**
(adres 0x800000).

### 1. Uygulamayi .bin olarak uret

    python sw_nexys/scripts/build.py

Cikti: `sw_nexys/build/app.bin`

### 2. Bitstream'i flash'a yaz (adres 0)

Vivado > **Open Hardware Manager** > **Add Configuration Memory Device**

    Aygit  : s25fl128sxxxxxx0-spi-x1_x2_x4
    Dosya  : arkhe.bin  (bitstream, .bit'ten .bin uretilmis)
    Adres  : 0x00000000

`.bit` -> `.bin` donusumu icin proje ayarlarinda
`BITSTREAM.GENERAL.COMPRESS` ve `-bin_file` etkin olmalidir.

### 3. Uygulamayi flash'a yaz (adres 0x800000)

Ayni pencerede ikinci bir programlama islemi:

    Dosya  : app.bin
    Adres  : 0x00800000

**Bu ofset `bootloader.S` icindeki `APP_FLASH_OFS` ile AYNI olmalidir.**
Biri degisirse digeri de degismelidir.

### 4. Karti QSPI'den boot edecek sekilde ayarla

Nexys A7 uzerindeki **JP1 jumper'i QSPI konumuna** alinmalidir
(USB/SD degil). Aksi halde kart flash'tan yapilandirilmaz.

---

## Simulasyon ayni ofseti modelliyor

`tb/spi_flash_model.sv` icine `APP_OFS` parametresi eklendi. Imaj yine
dizinin basinda tutulur (8 MB'lik dizi ayirmamak icin); yalnizca **adres
eslemesi** kaydirilir: mantiksal `APP_OFS` -> indeks 0.

    spi_flash_model #(
        .APP_OFS    (32'h0080_0000),
        .INIT_FILE  ("app.hex"),
        .WORD_COUNT (2048)
    ) u_flash ( ... );

Bu sarttir: aksi halde simulasyon, gercek donanimda kosacak olandan
**baska bir adresten** boot etmis olurdu ve ofset hatasi FPGA'ye kadar
gorunmezdi.

---

## Boot ROM imajini yeniden uretmeyi UNUTMA

`bootloader.S` kaynak dosyadir. Boot ROM icerigi **derlenmis**
`rtl/boot/boot.hex`'ten ve ondan uretilen `rtl/boot/boot_rom_pkg.sv`'den
gelir. Kaynagi degistirmek yetmez:

    python sw_nexys/scripts/build.py        # boot.hex'i yeniden uretir
    python scripts/gen_rom_paketleri.py     # boot_rom_pkg.sv'yi yeniler

Bu adim ilk denemede atlandi ve `sistem_gercek_boot` dustu. `sistem`
testi geciyordu cunku o I-RAM'i onyukluyor; hatayi yalnizca gercek boot
zinciri yakaladi.

---

## Dogrulama durumu

| | Durum |
|---|---|
| Regresyon | 13/13 test, 293 denetim - hepsi geciyor |
| `sistem_gercek_boot` | GECTI - gercek iki asamali boot, 0x800000'den |
| `qspi` blok testi | GECTI - 16 denetim, APP_OFS varsayilan 0 ile |
| **FPGA uzerinde** | **HENUZ KOSULMADI** |

Kart uzerinde dogrulama icin: yukaridaki programlama yordami, ardindan
UART'ta `*** ARKHE FPGA TEST ***` ciktisi beklenir.
