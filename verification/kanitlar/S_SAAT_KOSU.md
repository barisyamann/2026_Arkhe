# S_saat kosusu: ASIC saati 43,2 MHz  (11 Eylul 2026)

# 1. AMAC

Sartname EK-2: "SCL saat frekansi 400 kHz sabit hizinda olacaktir".

Cevre birimi bolucileri `soc_top.sv`'de UC YERDE 50 MHz sabit
kodluydu (satir 749, 766, 785). ASIC 43,5 MHz'de calisirsa I2C
347.826 Hz, UART 100.180 baud verirdi - ikisi de kabul edilemez.

Cozum: bolucileri parametreye baglamak ve ASIC saatini 400 kHz'e
TAM BOLUNEN bir degere cekmek.

# 2. NEDEN 43,2 MHz (23,148 ns)

400 kHz'e tam bolunen saatler tarandi:

    P=108 -> 43,200 MHz -> periyot 23,148 ns  <- SECILDI
    P=109 -> 43,600 MHz -> periyot 22,936 ns

43,2 MHz secildi cunku:
  - SCL TAM 400.000,00 Hz (sapma sifir)
  - periyot 23,148 ns; onceki beyan 23 ns'den DAHA GEVSEK,
    yani zamanlama marji artar, azalmaz
  - t_LOW = t_HIGH = 1,250 us (tam simetrik; FPGA'da 1,260/1,240)

# 3. RTL DEGISIKLIGI - SARTNAMEYE UYGUN

`soc_top.sv`'ye tek parametre eklendi:

    module soc_top #(
        parameter int SYS_CLK_HZ = 50_000_000
    ) ( ... );

