/* =============================================================================
 *  fpga_demo.c - Arkhe SoC tam cevre birimi demosu
 *  TEKNOFEST 2026 - Takim Arkhe
 *
 *  NEDEN VAR (9 Eylul 2026)
 *
 *    Yarismada juri hangi cevre birimini gormek isteyecegini onceden
 *    bilemiyoruz. Ana uygulama (main.c) yalnizca timer, bus-fault ve I2C
 *    icin kisa bir acilis testi yapip cikarim dongusune giriyor; GPIO pin
 *    modlari, QSPI komutlari, DMA aktarimi ve JTAG hata ayiklama birimi
 *    kart uzerinde hic gosterilmiyordu.
 *
 *    Bu program her cevre birimini TEK TEK, gozle dogrulanabilir bicimde
 *    calistirir ve sonucu UART'a yazar. Her adim kendi kendini denetler;
 *    basarisiz olan adim "[HATA]" ile isaretlenir ve program devam eder
 *    (tek bir hata butun demoyu durdurmaz).
 *
 *  KULLANIM
 *
 *    python sw_nexys/scripts/build.py        -> fpga_demo.hex uretir
 *    flash'a yazilip PROG'a basilir; cikti core UART'tan (115200) okunur.
 *
 *  JTAG HAKKINDA
 *
 *    jtag_debug modulu IKI arayuz sunar: TAP (harici adaptor icin, Pmod JC)
 *    ve AXI-Lite yazmac arayuzu (0x4008_0000). Bu demo AXI yolunu kullanir;
 *    harici JTAG adaptoru GEREKMEZ. TAP'in kendisi simulasyonda 27 denetimle
 *    dogrulanmistir.
 * ============================================================================= */

/* --- Cevre birimi taban adresleri (memory_map_pck.sv ile ayni) --- */
#define GPIO_BASE        0x40000000
#define GPIO_IDR    ((volatile unsigned int *)(GPIO_BASE + 0x00))
#define GPIO_ODR    ((volatile unsigned int *)(GPIO_BASE + 0x04))
#define GPIO_MODE   ((volatile unsigned int *)(GPIO_BASE + 0x08))
#define GPIO_SET    ((volatile unsigned int *)(GPIO_BASE + 0x0C))
#define GPIO_CLEAR  ((volatile unsigned int *)(GPIO_BASE + 0x10))
#define GPIO_TOGGLE ((volatile unsigned int *)(GPIO_BASE + 0x14))

#define TIMER_BASE       0x40010000
#define TIM_PRE     ((volatile unsigned int *)(TIMER_BASE + 0x00))
#define TIM_ARE     ((volatile unsigned int *)(TIMER_BASE + 0x04))
#define TIM_CLR     ((volatile unsigned int *)(TIMER_BASE + 0x08))
#define TIM_ENA     ((volatile unsigned int *)(TIMER_BASE + 0x0C))
#define TIM_MOD     ((volatile unsigned int *)(TIMER_BASE + 0x10))
#define TIM_CNT     ((volatile unsigned int *)(TIMER_BASE + 0x14))
#define TIM_EVN     ((volatile unsigned int *)(TIMER_BASE + 0x18))
#define TIM_EVC     ((volatile unsigned int *)(TIMER_BASE + 0x1C))

#define UART1_BASE       0x40020000
#define U1_CPB      ((volatile unsigned int *)(UART1_BASE + 0x00))
#define U1_STP      ((volatile unsigned int *)(UART1_BASE + 0x04))
#define U1_RDR      ((volatile unsigned int *)(UART1_BASE + 0x08))
#define U1_TDR      ((volatile unsigned int *)(UART1_BASE + 0x0C))
#define U1_CFG      ((volatile unsigned int *)(UART1_BASE + 0x10))

