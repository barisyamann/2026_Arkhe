#ifndef GPIO_H
#define GPIO_H

// memory_map_pck.sv: GPIO_BASE = 32'h4000_0000
#define GPIO_BASE_ADDR 0x40000000 

// Şartname: GPIO Yazmaç Ofsetleri
#define GPIO_IDR_REG (*(volatile unsigned int *)(GPIO_BASE_ADDR + 0x00))
#define GPIO_ODR_REG (*(volatile unsigned int *)(GPIO_BASE_ADDR + 0x04))

#endif // GPIO_H