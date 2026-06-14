`timescale 1ns/1ps

module iotpufs_terminal_top_tb;
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

  initial begin
    rst_ni        = 1'b0;
    start_i       = 1'b0;
    helper_mask_i = '1;
    helper_xor_i  = '0;
    salt_i        = 128'h0011_2233_4455_6677_8899_aabb_ccdd_eeff;
    checksum_i    = 128'h28f6_a05b_4331_99f5_a0d4_801f_2393_9cf0;
    device_id_i   = 128'h4445_5649_4345_5f30_3030_0000_0000_0001;
    nonce_d_i     = 128'habf8_2bce_5e84_f78f_1e3d_53f0_79c3_b39d;
    nonce_s_i     = 128'h1b7d_12f8_4691_62da_6ed7_2010_c60a_9cb0;
    v_i_i         = 128'heabc_8a51_7bc9_c497_a063_a2c0_e5ce_b081;
    c_init_i      = 128'h199d_985a_6675_dd1e_b878_80fb_7b39_9fee;
    s_tag_i       = 128'h6be0_336c_ea1f_cf61_d899_f68d_71cb_04e9;

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
    end else begin
      puf_resp_valid_i <= 1'b0;

      if (sample_req_o) begin
        puf_resp_valid_i <= 1'b1;
        puf_resp_i       <= sample_counter_q[0];
        sample_counter_q <= sample_counter_q + 1;
      end
    end
  end

  initial begin
    repeat (120000) @(posedge clk_i) begin
      if (auth_done_o) begin
        $display(
          "[TB] auth_done observed, samples=%0d, key=%h, checksum_match=%0d, auth_pass=%0d, h_tag=%h",
          sample_counter_q,
          key_hat_o,
          checksum_match_o,
          auth_pass_o,
          h_tag_o
        );
        #10;
        $finish;
      end
    end

    $fatal(1, "[TB] timeout before auth_done");
  end

endmodule
