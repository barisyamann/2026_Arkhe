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
}


// Kesme altyapisini kur
static void irq_init(void)
{
    unsigned int t;

    // mtvec: kesme rutininin adresi. Bit 0 = 0 -> dogrudan mod.
    t = (unsigned int)&trap_handler;
    __asm__ volatile ("csrw mtvec, %0" :: "r"(t));

    // mie: yalnizca NPU kesmesini etkinlestir
    t = (1u << NPU_IRQ_BIT);
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


// =============================================================================
// Ana program
// =============================================================================

int main(void)
{
    uart_init();
    irq_init();

    uart_print("\n*** ARKHE FPGA TEST ***\n");

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

        // Giris tensoru 1960 bayt = 490 kelime. TAMAMI doldurulmalidir;
        // yalnizca ilk kelimeyi yazmak girdinin binde ikisini degistirir
        // ve butun senaryolar ayni sinifi verir.
        //
        // TFLite girdi zero-point = -128. Gercek deger 0'a karsilik gelen
        // nicemlenmis bayt 0x80'dir; 0x00 sessizlik degil, buyuk pozitif
        // sinyal demektir.
        unsigned int pattern;
        int mode = run_count % 3;

        if (mode == 1) {
            pattern = 0x55555555;
            uart_print("In: PATTERN A\n");
        } else if (mode == 2) {
            pattern = 0xAAAAAAAA;
            uart_print("In: PATTERN B\n");
        } else {
            pattern = 0x80808080;
            uart_print("In: SILENCE\n");
        }

        for (int i = 0; i < 490; i++) {
            NPU_TCM_BASE[i] = pattern;
        }

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
        uart_print("Wait 3s\n");
        for (volatile int delay = 0; delay < 12000000; delay++) { }
    }

    return 0;
}