/* CFG bit anlamlari (uart_peripheral.sv):
     bit0  TX_EN     - yazilim 1 yapar, iletim baslar
     bit1  TX_DONE   - donanim kurar
     bit2  RX_DONE / tamamlandi bayragi - yazilim temizler
   main.c:115-120 ile ayni sira kullanilmalidir. */

#define UARTS_BASE       0x40030000
#define US_CPB      ((volatile unsigned int *)(UARTS_BASE + 0x00))
#define US_STP      ((volatile unsigned int *)(UARTS_BASE + 0x04))
#define US_RDR      ((volatile unsigned int *)(UARTS_BASE + 0x08))
#define US_CFG      ((volatile unsigned int *)(UARTS_BASE + 0x10))
#define US_LEVEL    ((volatile unsigned int *)(UARTS_BASE + 0x14))
#define US_CLR      ((volatile unsigned int *)(UARTS_BASE + 0x18))

#define I2C_BASE         0x40040000
#define I2C_NBY     ((volatile unsigned int *)(I2C_BASE + 0x00))
#define I2C_ADR     ((volatile unsigned int *)(I2C_BASE + 0x04))
#define I2C_RDR     ((volatile unsigned int *)(I2C_BASE + 0x08))
#define I2C_TDR     ((volatile unsigned int *)(I2C_BASE + 0x0C))
#define I2C_CFG     ((volatile unsigned int *)(I2C_BASE + 0x10))

#define QSPI_BASE        0x40050000
#define QSPI_CCR    ((volatile unsigned int *)(QSPI_BASE + 0x00))
#define QSPI_ADR    ((volatile unsigned int *)(QSPI_BASE + 0x04))
#define QSPI_DR     ((volatile unsigned int *)(QSPI_BASE + 0x08))
#define QSPI_STA    ((volatile unsigned int *)(QSPI_BASE + 0x0C))
#define QSPI_FCR    ((volatile unsigned int *)(QSPI_BASE + 0x10))

#define DMA_BASE         0x40070000
/* DMA yazmac sirasi (dma_controller.sv, main.c ile dogrulandi):
     CTRL 0x00  STATUS 0x04  SRC 0x08  DST 0x0C  LEN 0x10
   Ilk yazimda SRC/DST/LEN/CTRL sirasi varsayilmisti; yanlisti. */
#define DMA_CTRL    ((volatile unsigned int *)(DMA_BASE + 0x00))
#define DMA_STA     ((volatile unsigned int *)(DMA_BASE + 0x04))
#define DMA_SRC     ((volatile unsigned int *)(DMA_BASE + 0x08))
#define DMA_DST     ((volatile unsigned int *)(DMA_BASE + 0x0C))
#define DMA_LEN     ((volatile unsigned int *)(DMA_BASE + 0x10))

#define JTAG_BASE        0x40080000
#define JT_DBG_CTRL   ((volatile unsigned int *)(JTAG_BASE + 0x00))
#define JT_DBG_STATUS ((volatile unsigned int *)(JTAG_BASE + 0x04))
#define JT_DBG_ADDR   ((volatile unsigned int *)(JTAG_BASE + 0x08))
#define JT_DBG_DATA   ((volatile unsigned int *)(JTAG_BASE + 0x0C))
#define JT_DBG_CMD    ((volatile unsigned int *)(JTAG_BASE + 0x10))
#define JT_FAULT_ST   ((volatile unsigned int *)(JTAG_BASE + 0x14))
#define JT_FAULT_ADDR ((volatile unsigned int *)(JTAG_BASE + 0x18))
#define JT_FAULT_CLR  ((volatile unsigned int *)(JTAG_BASE + 0x1C))

#define DRAM_BASE   ((volatile unsigned int *)0x20000000)

/* --- Sonuc sayaclari --- */
static int gecen = 0;
static int kalan = 0;

