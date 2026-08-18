# G07 - Veri Yolu Hata Kesmesi (R8)

Tarih: 18 Agustos 2026

## Bulgu

obi_to_axi_simple, AXI yanit kodunu (bresp/rresp) hic okumuyordu.
AXI4-Lite'ta her islem OKAY (00), SLVERR (10) veya DECERR (11) doner.
Bir kole "bu erisim hatali" dese bile CPU normal tamamlanma goruyordu:

  - haritalanmamis adrese yazma sessizce yutuluyor
  - hatali okuma cop veriyi gercek veri gibi donduruyor

Belirtinin kaynaktan uzakta ciktigi, hata ayiklamasi en zor siniftan
bir kusur.

## Kurulan yol

    AXI kolesi SLVERR
      -> OBI->AXI koprusu (bir cevrimlik DARBE + adres)
      -> jtag_debug (yapiskan yakalama)
      -> irq_vector[20]
      -> CV32E40P -> ISR

Her iki kopru de (buyruk ve veri) bildiriyor.

### Neden kesme

Ilk onerim "gozlemlenebilir yapalim, kesme eklemeyelim" idi. Bu yanlisti:
hatayi yalnizca testbench gorebiliyorsa kart uzerinde hicbir ise yaramaz.
Yazilimin haberi olmali.

### Neden yeni AXI kolesi degil

axi_lite_interconnect.sv 607 satir elle acilmis kod ve 13 numarasi
"kole yok" isareti olarak kullaniliyor; 14. kole ~60 noktaya dokunmak
demekti. Yazmaclar jtag_debug'a kondu - veri yolu hatasi zaten bir
teshis olayi ve o blokta bos ofset vardi.

### Yazmaclar

    0x4008_0014  FAULT_ST    [0] hata var, [1] buyruk kopru, [2] veri kopru
    0x4008_0018  FAULT_ADDR  hatayi doguran adres
    0x4008_001C  FAULT_CLR   1 yazilinca temizlenir

Iki tasarim karari:

  - ILK hata saklanir, sonrakiler uzerine yazmaz. Ikincil hatalar
    genellikle birincinin sonucudur; asil bilgi ilk adrestir.
  - Temizleme ile yeni hata ayni cevrimde cakisirsa HATA kazanir,
    boylece hicbir hata kaybolmaz.

### Sonsuz kesme dongusu neden imkansiz

npu_csr'da yapiskan bayrak seviye kaynakliydi: yazilim temizliyor,
sonraki cevrimde done_i onu geri getiriyordu. Burada kaynak DARBE
oldugu icin o durum olusamaz. Tesadüf degil, o hatadan sonra bilerek
boyle tasarlandi.

## Kasitli hata testi

CPU acilista Boot ROM'a (0x100) yazmaya calisiyor; ROM salt-okunur ve
SLVERR donuyor. Bu yanit R9'da eklenmisti ama bugune kadar hic
tetiklenmemisti - ilk kez gercekten sinandi.

Hic tetiklenmeyen bir onlem, calistigi kanitlanmamis onlemdir. Bu
yuzden "hata olmadigini dogrulayan" degil, HATAYI URETEN bir test
yazildi. Testbench su satiri birebir ariyor:

    Bus fault @ 0x00000100 ST=0x05

ST = 0x05 -> bit0 (hata var) + bit2 (veri koprusu).

## Mekanizma ilk dakikada eski bir hata yakaladi

Ilk kosumda beklenmeyen iki satir cikti:

    [IRQ] Bus fault @ 0x40010008
    [IRQ] Bus fault @ 0x4001001C

0x4001_0000 = TIMER_BASE. Ofset 0x08 = TIM_CLR, 0x1C = TIM_EVC.

timer_peripheral.sv'de bu ikisi yan etkili yazma yazmaclaridir; asil
islerini ayri always_ff bloklari yapar. Ancak yanit ureten case onlari
listelemiyordu ve default dalina dusup SLVERR donuyorlardi.

Islev DOGRU calisiyordu, yalnizca yanit kodu yanlisti. Kimse yaniti
okumadigi icin aylarca gorunmedi. Duzeltme: ikisi de gecerli adres
olarak eklendi.

Bu, R8'i kapatmanin en iyi gerekcesi: teshis araci kuruldugu gun eski
bir kusuru buldu.

## Ikinci bulgu - ISR'da yazdirmak

Ilk surumde hata adresi ISR icinde UART'a yaziliyordu. 115200 baud'da
28 karakterlik bir satir 2,4 ms surer. Timer her milisaniyede hata
urettigi icin ISR'lar ust uste bindi:

    onceki kosum : 57 ms simulasyon / 1:16 gercek
    hatali kosum : 23 ms simulasyon / 11:28 gercek  (elle durduruldu)

Ayrica "Stream ready" 20 ms'lik zaman asimini kacirdi ve test
basarisiz gorundu - hata veri yolunda degil, olcum duzenegindeydi.

2,4 ms suren bir kesme rutini kart uzerinde de kabul edilemez. ISR
artik yalnizca durumu kaydediyor; yazdirmayi ana dongu yapiyor.

## Ucuncu bulgu - zaman asimsiz beklemeler

Kosumun elle durdurulmasi gerekti cunku iki bekleme sinirsizdi:

    tb_soc_top.sv : wait (u_npu_engine.done_o == 1'b1)   -> zaman asimi yok
    main.c        : while (!bus_fault_flag) { }          -> sonsuz

Ikisi de sinirlandi (NPU 60 ms, yazilim 100k iterasyon). Takilan bir
test artik asili kalmak yerine hata bildirip bitiyor.

## GCC tuzagi

Kasitli hata icin ilk adres 0x0 secilmisti. GCC bunu null pointer
dereference sayip tanimsiz davranis kabul etti ve -Os ile main'in
kalanini SILDI:

    ikili 1728 -> 1328 bayt, "Stream ready" dahil her sey kayboldu

Derlemeden sonra ikilideki metinler kontrol edildigi icin simulasyona
gitmedi. Adres 0x100 yapildi (Boot ROM 1 kB, o da salt-okunur).

## Olculen

    Sistem testi : 61,078150 ms simulasyon / 1:04 gercek / 0 hata

    Timer test -> Timer OK arasinda hata satiri yok  (timer duzeltmesi)
    Bus fault @ 0x00000100 ST=0x05                   (mekanizma calisiyor)

## Kapanan

  R8 - OBI->AXI hata yanitlari
  timer_peripheral TIM_CLR/TIM_EVC yanlis SLVERR yaniti
  tb ve yazilimdaki zaman asimsiz beklemeler

## Bilinen sinir

CV32E40P'nin OBI arayuzunde hata girisi yok, bu yuzden hata hassas bir
istisna (load/store access fault) olarak bildirilemiyor - mepc hatayi
doguran komutu gostermez. Kesme asenkrondur; yazilim adresi gorur ama
hangi komutun sebep oldugunu goremez. Tam cozum, hata girisi olan bir
OBI surumu gerektirir.
