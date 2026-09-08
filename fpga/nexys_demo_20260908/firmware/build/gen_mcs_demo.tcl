# Vivado MCS generator - DEMO imaji (DEMO_MODE firmware)
write_cfgmem -format mcs -size 16 -interface SPIx4 \
    -loadbit "up 0x00000000 C:/Users/ybari/2026_Arkhe/vivado/vivado_nexys_project/Arkhe_SoC_Nexys.runs/impl_1/nexys_top.bit" \
    -loaddata "up 0x00800000 C:/Users/ybari/2026_Arkhe/sw_nexys/build/flash_demo.bin" \
    -file "C:/Users/ybari/2026_Arkhe/sw_nexys/build/arkhe_demo_flash.mcs" -force
puts "\[OK\] Generated: arkhe_demo_flash.mcs"
