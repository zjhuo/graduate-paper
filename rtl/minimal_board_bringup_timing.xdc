create_clock -name sys_clk -period 10.000 [get_ports clk_i]
set_false_path -from [get_ports rst_ni]
set_input_delay -clock [get_clocks sys_clk] 2.000 [get_ports {start_i}]
set_false_path -to [get_ports {session_busy_o auth_done_o auth_pass_o recover_success_o checksum_match_o}]
