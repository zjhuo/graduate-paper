`timescale 1ns/1ps

module iotpufs_terminal_board_bringup_top (
  input  logic clk_i,
  input  logic rst_ni,
  input  logic start_i,
  output logic session_busy_o,
  output logic auth_done_o,
  output logic auth_pass_o,
  output logic recover_success_o,
  output logic checksum_match_o
);
  import iotpufs_pkg::*;

  localparam logic [HELPER_MASK_W-1:0] HELPER_MASK_INIT = {HELPER_MASK_W{1'b1}};
  localparam logic [HELPER_XOR_W-1:0]  HELPER_XOR_INIT  = {HELPER_XOR_W{1'b0}};
  localparam logic [SALT_W-1:0]        SALT_INIT        = 128'h0011_2233_4455_6677_8899_aabb_ccdd_eeff;
  localparam logic [CHECKSUM_W-1:0]    CHECKSUM_INIT    = 128'h28f6_a05b_4331_99f5_a0d4_801f_2393_9cf0;
  localparam logic [DEVICE_ID_W-1:0]   DEVICE_ID_INIT   = 128'h4445_5649_4345_5f30_3030_0000_0000_0001;
  localparam logic [NONCE_W-1:0]       NONCE_D_INIT     = 128'habf8_2bce_5e84_f78f_1e3d_53f0_79c3_b39d;
  localparam logic [NONCE_W-1:0]       NONCE_S_INIT     = 128'h1b7d_12f8_4691_62da_6ed7_2010_c60a_9cb0;
  localparam logic [V_W-1:0]           V_I_INIT         = 128'heabc_8a51_7bc9_c497_a063_a2c0_e5ce_b081;
  localparam logic [C_INIT_W-1:0]      C_INIT_INIT      = 128'h199d_985a_6675_dd1e_b878_80fb_7b39_9fee;
  localparam logic [TAG_W-1:0]         S_TAG_INIT       = 128'h6be0_336c_ea1f_cf61_d899_f68d_71cb_04e9;

  (* keep = "true" *) logic [HELPER_MASK_W-1:0] helper_mask_q;
  (* keep = "true" *) logic [HELPER_XOR_W-1:0]  helper_xor_q;
  (* keep = "true" *) logic [SALT_W-1:0]        salt_q;
  (* keep = "true" *) logic [CHECKSUM_W-1:0]    checksum_q;
  (* keep = "true" *) logic [DEVICE_ID_W-1:0]   device_id_q;

  logic sample_req_int;
  logic session_busy_int;
  logic auth_done_int;
  logic auth_pass_int;
  logic recover_success_int;
  logic checksum_match_int;

  logic [KEY_W-1:0]   key_hat;
  logic [TAG_W-1:0]   h_tag;
  logic [UNREL_W-1:0] unreliable_vector;

  logic puf_resp_q;
  logic puf_resp_valid_q;
  logic [15:0] sample_counter_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      helper_mask_q <= HELPER_MASK_INIT;
      helper_xor_q  <= HELPER_XOR_INIT;
      salt_q        <= SALT_INIT;
      checksum_q    <= CHECKSUM_INIT;
      device_id_q   <= DEVICE_ID_INIT;

      puf_resp_q       <= 1'b0;
      puf_resp_valid_q <= 1'b0;
      sample_counter_q <= 16'd0;

      session_busy_o    <= 1'b0;
      auth_done_o       <= 1'b0;
      auth_pass_o       <= 1'b0;
      recover_success_o <= 1'b0;
      checksum_match_o  <= 1'b0;
    end else begin
      puf_resp_valid_q <= 1'b0;
      if (sample_req_int) begin
        puf_resp_valid_q <= 1'b1;
        puf_resp_q       <= sample_counter_q[0];
        sample_counter_q <= sample_counter_q + 16'd1;
      end

      session_busy_o    <= session_busy_int;
      auth_done_o       <= auth_done_int;
      auth_pass_o       <= auth_pass_int;
      recover_success_o <= recover_success_int;
      checksum_match_o  <= checksum_match_int;
    end
  end

  iotpufs_terminal_top u_iotpufs_terminal_top (
    .clk_i               (clk_i),
    .rst_ni              (rst_ni),
    .start_i             (start_i),
    .puf_resp_i          (puf_resp_q),
    .puf_resp_valid_i    (puf_resp_valid_q),
    .helper_mask_i       (helper_mask_q),
    .helper_xor_i        (helper_xor_q),
    .salt_i              (salt_q),
    .checksum_i          (checksum_q),
    .device_id_i         (device_id_q),
    .nonce_d_i           (NONCE_D_INIT),
    .nonce_s_i           (NONCE_S_INIT),
    .v_i_i               (V_I_INIT),
    .c_init_i            (C_INIT_INIT),
    .s_tag_i             (S_TAG_INIT),
    .sample_req_o        (sample_req_int),
    .session_busy_o      (session_busy_int),
    .auth_done_o         (auth_done_int),
    .auth_pass_o         (auth_pass_int),
    .recover_success_o   (recover_success_int),
    .checksum_match_o    (checksum_match_int),
    .h_tag_o             (h_tag),
    .key_hat_o           (key_hat),
    .unreliable_vector_o (unreliable_vector)
  );

endmodule