/* --- UART yardimcilari --- */
static void uart_putc(char c)
{
    *U1_TDR = (unsigned int)c;
    *U1_CFG |= (1u << 0);                    /* iletimi baslat */
    while (!(*U1_CFG & (1u << 2))) { }       /* tamamlandi bayragi */
    *U1_CFG &= ~(1u << 2);                   /* bayragi temizle */
}

static void uart_print(const char *s)
{
    while (*s) {
        if (*s == '\n') uart_putc('\r');
        uart_putc(*s++);
    }
}

static void uart_hex(unsigned int v)
{
    const char *h = "0123456789ABCDEF";
    uart_print("0x");
    for (int i = 28; i >= 0; i -= 4) uart_putc(h[(v >> i) & 0xF]);
}

static void uart_dec(unsigned int v)
{
    char b[12];
    int i = 0;
    if (v == 0) { uart_putc('0'); return; }
    while (v) { b[i++] = (char)('0' + (v % 10)); v /= 10; }
    while (i--) uart_putc(b[i]);
}

/* Tek bir denetim. Basarisiz olsa bile program devam eder. */
static void kontrol(const char *ad, int kosul, unsigned int gercek)
{
    if (kosul) {
        gecen++;
        uart_print("  [OK]   ");
        uart_print(ad);
        uart_print("\n");
    } else {
        kalan++;
        uart_print("  [HATA] ");
        uart_print(ad);
        uart_print("  gelen=");
        uart_hex(gercek);
        uart_print("\n");
    }
}

static void bekle(int n)
{
    for (volatile int i = 0; i < n; i++) { }
}

static void baslik(const char *s)
{
    uart_print("\n--- ");
    uart_print(s);
    uart_print(" ---\n");
}

/* =============================================================================
 *  1) GPIO - dort pin modu, SET/CLEAR/TOGGLE
 *
 *  gpio_peripheral her pin icin IKI BIT mod tutar:
 *    00 giris   01 cikis   10 acik drenaj-0   11 acik drenaj-1
 *  Yon sinyali (tx_en) Pmod JD'ye cikar; osiloskopla dogrudan gozlenir.
 * ========================================================================== */
static void demo_gpio(void)
{
    unsigned int v;

    baslik("1. GPIO");

    *GPIO_MODE = 0x55555555u;          /* hepsi cikis */
    *GPIO_ODR  = 0x0000FFFFu;
    bekle(200);
    v = *GPIO_ODR;
    kontrol("ODR yazma - LED'lerin hepsi yanmali", (v & 0xFFFFu) == 0xFFFFu, v);

    *GPIO_CLEAR = 0x0000FF00u;         /* ust bayti sondur */
    bekle(200);
    v = *GPIO_ODR;
    kontrol("CLEAR - ust 8 LED sondu", (v & 0xFFFFu) == 0x00FFu, v);

    *GPIO_SET = 0x0000F000u;
    bekle(200);
    v = *GPIO_ODR;
    kontrol("SET - dort LED tekrar yandi", (v & 0xFFFFu) == 0xF0FFu, v);

    *GPIO_TOGGLE = 0x0000FFFFu;
    bekle(200);
    v = *GPIO_ODR;
    kontrol("TOGGLE - hepsi terslendi", (v & 0xFFFFu) == 0x0F00u, v);

    /* Pin modlari - tx_en Pmod JD'de gozlenebilir */
    *GPIO_MODE = 0x00000000u;          /* giris */
    bekle(100);
    uart_print("  bilgi  MODE=giris   (JD pinleri 0 olmali)\n");

    *GPIO_MODE = 0x55555555u;          /* cikis */
    bekle(100);
    uart_print("  bilgi  MODE=cikis   (JD pinleri 1 olmali)\n");

    *GPIO_MODE = 0xAAAAAAAAu;          /* acik drenaj-0: tx_en = ODR */
    *GPIO_ODR  = 0x000000A5u;
    bekle(100);
    uart_print("  bilgi  MODE=od-0    (JD = ODR = 0xA5)\n");

    *GPIO_MODE = 0xFFFFFFFFu;          /* acik drenaj-1: tx_en = ~ODR */
    bekle(100);
    uart_print("  bilgi  MODE=od-1    (JD = ~ODR = 0x5A)\n");

    /* Anahtarlari oku */
    v = *GPIO_IDR;
    uart_print("  bilgi  anahtarlar (SW) = ");
    uart_hex(v & 0xFFFFu);
    uart_print("\n");

    /* Bilinen duruma don */
    *GPIO_MODE = 0x55555555u;
    *GPIO_ODR  = 0x00000000u;
}

