#ifndef UART_H
#define UART_H

#include <stdint.h>

// 1. ADIM: Vivado'daki memory_map_pck.sv dosyasını aç. 
// Oradaki UART1 Base Adresini bul ve buraya yaz.
#define UART1_BASE_ADDR 0x10000000  // DİKKAT: Bu örnek adrestir, kendinizinkiyle değiştirin!

// 2. ADIM: Register Offsetlerini Tanımla (Donanım tasarımına göre)
#define UART_TX_REG   (*(volatile uint32_t*)(UART1_BASE_ADDR + 0x00))
#define UART_RX_REG   (*(volatile uint32_t*)(UART1_BASE_ADDR + 0x04))
#define UART_CTRL_REG (*(volatile uint32_t*)(UART1_BASE_ADDR + 0x08))
#define UART_STAT_REG (*(volatile uint32_t*)(UART1_BASE_ADDR + 0x0C))

// 3. ADIM: Donanıma veri gönderen basit bir C fonksiyonu
void uart_send_char(char c) {
    // TX buffer'ın müsait olup olmadığını kontrol et
    while ((UART_STAT_REG & 0x01) == 0); 
    // Karakteri doğrudan donanım adresine yaz
    UART_TX_REG = c;
}

#endif