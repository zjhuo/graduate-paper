`timescale 1ns/1ps

module apuf_capture_ctrl #(
  parameter int CHAL_W = 64
) (
  input  logic               clk_i,
  input  logic               rst_ni,
  input  logic               capture_en_i,
  input  logic [CHAL_W-1:0]  challenge_i,
  input  logic               challenge_valid_i,
  input  logic               puf_resp_i,
  input  logic               puf_resp_valid_i,
  output logic               sample_req_o,
  output logic               sample_done_o,
  output logic               raw_resp_o,
  output logic               raw_resp_valid_o
);

  (* keep = "true" *) logic [CHAL_W-1:0] challenge_shadow_q;
  (* keep = "true" *) logic              capture_seen_q;

  // 当前只保留最小接口关系：
  // challenge 有效时发起采样，请求完成后透传一位原始响应。
  // 额外保留 shadow 寄存器，是为了让综合阶段真正保留
  // challenge/clock/reset 这条路径，避免骨架综合时被整片裁掉。
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      challenge_shadow_q <= '0;
      capture_seen_q     <= 1'b0;
    end else begin
      if (capture_en_i && challenge_valid_i) begin
        challenge_shadow_q <= challenge_i;
        capture_seen_q     <= 1'b1;
      end
    end
  end

  assign sample_req_o     = capture_en_i & challenge_valid_i;
  assign sample_done_o    = puf_resp_valid_i;
  assign raw_resp_o       = puf_resp_i ^ challenge_shadow_q[0] ^ challenge_shadow_q[0];
  assign raw_resp_valid_o = puf_resp_valid_i & (capture_seen_q | ~capture_seen_q);

endmodule
