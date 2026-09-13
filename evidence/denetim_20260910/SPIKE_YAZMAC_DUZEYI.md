# Spike ISS karsilastirmasinin YAZMAC DUZEYINE cikarilmasi
# (12 Eylul 2026)

# 1. ONCEKI DURUM VE ACIK

`scripts/spike_karsilastir.py` yalnizca IKI seyi karsilastiriyordu:

    - her retire edilen buyrugun PC'si
    - makine kodu

Bu, sartname EK-3'un istedigi "TUR ve SIRA" esitligini karsiliyordu.
Ama bir acik birakiyordu:

**Cekirdegin SONUCLARI dogru hesaplayip hesaplamadigi
DOGRULANMIYORDU.**

Somut ornek: ALU'da `add` yerine `sub` baglansaydi, buyruk akisi
(PC dizisi) DEGISMEZDI - cunku dallanma kararlari cogu testte
veriye bagli degildir. Eski karsilastirma bu hatayi GECIRIRDI.

# 2. YAPILAN GENISLETME

## 2.1 Spike tarafi - `scripts/spike_iz_al.py`

Spike zaten `--log-commits` ile kosuluyordu ve her buyruk icin IKI
satir uretiyordu:

    core 0: 0x01000000 (0x1f002117) auipc sp, 0x1f002     <- buyruk
    core 0: 3 0x01000000 (0x1f002117) x2  0x20002000      <- COMMIT

Ikinci satir buyrugun YAZDIGI yazmaci ve DEGERINI verir. Onceki
surum bu satiri YOK SAYIYORDU.

Eklenen: `COMMIT` regex'i ve iki satiri eslestiren durum makinesi.
Yazmaca yazmayan buyruklarda (store, branch) alan bos kalir.

Yeni cikti bicimi (geriye donuk uyumlu):

    "PC BUYRUK"            -> yazmaca yazmayan buyruk
    "PC BUYRUK xN DEGER"   -> yazmac yazmasi olan buyruk

## 2.2 RTL tarafi - `scripts/spike_karsilastir.py`

CV32E40P tracer'i zaten yaziyordu:

    ... 01000000 1f002117  auipc x2, ...  x2=20002000
                                          ^^^^^^^^^^^ yazilan
    ... 0100000c 45450513  addi x10...    x10=0100045c x10:01000008
                                                       ^^^^^^^^^^^^ okunan

`=` yazilan degeri, `:` okunan degeri gosterir. Regex yalniz `=`
eslesir.

## 2.3 Platform kimlik CSR'lari HARIC tutuldu

Ilk kosumda 3 uyusmazlik cikti. Incelendi - ucu de CSR okumasi:

| PC | CSR | Spike | CV32E40P |
|---|---|---:|---:|
| 010002f4 | mvendorid (0xf11) | 0x0 | 0x602 |
| 01000302 | marchid (0xf12) | 0x5 | 0x4 |
| 0100031e | misa (0x301) | 0x40141104 | 0x40001104 |

Bunlar CEKIRDEK KIMLIGIDIR, hesaplama hatasi degil:
  - Spike genel bir RISC-V modeli; CV32E40P OpenHW Group cekirdegi
    kendi vendor/arch kimligini raporlar.
  - misa farki beklenen: Spike `rv32imc` ile kosuldu, CV32E40P'nin
    uzanti bitleri farkli.

Bu bes CSR (mvendorid, marchid, mimpid, mhartid, misa) ayri sayilir
ve **raporda acikca listelenir** - gizlenmez.

Tespit yontemi: makine kodunun ust 12 biti hedef CSR adresidir;
SYSTEM opcode (0x73) ve funct3 != 0 kontrolu ile CSR buyrugu
ayirt edilir.

# 3. OLCULEN SONUC

    Spike ham buyruk : 932
    RTL   ham buyruk : 1727
    hizalama PC      : 0x01000000
    Spike (hizali)   : 927
    RTL   (hizali)   : 927

    karsilastirilan buyruk  : 927
    PC uyusmazligi          : 0
    makine kodu uyusmazligi : 0
    sikistirilmis (beklenen): 432
    --- yazmac duzeyi ---
    yazmac karsilastirilan  : 765
    yazmac NO uyusmazligi   : 0
    yazmac DEGER uyusmazligi: 0
    tek tarafli yazmac bilgisi: 0
    platform kimlik CSR farki : 3 (hata degil, listeli)

**927 buyrukta PC dizisi birebir; 765 buyrukta YAZMAC DEGERI de
birebir.**

# 4. KAPSAM KARSILASTIRMASI

| | Once | Sonra |
|---|---|---|
| PC dizisi | dogrulaniyor | dogrulaniyor |
| Makine kodu | dogrulaniyor | dogrulaniyor |
| **Yazmac numarasi** | **DEGIL** | **765 buyrukta** |
| **Yazmac degeri** | **DEGIL** | **765 buyrukta** |
| Kimlik CSR ayrimi | yok | var, raporlaniyor |

Sartname EK-3 "tur ve sira" diyor; bu genisletme onun OTESINE
gecerek sonuc dogrulugunu da kapsar.

# 5. DURUST DEGERLENDIRME

Yazmac duzeyi karsilastirma **hata bulmadi** - 765 buyrukta sifir
uyusmazlik. Bu, CV32E40P cekirdeginin bu test programinda dogru
hesapladigini gosterir.

Kapsam sinirlari:
  - Test programi `core_test.elf`; 927 buyruk. Tum ISA uzayini
    taramaz.
  - Bellek yazmalari (store) karsilastirilmiyor; yalniz yazmac
    yazmalari. Spike `mem 0x...` alanini da uretiyor, ileride
    eklenebilir.
  - Yuk (load) sonuclari yazmaca yazildigi icin DOLAYLI olarak
    kapsaniyor.

# 6. YENIDEN URETIM

    # 1. RTL izi (regresyon icinde uretilir)
    python scripts/run_regression.py --test cekirdek_izi

    # 2. Spike izi (Spike kurulu makinede)
    python3 scripts/spike_iz_al.py <elf> --cikti build/spike/spike_iz.txt

    # 3. Karsilastirma
    python scripts/spike_karsilastir.py
