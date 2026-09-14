set_param general.maxThreads 2
create_project Arkhe_DemoC ./fpga/DEMO_C_I2C/vivado -part xc7a100tcsg324-1 -force
set_property target_language Verilog [current_project]
set_property include_dirs [list [file normalize rtl/cv32e40p-master/rtl/include] [file normalize rtl/Memory] [file normalize rtl/Cevre_Birimleri/files_1]] [current_fileset]
set f [open asic/filelist.f r]
foreach line [split [read $f] "\n"] {
    set line [string trim $line]
    if {$line eq "" || [string index $line 0] eq "#"} {continue}
    if {[string match "*boot_rom_pkg.sv" $line]} {add_files -norecurse fpga/DEMO_C_I2C/boot_rom_pkg.sv} else {add_files -norecurse [file normalize $line]}
}
close $f
add_files -norecurse fpga/DEMO_C_I2C/nexys_usb_top.sv
add_files -fileset constrs_1 -norecurse fpga/DEMO_C_I2C/nexys_usb.xdc
set_property top nexys_usb_top [current_fileset]
update_compile_order -fileset sources_1
launch_runs impl_1 -to_step write_bitstream -jobs 2
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {error "FPGA build incomplete"}
open_run impl_1
report_timing_summary -file fpga/DEMO_C_I2C/timing.rpt
report_utilization -file fpga/DEMO_C_I2C/utilization.rpt
report_drc -file fpga/DEMO_C_I2C/drc.rpt
set f [open fpga/DEMO_C_I2C/build_result.txt w]
puts $f "STATUS [get_property STATUS [get_runs impl_1]]"
foreach k {WNS TNS WHS THS} {puts $f "$k [get_property STATS.$k [get_runs impl_1]]"}
close $f
file copy -force fpga/DEMO_C_I2C/vivado/Arkhe_DemoC.runs/impl_1/nexys_usb_top.bit fpga/DEMO_C_I2C/nexys_usb_top.bit
write_cfgmem -format mcs -size 16 -interface SPIx4 -loadbit "up 0x00000000 fpga/DEMO_C_I2C/nexys_usb_top.bit" -loaddata "up 0x00800000 fpga/DEMO_C_I2C/flash_jury.bin" -file fpga/DEMO_C_I2C/arkhe_demo_c.mcs -force
close_project
