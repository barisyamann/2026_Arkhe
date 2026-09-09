/* En kucuk olasi test: yalnizca UART'a yazar, baska hicbir seye dokunmaz.
 *
 * NEDEN: npu_demo.c hicbir cikti vermedi; fpga_demo.c ayni kartta ayni
 * UART ile calisiyordu. "UART tek basina calisiyor mu" sorusunu ayirmak
 * icin yazildi.
 *
 * Bu imaj hicbir dongu, dizi, TCM erisimi veya NPU islemi icermez -
 * yalnizca UART yazma yolunu kullanir.
 *
 * SONUC (9 Eylul 2026): bu imaj da sessiz kaldi ve ayni koku paylastigi
 * ortaya cikti - U1_CFG icin UART1_BASE + 0x00 kullanilmisti, dogrusu
 * + 0x10 (uart_peripheral.sv:13). Yanlis yazmac yoklandigi icin
 * "iletim tamamlandi" biti hic kurulmuyor ve uart_putc ilk karakterde
 * sonsuza kadar donuyordu.
 *
 * Araci depoda tutuyoruz: benzer bir tam-sessizlik arizasinda ilk
 * basvurulacak en kucuk test budur.
 */

#define UART1_BASE  0x40020000u
#define U1_CFG      ((volatile unsigned int *)(UART1_BASE + 0x10))  /* uart_peripheral.sv:13 */
#define U1_TDR      ((volatile unsigned int *)(UART1_BASE + 0x0C))

static void uart_putc(char c)
{
    *U1_TDR = (unsigned int)c;
    *U1_CFG |= (1u << 0);
    while (!(*U1_CFG & (1u << 2))) { }
    *U1_CFG &= ~(1u << 2);
}

static void uart_print(const char *s)
{
    while (*s) {
        if (*s == '\n') uart_putc('\r');
        uart_putc(*s++);
    }
}

int main(void)
{
    volatile unsigned int i;

    for (;;) {
        uart_print("UART_MIN CALISIYOR\n");
        for (i = 0; i < 2000000u; i++) { }
    }
    return 0;
}
