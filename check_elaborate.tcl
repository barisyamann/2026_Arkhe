set_param general.maxThreads 1
set_msg_config -id {Synth 8-7129} -suppress
set_msg_config -id {Synth 8-11067} -suppress
open_project ./vivado_project/Arkhe_SoC.xpr
if {[catch {synth_design -top soc_top -part xc7a35tcsg324-1 -rtl} result]} {
    puts "========================================"
    puts "ELABORATION FAILED!"
    puts "Result: $result"
    puts "Error Code: $errorCode"
    puts "Error Info:\n$errorInfo"
    puts "========================================"
} else {
    puts "ELABORATION SUCCEEDED!"
}
close_project