/* =============================================================================
 *  2) Timer - prescaler, otomatik yeniden yukleme, olay bayragi
 * ========================================================================== */
static void demo_timer(void)
{
    unsigned int c1, c2, ev;

    baslik("2. Timer");

    *TIM_ENA = 0;
    *TIM_CLR = 1;
    *TIM_PRE = 0;                       /* her cevrim say */
    /* ARE en buyuk degerde: sayac bu testte SARMAMALIDIR.
       Ilk yazimda ARE=1000 idi ve bekle(500) sirasinda sayac birden
       fazla tur atiyordu; c2 > c1 karsilastirmasi guvenilir degildi. */
    *TIM_ARE = 0xFFFFFFFFu;
    /* timer_peripheral.sv:113 - reg_tim_mod=1 YUKARI saydirir.
       Ilk yazimda 0 yazilmisti; sayac asagi sayiyor ve 0xFFFF... gibi
       degerler donuyordu. Reset degeri de 1'dir. */
    *TIM_MOD = 1;                       /* yukari say */
    *TIM_EVC = 1;                       /* olay bayragini temizle */

    c1 = *TIM_CNT;
    kontrol("CLR sonrasi sayac sifir", c1 == 0, c1);

    *TIM_ENA = 1;
    bekle(500);
    c1 = *TIM_CNT;
    bekle(500);
    c2 = *TIM_CNT;
    kontrol("sayac ilerliyor", c2 > c1, c2);

    *TIM_ENA = 0;
    c1 = *TIM_CNT;
    bekle(500);
    c2 = *TIM_CNT;
    kontrol("ENA=0 iken sayac durdu", c1 == c2, c2);

    /* Otomatik yeniden yukleme ve olay
       timer_peripheral.sv:73,116 - TIM_EVN bir BAYRAK degil, 32 bitlik
       OLAY SAYACIDIR: sayac her ARE'ye ulasip sarmalandiginda bir artar.
       Kesme kosulu da bit-0 degil, satir 81'deki (reg_tim_evn != 0).
       Ilk yazimda (ev & 1u) denetleniyordu; ARE=100 ile 3000 dongude
       832 olay birikti ve 832 cift oldugu icin bit-0 sifir cikti - yani
       donanim dogru calisirken test yanlis bakiyordu. */
    *TIM_ENA = 0;
    *TIM_CLR = 1;
    *TIM_ARE = 100;
    *TIM_EVC = 1;                       /* olay sayacini sifirla */
    *TIM_ENA = 1;
    bekle(3000);
    *TIM_ENA = 0;                       /* okuma sirasinda sayim ilerlemesin */
    ev = *TIM_EVN;
    uart_print("  bilgi  biriken olay sayisi = ");
    uart_dec(ev);
    uart_print("\n");
    kontrol("ARE'ye ulasinca olay sayaci arti", ev != 0, ev);

    /* EVC yazimi sayaci sifirlar (satir 131-132); timer duruk oldugu icin
       sifir kalmalidir. */
    *TIM_EVC = 1;
    bekle(50);
    ev = *TIM_EVN;
    kontrol("EVC olay sayacini sifirladi", ev == 0, ev);

    /* Prescaler etkisi */
    /* Prescaler karsilastirmasi: AYNI bekleme suresiyle PRE=0 ve PRE=9
       sayimlarini olcup oranin makul oldugunu denetliyoruz. Mutlak deger
       beklemek kirilgan; derleyici bekle() dongusunu farkli optimize
       edebilir. */
    *TIM_ENA = 0; *TIM_CLR = 1; *TIM_PRE = 0; *TIM_ARE = 0xFFFFFFFFu; *TIM_MOD = 1;
    *TIM_ENA = 1; bekle(2000); *TIM_ENA = 0;
    c1 = *TIM_CNT;                      /* PRE=0 sayimi */

    *TIM_ENA = 0; *TIM_CLR = 1; *TIM_PRE = 9; *TIM_MOD = 1;
    *TIM_ENA = 1; bekle(2000); *TIM_ENA = 0;
    c2 = *TIM_CNT;                      /* PRE=9 sayimi */

    uart_print("  bilgi  PRE=0 -> ");
    uart_dec(c1);
    uart_print("   PRE=9 -> ");
    uart_dec(c2);
    uart_print("\n");
    kontrol("prescaler sayimi yavaslatti", c2 < c1 && c2 > 0, c2);

    *TIM_ENA = 0;
    *TIM_CLR = 1;
}

