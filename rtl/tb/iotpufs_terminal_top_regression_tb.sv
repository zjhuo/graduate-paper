`timescale 1ns/1ps

module iotpufs_terminal_top_regression_tb;
  import iotpufs_pkg::*;

  localparam logic [SALT_W-1:0]      SALT_GOOD     = 128'h0011_2233_4455_6677_8899_aabb_ccdd_eeff;
  localparam logic [CHECKSUM_W-1:0]  CHECKSUM_GOOD = 128'h28f6_a05b_4331_99f5_a0d4_801f_2393_9cf0;
  localparam logic [DEVICE_ID_W-1:0] DEVICE_ID     = 128'h4445_5649_4345_5f30_3030_0000_0000_0001;
  localparam logic [NONCE_W-1:0]     NONCE_D       = 128'habf8_2bce_5e84_f78f_1e3d_53f0_79c3_b39d;
  localparam logic [NONCE_W-1:0]     NONCE_S       = 128'h1b7d_12f8_4691_62da_6ed7_2010_c60a_9cb0;
  localparam logic [V_W-1:0]         V_I           = 128'heabc_8a51_7bc9_c497_a063_a2c0_e5ce_b081;
  localparam logic [C_INIT_W-1:0]    C_INIT        = 128'h199d_985a_6675_dd1e_b878_80fb_7b39_9fee;
  localparam logic [TAG_W-1:0]       S_TAG_GOOD    = 128'h6be0_336c_ea1f_cf61_d899_f68d_71cb_04e9;
  localparam logic [KEY_W-1:0]       K_HAT_GOOD    = 128'hf756_8117_c937_28f7_2ca4_886f_766f_3ac3;
  localparam logic [TAG_W-1:0]       H_TAG_GOOD    = 128'h08ca_eb20_0486_0a4e_b6c6_4a1f_016e_4ad0;

  typedef enum int {
    RESP_NORMAL = 0,
    RESP_INVERT = 1
  } resp_mode_e;

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
  logic [NONCE_W-1:0]       nonce_d_i;
  logic [NONCE_W-1:0]       nonce_s_i;
  logic [V_W-1:0]           v_i_i;
  logic [C_INIT_W-1:0]      c_init_i;
  logic [TAG_W-1:0]         s_tag_i;
  logic sample_req_o;
  logic session_busy_o;
  logic auth_done_o;
  logic auth_pass_o;
  logic recover_success_o;
  logic checksum_match_o;
  logic [TAG_W-1:0]         h_tag_o;
  logic [KEY_W-1:0]         key_hat_o;
  logic [UNREL_W-1:0]       unreliable_vector_o;

  int sample_counter_q;
  int failure_count_q;
  int current_resp_mode_q;
  string current_case_name_q;

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
    .nonce_d_i(nonce_d_i),
    .nonce_s_i(nonce_s_i),
    .v_i_i(v_i_i),
    .c_init_i(c_init_i),
    .s_tag_i(s_tag_i),
    .sample_req_o(sample_req_o),
    .session_busy_o(session_busy_o),
    .auth_done_o(auth_done_o),
    .auth_pass_o(auth_pass_o),
    .recover_success_o(recover_success_o),
    .checksum_match_o(checksum_match_o),
    .h_tag_o(h_tag_o),
    .key_hat_o(key_hat_o),
    .unreliable_vector_o(unreliable_vector_o)
  );

  initial begin
    clk_i = 1'b0;
    forever #5 clk_i = ~clk_i;
  end

  task automatic apply_defaults;
    begin
      start_i             = 1'b0;
      helper_mask_i       = '1;
      helper_xor_i        = '0;
      salt_i              = SALT_GOOD;
      checksum_i          = CHECKSUM_GOOD;
      device_id_i         = DEVICE_ID;
      nonce_d_i           = NONCE_D;
      nonce_s_i           = NONCE_S;
      v_i_i               = V_I;
      c_init_i            = C_INIT;
      s_tag_i             = S_TAG_GOOD;
      current_resp_mode_q = RESP_NORMAL;
    end
  endtask

  task automatic pulse_reset;
    begin
      rst_ni = 1'b0;
      repeat (4) @(posedge clk_i);
      rst_ni = 1'b1;
      repeat (2) @(posedge clk_i);
    end
  endtask

  task automatic pulse_start;
    begin
      start_i = 1'b1;
      @(posedge clk_i);
      start_i = 1'b0;
    end
  endtask

  task automatic wait_auth_done(output bit timed_out);
    int cyc;
    begin : wait_loop
      timed_out = 1'b1;
      for (cyc = 0; cyc < 120000; cyc = cyc + 1) begin
        @(posedge clk_i);
        if (auth_done_o) begin
          timed_out = 1'b0;
          disable wait_loop;
        end
      end
    end
  endtask

  task automatic check_equal_bit(input string label_s, input logic actual_v, input logic expect_v);
    begin
      if (actual_v !== expect_v) begin
        failure_count_q = failure_count_q + 1;
        $display("[REG][FAIL][%s] %s actual=%0d expect=%0d", current_case_name_q, label_s, actual_v, expect_v);
      end
    end
  endtask

  task automatic check_equal_vec(input string label_s, input logic [127:0] actual_v, input logic [127:0] expect_v);
    begin
      if (actual_v !== expect_v) begin
        failure_count_q = failure_count_q + 1;
        $display("[REG][FAIL][%s] %s actual=%h expect=%h", current_case_name_q, label_s, actual_v, expect_v);
      end
    end
  endtask

  task automatic run_case(
    input string case_name,
    input logic [CHECKSUM_W-1:0] checksum_val,
    input logic [TAG_W-1:0]      s_tag_val,
    input logic [HELPER_XOR_W-1:0] helper_xor_val,
    input int resp_mode,
    input logic exp_checksum_match,
    input logic exp_auth_pass,
    input logic check_fixed_vectors
  );
    bit timed_out;
    begin
      current_case_name_q = case_name;
      apply_defaults();
      checksum_i          = checksum_val;
      s_tag_i             = s_tag_val;
      helper_xor_i        = helper_xor_val;
      current_resp_mode_q = resp_mode;

      pulse_reset();
      pulse_start();
      wait_auth_done(timed_out);

      if (timed_out) begin
        failure_count_q = failure_count_q + 1;
        $display("[REG][FAIL][%s] timeout before auth_done", case_name);
      end else begin
        $display(
          "[REG][%s] auth_done=%0d checksum_match=%0d auth_pass=%0d k_hat=%h h_tag=%h",
          case_name,
          auth_done_o,
          checksum_match_o,
          auth_pass_o,
          key_hat_o,
          h_tag_o
        );

        check_equal_bit("auth_done", auth_done_o, 1'b1);
        check_equal_bit("checksum_match", checksum_match_o, exp_checksum_match);
        check_equal_bit("auth_pass", auth_pass_o, exp_auth_pass);

        if (check_fixed_vectors) begin
          check_equal_vec("k_hat", key_hat_o, K_HAT_GOOD);
          check_equal_vec("h_tag", h_tag_o, H_TAG_GOOD);
        end
      end

      repeat (5) @(posedge clk_i);
    end
  endtask

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      puf_resp_valid_i <= 1'b0;
      puf_resp_i       <= 1'b0;
      sample_counter_q <= 0;
    end else begin
      puf_resp_valid_i <= 1'b0;

      if (sample_req_o) begin
        puf_resp_valid_i <= 1'b1;
        case (current_resp_mode_q)
          RESP_NORMAL: puf_resp_i <= sample_counter_q[0];
          RESP_INVERT: puf_resp_i <= ~sample_counter_q[0];
          default:     puf_resp_i <= sample_counter_q[0];
        endcase
        sample_counter_q <= sample_counter_q + 1;
      end
    end
  end

  initial begin
    rst_ni              = 1'b0;
    start_i             = 1'b0;
    failure_count_q     = 0;
    current_case_name_q = "boot";
    apply_defaults();

    run_case("correct_path", CHECKSUM_GOOD, S_TAG_GOOD, '0, RESP_NORMAL, 1'b1, 1'b1, 1'b1);
    run_case("wrong_checksum", CHECKSUM_GOOD ^ 128'h1, S_TAG_GOOD, '0, RESP_NORMAL, 1'b0, 1'b0, 1'b1);
    run_case("wrong_s_tag", CHECKSUM_GOOD, S_TAG_GOOD ^ 128'h1, '0, RESP_NORMAL, 1'b1, 1'b0, 1'b1);
    run_case("wrong_helper", CHECKSUM_GOOD, S_TAG_GOOD, '1, RESP_NORMAL, 1'b0, 1'b0, 1'b0);
    run_case("wrong_response", CHECKSUM_GOOD, S_TAG_GOOD, '0, RESP_INVERT, 1'b0, 1'b0, 1'b0);

    if (failure_count_q == 0) begin
      $display("[REG][PASS] all regression cases passed");
      #10;
      $finish;
    end else begin
      $fatal(1, "[REG][FAIL] regression failures=%0d", failure_count_q);
    end
  end

endmodule
