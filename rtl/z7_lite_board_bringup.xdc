## Z7 Lite board-specific bring-up constraints
## Derived from MicroPhase Z7_LITE.xdc, adapted to iotpufs_terminal_board_bringup_top

## Clock: PL 50 MHz
set_property PACKAGE_PIN N18 [get_ports clk_i]
set_property IOSTANDARD LVCMOS33 [get_ports clk_i]
create_clock -name sys_clk -period 20.000 [get_ports clk_i]

## Keys
## Note: electrical polarity of board buttons should be confirmed on schematic/board test.
## Here we only bind pins; logic polarity is left unchanged.
set_property PACKAGE_PIN T12 [get_ports rst_ni]
set_property PACKAGE_PIN P16 [get_ports start_i]
set_property IOSTANDARD LVCMOS33 [get_ports rst_ni]
set_property IOSTANDARD LVCMOS33 [get_ports start_i]

## LEDs
set_property PACKAGE_PIN P15 [get_ports auth_pass_o]
set_property PACKAGE_PIN U12 [get_ports auth_done_o]
set_property IOSTANDARD LVCMOS33 [get_ports auth_pass_o]
set_property IOSTANDARD LVCMOS33 [get_ports auth_done_o]

## Optional status outputs via GPIO header
set_property PACKAGE_PIN N17 [get_ports session_busy_o]
set_property PACKAGE_PIN R16 [get_ports recover_success_o]
set_property PACKAGE_PIN T16 [get_ports checksum_match_o]
set_property IOSTANDARD LVCMOS33 [get_ports session_busy_o]
set_property IOSTANDARD LVCMOS33 [get_ports recover_success_o]
set_property IOSTANDARD LVCMOS33 [get_ports checksum_match_o]

## Bring-up timing semantics
set_false_path -from [get_ports rst_ni]
set_input_delay -clock [get_clocks sys_clk] 2.000 [get_ports {start_i}]
set_false_path -to [get_ports {session_busy_o auth_done_o auth_pass_o recover_success_o checksum_match_o}]