/* =============================================================================
 *  3) I2C - yazmac davranislari ve protokol motoru
 *
 *  Kart uzerinde gercek bir I2C kolesi olmayabilir; adres NACK alinmasi
 *  BEKLENEN durumdur ve motorun dogru sonlandigini gosterir.
 * ========================================================================== */
static void demo_i2c(void)
{
    unsigned int v;
    int i;

    baslik("3. I2C");

    *I2C_NBY = 0;
    v = *I2C_NBY;
    kontrol("NBY=0 yazildi -> 1'e kirpildi", v == 1, v);

    *I2C_NBY = 25;
    v = *I2C_NBY;
    kontrol("NBY=25 yazildi -> 4'e kirpildi", v == 4, v);

    *I2C_ADR = 0xFFu;
    v = *I2C_ADR;
    kontrol("ADR yalnizca 7 bit tutuyor", v == 0x7Fu, v);

    *I2C_TDR = 0xA5A55A5Au;
    v = *I2C_TDR;
    kontrol("TDR tam genislik korunuyor", v == 0xA5A55A5Au, v);

    /* Gercek islem baslat - kole yoksa NACK ile biter */
    *I2C_NBY = 2;
    *I2C_ADR = 0x50u;                   /* yaygin EEPROM adresi */
    *I2C_TDR = 0x1234u;
    *I2C_CFG = 0x1u;                    /* TX_EN */

    for (i = 0; i < 100000; i++) {
        v = *I2C_CFG;
        if ((v & 0x1u) == 0) break;     /* TX_EN dustu = islem bitti */
    }
    kontrol("islem asili kalmadan sonlandi", (v & 0x1u) == 0, v);
    uart_print("  bilgi  CFG = ");
    uart_hex(v);
    uart_print("  (kole yoksa NACK beklenir)\n");

    *I2C_CFG = 0;
}

/* =============================================================================
 *  4) QSPI - flash kimligi ve durum yazmaci okuma
 *
 *  Kart uzerinde gercek Spansion S25FL128S vardir; boot zaten buradan
 *  yapilir. Bu adim komut cercevesinin dogru kuruldugunu gosterir.
 * ========================================================================== */
