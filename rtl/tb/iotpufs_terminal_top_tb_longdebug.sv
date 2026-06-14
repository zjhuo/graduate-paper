`timescale 1ns/1ps

module iotpufs_terminal_top_tb_longdebug;
  import iotpufs_pkg::*;

  logic clk_i;
  logic rst_ni;
  logic start_i;
  logic puf_resp_i;
  logic puf_resp_valid_i;
  logic [HELPER_MASK_W-1:0] helper_mask_i;
  logic [HELPER_XOR_W-1:0]  helper_xor_i;
  logic [SALT_W-1:0]        salt_i;
  logic [CHECKSUM_W-1:0]    checksum_i;
  logic [DEVICE_ID_W-1:0]   device_id_i;
  logic sample_req_o;
  logic session_busy_o;
  logic auth_done_o;
  logic auth_pass_o;
  logic recover_success_o;
  logic checksum_match_o;
  logic [KEY_W-1:0]         key_hat_o;
  logic [UNREL_W-1:0]       unreliable_vector_o;

  int sample_counter_q;
  int cycle_q;
  logic [2:0] prev_fsm_q;
  logic [2:0] prev_ham_q;
  logic [CHECKSUM_W-1:0] checksum_calc_q;
  logic                  checksum_calc_seen_q;

  iotpufs_terminal_top u_dut (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .start_i(start_i),
    .puf_resp_i(puf_resp_i),
    .puf_resp_valid_i(puf_resp_valid_i),
    .helper_mask_i(helper_mask_i),
    .helper_xor_i(helper_xor_i),
    .salt_i(salt_i),
    .checksum_i(checksum_i),
    .device_id_i(device_id_i),
    .sample_req_o(sample_req_o),
    .session_busy_o(session_busy_o),
    .auth_done_o(auth_done_o),
    .auth_pass_o(auth_pass_o),
    .recover_success_o(recover_success_o),
    .checksum_match_o(checksum_match_o),
    .key_hat_o(key_hat_o),
    .unreliable_vector_o(unreliable_vector_o)
  );

  initial begin
    clk_i = 1'b0;
    forever #5 clk_i = ~clk_i;
  end

  initial begin
    rst_ni        = 1'b0;
    start_i       = 1'b0;
    helper_mask_i = '1;
    helper_xor_i  = '0;
    salt_i        = 128'h0011_2233_4455_6677_8899_aabb_ccdd_eeff;
    checksum_i    = 128'h28f6_a05b_4331_99f5_a0d4_801f_2393_9cf0;
    device_id_i   = 128'h4445_5649_4345_5f30_3030_0000_0000_0001;

    repeat (4) @(posedge clk_i);
    rst_ni = 1'b1;

    repeat (2) @(posedge clk_i);
    start_i = 1'b1;
    @(posedge clk_i);
    start_i = 1'b0;
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      puf_resp_valid_i <= 1'b0;
      puf_resp_i       <= 1'b0;
      sample_counter_q <= 0;
      cycle_q          <= 0;
      prev_fsm_q       <= '0;
      prev_ham_q       <= '0;
      checksum_calc_q       <= '0;
      checksum_calc_seen_q  <= 1'b0;
    end else begin
      cycle_q <= cycle_q + 1;
      puf_resp_valid_i <= 1'b0;

      if (sample_req_o) begin
        puf_resp_valid_i <= 1'b1;
        puf_resp_i       <= sample_counter_q[0];
        sample_counter_q <= sample_counter_q + 1;
      end

      if ((cycle_q == 0) ||
          (u_dut.u_protocol_fsm_stub.state_q != prev_fsm_q) ||
          (u_dut.u_hamming1611_core_stub.state_q != prev_ham_q) ||
          ((cycle_q % 2000) == 0)) begin
        $display("[LONGDBG] cyc=%0d fsm=%0d ham=%0d sp_state=%0d sp_phase=%0d seg=%0d seg_b=%0d dig=%0d sample_req=%0d puf_resp_valid=%0d agg_done=%0d cap_done=%0d rec_done=%0d hash_done=%0d auth_done=%0d samples=%0d blk=%0d scan=%0d usable=%0d checksum_match=%0d auth_pass=%0d", 
          cycle_q,
          u_dut.u_protocol_fsm_stub.state_q,
          u_dut.u_hamming1611_core_stub.state_q,
          u_dut.u_spongent_core_stub.state_q,
          u_dut.u_spongent_core_stub.phase_q,
          u_dut.u_spongent_core_stub.seg_step_q,
          u_dut.u_spongent_core_stub.seg_byte_idx_q,
          u_dut.u_spongent_core_stub.digest_idx_q,
          sample_req_o,
          puf_resp_valid_i,
          u_dut.u_response_aggregate_ctrl.aggregate_done_o,
          u_dut.capture_pass_done_q,
          u_dut.recover_done,
          u_dut.hash_done,
          auth_done_o,
          sample_counter_q,
          u_dut.u_hamming1611_core_stub.block_idx_q,
          u_dut.u_hamming1611_core_stub.scan_idx_q,
          u_dut.u_hamming1611_core_stub.usable_count_q,
          checksum_match_o,
          auth_pass_o);
      end

      if (!checksum_calc_seen_q &&
          (u_dut.u_spongent_core_stub.state_q == u_dut.u_spongent_core_stub.ST_SQUEEZE) &&
          (u_dut.u_spongent_core_stub.phase_q == u_dut.u_spongent_core_stub.PH_CHECKSUM) &&
          u_dut.u_spongent_core_stub.last_digest_byte) begin
        checksum_calc_q      <= u_dut.u_spongent_core_stub.digest_next;
        checksum_calc_seen_q <= 1'b1;
        $display("[LONGDBG] checksum_capture cyc=%0d checksum_i=%h checksum_calc=%h",
          cycle_q,
          checksum_i,
          u_dut.u_spongent_core_stub.digest_next);
      end

      prev_fsm_q <= u_dut.u_protocol_fsm_stub.state_q;
      prev_ham_q <= u_dut.u_hamming1611_core_stub.state_q;
    end
  end

  initial begin
    repeat (120000) @(posedge clk_i) begin
      if (auth_done_o) begin
        $display("[LONGDBG] vector_dump message_bits_hat=%h", u_dut.message_bits_hat);
        $display("[LONGDBG] vector_dump salt=%h", salt_i);
        $display("[LONGDBG] vector_dump device_id=%h", device_id_i);
        $display("[LONGDBG] vector_dump checksum_i=%h", checksum_i);
        $display("[LONGDBG] vector_dump checksum_calc=%h", checksum_calc_q);
        $display("[LONGDBG] vector_dump k_hat=%h", key_hat_o);
        $display("[LONGDBG] auth_done observed, samples=%0d, key=%h, checksum_match=%0d",
          sample_counter_q,
          key_hat_o,
          checksum_match_o);
        #10;
        $finish;
      end
    end

    $fatal(1, "[LONGDBG] timeout before auth_done");
  end
endmodule
