#ifndef I2C_H
#define I2C_H

// memory_map_pck.sv: I2C_BASE = 32'h4004_0000
#define I2C_BASE_ADDR 0x40040000 

// Şartname: I2C Master Yazmaç Ofsetleri
#define I2C_NBY_REG (*(volatile unsigned int *)(I2C_BASE_ADDR + 0x00))
#define I2C_ADR_REG (*(volatile unsigned int *)(I2C_BASE_ADDR + 0x04))
#define I2C_RDR_REG (*(volatile unsigned int *)(I2C_BASE_ADDR + 0x08))
#define I2C_TDR_REG (*(volatile unsigned int *)(I2C_BASE_ADDR + 0x0C))
#define I2C_CFG_REG (*(volatile unsigned int *)(I2C_BASE_ADDR + 0x10))

#endif // I2C_H