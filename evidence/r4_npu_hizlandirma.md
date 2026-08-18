# R4 - NPU Cikarim Hizlandirmasi

Tarih: 18 Agustos 2026

## Bulgu

Denetim R4: "NPU cikarim suresi mimari olarak 24x iyilestirilebilir."
Tek cikarim 992.083 cevrim = 50 MHz'de 19,84 ms.

Sartname hizlandirici basarimini "veri/saat cevrimi" ve "islenmis
veri/saniye" uzerinden degerlendiriyor ve yazilim gerceklemesine kiyasla
hizlanma bekliyor - yani bu bir suslemedir degil, puanlanan kalem.

## Onemli ayrim

Bugune kadar yapilan boru hatti calismasi ZAMANLAMA icindi (kombinasyonel
zinciri bolup WNS'i -14,2 ns'den +2,1 ns'ye cikarmak). O calisma cevrim
sayisini aslinda %2,9 ARTIRMISTI.

R4 ise VERIM optimizasyonudur; bugune kadar hic dokunulmamisti.

## Cikis noktasi - dongu maliyeti

    25 (t_out) x 20 (f_out) x 8 (kanal) x 80 (tap) x 3 cevrim = 960.000
    + kanal basina 8 cevrim (requant + FC)                    =  32.000
                                                               ---------
                                                                 992.000   (olculen 992.083)

## Asama 1 - Kanal paylasimi

Girdi adresi:

    t_in = t_out*2 - 4 + kh
    f_in = f_out*2 - 3 + kw

d_out ADRESE GIRMIYOR. Yani sekiz kanalin hepsi tam olarak ayni girdi
piksellerini okuyordu; ayni 10x8 pencere sekiz kez taraniyordu.

Yeni duzen:

    for kh,kw:            piksel BIR KEZ okunur, sekiz kanala paralel
                          dagitilir (her kanalin kendi biriktiricisi)
    for d_out 0..7:       requant + FC

dw_weights indisleri d icin ardisiktir (kh*64 + kw*8 + d), yani sekiz
agirlik bitisik bir blokta duruyor - paralel okuma dogal.

    Sonuc: 992.083 -> 152.083 cevrim   (6,52x)
           19,84 ms -> 3,04 ms

## Asama 2 - Okuma boru hatti

TCM okuma cikisi KAYITLIDIR: adres verildikten bir cevrim sonra veri
gecerli olur. Eski FSM bunu uc cevrime yayiyordu:

    CONV_READ_REQ -> CONV_READ_WAIT -> CONV_MAC

Iki asamali boru hattina cevrildi:

    kh / kw          bu cevrim ADRESI verilen tap   (okuma isaretcisi)
    mac_kh / mac_kw  bu cevrim VERISI hazir olan tap (bir cevrim gecikmeli)

Her cevrimde hem yeni bir okuma baslatilir hem onceki okumanin verisi
islenir.

### Dikkat edilen iki nokta

1. in_bounds ve byte_offset de gecikmeli kopyalandi (mac_ib, mac_bo).
   Bunlar TUKETILEN tap'a ait olmali, adresi verilene degil. Karistirilsaydi
   kenar piksellerinde yanlis padding uygulanir ve sonuc SESSIZCE bozulurdu.

2. Cikis kosulu mac_* uzerinden kontrol edilir. Son tap'in adresi
   verildikten sonra okuma isaretcisi kh=10'a tasar; o cevrimde tuketim
   surer ama yeni okuma baslatilmamalidir - bellek kontroluna kh <= 9
   kosulu eklendi.

    Sonuc: 152.083 -> 72.583 cevrim   (2,10x)
           3,04 ms -> 1,45 ms

## Toplam

    Cevrim  : 992.083 -> 72.583      13,67x
    Sure    : 19,84 ms -> 1,45 ms
    Verim   : 50,4 -> 689 cikarim/saniye
    Veri    : 1960 bayt / 72.583 cevrim = 0,027 bayt/cevrim

Sistem testi: 61,08 ms -> 42,69 ms, 0 hata.

## Dogrulama - bit birebir ozdeslik

Uc kosumun ucunde de sonuclar DEGISMEDI:

    fc_acc [0]=-985885  [1]=242268  [2]=240758  [3]=387226
    probs  [0]=0  [1]=1050  [2]=1050  [3]=1995

Bu tesadufi degil, tasarim geregi: kanallar birbirinden bagimsiz ve kanal
ICI toplama sirasi (kh, kw duzeni) hic degismedi. Boru hatti yalnizca
zamanlamayi degistirdi, aritmetigi degil.

Ozdeslik, optimizasyonun dogrulugunun dogrudan kanitidir - tek bit fark
hizalama hatasina isaret ederdi.

## Kalan darbogaz

    konvolusyon    : 40.500 cevrim  (%56)   25 x 20 x 81
    requant + FC   : 32.000 cevrim  (%44)   25 x 20 x 8 kanal x 8 cevrim

Konvolusyon artik tap basina 1 cevrimde; daha fazla kazanc requant/FC
zincirini boru hattina almayi gerektirir. Azalan getiri bolgesi, su an
onerilmiyor.

## Acik

Bu degisiklikler sentezlenmedi. Sekiz paralel carpici DSP sayisini
artiracak (9 -> ~16 bekleniyor) ve yeni bir kritik yol yaratabilir.
FPGA'de 240 DSP var, kaynak sorunu beklenmiyor; zamanlama olculmeli.
