# Tam cevre birimi demosu - fpga_demo.hex + 9 Eylul bitstream (JTAG/GPIO pinli)
write_cfgmem -format mcs -size 16 -interface SPIx4 \
    -loadbit "up 0x00000000 C:/Users/ybari/2026_Arkhe/fpga/nexys_demo_20260908/bitstream/nexys_top.bit" \
    -loaddata "up 0x00800000 C:/Users/ybari/2026_Arkhe/sw_nexys/build/flash_fpga_demo.bin" \
    -file "C:/Users/ybari/2026_Arkhe/sw_nexys/build/arkhe_fpga_demo.mcs" -force
puts "\[OK\] arkhe_fpga_demo.mcs uretildi"
