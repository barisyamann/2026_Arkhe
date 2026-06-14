# ==============================================================================
#  build_nexys.tcl
#  Automate synthesis, implementation, and bitstream generation for Nexys 4 DDR
# ==============================================================================

# Close any open project
catch {close_project}

# Open the project
open_project ./vivado_nexys_project/Arkhe_SoC_Nexys.xpr

# Reset existing runs to ensure a clean build
puts "Resetting existing runs..."
reset_run synth_1
reset_run impl_1

# Launch synthesis and implementation up to bitstream generation
puts "Launching implementation and bitstream generation..."
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

# Check progress and status
set status [get_property STATUS [get_runs impl_1]]
set progress [get_property PROGRESS [get_runs impl_1]]
puts "Implementation Run Status: $status ($progress)"

# Close project
close_project