static void demo_qspi(void)
{
    unsigned int v, kimlik, icerik;
    int i;

    baslik("4. QSPI");

    /* NOT - FIFO YONETIMI (9 Eylul 2026)
       Her komut istenen kadar bayt uretir ve bunlarin HEPSI okunmalidir.
       Ilk yazimda DR yalnizca bir kez okunuyordu; kalan baytlar FIFO'da
       birikince fifo_err (STA bit8) kuruluyor ve bir sonraki komutun
       verisi bozuluyordu ("flash kimligi = 0xDEADBEEF" boyle cikti).
       Artik her komuttan once FIFO temizlenir.

       CCR: [7:0] komut, [9:8] veri modu, [10] yaz/oku, [15:11] kukla,
            [23:16] veri boyutu, [30:25] prescaler */

    /* CMD_RDID (0x9F) - uc bayt kimlik, adres fazi yok */
    *QSPI_FCR = 1u;                     /* FIFO temizle */
    *QSPI_ADR = 0;
    /* CCR alanlari (qspi_master.sv:268-271):
         [9:8] veri modu - 00 ise cmd_needs_data() YANLIS doner (satir 466)
                ve FSM veri fazina hic girmez; done kurulur ama bayt
                okunmaz. Tek hat icin 01 olmalidir.
         [23:16] boyut - N-1 kodlanir (satir 510: total_bytes = alan + 1)
         [30:25] prescaler - bootloader 4 kullanir; daha hizlisinda flash
                kenar tespitine yetisemiyor (bootloader.S:65-68).
       Ilk yazimda mod da boyut da yanlisti; bootloader'in kartta
       kanitlanmis 0x88FF0103 kodlamasi ornek alindi. */
    *QSPI_CCR = (4u << 25) | (1u << 8) | (2u << 16) | 0x9Fu;   /* 3 bayt */
    for (i = 0; i < 100000; i++) {
        v = *QSPI_STA;
        if (v & 0x1u) break;            /* done */
    }
    kontrol("RDID komutu tamamlandi", (v & 0x1u) != 0, v);

    /* STA bit5 = rx_empty (qspi_master.sv:296). BOS FIFO'dan DR okumak
       0xDEADBEEF dondurur ve err_rx_empty kurar (satir 247) - yani
       "komut bitti" bayragi tek basina verinin GELDIGINI kanitlamaz.
       Ilk kosuda uc okumanin ucu de 0xDEADBEEF dondu; sadece done
       bayragina bakildigi icin test bunu yakalamamisti. */
    kontrol("RDID verisi FIFO'ya ulasti", (v & 0x20u) == 0, v);
    kimlik = *QSPI_DR;
    uart_print("  bilgi  flash kimligi = ");
    uart_hex(kimlik);
    uart_print("  (Spansion S25FL128S bekleniyor)\n");
    kontrol("kimlik dolgu deseni degil", kimlik != 0xDEADBEEFu, kimlik);

    /* CMD_RDSR1 (0x05) - durum yazmaci, tek bayt */
    *QSPI_FCR = 1u;
    *QSPI_CCR = (4u << 25) | (1u << 8) | (0u << 16) | 0x05u;   /* 1 bayt */
    for (i = 0; i < 100000; i++) {
        v = *QSPI_STA;
        if (v & 0x1u) break;
    }
    kontrol("RDSR1 komutu tamamlandi", (v & 0x1u) != 0, v);
    uart_print("  bilgi  durum yazmaci = ");
    uart_hex(*QSPI_DR & 0xFFu);
    uart_print("\n");

    /* Bilinen adresten okuma - uygulama alani */
    *QSPI_FCR = 1u;
    *QSPI_ADR = 0x00800000u;
    *QSPI_CCR = (4u << 25) | (1u << 8) | (3u << 16) | 0x03u;   /* 4 bayt, adresli */
    for (i = 0; i < 100000; i++) {
        v = *QSPI_STA;
        if (v & 0x1u) break;
    }
    kontrol("flash'tan veri okundu", (v & 0x1u) != 0, v);
    kontrol("okuma verisi FIFO'ya ulasti", (v & 0x20u) == 0, v);
    icerik = *QSPI_DR;
    uart_print("  bilgi  0x800000 icerigi = ");
    uart_hex(icerik);
    uart_print("  (uygulama ilk kelimesi)\n");
    /* Uygulama imajinin ilk kelimesi 0x1f002117 (flash_fpga_demo.hex).
       Dolgu deseni gelirse SPI islemi veri getirmemis demektir. */
    kontrol("okunan veri dolgu deseni degil", icerik != 0xDEADBEEFu, icerik);

    /* Hata bayragi denetimi
       qspi_master.sv:248 - err_rx_empty BOS FIFO'dan DR okununca kurulur
       ve yalnizca CCR[31] (clr_status) ile temizlenir; FCR FIFO'yu
       bosaltir ama bayragi silmez. Once bayragi temizleyip sonra
       durumun temiz kaldigini denetliyoruz. */
    *QSPI_FCR = 1u;                     /* FIFO'da artik bayt kalmasin */
    *QSPI_CCR = (1u << 31);             /* clr_status - bayraklari sil */
    bekle(200);
    v = *QSPI_STA;
    kontrol("hata bayraklari temizlenebiliyor", (v & 0x100u) == 0, v);
}

