#ifndef QSPI_H
#define QSPI_H

// memory_map_pck.sv: QSPI_BASE = 32'h4005_0000
#define QSPI_BASE_ADDR 0x40050000 

// Şartname: QSPI Yazmaç Ofsetleri
#define QSPI_CCR_REG (*(volatile unsigned int *)(QSPI_BASE_ADDR + 0x00))
#define QSPI_ADR_REG (*(volatile unsigned int *)(QSPI_BASE_ADDR + 0x04))
#define QSPI_DR_REG  (*(volatile unsigned int *)(QSPI_BASE_ADDR + 0x08))
#define QSPI_STA_REG (*(volatile unsigned int *)(QSPI_BASE_ADDR + 0x0C))
#define QSPI_FCR_REG (*(volatile unsigned int *)(QSPI_BASE_ADDR + 0x10))

#endif // QSPI_H