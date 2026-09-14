set_param general.maxThreads 2
create_project Arkhe_Jury ./jury_demo/vivado -part xc7a100tcsg324-1 -force
set_property target_language Verilog [current_project]
set_property include_dirs [list [file normalize rtl/cv32e40p-master/rtl/include] [file normalize rtl/Memory] [file normalize rtl/Cevre_Birimleri/files_1]] [current_fileset]
set f [open asic/filelist.f r]
foreach line [split [read $f] "\n"] {
    set line [string trim $line]
    if {$line eq "" || [string index $line 0] eq "#"} {continue}
    if {[string match "*boot_rom_pkg.sv" $line]} {add_files -norecurse jury_demo/boot_rom_pkg.sv} else {add_files -norecurse [file normalize [file join asic $line]]}
}
close $f
add_files -norecurse jury_demo/nexys_usb_top.sv
add_files -fileset constrs_1 -norecurse jury_demo/nexys_usb.xdc
set_property top nexys_usb_top [current_fileset]
update_compile_order -fileset sources_1
launch_runs impl_1 -to_step write_bitstream -jobs 2
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {error "FPGA build incomplete"}
open_run impl_1
report_timing_summary -file jury_demo/timing.rpt
report_utilization -file jury_demo/utilization.rpt
report_drc -file jury_demo/drc.rpt
set f [open jury_demo/build_result.txt w]
puts $f "STATUS [get_property STATUS [get_runs impl_1]]"
foreach k {WNS TNS WHS THS} {puts $f "$k [get_property STATS.$k [get_runs impl_1]]"}
close $f
file copy -force jury_demo/vivado/Arkhe_Jury.runs/impl_1/nexys_usb_top.bit jury_demo/nexys_usb_top.bit
write_cfgmem -format mcs -size 16 -interface SPIx4 -loadbit "up 0x00000000 jury_demo/nexys_usb_top.bit" -loaddata "up 0x00800000 jury_demo/flash_jury.bin" -file jury_demo/arkhe_jury.mcs -force
close_project