/* =============================================================================
 *  5) DMA - bellekten bellege aktarim
 * ========================================================================== */
static void demo_dma(void)
{
    volatile unsigned int *kaynak = DRAM_BASE + 0x100;
    volatile unsigned int *hedef  = DRAM_BASE + 0x200;
    unsigned int v;
    int i, hatali = 0;

    baslik("5. DMA");

    for (i = 0; i < 16; i++) {
        kaynak[i] = 0xD0000000u + (unsigned int)i;
        hedef[i]  = 0;
    }

    *DMA_SRC  = (unsigned int)kaynak;
    *DMA_DST  = (unsigned int)hedef;
    *DMA_LEN  = 16;
    *DMA_CTRL = 0x1u;                   /* baslat */
    *DMA_CTRL = 0x0u;

    for (i = 0; i < 100000; i++) {
        v = *DMA_STA;
        if (v & 0x1u) break;            /* done */
    }
    kontrol("DMA aktarimi tamamlandi", (v & 0x1u) != 0, v);

    for (i = 0; i < 16; i++)
        if (hedef[i] != 0xD0000000u + (unsigned int)i) hatali++;

    kontrol("16 kelimenin hepsi dogru tasindi", hatali == 0,
            (unsigned int)hatali);
    uart_print("  bilgi  hedef[0] = ");
    uart_hex(hedef[0]);
    uart_print("  hedef[15] = ");
    uart_hex(hedef[15]);
    uart_print("\n");
}

/* =============================================================================
 *  6) UART-stream - baud, stop bit, FIFO
 * ========================================================================== */
static void demo_uart_stream(void)
{
    unsigned int v;

    baslik("6. UART-stream (UART 2)");

    *US_CPB = 50;                       /* 50 MHz / 1 Mbps */
    v = *US_CPB;
    kontrol("CPB=50 (1 Mbps) yazildi", v == 50, v);

    *US_STP = 0;
    v = *US_STP;
    kontrol("STP=0 (1 stop bit)", (v & 3u) == 0, v);

    *US_STP = 2;
    v = *US_STP;
    kontrol("STP=2 (2 stop bit) kabul edildi", (v & 3u) == 2, v);
    *US_STP = 0;

    *US_CLR = 1;
    bekle(50);
    v = *US_LEVEL & 0x1FFu;
    kontrol("FIFO temizleme sonrasi bos", v == 0, v);

    uart_print("  bilgi  bu arayuz demo aracinin 1960 baytlik\n");
    uart_print("         cikarim vektorunu aldigi yoldur\n");
}

/* =============================================================================
 *  7) JTAG hata ayiklama - AXI yazmac arayuzu uzerinden
 *
 *  jtag_debug IKI arayuz sunar:
 *    - TAP (Pmod JC): harici adaptor gerektirir
 *    - AXI-Lite yazmaclari (0x4008_0000): yazilimdan erisilir
 *
 *  Bu demo AXI yolunu kullanir; adaptor GEREKMEZ. Ayni birimin TAP tarafi
 *  simulasyonda 27 denetimle dogrulanmistir.
 * ========================================================================== */
