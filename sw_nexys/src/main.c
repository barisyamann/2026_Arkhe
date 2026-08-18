#include "user_defines.h"

// UART Registers Map
typedef struct {
    volatile unsigned int CPB; // Clock per bit
    volatile unsigned int STP; // Stop bits
    volatile unsigned int RDR; // Read Data Register
    volatile unsigned int TDR; // Transmit Data Register
    volatile unsigned int CFG; // Configuration register
} uart_regspace;

// Memory and Peripheral Bases
#define UART             ((volatile uart_regspace *) UART_BASE_ADDR)

#define GPIO_ODR         ((volatile unsigned int *)(0x40000000 + 0x04))
#define GPIO_MODE        ((volatile unsigned int *)(0x40000000 + 0x08))

#define NPU_REG_CTRL     ((volatile unsigned int *)(0x40060000 + 0x00))
#define NPU_REG_STATUS   ((volatile unsigned int *)(0x40060000 + 0x04))
#define NPU_REG_CLASS    ((volatile unsigned int *)(0x40060000 + 0x10))

#define NPU_TCM_BASE     ((volatile unsigned int *)(0x20010000))

// --- NPU kontrol yazmaci bitleri (npu_csr.sv REG_CTRL) ---
#define NPU_CTRL_START      (1u << 0)
#define NPU_CTRL_RESET      (1u << 1)
#define NPU_CTRL_IRQ_CLEAR  (1u << 2)   // darbe: done_sticky'yi temizler
#define NPU_CTRL_IRQ_EN     (1u << 3)   // kesme cikisini etkinlestirir

// --- Kesme vektorundeki bit konumu (soc_top.sv irq_vector) ---
//     24 dma · 23 i2c · 22 NPU · 21 qspi · 19 uart2 · 18 uart1 · 17 timer · 16 gpio
#define NPU_IRQ_BIT      22
// --- Timer yazmaclari (EK-2 s.21) ---
#define TIMER_BASE       0x40010000
#define TIM_PRE   ((volatile unsigned int *)(TIMER_BASE + 0x00))
#define TIM_ARE   ((volatile unsigned int *)(TIMER_BASE + 0x04))
#define TIM_CLR   ((volatile unsigned int *)(TIMER_BASE + 0x08))
#define TIM_ENA   ((volatile unsigned int *)(TIMER_BASE + 0x0C))
#define TIM_MOD   ((volatile unsigned int *)(TIMER_BASE + 0x10))
#define TIM_EVC   ((volatile unsigned int *)(TIMER_BASE + 0x1C))

#define TIMER_IRQ_BIT    17

volatile int timer_flag = 0;

// --- UART-stream (UART2) yazmaclari ---
// Sartname EK-1 s.21: cikarim verisi bu birim uzerinden gelir.
#define UARTS_BASE       0x40030000
#define UARTS_CPB   ((volatile unsigned int *)(UARTS_BASE + 0x00))
#define UARTS_STP   ((volatile unsigned int *)(UARTS_BASE + 0x04))
#define UARTS_CFG   ((volatile unsigned int *)(UARTS_BASE + 0x10))
#define UARTS_LEVEL ((volatile unsigned int *)(UARTS_BASE + 0x14))
#define UARTS_CLR   ((volatile unsigned int *)(UARTS_BASE + 0x18))
// Paketli FIFO okuma yazmaci: her okumada FIFO'dan dort bayt cekip
// tek kelimede paketler. DMA'nin sabit kaynak adresi bu.
#define UARTS_RDR32_ADDR (UARTS_BASE + 0x20)

// --- DMA yazmaclari ---
#define DMA_BASE         0x40070000
#define DMA_CTRL    ((volatile unsigned int *)(DMA_BASE + 0x00))
#define DMA_STATUS  ((volatile unsigned int *)(DMA_BASE + 0x04))
#define DMA_SRC     ((volatile unsigned int *)(DMA_BASE + 0x08))
#define DMA_DST     ((volatile unsigned int *)(DMA_BASE + 0x0C))
#define DMA_LEN     ((volatile unsigned int *)(DMA_BASE + 0x10))

