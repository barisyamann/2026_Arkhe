open_project ./vivado_project/Arkhe_SoC.xpr
puts "========================================"
set runs [get_runs]
foreach r $runs {
    set status [get_property STATUS [get_runs $r]]
    set progress [get_property PROGRESS [get_runs $r]]
    puts "Run: $r -> Status: $status, Progress: $progress"
}
puts "========================================"
close_project
