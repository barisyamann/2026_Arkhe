# Hata enjeksiyonu: testler gercekten hata yakaliyor mu?
# (12 Eylul 2026)

# 1. NEDEN YAPILDI

Regresyonda 28/28 test geciyordu. Ama bu tek basina "testler iyi"
demek DEGILDIR - hicbir sey denetlemeyen bir test de gecer.

Tek kanit yolu: RTL'e KASITLI hata sokup ilgili testin KIRMIZIYA
dondugunu gostermek. Donmuyorsa o test dekoratiftir.

Arac: `scripts/hata_enjeksiyon.py`
  - hedef dosyayi yedekler
  - tek satirlik GERCEKCI bir hata uygular
  - ilgili testi kosar
  - dosyayi HER DURUMDA geri yukler (try/finally)

# 2. ILK KOSUM: 4 MUTASYON, 2'SI KACIRILDI

| Mutasyon | Test | Sonuc |
|---|---|---|
| wstrb_bit | wstrb_kismi_yazma | **[OK] yakalandi** |
| sram_w_yakalama | sram_w_yakalama | **[OK] yakalandi** |
| qspi_presc_bit | qspi_presc_sinir | **[HATA] KACIRILDI** |
| i2c_bolen | i2c | **[HATA] KACIRILDI** |

Iki gercek bosluk bulundu.

# 3. BOSLUK 1: QSPI TESTI DUT'U HIC ORNEKLEMIYORDU

## Tespit

`tb_qspi_presc_sinir.sv` kendi `beklenen_tam()` fonksiyonunu
dogruluyordu. Regresyon kaydinda RTL dosyasi bile yoktu:

    kaynak=[TB/"tb_qspi_presc_sinir.sv"]      <- qspi_master.sv YOK

Yani RTL'de `sck_tam_periyot` 7 bitten 6 bite dusurulse bile test
GECERDI. Bu bir **tautoloji** - test kendi formulunu test ediyordu.

## Cozum: tb_qspi_sck_olcum.sv (5 denetim)

Gercek `qspi_master` modulunu ORNEKLER, CCR'a prescaler yazar,
islem baslatir ve URETILEN SCK KENARLARINI SAYAR.

Olculen:

    presc=0  -> 200 SCK kenar   (en hizli mod, sck = ~clk)
    presc=1  ->  32 SCK kenar
    presc=62 ->  32 SCK kenar
    presc=63 ->  32 SCK kenar   <- ASIL SINIR, tasma YOK

## Test yazarken yapilan olcum hatasi

Ilk surum presc=0 icin 0 kenar raporladi. Sebep RTL degil, OLCUM:

    assign qspi_sck = sck_en ? (presc_sifir ? ~clk : sck_int) : 1'b0;

presc=0'da SCK dogrudan `~clk`. Yalniz posedge'de orneklenirse
`~clk` her zaman DUSUK gorunur. Cozum: her iki clk kenarinda
ornekleme.

# 4. BOSLUK 2: I2C TESTI SCL FREKANSINI OLCMUYORDU

## Tespit

`i2c_peripheral_tb.sv` yazmac okuma/yazma ve ACK akisini
dogruluyordu ama SCL'in FREKANSINI hic olcmuyordu. Bolen bir
eksik olsa test yine gecerdi.

Bu onemli, cunku sartname EK-2 acikca sunu istiyor:
  "SCL saat frekansi 400 kHz sabit hizinda olacaktir"

## Cozum: tb_i2c_scl_periyot.sv (4 denetim)

Gercek `i2c_peripheral` modulunu ornekler, islem baslatir ve
URETILEN SCL DARBELERININ SURESINI simulasyon zamaniyla OLCER.

Olculen (50 MHz sistem saati):

    toplanan yukselen kenar : 10
    olculen periyot sayisi  : 9
    ortalama periyot        : 2500,0 ns
    en kucuk / en buyuk     : 2500,0 / 2500,0 ns
    karsilik gelen frekans  : 400.000,0 Hz

Tam hedefte, sifir jitter.

## Tolerans duzeltmesi - ikinci bir bulgu

Ilk surumde tolerans %2 idi ve mutasyonu YINE kacirdi. Olculdu:

    normal        PERIYOT=125  ->  2500,0 ns  ->  400.000,0 Hz
    mutasyon (-1) PERIYOT=124  ->  2480,0 ns  ->  403.225,8 Hz

Sapma %0,8 - %2 toleransin altinda kaliyordu.

Tolerans %0,5'e cekildi. Gerekce: tasarim tam 400.000,0 Hz
uretiyor (50 MHz / 125 tam bolunur) ve sartname "SABIT" diyor;
gevsek tolerans gerekcesizdir.

Bu, hata enjeksiyonunun ikinci kazanimi: yalniz eksik testi degil,
GEVSEK ESIGI de ortaya cikardi.

# 5. SON KOSUM: 4/4 YAKALANDI

    MUTASYON : wstrb_bit        -> [OK] test hatayi YAKALADI
    MUTASYON : sram_w_yakalama  -> [OK] test hatayi YAKALADI
    MUTASYON : qspi_presc_bit   -> [OK] test hatayi YAKALADI
    MUTASYON : i2c_bolen        -> [OK] test hatayi YAKALADI

    yakalanan : 4
    KACIRILAN : 0
    atlanan   : 0

# 6. RTL BUTUNLUGU

Kampanya oncesi ve sonrasi 57 RTL dosyasinin SHA-256 manifesti
karsilastirildi:

    57/57 dosya BIREBIR AYNI

Mutasyonlar try/finally icinde uygulanir; kesinti olsa bile
dosya geri yuklenir.

# 7. EKLENEN TESTLER

| Test | Denetim | Kapattigi bosluk |
|---|---:|---|
| `tb_qspi_sck_olcum` | 5 | QSPI testi DUT'u ornekleMIYORDU |
| `tb_i2c_scl_periyot` | 4 | I2C testi SCL frekansini olcMUYORDU |

Regresyon: 28/28 -> **30/30 test**

# 8. DURUST DEGERLENDIRME

Bu calisma iki testin dekoratif oldugunu ORTAYA CIKARDI. Ikisi de
geciyordu ama ilgili hatalari yakalamiyordu:
  - biri DUT'u hic orneklemiyordu
  - digeri olcmesi gereken buyuklugu olcmuyordu

Sartname EK-3 testlerin "kendi kendini kontrol eden" olmasini
istiyor. Bu kampanya o iddiayi OLCTU ve iki yerde yanlis cikti;
ikisi de duzeltildi.

Kapsam siniri: 4 mutasyon tum RTL'i temsil etmez. Genisletilebilir -
her yeni kritik duzeltme icin bir mutasyon eklenmelidir.

# 9. YENIDEN URETIM

    python scripts/hata_enjeksiyon.py --liste
    python scripts/hata_enjeksiyon.py
    python scripts/rtl_manifest.py dogrula rtl_manifest.txt