#define DMA_CTRL_START      (1u << 0)
#define DMA_CTRL_RESET      (1u << 1)
#define DMA_CTRL_SRC_FIXED  (1u << 2)   // kaynak adresi artmaz
#define DMA_CTRL_DST_FIXED  (1u << 3)   // hedef adresi artmaz

#define DMA_IRQ_BIT      24

volatile int dma_flag = 0;

// Girdi tensoru: 1960 bayt = 490 kelime
#define TENSOR_WORDS     490


// ISR ile ana dongu arasinda paylasilan durum.
// volatile: derleyici onbellege almasin, her seferinde bellekten okusun.
volatile int          npu_done_flag = 0;
volatile unsigned int npu_class     = 0;


// =============================================================================
// UART surucusu
// =============================================================================

void uart_init(void) {
    UART->CPB = 434; // 50 MHz / 115200 Baud = 434
    UART->STP = 0;   // 1 Stop bit
    UART->CFG = 0;
}

void uart_putc(char c) {
    UART->TDR = c;
    UART->CFG |= (0x1UL << 0);              // iletimi baslat
    while (!(UART->CFG & (0x1UL << 2))) {}  // tamamlandi bayragini bekle
    UART->CFG &= ~(0x1UL << 2);             // bayragi temizle
}

void uart_print(const char *str) {
    while (*str) {
        if (*str == '\n') {
            uart_putc('\r');
        }
        uart_putc(*str++);
    }
}

void uart_print_dec(unsigned int val) {
    if (val == 0) {
        uart_putc('0');
        return;
    }
    char buf[12];
    int idx = 0;
    while (val > 0) {
        buf[idx++] = '0' + (val % 10);
        val /= 10;
    }
    for (int i = idx - 1; i >= 0; i--) {
        uart_putc(buf[i]);
    }
}


// =============================================================================
// Kesme servis rutini (ISR)
//
// Sartname s.16: "CPU kesmeyi aldiginda ... interrupt service routine'ini
// yurutmeli ve ... sonuclari UART arayuzu uzerinden yazdirmalidir."
//
// __attribute__((interrupt("machine"))) derleyiciye bunun bir kesme rutini
// oldugunu soyler: kullandigi yazmaclari otomatik saklar/geri yukler ve
// sonunda normal 'ret' yerine 'mret' uretir.
//
// aligned(256) zorunlu: CV32E40P'de mtvec yalnizca adresin [31:8] bitlerini
// saklar (cv32e40p_cs_registers.sv:666), yani rutin 256 bayt hizali bir
// adreste olmalidir.
// =============================================================================
void __attribute__((interrupt("machine"), aligned(256))) trap_handler(void)
{
    unsigned int cause;
    __asm__ volatile ("csrr %0, mcause" : "=r"(cause));

    // mcause'un en ust biti 1 ise kesme, 0 ise istisna.
    // Alt bitler kesme numarasini verir.
    if ((cause & 0x80000000u) && ((cause & 0x1Fu) == NPU_IRQ_BIT)) {

        npu_class     = *NPU_REG_CLASS & 3;
        npu_done_flag = 1;

        // Sonucu UART'tan yazdir - sartnamenin istedigi adim
        uart_print("[IRQ] Class: ");
        uart_print_dec(npu_class);
        uart_print("\n");

        // --- Kesmeyi sustur ---
        //
        // irq_clear darbesi tek basina yetmez: hesaplama motoru DONE
        // durumunda kaldigi surece done_i = 1 kalir ve done_sticky bir
        // sonraki cevrimde yeniden 1 olur. Bu yuzden irq_enable bitini
        // de dusuruyoruz (bit 3 = 0 yazarak) - irq_o = done_sticky &&
        // reg_irq_enable oldugu icin kesme hatti duser.
        //
        // Ana dongu, bir sonraki calistirmadan once yeniden aciyor.
        *NPU_REG_CTRL = NPU_CTRL_IRQ_CLEAR;
    }
        // --- Timer kesmesi ---
    if ((cause & 0x80000000u) && ((cause & 0x1Fu) == TIMER_IRQ_BIT)) {
        timer_flag = 1;
        *TIM_ENA = 0;   // sayaci durdur
        *TIM_EVC = 1;   // olay bayragini temizle -> timer_irq duser
    }

    // --- DMA kesmesi ---
    // irq_o = dma_done. dma_done yalnizca reset, dma_reset (CTRL[1])
    // veya yeni bir start ile temizlenir. Burada reset darbesi gonderiyoruz.
    if ((cause & 0x80000000u) && ((cause & 0x1Fu) == DMA_IRQ_BIT)) {
        dma_flag  = 1;
        *DMA_CTRL = DMA_CTRL_RESET;   // dma_done temizlenir -> irq duser
        *DMA_CTRL = 0;                // reset seviyesini birak
    }

}


