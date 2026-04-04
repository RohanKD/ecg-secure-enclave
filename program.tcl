# program.tcl — Program Basys 3 FPGA with bitstream
# Usage: vivado -mode batch -source program.tcl

open_hw_manager
connect_hw_server -allow_non_jtag

# Auto-detect the FPGA
open_hw_target

set device [get_hw_devices xc7a35t_0]
current_hw_device $device
set_property PROGRAM.FILE {./ecg_secure_enclave.bit} $device

puts "Programming FPGA..."
program_hw_devices $device

puts "Programming complete!"
close_hw_target
disconnect_hw_server
close_hw_manager
