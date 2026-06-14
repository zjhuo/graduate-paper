`timescale 1ns/1ps

module response_aggregate_ctrl #(
  parameter int N_REP = 5
) (
  input  logic clk_i,
  input  logic rst_ni,
  input  logic capture_en_i,
  input  logic raw_resp_i,
  input  logic raw_resp_valid_i,
  output logic rsel_bit_o,
  output logic rsel_bit_valid_o,
  output logic unreliable_bit_o,
  output logic aggregate_done_o
);

  localparam int SAMPLE_CNT_W = $clog2(N_REP + 1);

  (* keep = "true" *) logic [SAMPLE_CNT_W-1:0] sample_count_q;
  (* keep = "true" *) logic [SAMPLE_CNT_W-1:0] cnt1_q;

  generate
    if (N_REP == 5) begin : g_rep5
      logic [SAMPLE_CNT_W-1:0] cnt1_n;

      assign cnt1_n = cnt1_q + {{(SAMPLE_CNT_W-1){1'b0}}, raw_resp_i};

      always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
          sample_count_q   <= '0;
          cnt1_q           <= '0;
          rsel_bit_o       <= 1'b0;
          rsel_bit_valid_o <= 1'b0;
          unreliable_bit_o <= 1'b0;
          aggregate_done_o <= 1'b0;
        end else begin
          rsel_bit_valid_o <= 1'b0;
          aggregate_done_o <= 1'b0;

          if (!capture_en_i) begin
            sample_count_q <= '0;
            cnt1_q         <= '0;
          end else if (raw_resp_valid_i) begin
            if (sample_count_q == 3'd4) begin
              rsel_bit_o       <= (cnt1_n >= 3);
              unreliable_bit_o <= (cnt1_n == 3'd2) || (cnt1_n == 3'd3);
              rsel_bit_valid_o <= 1'b1;
              aggregate_done_o <= 1'b1;
              sample_count_q   <= '0;
              cnt1_q           <= '0;
            end else begin
              sample_count_q <= sample_count_q + 1'b1;
              cnt1_q         <= cnt1_n;
            end
          end
        end
      end
    end else begin : g_rep_generic
      localparam int MAJOR_RELIABLE_THRESH = (N_REP / 2) + 2;
      localparam int CNT1_RELIABLE_LO      = N_REP - MAJOR_RELIABLE_THRESH;

      logic [SAMPLE_CNT_W-1:0] sample_count_n;
      logic [SAMPLE_CNT_W-1:0] cnt1_n;
      logic                    final_sample;
      logic                    majority_bit;
      logic                    unreliable_bit_n;

      assign sample_count_n   = sample_count_q + 1'b1;
      assign cnt1_n           = cnt1_q + {{(SAMPLE_CNT_W-1){1'b0}}, raw_resp_i};
      assign final_sample     = raw_resp_valid_i && (sample_count_n == N_REP);
      assign majority_bit     = (cnt1_n > (N_REP / 2));
      assign unreliable_bit_n = (cnt1_n > CNT1_RELIABLE_LO) &&
                                (cnt1_n < MAJOR_RELIABLE_THRESH);

      always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
          sample_count_q   <= '0;
          cnt1_q           <= '0;
          rsel_bit_o       <= 1'b0;
          rsel_bit_valid_o <= 1'b0;
          unreliable_bit_o <= 1'b0;
          aggregate_done_o <= 1'b0;
        end else begin
          rsel_bit_valid_o <= 1'b0;
          aggregate_done_o <= 1'b0;

          if (!capture_en_i) begin
            sample_count_q <= '0;
            cnt1_q         <= '0;
          end else if (raw_resp_valid_i) begin
            if (final_sample) begin
              rsel_bit_o       <= majority_bit;
              unreliable_bit_o <= unreliable_bit_n;
              rsel_bit_valid_o <= 1'b1;
              aggregate_done_o <= 1'b1;
              sample_count_q   <= '0;
              cnt1_q           <= '0;
            end else begin
              sample_count_q <= sample_count_n;
              cnt1_q         <= cnt1_n;
            end
          end
        end
      end
    end
  endgenerate

endmodule