// Kesme altyapisini kur
static void irq_init(void)
{
    unsigned int t;

    // mtvec: kesme rutininin adresi. Bit 0 = 0 -> dogrudan mod.
    t = (unsigned int)&trap_handler;
    __asm__ volatile ("csrw mtvec, %0" :: "r"(t));

    // mie: yalnizca NPU kesmesini etkinlestir
    t = (1u << NPU_IRQ_BIT) | (1u << TIMER_IRQ_BIT) | (1u << DMA_IRQ_BIT);

    __asm__ volatile ("csrw mie, %0" :: "r"(t));

    // mstatus.MIE (bit 3): global kesme izni.
    //
    // csrsi (anlik degerli set) bu cekirdekte mstatus uzerinde
    // islemedi - olculdu, mstatus.mie 0 kaldi. csrr/csrw ikilisi
    // calisiyor (mtvec ve mie bu yolla yazildi), o yuzden
    // oku-degistir-yaz kullaniyoruz.
    __asm__ volatile ("csrr %0, mstatus" : "=r"(t));
    t |= (1u << 3);
    __asm__ volatile ("csrw mstatus, %0" :: "r"(t));
}
// Timer kesmesiyle bekleme. Islemci bu sure boyunca uyur;
// mesgul bekleme dongusunun aksine bos yere calismaz.
static void timer_wait_ms(unsigned int ms)
{
    if (ms == 0) return;

    *TIM_ENA = 0;         // durdur
    *TIM_CLR = 1;         // sayaci sifirla
    *TIM_EVC = 1;         // eski olaylari temizle
    *TIM_MOD = 1;         // yukari say
    *TIM_PRE = 49999;     // 50000 cevrim = 1 ms @ 50 MHz
    *TIM_ARE = ms - 1;    // ms adet tik sonra olay
    timer_flag = 0;
    *TIM_ENA = 1;         // baslat

    while (!timer_flag) {
        __asm__ volatile ("wfi");
    }
}


// =============================================================================
// Ana program
// =============================================================================

