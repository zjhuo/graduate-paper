`timescale 1ns/1ps

module protocol_fsm_stub (
  input  logic clk_i,
  input  logic rst_ni,
  input  logic start_i,
  input  logic capture_done_i,
  input  logic recover_done_i,
  input  logic hash_done_i,
  output logic table_read_en_o,
  output logic capture_en_o,
  output logic recover_start_o,
  output logic hash_start_o,
  output logic session_busy_o,
  output logic auth_done_o
);

  typedef enum logic [2:0] {
    ST_IDLE,
    ST_FETCH,
    ST_CAPTURE,
    ST_RECOVER,
    ST_HASH,
    ST_DONE
  } state_t;

  state_t state_q, state_d;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q <= ST_IDLE;
    end else begin
      state_q <= state_d;
    end
  end

  always_comb begin
    state_d         = state_q;
    table_read_en_o = 1'b0;
    capture_en_o    = 1'b0;
    recover_start_o = 1'b0;
    hash_start_o    = 1'b0;
    session_busy_o  = 1'b1;
    auth_done_o     = 1'b0;

    unique case (state_q)
      ST_IDLE: begin
        session_busy_o = 1'b0;
        if (start_i) begin
          state_d = ST_FETCH;
        end
      end

      ST_FETCH: begin
        table_read_en_o = 1'b1;
        state_d         = ST_CAPTURE;
      end

      ST_CAPTURE: begin
        capture_en_o = 1'b1;
        if (capture_done_i) begin
          state_d = ST_RECOVER;
        end
      end

      ST_RECOVER: begin
        recover_start_o = 1'b1;
        if (recover_done_i) begin
          state_d = ST_HASH;
        end
      end

      ST_HASH: begin
        hash_start_o = 1'b1;
        if (hash_done_i) begin
          state_d = ST_DONE;
        end
      end

      ST_DONE: begin
        auth_done_o = 1'b1;
        state_d     = ST_IDLE;
      end

      default: begin
        state_d = ST_IDLE;
      end
    endcase
  end

endmodule
