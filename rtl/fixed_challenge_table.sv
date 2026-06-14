`timescale 1ns/1ps

module fixed_challenge_table #(
  parameter int CHAL_W     = 64,
  parameter int CHAL_COUNT = 256
) (
  input  logic                          clk_i,
  input  logic                          rst_ni,
  input  logic                          read_en_i,
  input  logic [$clog2(CHAL_COUNT)-1:0] read_idx_i,
  output logic [CHAL_W-1:0]             challenge_o,
  output logic                          challenge_valid_o
);

  logic [CHAL_W-1:0] challenge_mem [0:CHAL_COUNT-1];
  (* keep = "true" *) logic [CHAL_W-1:0] challenge_q;
  (* keep = "true" *) logic              challenge_valid_q;

  integer idx;
  initial begin
    for (idx = 0; idx < CHAL_COUNT; idx++) begin
      challenge_mem[idx] = '0;
    end
    $readmemh("fixed_challenges_256x64.hex", challenge_mem);
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      challenge_q       <= '0;
      challenge_valid_q <= 1'b0;
    end else if (read_en_i) begin
      challenge_q       <= challenge_mem[read_idx_i];
      challenge_valid_q <= 1'b1;
    end
  end

  assign challenge_o       = challenge_q;
  assign challenge_valid_o = challenge_valid_q;

endmodule
