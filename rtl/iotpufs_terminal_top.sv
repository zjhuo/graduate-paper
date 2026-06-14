`timescale 1ns/1ps

module iotpufs_terminal_top #(
  parameter int HELPER_XOR_W  = iotpufs_pkg::HELPER_XOR_W,
  parameter int HELPER_MASK_W = iotpufs_pkg::HELPER_MASK_W,
  parameter int UNREL_W       = iotpufs_pkg::UNREL_W
) (
  input  logic                         clk_i,
  input  logic                         rst_ni,
  input  logic                         start_i,
  input  logic                         puf_resp_i,
  input  logic                         puf_resp_valid_i,
  input  logic [HELPER_MASK_W-1:0]     helper_mask_i,
  input  logic [HELPER_XOR_W-1:0]      helper_xor_i,
  input  logic [iotpufs_pkg::SALT_W-1:0]       salt_i,
  input  logic [iotpufs_pkg::CHECKSUM_W-1:0]   checksum_i,
  input  logic [iotpufs_pkg::DEVICE_ID_W-1:0]  device_id_i,
  input  logic [iotpufs_pkg::NONCE_W-1:0]      nonce_d_i,
  input  logic [iotpufs_pkg::NONCE_W-1:0]      nonce_s_i,
  input  logic [iotpufs_pkg::V_W-1:0]          v_i_i,
  input  logic [iotpufs_pkg::C_INIT_W-1:0]     c_init_i,
  input  logic [iotpufs_pkg::TAG_W-1:0]        s_tag_i,
  output logic                         sample_req_o,
  output logic                         session_busy_o,
  output logic                         auth_done_o,
  output logic                         auth_pass_o,
  output logic                         recover_success_o,
  output logic                         checksum_match_o,
  output logic [iotpufs_pkg::TAG_W-1:0]        h_tag_o,
  output logic [iotpufs_pkg::KEY_W-1:0]        key_hat_o,
  output logic [UNREL_W-1:0]           unreliable_vector_o,
  output logic [iotpufs_pkg::CHAL_W-1:0] challenge_o,
  output logic                         challenge_valid_o
);
  import iotpufs_pkg::*;

  logic [CHAL_W-1:0] challenge;
  logic              challenge_valid;
  logic              table_read_en;
  logic [$clog2(CHAL_COUNT)-1:0] challenge_idx_q;

  logic sample_req;
  logic sample_done;
  logic raw_resp;
  logic raw_resp_valid;

  logic agg_bit;
  logic agg_bit_valid;
  logic unreliable_bit;
  logic capture_pass_done_q;

  logic [RESP_W-1:0]  rsel_vector_q;
  logic [UNREL_W-1:0] unreliable_vector_q;
  logic [MSG_W-1:0]   message_bits_hat;
  logic               recover_start;
  logic               recover_done;
  logic               recover_success;

  logic [KEY_W-1:0] key_hat;
  logic [TAG_W-1:0] h_tag;
  logic             checksum_match;
  logic             auth_pass;
  logic             hash_start;
  logic             hash_done;

  logic capture_en;
  logic session_busy;
  logic auth_done;

  fixed_challenge_table #(
    .CHAL_W(CHAL_W),
    .CHAL_COUNT(CHAL_COUNT)
  ) u_fixed_challenge_table (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .read_en_i(table_read_en),
    .read_idx_i(challenge_idx_q),
    .challenge_o(challenge),
    .challenge_valid_o(challenge_valid)
  );

  apuf_capture_ctrl #(
    .CHAL_W(CHAL_W)
  ) u_apuf_capture_ctrl (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .capture_en_i(capture_en),
    .challenge_i(challenge),
    .challenge_valid_i(challenge_valid),
    .puf_resp_i(puf_resp_i),
    .puf_resp_valid_i(puf_resp_valid_i),
    .sample_req_o(sample_req),
    .sample_done_o(sample_done),
    .raw_resp_o(raw_resp),
    .raw_resp_valid_o(raw_resp_valid)
  );

  response_aggregate_ctrl u_response_aggregate_ctrl (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .capture_en_i(capture_en),
    .raw_resp_i(raw_resp),
    .raw_resp_valid_i(raw_resp_valid),
    .rsel_bit_o(agg_bit),
    .rsel_bit_valid_o(agg_bit_valid),
    .unreliable_bit_o(unreliable_bit),
    .aggregate_done_o()
  );

  hamming1611_core_stub #(
    .RESP_W(RESP_W),
    .MSG_W(MSG_W),
    .HELPER_XOR_W(HELPER_XOR_W),
    .HELPER_MASK_W(HELPER_MASK_W)
  ) u_hamming1611_core_stub (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .start_i(recover_start),
    .rsel_i(rsel_vector_q),
    .helper_mask_i(helper_mask_i),
    .helper_xor_i(helper_xor_i),
    .message_bits_o(message_bits_hat),
    .done_o(recover_done),
    .success_o(recover_success)
  );

  spongent_core_stub #(
    .MSG_W(MSG_W),
    .KEY_W(KEY_W),
    .SALT_W(SALT_W),
    .CHECKSUM_W(CHECKSUM_W),
    .DEVICE_ID_W(DEVICE_ID_W),
    .NONCE_W(NONCE_W),
    .V_W(V_W),
    .C_INIT_W(C_INIT_W),
    .TAG_W(TAG_W)
  ) u_spongent_core_stub (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .start_i(hash_start),
    .message_bits_i(message_bits_hat),
    .salt_i(salt_i),
    .checksum_i(checksum_i),
    .device_id_i(device_id_i),
    .nonce_d_i(nonce_d_i),
    .nonce_s_i(nonce_s_i),
    .v_i_i(v_i_i),
    .c_init_i(c_init_i),
    .s_tag_i(s_tag_i),
    .key_o(key_hat),
    .h_tag_o(h_tag),
    .checksum_match_o(checksum_match),
    .auth_pass_o(auth_pass),
    .done_o(hash_done)
  );

  protocol_fsm_stub u_protocol_fsm_stub (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .start_i(start_i),
    .capture_done_i(capture_pass_done_q),
    .recover_done_i(recover_done),
    .hash_done_i(hash_done),
    .table_read_en_o(table_read_en),
    .capture_en_o(capture_en),
    .recover_start_o(recover_start),
    .hash_start_o(hash_start),
    .session_busy_o(session_busy),
    .auth_done_o(auth_done)
  );

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      challenge_idx_q      <= '0;
      capture_pass_done_q  <= 1'b0;
      rsel_vector_q        <= '0;
      unreliable_vector_q  <= '0;
    end else begin
      capture_pass_done_q <= 1'b0;

      if (capture_en && agg_bit_valid) begin
        rsel_vector_q[challenge_idx_q]       <= agg_bit;
        unreliable_vector_q[challenge_idx_q] <= unreliable_bit;

        if (challenge_idx_q == CHAL_COUNT-1) begin
          challenge_idx_q     <= '0;
          capture_pass_done_q <= 1'b1;
        end else begin
          challenge_idx_q <= challenge_idx_q + 1'b1;
        end
      end

      if (!session_busy) begin
        challenge_idx_q <= '0;
      end
    end
  end

  assign sample_req_o        = sample_req;
  assign session_busy_o      = session_busy;
  assign auth_done_o         = auth_done;
  assign auth_pass_o         = auth_pass;
  assign recover_success_o   = recover_success;
  assign checksum_match_o    = checksum_match;
  assign h_tag_o             = h_tag;
  assign key_hat_o           = key_hat;
  assign unreliable_vector_o = unreliable_vector_q;
  assign challenge_o         = challenge;
  assign challenge_valid_o   = challenge_valid;

endmodule