int main(void)
{
    uart_init();
    irq_init();

    uart_print("\n*** ARKHE FPGA TEST ***\n");
        // Timer kesmesi oz testi - simulasyonda deterministik olarak
    // dogrulanabilsin diye kisa tutuldu
    uart_print("Timer test\n");
    timer_wait_ms(2);
    uart_print("Timer OK\n");

    // GPIO'nun tum pinlerini cikis moduna al
    *GPIO_MODE = 0x55555555;
    *GPIO_ODR  = 0x0000;

    int run_count = 0;

    while (1) {
        run_count++;
        uart_print("\nRun: ");
        uart_print_dec(run_count);
        uart_print("\n");

        // NPU yerel bellegini temizle (30 kB = 7680 kelime)
        uart_print("Clear TCM\n");
        for (int i = 0; i < 7680; i++) {
            NPU_TCM_BASE[i] = 0;
        }

        // =================================================================
        // Girdi tensorunu UART-stream uzerinden al ve DMA ile TCM'e tasi
        //
        // Sartname EK-1 s.21:
        //   "UART-stream cevresel birimi cikarim yapilacak veriyi iletecek
        //    ve bu veri istenilen hizlandirici bellek adresine yazilacaktir."
        //
        // Akis:  UART2 RX -> stream FIFO -> UARTS_RDR32 (4 bayt paketli)
        //        -> DMA -> TCM (0x20010000) -> NPU
        //
        // CPU veriyi tasimaz; yalnizca konfigurasyonu yazip uyur.
        // =================================================================

        // UART-stream'i 1 Mbps'e ayarla (EK-2 s.22: 1 Mbps destegi zorunlu).
        // Genel UART 115200'de kalir - iki farkli baud hizi boylece gosterilir.
        *UARTS_CPB = 50;          // 50 MHz / 1 Mbps
        *UARTS_STP = 0;           // 1 stop biti
        *UARTS_CLR = 1;           // FIFO'yu temizle

        // DMA: kaynak sabit (paketli FIFO yazmaci), hedef artan (TCM)
        *DMA_SRC = (unsigned int)UARTS_RDR32_ADDR;
        *DMA_DST = (unsigned int)NPU_TCM_BASE;
        *DMA_LEN = TENSOR_WORDS;
        dma_flag = 0;

        // Testbench bu satiri gorunce veri gondermeye baslar.
        //
        // SIRA ONEMLI: bu mesaj DMA baslatilmadan ONCE yazilmali. DMA
        // basladiktan sonra bos FIFO'yu beklerken veri yolunu tutar ve
        // CPU'nun UART yazmasi tikanir - o durumda testbench "Stream ready"
        // satirini hic gormez ve sistem kilitlenir.
        //
        // FIFO 256 bayt; DMA mikrosaniyeler icinde basladigi icin erken
        // gelen baytlar kaybolmaz.
        uart_print("Stream ready\n");

        *DMA_CTRL = DMA_CTRL_SRC_FIXED | DMA_CTRL_START;
        *DMA_CTRL = DMA_CTRL_SRC_FIXED;   // start seviyesini birak

        // DMA bitene kadar uyu
        while (!dma_flag) {
            __asm__ volatile ("wfi");
        }
        uart_print("DMA done\n");

        // --- NPU'yu sifirla ---
        *NPU_REG_CTRL = NPU_CTRL_RESET;
        for (volatile int d = 0; d < 50; d++) { }

        // Reseti birak, kesmeyi etkinlestir
        *NPU_REG_CTRL = NPU_CTRL_IRQ_EN;
        npu_done_flag = 0;

        uart_print("Start NPU\n");

        // Baslat, sonra start bitini birak (irq_enable acik kalir).
        // Start yuksek kalirsa npu_csr done_sticky'yi surekli sifirlar.
        *NPU_REG_CTRL = NPU_CTRL_IRQ_EN | NPU_CTRL_START;
        *NPU_REG_CTRL = NPU_CTRL_IRQ_EN;

        // Kesme gelene kadar uyu. WFI islemciyi durdurur; yoklama
        // dongusunun aksine bos yere guc harcamaz.
        while (!npu_done_flag) {
            __asm__ volatile ("wfi");
        }

        unsigned int decision = npu_class;

        if (decision == 0) {
            uart_print("-> SILENCE\n");
            *GPIO_ODR = 0x0F0F;
        } else if (decision == 2) {
            uart_print("-> YES\n");
            *GPIO_ODR = 0x5555;
        } else if (decision == 3) {
            uart_print("-> NO\n");
            *GPIO_ODR = 0xAAAA;
        } else {
            uart_print("-> UNKNOWN\n");
            *GPIO_ODR = 0xFFFF;
        }

        // Yaklasik 3 saniye bekle
        // 3 saniye bekle. Islemci timer kesmesini bekleyerek uyur;
        // eskiden 12 milyon iterasyonluk mesgul bekleme vardi.
        uart_print("Wait 3s\n");
        timer_wait_ms(3000);

    }

    return 0;
}
