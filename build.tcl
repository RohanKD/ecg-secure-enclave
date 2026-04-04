# build.tcl — Vivado batch build script for ECG Secure Enclave
# Usage: vivado -mode batch -source build.tcl
#
# Run from the i2p_fpga/ project directory.

set project_name "ecg_secure_enclave"
set part "xc7a35tcpg236-1"
set top_module "top_basys3"

# Create project
create_project $project_name ./$project_name -part $part -force

# Add RTL sources
add_files -norecurse [glob ./rtl/*.v]

# Add constraints
add_files -fileset constrs_1 -norecurse ./constraints/basys3.xdc

# Add memory init files
add_files -norecurse [glob ./mem/*.mem]

# Set top module
set_property top $top_module [current_fileset]

# Update compile order
update_compile_order -fileset sources_1

# ---- Synthesis ----
puts "=== Starting Synthesis ==="
launch_runs synth_1 -jobs 4
wait_on_run synth_1

# Check for errors
if {[get_property STATUS [get_runs synth_1]] != "synth_design Complete!"} {
    puts "ERROR: Synthesis failed!"
    exit 1
}

# Report synthesis utilization
open_run synth_1
report_utilization -file ./reports/synth_utilization.txt
report_timing_summary -file ./reports/synth_timing.txt
puts "Synthesis utilization report written to reports/"

# ---- Implementation ----
puts "=== Starting Implementation ==="
launch_runs impl_1 -jobs 4
wait_on_run impl_1

if {[get_property STATUS [get_runs impl_1]] != "route_design Complete!"} {
    puts "ERROR: Implementation failed!"
    exit 1
}

# Report implementation
open_run impl_1
report_utilization -file ./reports/impl_utilization.txt
report_timing_summary -file ./reports/impl_timing.txt
report_power -file ./reports/impl_power.txt
puts "Implementation reports written to reports/"

# ---- Generate Bitstream ----
puts "=== Generating Bitstream ==="
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

# Copy bitstream to project root
set bit_file [glob ./$project_name/$project_name.runs/impl_1/*.bit]
file copy -force $bit_file ./${project_name}.bit
puts "=== Bitstream generated: ${project_name}.bit ==="

# ---- Summary ----
puts ""
puts "Build complete!"
puts "  Bitstream: ${project_name}.bit"
puts "  Reports:   reports/"
puts ""
puts "To program the FPGA:"
puts "  1. Connect Basys 3 via USB"
puts "  2. Open Vivado Hardware Manager"
puts "  3. Auto-connect, then program with ${project_name}.bit"

exit 0
