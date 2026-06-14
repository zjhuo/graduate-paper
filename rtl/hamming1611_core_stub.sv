`timescale 1ns/1ps

module hamming1611_core_stub #(
  parameter int RESP_W        = 256,
  parameter int MSG_W         = 176,
  parameter int HELPER_XOR_W  = RESP_W,
  parameter int HELPER_MASK_W = RESP_W,
  parameter bit ASSUME_ALL_ONE_MASK = 1'b1
) (
  input  logic                     clk_i,
  input  logic                     rst_ni,
  input  logic                     start_i,
  input  logic [RESP_W-1:0]        rsel_i,
  input  logic [HELPER_MASK_W-1:0] helper_mask_i,
  input  logic [HELPER_XOR_W-1:0]  helper_xor_i,
  output logic [MSG_W-1:0]         message_bits_o,
  output logic                     done_o,
  output logic                     success_o
);

  localparam int CODE_N    = 16;
  localparam int CODE_K    = 11;
  localparam int BLOCK_MAX = MSG_W / CODE_K;

  typedef enum logic [2:0] {
    ST_IDLE,
    ST_GATHER,
    ST_LOAD_BLOCK,
    ST_CORRECT_BLOCK,
    ST_WRITE_BLOCK,
    ST_DONE
  } state_t;

  state_t state_q, state_d;

  logic [MSG_W-1:0]             message_bits_q, message_bits_d;
  logic [8:0]                   scan_idx_q, scan_idx_d;
  logic [8:0]                   usable_count_q, usable_count_d;
  logic [$clog2(BLOCK_MAX):0]   block_idx_q, block_idx_d;
  logic                         success_q, success_d;

  logic [CODE_N-1:0]            current_block_q, current_block_d;
  logic [CODE_N-1:0]            corrected_block_q, corrected_block_d;
  logic                         block_success_q, block_success_d;

  logic                         take_bit;
  logic [8:0]                   usable_count_n;
  logic [CODE_N-1:0]            selected_block;
  logic [CODE_N-1:0]            corrected_block_comb;
  logic [CODE_K-1:0]            decoded_data_comb;
  logic                         block_success_comb;
  logic                         done_d;

  function automatic [CODE_N-1:0] correct_block(
    input logic [CODE_N-1:0] block_i,
    output logic             success_o_f
  );
    integer parity_position;
    integer position;
    integer syndrome_local;
    logic parity;
    logic overall;
    logic [CODE_N-1:0] corrected_local;
    begin
      corrected_local = block_i;
      syndrome_local  = 0;

      for (parity_position = 1; parity_position < CODE_N; parity_position = parity_position << 1) begin
        parity = 1'b0;
        for (position = 1; position < CODE_N; position++) begin
          if ((position & parity_position) != 0) begin
            parity = parity ^ corrected_local[position-1];
          end
        end
        if (parity) begin
          syndrome_local = syndrome_local + parity_position;
        end
      end

      overall = 1'b0;
      for (position = 0; position < CODE_N; position++) begin
        overall = overall ^ corrected_local[position];
      end

      success_o_f = 1'b1;
      if ((syndrome_local == 0) && (overall == 1'b0)) begin
        // no error
      end else if ((syndrome_local == 0) && (overall == 1'b1)) begin
        corrected_local[15] = ~corrected_local[15];
      end else if ((syndrome_local != 0) && (overall == 1'b1)) begin
        corrected_local[syndrome_local-1] = ~corrected_local[syndrome_local-1];
      end else begin
        success_o_f = 1'b0;
      end

      correct_block = corrected_local;
    end
  endfunction

  function automatic [CODE_K-1:0] extract_data_bits(
    input logic [CODE_N-1:0] block_i
  );
    begin
      extract_data_bits[0]  = block_i[2];
      extract_data_bits[1]  = block_i[4];
      extract_data_bits[2]  = block_i[5];
      extract_data_bits[3]  = block_i[6];
      extract_data_bits[4]  = block_i[8];
      extract_data_bits[5]  = block_i[9];
      extract_data_bits[6]  = block_i[10];
      extract_data_bits[7]  = block_i[11];
      extract_data_bits[8]  = block_i[12];
      extract_data_bits[9]  = block_i[13];
      extract_data_bits[10] = block_i[14];
    end
  endfunction

  assign take_bit       = helper_mask_i[scan_idx_q] && (usable_count_q < RESP_W);
  assign usable_count_n = usable_count_q + take_bit;
  assign selected_block = ASSUME_ALL_ONE_MASK
                        ? (rsel_i[block_idx_q*CODE_N +: CODE_N] ^
                           helper_xor_i[block_idx_q*CODE_N +: CODE_N])
                        : '0;

  always_comb begin
    corrected_block_comb = correct_block(current_block_q, block_success_comb);
    decoded_data_comb    = extract_data_bits(corrected_block_q);
  end

  always_comb begin
    state_d            = state_q;
    message_bits_d     = message_bits_q;
    scan_idx_d         = scan_idx_q;
    usable_count_d     = usable_count_q;
    block_idx_d        = block_idx_q;
    success_d          = success_q;
    current_block_d    = current_block_q;
    corrected_block_d  = corrected_block_q;
    block_success_d    = block_success_q;
    done_d             = 1'b0;

    unique case (state_q)
      ST_IDLE: begin
        if (start_i) begin
          state_d           = ASSUME_ALL_ONE_MASK ? ST_LOAD_BLOCK : ST_GATHER;
          message_bits_d    = '0;
          scan_idx_d        = '0;
          usable_count_d    = '0;
          block_idx_d       = '0;
          success_d         = 1'b1;
          current_block_d   = '0;
          corrected_block_d = '0;
          block_success_d   = 1'b0;
        end
      end

      ST_GATHER: begin
        if (!ASSUME_ALL_ONE_MASK) begin
          usable_count_d = usable_count_n;

          if (scan_idx_q == RESP_W-1) begin
            if (usable_count_n != RESP_W) begin
              success_d = 1'b0;
            end
            state_d     = ST_LOAD_BLOCK;
            block_idx_d = '0;
          end else begin
            scan_idx_d = scan_idx_q + 1'b1;
          end
        end
      end

      ST_LOAD_BLOCK: begin
        if (ASSUME_ALL_ONE_MASK) begin
          current_block_d = selected_block;
        end else begin
          current_block_d = '0;
        end
        state_d         = ST_CORRECT_BLOCK;
      end

      ST_CORRECT_BLOCK: begin
        corrected_block_d = corrected_block_comb;
        block_success_d   = block_success_comb;
        state_d           = ST_WRITE_BLOCK;
      end

      ST_WRITE_BLOCK: begin
        if (success_q && block_success_q) begin
          message_bits_d[block_idx_q*CODE_K +: CODE_K] = decoded_data_comb;
        end else begin
          success_d = 1'b0;
        end

        if (block_idx_q == BLOCK_MAX-1) begin
          state_d = ST_DONE;
        end else begin
          block_idx_d = block_idx_q + 1'b1;
          state_d     = ST_LOAD_BLOCK;
        end
      end

      ST_DONE: begin
        done_d  = 1'b1;
        state_d = ST_IDLE;
      end

      default: begin
        state_d = ST_IDLE;
      end
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q           <= ST_IDLE;
      message_bits_q    <= '0;
      scan_idx_q        <= '0;
      usable_count_q    <= '0;
      block_idx_q       <= '0;
      success_q         <= 1'b0;
      current_block_q   <= '0;
      corrected_block_q <= '0;
      block_success_q   <= 1'b0;
      message_bits_o    <= '0;
      done_o            <= 1'b0;
      success_o         <= 1'b0;
    end else begin
      state_q           <= state_d;
      message_bits_q    <= message_bits_d;
      scan_idx_q        <= scan_idx_d;
      usable_count_q    <= usable_count_d;
      block_idx_q       <= block_idx_d;
      success_q         <= success_d;
      current_block_q   <= current_block_d;
      corrected_block_q <= corrected_block_d;
      block_success_q   <= block_success_d;

      done_o <= done_d;
      if (done_d) begin
        message_bits_o <= message_bits_d;
        success_o      <= success_d;
      end else begin
        success_o <= 1'b0;
      end
    end
  end

endmodule
