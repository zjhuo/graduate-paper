if {![info exists TARGET_PART]} {
  if {[info exists ::argv] && [llength $::argv] >= 1} {
    set TARGET_PART [lindex $::argv 0]
  }
}

if {![info exists TARGET_PART]} {
  puts "ERROR: TARGET_PART is not set."
  puts "Usage example:"
  puts "  vivado -mode batch -source run_z7_lite_board_bringup_synth.tcl -tclargs xc7z010clg400-1"
  exit 1
}

set part_name $TARGET_PART

read_verilog -sv [list \
  iotpufs_pkg.sv \
  fixed_challenge_table.sv \
  apuf_capture_ctrl.sv \
  response_aggregate_ctrl.sv \
  hamming1611_core_stub.sv \
  spongent_core_stub.sv \
  protocol_fsm_stub.sv \
  iotpufs_terminal_top.sv \
  iotpufs_terminal_board_bringup_top.sv \
]

read_xdc z7_lite_board_bringup.xdc

synth_design -top iotpufs_terminal_board_bringup_top -part $part_name

report_utilization -file synth_z7_lite_bringup_utilization.rpt
report_timing_summary -file synth_z7_lite_bringup_timing_summary.rpt
report_timing -max_paths 20 -file synth_z7_lite_bringup_timing_paths.rpt

write_checkpoint -force synth_z7_lite_bringup.dcp

puts "Z7 Lite board bring-up synthesis completed for part: $part_name"
