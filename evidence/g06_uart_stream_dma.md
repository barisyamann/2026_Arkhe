# G06 - UART-stream -> DMA -> Hizlandirici Bellegi

Tarih: 18 Agustos 2026

## Sartname maddesi

EK-1 s.21:

> "UART-stream cevresel birimi cikarim yapilacak veriyi iletecek ve bu
>  veri istenilen hizlandirici bellek adresine yazilacaktir."

Onceki durumda girdi tensorunu CPU bir dongude TCM'e yaziyordu; UART-stream
birimi sentezleniyordu ama veri yolunda hic kullanilmiyordu. Artik veri
gercekten dis dunyadan geliyor ve CPU tasima isine hic karismiyor.

## Kurulan yol

    UART2 RX (1 Mbps) -> stream FIFO (256 bayt)
      -> UARTS_RDR32 (0x4003_0020, 4 bayti bir kelimede paketler)
      -> DMA (SRC_FIXED)  -> TCM 0x2001_0000
      -> NPU

CPU yalnizca uc yazmac grubunu kuruyor ve uyuyor:

    *UARTS_CPB = 50;                 // 50 MHz / 1 Mbps
    *DMA_SRC   = 0x40030020;         // paketli FIFO yazmaci
    *DMA_DST   = 0x20010000;         // hizlandirici bellegi
    *DMA_LEN   = 490;                // kelime
    *DMA_CTRL  = SRC_FIXED | START;
    while (!dma_flag) __asm__ volatile ("wfi");

## Eklenen donanim

### 1. DMA'ya sabit adres kipi

    REG_DMA_CTRL[2] = SRC_FIXED    kaynak adresi artmaz
    REG_DMA_CTRL[3] = DST_FIXED    hedef adresi artmaz

Bir cevre biriminin veri yazmacindan akis okumak icin sart. UARTS_RDR32
tek bir adrestir ve her okumada FIFO ilerler; adres artsaydi ikinci okuma
bambaska bir yazmaca giderdi.

### 2. UART-stream'e paketli okuma yazmaci (UARTS_RDR32, offset 0x20)

DMA 32-bit kelime tasir, UART ise bayt uretir. Bu yazmac FIFO'dan dort
bayt toplayip tek kelime olarak sunuyor. Kelime hazir degilse AXI
okumasi tamamlanmaz: `arready` dusuk kalir, DMA bekler.

Bu, protokolun dogru kullanimi: veri hazir olana kadar geri bastirmak,
gecersiz veri dondurmekten iyidir.

## Yol boyunca cikan uc engel

### 1. Kilitlenme - mesaj sirasi

Ilk yazimda CPU once DMA'yi baslatip sonra "Stream ready" yaziyordu.
DMA bos FIFO'yu beklerken veri yolunu tutuyor, CPU'nun UART yazmasi
tikaniyor, testbench "Stream ready" satirini hic gormedigi icin veri
gondermiyor, DMA da beklemeye devam ediyor.

Cozum: mesaj DMA baslatilmadan ONCE yaziliyor. FIFO 256 bayt oldugu ve
DMA mikrosaniyeler icinde basladigi icin erken gelen bayt kaybolmuyor.

### 2. Paketleyicide bayt kaymasi

    assign pack_rd_en = !pack_valid_r && !fifo_empty_w && (pack_cnt_r < 4);

sync_fifo cikisi KAYITLI oldugu icin pack_cnt_r ancak okumadan bir
cevrim sonra artiyor. Sayac 3'teyken besinci okuma da baslatiliyor ve o
bayt sonraki cevrimde pack_data_r'ye kayarak kelimeyi bozuyordu.

Duzeltme - ayni anda tek okuma:

    assign pack_rd_en = !pack_valid_r && !fifo_empty_w && !pack_rd_d &&
                        (pack_cnt_r < 3'd4);

Bayt basina 2 cevrim eder; 1 Mbps'te bayt basina 50 cevrim var, hiz
kaybi yok.

### 3. Simulasyon eski yazilimi kosuyordu

Ilk kosum iki hata verdi. Sebep RTL degildi: Vivado 11:47'de derlenmis
app.hex'i okuyordu, main.c ise 12:22'de degismisti. Kanit, logdaki
"In: PATTERN A" satiriydi - o metin artik kaynak kodda yok.

Ders: her kosumdan once app.hex'in main.c'den yeni oldugu kontrol
edilmeli. G07'de build.py'nin cikti dosyasini xsim dizinine kendisinin
kopyalamasi planlandi.

## Bit-birebir dogrulama

Bu koşumun en degerli sonucu, dogrulamanin bedavaya gelmesiydi.

Eski yazilimda PATTERN A = 0x5555_5555 idi ve tensoru CPU dogrudan
yaziyordu. Testbench simdi UART'tan 0x55 baytlari gonderiyor; paketleyici
bunlari 0x5555_5555'e ceviriyor. Yani ayni girdi, iki farkli yoldan.

                        fc_acc[0]  [1]     [2]     [3]      probs           Class
    CPU dogrudan yazdi   -985885   242268  240758  387226   0/1050/1050/1995   3
    UART -> DMA -> TCM   -985885   242268  240758  387226   0/1050/1050/1995   3

Paketleyicide tek bayt kaymasi olsaydi sonuc degisirdi. Yol dogru.

## Olculen

    UART-stream gonderimi   : 1960 bayt @ 1 Mbps
    DMA transferi           : 12,557 ms -> 32,151 ms = 19,594 ms (490 kelime)
    Teorik alt sinir        : 1960 x 10 bit x 1 us = 19,600 ms
    -> Darbogaz UART hatti; DMA gecikme eklemiyor.

    DMA kesmesi -> ISR temizledi : ~3,7 us (186 cevrim)
    Toplam sistem testi          : 56,04 ms sim / 50 s gercek / 0 hata

## Testbench'e eklenenler

  - uart2_send_byte / uart2_send_tensor : 1 Mbps 8N1 gonderici
  - "Stream ready" el sikismasi (UART cozucusu uzerinden, 20 ms zaman asimi)
  - "DMA done" kontrolu -> uart_saw_dma_done

Kesme izleyicileri seviye tetikliden KENAR tetikliye cevrildi. Onceki
halde DMA kesmesi ISR onu temizleyene kadar ~190 satir basiyor ve log
okunamaz hale geliyordu. Simdi hem yukselen kenar hem de temizlenme
bildiriliyor; kesmenin gercekten dustugu de gorulebiliyor.

## Kapanan

  Sartname EK-1 s.21 - UART-stream veri yolu
  EK-2 s.22 - 1 Mbps destegi (genel UART 115200'de kalarak iki farkli
              baud hizi ayni kosumda gosterildi)
  DMA cevre birimi - ilk kez gercek bir is yapiyor

## Acik kalan

  - UART_RDR (bayt okuma, offset 0x08) hala bir eksik kayma iceriyor;
    FIFO cikisi kayitli oldugu icin ilk okuma bir onceki bayti dondurur.
    UARTS_RDR32 yolu bundan etkilenmiyor. G07'de duzeltilecek.
  - Girdi hala sabit bir oruntudur; G08'de gercek TFLite vektorleri
    gonderilecek.