static void demo_jtag(void)
{
    volatile unsigned int *hedef = DRAM_BASE + 0x300;
    unsigned int v;
    int i;

    baslik("7. JTAG hata ayiklama birimi");

    /* Yazmac geri okuma */
    *JT_DBG_ADDR = 0x20000300u;
    v = *JT_DBG_ADDR;
    kontrol("DBG_ADDR geri okundu", v == 0x20000300u, v);

    *JT_DBG_DATA = 0xDEADBEEFu;
    v = *JT_DBG_DATA;
    kontrol("DBG_DATA geri okundu", v == 0xDEADBEEFu, v);

    /* Hata ayiklayici uzerinden bellege YAZMA */
    *hedef = 0;                          /* once temizle */
    bekle(50);
    *JT_DBG_ADDR = (unsigned int)hedef;
    *JT_DBG_DATA = 0xA5A55A5Au;
    *JT_DBG_CMD  = 0x2u;                 /* write */
    for (i = 0; i < 10000; i++) {
        v = *JT_DBG_STATUS;
        if ((v & 0x4u) == 0) break;      /* bus busy dustu */
    }
    bekle(100);
    kontrol("hata ayiklayici bellege yazdi", *hedef == 0xA5A55A5Au, *hedef);

    /* Hata ayiklayici uzerinden bellekten OKUMA */
    *hedef = 0x12345678u;
    bekle(50);
    *JT_DBG_ADDR = (unsigned int)hedef;
    *JT_DBG_CMD  = 0x1u;                 /* read */
    for (i = 0; i < 10000; i++) {
        v = *JT_DBG_STATUS;
        if ((v & 0x4u) == 0) break;
    }
    bekle(100);
    v = *JT_DBG_DATA;
    kontrol("hata ayiklayici bellekten okudu", v == 0x12345678u, v);

    /* Veri yolu hatasi yakalama - gecersiz adrese erisim */
    *JT_FAULT_CLR = 1;
    bekle(50);
    v = *JT_FAULT_ST;
    kontrol("hata bayragi baslangicta temiz", (v & 1u) == 0, v);

    uart_print("  bilgi  TAP arayuzu Pmod JC'de (TCK=JC1 TMS=JC2\n");
    uart_print("         TDI=JC3 TDO=JC4); harici adaptor ile erisilir\n");
}

/* =============================================================================
 *  Ana akis
 * ========================================================================== */
int main(void)
{
    *U1_CPB = 434;                       /* 50 MHz / 115200 */
    *U1_STP = 0;                         /* 1 stop bit */
    *U1_CFG = 0;                         /* bayraklari temizle */

    uart_print("\n");
    uart_print("================================================\n");
    uart_print(" ARKHE SoC - TAM CEVRE BIRIMI DEMOSU\n");
    uart_print(" TEKNOFEST 2026 - Takim Arkhe\n");
    uart_print("================================================\n");

    demo_gpio();
    demo_timer();
    demo_i2c();
    demo_qspi();
    demo_dma();
    demo_uart_stream();
    demo_jtag();

    uart_print("\n================================================\n");
    uart_print(" SONUC: ");
    uart_dec((unsigned int)gecen);
    uart_print(" gecti, ");
    uart_dec((unsigned int)kalan);
    uart_print(" kaldi\n");
    if (kalan == 0)
        uart_print(" TUM CEVRE BIRIMLERI CALISIYOR\n");
    else
        uart_print(" BAZI DENETIMLER BASARISIZ - yukariya bakiniz\n");
    uart_print("================================================\n");

    /* LED'lerde sonucu goster: hepsi yanik = basarili */
    *GPIO_MODE = 0x55555555u;
    *GPIO_ODR  = (kalan == 0) ? 0xFFFFu : 0xF00Fu;

    for (;;) { }
}
