open_project ./vivado/vivado_project/Arkhe_SoC.xpr
set run [get_runs synth_1]
foreach prop [list_property $run] {
    catch {
        puts "$prop: [get_property $prop $run]"
    }
}
close_project
