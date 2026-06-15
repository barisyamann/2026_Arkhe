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

// Initialise UART
void uart_init() {
    UART->CPB = 434; // 50 MHz / 115200 Baud = 434
    UART->STP = 0;   // 1 Stop bit
    UART->CFG = 0;
}

// Write a character to UART
void uart_putc(char c) {
    UART->TDR = c;
    UART->CFG |= (0x1UL << 0); // Enable data transmit
    while (!(UART->CFG & (0x1UL << 2))){} // Wait for transmit completed flag
    UART->CFG &= ~(0x1UL << 2); // Clear flag
}

// Print string to UART
void uart_print(const char *str) {
    while (*str) {
        if (*str == '\n') {
            uart_putc('\r');
        }
        uart_putc(*str++);
    }
}

// Print integer value in decimal
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

int main() {
    uart_init();
    uart_print("\n*** ARKHE FPGA TEST ***\n");

    // GPIO All Outputs Mode (0x55555555)
    *GPIO_MODE = 0x55555555;
    *GPIO_ODR = 0x0000;

    int run_count = 0;

    while (1) {
        run_count++;
        uart_print("\nRun: ");
        uart_print_dec(run_count);
        uart_print("\n");

        // Clear NPU TCM SRAM (30 kB = 7680 words)
        uart_print("Clear TCM\n");
        for (int i = 0; i < 7680; i++) {
            NPU_TCM_BASE[i] = 0;
        }

        // Alternating input template (YES on odd runs, NO on even runs)
        if (run_count % 2 == 1) {
            NPU_TCM_BASE[0] = 0x55555555;
            uart_print("In: YES\n");
        } else {
            NPU_TCM_BASE[0] = 0xAAAAAAAA;
            uart_print("In: NO\n");
        }

        // Reset and start NPU
        *NPU_REG_CTRL = 2; // Reset
        for (volatile int d = 0; d < 50; d++); // delay
        *NPU_REG_CTRL = 0; // Release Reset

        uart_print("Start NPU\n");
        *NPU_REG_CTRL = 1; // Start

        // Wait for Done status (Done bit = 1)
        int timeout = 0;
        while (!(*NPU_REG_STATUS & 2)) {
            timeout++;
            if (timeout > 4000000) {
                uart_print("Timeout!\n");
                break;
            }
        }

        if (*NPU_REG_STATUS & 2) {
            unsigned int decision = *NPU_REG_CLASS & 3;
            uart_print("Class: ");
            uart_print_dec(decision);
            
            if (decision == 2) {
                uart_print(" (YES)\n");
                *GPIO_ODR = 0x5555; // YES Pattern
            } else if (decision == 3) {
                uart_print(" (NO)\n");
                *GPIO_ODR = 0xAAAA; // NO Pattern
            } else {
                uart_print(" (UNK)\n");
                *GPIO_ODR = 0xFFFF;
            }
        }

        // Delay ~3 seconds
        uart_print("Wait 3s\n");
        for (volatile int delay = 0; delay < 12000000; delay++);
    }

    return 0;
}