ve uc ornekleme ona baglandi. `ifdef KULLANILMADI - tasarim
AYRILMADI. Sartname kurali "farkli MHz'lerde calistirabilirsiniz
ama ayni tasarimi istiyoruz" karsilanir: tek RTL, iki parametre
degeri.

Varsayilan 50 MHz oldugu icin FPGA akisi ETKILENMEZ.

# 4. OLCULEN SONUC (tb_i2c_scl_frekans, 9 denetim)

| Hedef | Saat | PERIYOT | SCL | t_LOW | t_HIGH |
|---|---:|---:|---:|---:|---:|
| FPGA | 50,0 MHz | 125 | **400.000,00 Hz** | 1,260 us | 1,240 us |
| ASIC | 43,2 MHz | 108 | **400.000,00 Hz** | 1,250 us | 1,250 us |

Her iki hedefte de sapma SIFIR.

Bozulma kontrolu: i2c, uart, sartname_uart, sartname_uart_stream,
sistem -> 5/5 test, 135 denetim gecti.

# 5. KOSU YAPILANDIRMASI

`config_S_saat.yaml`, `config_K_diyot.yaml`den uretildi.
**Tek fark** (diff ile dogrulandi):

    SYNTH_PARAMETERS: null -> ["SYS_CLK_HZ=43200000"]

CLOCK_PERIOD 14 ns (PnR hedefi) AYNEN korundu; diyot/anten
ayarlari degismedi. Boylece K ile S arasindaki her fark yalnizca
saat parametresinden gelir.

RTL esligi: 57/57 dosya sunucuda birebir dogrulandi.

# 6. PARAMETRENIN UYGULANDIGI KANITLANDI

Sentez netlisti K ile karsilastirildi:

| | K_diyot | S_saat | Yorum |
|---|---:|---:|---|
| u_i2c hucre | 986 | **1028** | bolen 125 -> 108, sayac yapisi degisti |
| u_uart1 hucre | 1330 | **1312** | CPB 434 -> 377, sayac kuculdu |
| toplam std hucre | 102.291 | 102.437 | |

Parametre sentezde FIILEN etkili oldu.

# 7. BEKLENEN SONUC

Imza periyodu 23,148 ns olacak (23 ns yerine). K_diyot 23 ns'de
dokuz kosede pozitifti; daha gevsek periyotta marjin artmasi
beklenir. Kosu bitince dokuz kose olculup K ile karsilastirilacak.

Basarili olursa beyan: **43,2 MHz**, ve I2C sartname isteri
ASIC'te de tam karsilaniyor.

---

# 8. IMZA PERIYODU DUZELTMESI (12 Eylul 2026)

## Bulunan sorun

Kullanici sordu: "uretime hazir bir akis istendigi icin 14 ve 23
yapmamiz gerekmiyor mu".

Inceleme sonucu GERCEK BIR TUTARSIZLIK bulundu:

    final/metrics.json  ->  setup -1,1638 ns, 45 ihlal   (20 ns'e gore)
    README beyani       ->  23,148 ns'de dokuz kose POZITIF

Jüri paketi acip metrics.json'a baktiginda NEGATIF setup gorecekti ve
beyanla celisiyor gorunecekti.

## Kok neden

`constraints/signoff_50mhz_hedef.sdc` sunu yapiyordu:

    if {[info exists ::env(SIGNOFF_CLOCK_PERIOD)]} {
        set clk_period $::env(SIGNOFF_CLOCK_PERIOD)
    } else {
        set clk_period 20.0        <-- VARSAYILAN
    }

20,0 ns hicbir zaman beyan edilen deger DEGILDI; sadece SDC'nin
varsayilaniydi. Akis her imza adiminda bunu kullaniyordu.

## Denenen ve BASARISIZ olan yol

    librelane ... -c SIGNOFF_CLOCK_PERIOD=23.148

Ise YARAMADI. Sebep olculdu: `SIGNOFF_CLOCK_PERIOD` LibreLane'in
tanidigi bir yapilandirma degiskeni DEGIL - bizim SDC dosyamizin
kendi `::env` okumasi. LibreLane tanimadigi anahtari sessizce yok
saydi ve adim yine 20 ns ile kostu (adim 78, setup yine -1,1638).

## Uygulanan cozum

SDC'nin VARSAYILANI beyan edilen degere esitlendi:

    set clk_period 23.148

Gerekcesi dosyaya yorum olarak yazildi. Sonra imza zinciri
`-F OpenROAD.STAPostPNR` ile yeniden kosuldu (adim 80-101).

## Sonuc - OLCULDU

| | Once (20 ns) | Sonra (23,148 ns) |
|---|---:|---:|
| setup WNS | -1,1638 | **+0,4101** |
| setup ihlal | 45 | **0** |
| hold WNS | +0,1857 | +0,1857 |
| hold ihlal | 0 | **0** |

Tekrar kosulan denetimler (hepsi temiz):

    KLayout DRC ......... 0
    LVS ................. Circuits match uniquely
    XOR ................. 0
    Anten net/pin ....... 0/0
    Magic DRC ........... 7.658 (makro kaynakli, ucuncu kez ayni)

Dokuz kose olcumu netlist degismedigi icin AYNI kaldi:
max_ss setup +0,6718 / hold +0,2857.

## Neden onemli

Artik paketin KENDI CIKTISI beyani destekliyor. Juri hangi dosyaya
bakarsa baksin ayni periyodu gorur:

    results/metrics/metrics.json   -> 23,148 ns, setup +0,4101, 0 ihlal
    results/sdc/signoff.sdc        -> set clk_period 23.148
    asic/README.md §11             -> 23,148 ns (43,2 MHz), 9/9 pozitif

## Not: kosu sonunda "ERROR" mesaji

Akis su mesajla bitti:

    One or more deferred errors were encountered:
      7658 Magic DRC errors found.
      Max Cap violations found in the following corners: ...

Bu bir COKME DEGILDIR - akis tum adimlari tamamladi, sonunda BILINEN
ihlalleri toplu raporladi. Ikisi de daha once belgelendi:
  - Magic DRC 7.658: makro kaynakli nwell.4 (MAGIC_DRC_KOK_NEDEN.md)
  - Max Cap: makro Liberty limiti 0,0276 pF (LIBERTY_EK_ANALIZ.md)

K_diyot da ayni sekilde bitmisti. `final/` dizini eksiksiz uretildi.
