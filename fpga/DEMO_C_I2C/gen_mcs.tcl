write_cfgmem -format mcs -size 16 -interface SPIx4 \
  -loadbit  "up 0x00000000 C:/Users/ybari/2026_Arkhe/fpga/DEMO_C_I2C/nexys_usb_top.bit" \
  -loaddata "up 0x00800000 C:/Users/ybari/2026_Arkhe/fpga/DEMO_C_I2C/flash_jury.bin" \
  -file     "C:/Users/ybari/2026_Arkhe/fpga/DEMO_C_I2C/arkhe_demo_c.mcs" -force
