set here [file dirname [file normalize [info script]]]
set root [file normalize [file join $here ../..]]
cd $root
set out [file join $here build]
if {[file exists $out]} {error "build already exists; preserve it before a fresh build"}
create_project arkhe_d45_demo $out -part xc7a100tcsg324-1
set_property include_dirs [list $root/rtl/cv32e40p-master/rtl/include $root/rtl/Memory $root/rtl/Cevre_Birimleri/files_1] [current_fileset]
set fh [open $root/asic/filelist.f r]
foreach line [split [read $fh] "\n"] {
 set line [string trim $line]
 if {$line ne "" && ![string match "#*" $line]} {add_files -norecurse [file join $root $line]}
}
close $fh
add_files -norecurse $here/rtl/nexys_top.sv
add_files -fileset constrs_1 -norecurse $here/constraints/nexys4ddr.xdc
set_property top nexys_top [current_fileset]
update_compile_order -fileset sources_1
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {error "FPGA implementation failed"}
close_project
