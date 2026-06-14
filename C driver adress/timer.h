#ifndef TIMER_H
#define TIMER_H

// memory_map_pck.sv: TIMER_BASE = 32'h4001_0000
#define TIMER_BASE_ADDR 0x40010000 

// Şartname: Timer Yazmaç Ofsetleri
#define TIM_PRE_REG (*(volatile unsigned int *)(TIMER_BASE_ADDR + 0x00))
#define TIM_ARE_REG (*(volatile unsigned int *)(TIMER_BASE_ADDR + 0x04))
#define TIM_CLR_REG (*(volatile unsigned int *)(TIMER_BASE_ADDR + 0x08))
#define TIM_ENA_REG (*(volatile unsigned int *)(TIMER_BASE_ADDR + 0x0C))
#define TIM_MOD_REG (*(volatile unsigned int *)(TIMER_BASE_ADDR + 0x10))
#define TIM_CNT_REG (*(volatile unsigned int *)(TIMER_BASE_ADDR + 0x14))
#define TIM_EVN_REG (*(volatile unsigned int *)(TIMER_BASE_ADDR + 0x18))
#define TIM_EVC_REG (*(volatile unsigned int *)(TIMER_BASE_ADDR + 0x1C))

#endif // TIMER_H