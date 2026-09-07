/* Uygulama: yukleyici tarafindan QSPI flash'tan I-RAM'e yazilir.
   Kod   -> I-RAM  0x01000000 (8 kB)
   Veri  -> D-RAM  0x20000000 (8 kB) */

OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY
{
  IRAM (rx)  : ORIGIN = 0x01000000, LENGTH = 8K
  RAM  (rwx) : ORIGIN = 0x20000000, LENGTH = 8K
}

SECTIONS
{
  .text :
  {
    . = ALIGN(4);
    KEEP(*(.init))
    KEEP(*(.text.start))
    *(.text*)
    *(.rodata*)
    . = ALIGN(4);
  } > IRAM

  .data :
  {
    . = ALIGN(4);
    __data_start = .;
    *(.data*)
    . = ALIGN(4);
    __data_end = .;
  } > RAM AT > IRAM

  __data_load_start = LOADADDR(.data);

  .bss (NOLOAD) :
  {
    . = ALIGN(4);
    __bss_start = .;
    *(.bss*)
    *(COMMON)
    . = ALIGN(4);
    __bss_end = .;
  } > RAM

  .stack (NOLOAD) :
  {
    . = ALIGN(16);
    __stack_top = ORIGIN(RAM) + LENGTH(RAM);
  } > RAM
}
