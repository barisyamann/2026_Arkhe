/* 1. Asama yukleyici: yalnizca Boot ROM'da calisir.
   Veri ve bss yok - saf assembly. */

OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY
{
  BOOTROM (rx) : ORIGIN = 0x00000000, LENGTH = 1K
}

SECTIONS
{
  .text :
  {
    . = ALIGN(4);
    KEEP(*(.text.start))
    *(.text*)
    *(.rodata*)
    . = ALIGN(4);
  } > BOOTROM

  /DISCARD/ : { *(.comment) *(.note*) *(.eh_frame*) }
}
