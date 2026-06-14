`timescale 1ns/1ps

module spongent_core_stub #(
  parameter int MSG_W       = 176,
  parameter int KEY_W       = 128,
  parameter int SALT_W      = 128,
  parameter int CHECKSUM_W  = 128,
  parameter int DEVICE_ID_W = 128,
  parameter int NONCE_W     = 128,
  parameter int V_W         = 128,
  parameter int C_INIT_W    = 128,
  parameter int TAG_W       = 128
) (
  input  logic                    clk_i,
  input  logic                    rst_ni,
  input  logic                    start_i,
  input  logic [MSG_W-1:0]        message_bits_i,
  input  logic [SALT_W-1:0]       salt_i,
  input  logic [CHECKSUM_W-1:0]   checksum_i,
  input  logic [DEVICE_ID_W-1:0]  device_id_i,
  input  logic [NONCE_W-1:0]      nonce_d_i,
  input  logic [NONCE_W-1:0]      nonce_s_i,
  input  logic [V_W-1:0]          v_i_i,
  input  logic [C_INIT_W-1:0]     c_init_i,
  input  logic [TAG_W-1:0]        s_tag_i,
  output logic [KEY_W-1:0]        key_o,
  output logic [TAG_W-1:0]        h_tag_o,
  output logic                    checksum_match_o,
  output logic                    auth_pass_o,
  output logic                    done_o
);

  localparam int SPONGENT_B_BITS    = 136;
  localparam int SPONGENT_ROUNDS    = 70;
  localparam int SPONGENT_LFSR_BITS = 7;
  localparam logic [SPONGENT_LFSR_BITS-1:0] SPONGENT_LFSR_IV = 7'h7A;

  localparam int MSG_BYTES       = (MSG_W + 7) / 8;
  localparam int KEY_BYTES       = KEY_W / 8;
  localparam int TAG_BYTES       = TAG_W / 8;
  localparam int SALT_BYTES      = SALT_W / 8;
  localparam int DEVICE_ID_BYTES = DEVICE_ID_W / 8;
  localparam int NONCE_BYTES     = NONCE_W / 8;
  localparam int V_BYTES         = V_W / 8;
  localparam int C_INIT_BYTES    = C_INIT_W / 8;

  localparam int CHECKSUM_PREFIX_BYTES = 30;
  localparam int SPONGENT_BRAND_BYTES  = 14;
  localparam int KDF_DOMAIN_BYTES      = 3;
  localparam int FE_KDF_LABEL_BYTES    = 18;
  localparam int RV_LABEL_BYTES        = 9;
  localparam int SK_LABEL_BYTES        = 2;
  localparam int HTAG_LABEL_BYTES      = 5;
  localparam int SRV_LABEL_BYTES       = 7;

  localparam int SEG_STEP_W   = 5;
  localparam int SEG_BYTE_W   = 5;
  localparam int DIGEST_IDX_W = $clog2(KEY_BYTES);
  localparam int ROUND_CNT_W  = $clog2(SPONGENT_ROUNDS);

  localparam logic [CHECKSUM_PREFIX_BYTES*8-1:0] CHECKSUM_PREFIX = {
    8'h50, 8'h55, 8'h46, 8'h76, 8'h31, 8'h20, 8'h46, 8'h45,
    8'h20, 8'h48, 8'h61, 8'h6D, 8'h6D, 8'h69, 8'h6E, 8'h67,
    8'h31, 8'h36, 8'h31, 8'h31, 8'h20, 8'h63, 8'h68, 8'h65,
    8'h63, 8'h6B, 8'h73, 8'h75, 8'h6D, 8'h0A
  };
  localparam logic [SPONGENT_BRAND_BYTES*8-1:0] SPONGENT_BRAND = {
    8'h50, 8'h55, 8'h46, 8'h76, 8'h31, 8'h2D, 8'h53,
    8'h50, 8'h4F, 8'h4E, 8'h47, 8'h45, 8'h4E, 8'h54
  };
  localparam logic [KDF_DOMAIN_BYTES*8-1:0] KDF_DOMAIN = {
    8'h4B, 8'h44, 8'h46
  };
  localparam logic [FE_KDF_LABEL_BYTES*8-1:0] FE_KDF_LABEL = {
    8'h46, 8'h45, 8'h5F, 8'h48, 8'h41, 8'h4D, 8'h4D, 8'h49, 8'h4E,
    8'h47, 8'h31, 8'h36, 8'h31, 8'h31, 8'h5F, 8'h4B, 8'h45, 8'h59
  };
  localparam logic [RV_LABEL_BYTES*8-1:0] RV_LABEL = {
    8'h52, 8'h5F, 8'h76, 8'h69, 8'h72, 8'h74, 8'h75, 8'h61, 8'h6C
  };
  localparam logic [SK_LABEL_BYTES*8-1:0] SK_LABEL = {
    8'h53, 8'h4B
  };
  localparam logic [HTAG_LABEL_BYTES*8-1:0] HTAG_LABEL = {
    8'h48, 8'h5F, 8'h74, 8'h61, 8'h67
  };
  localparam logic [SRV_LABEL_BYTES*8-1:0] SRV_LABEL = {
    8'h53, 8'h72, 8'h76, 8'h41, 8'h75, 8'h74, 8'h68
  };

  typedef enum logic [2:0] {
    ST_IDLE,
    ST_ABSORB,
    ST_PERMUTE,
    ST_SQUEEZE,
    ST_DONE
  } state_t;

  typedef enum logic [2:0] {
    PH_CHECKSUM,
    PH_FE_KDF,
    PH_R_VIRTUAL,
    PH_SK,
    PH_H_TAG,
    PH_S_TAG
  } phase_t;

  typedef enum logic {
    OP_ABSORB,
    OP_SQUEEZE
  } op_t;

  typedef enum logic [4:0] {
    SEG_CSUM_PREFIX,
    SEG_DEVICE_ID,
    SEG_NEWLINE,
    SEG_SALT,
    SEG_LEN_MSG,
    SEG_MSG_BITS,
    SEG_LEN_BRAND,
    SEG_BRAND,
    SEG_LEN_DOMAIN,
    SEG_DOMAIN,
    SEG_LEN_KEY,
    SEG_KEY,
    SEG_LEN_LABEL,
    SEG_LABEL,
    SEG_LEN_ONE,
    SEG_VAL_ZERO,
    SEG_LEN_NONCE,
    SEG_NONCE_S,
    SEG_NONCE_D,
    SEG_LEN_V,
    SEG_V,
    SEG_LEN_C_INIT,
    SEG_C_INIT,
    SEG_LEN_SALT,
    SEG_LEN_DEVICE_ID,
    SEG_VAL_B0,
    SEG_PAD
  } seg_t;

  state_t state_q, state_d;
  phase_t phase_q, phase_d;
  op_t    op_q, op_d;

  logic [SPONGENT_B_BITS-1:0]     sponge_state_q, sponge_state_d;
  logic [SPONGENT_LFSR_BITS-1:0]  lfsr_q, lfsr_d;
  logic [ROUND_CNT_W-1:0]         round_idx_q, round_idx_d;
  logic [SEG_STEP_W-1:0]          seg_step_q, seg_step_d;
  logic [SEG_BYTE_W-1:0]          seg_byte_idx_q, seg_byte_idx_d;
  logic [DIGEST_IDX_W-1:0]        digest_idx_q, digest_idx_d;

  logic [KEY_W-1:0] digest_q, digest_d;
  logic [KEY_W-1:0] key_q, key_d;
  logic [KEY_W-1:0] r_virtual_q, r_virtual_d;
  logic [KEY_W-1:0] sk_q, sk_d;
  logic [KEY_W-1:0] phase_key_q, phase_key_d;
  logic [TAG_W-1:0] h_tag_q, h_tag_d;
  logic             checksum_match_q, checksum_match_d;
  logic             auth_pass_q, auth_pass_d;
  logic             done_d;

  function automatic logic [SPONGENT_LFSR_BITS-1:0] reverse_bits7(
    input logic [SPONGENT_LFSR_BITS-1:0] value_i
  );
    integer bit_idx;
    begin
      reverse_bits7 = '0;
      for (bit_idx = 0; bit_idx < SPONGENT_LFSR_BITS; bit_idx++) begin
        reverse_bits7[SPONGENT_LFSR_BITS-1-bit_idx] = value_i[bit_idx];
      end
    end
  endfunction

  function automatic logic [SPONGENT_LFSR_BITS-1:0] lfsr_step(
    input logic [SPONGENT_LFSR_BITS-1:0] value_i
  );
    logic feedback;
    begin
      feedback  = value_i[6] ^ value_i[5];
      lfsr_step = {value_i[5:0], feedback};
    end
  endfunction

  function automatic logic [3:0] sbox4(input logic [3:0] nibble_i);
    begin
      unique case (nibble_i)
        4'h0: sbox4 = 4'hE;
        4'h1: sbox4 = 4'hD;
        4'h2: sbox4 = 4'hB;
        4'h3: sbox4 = 4'h0;
        4'h4: sbox4 = 4'h2;
        4'h5: sbox4 = 4'h1;
        4'h6: sbox4 = 4'h4;
        4'h7: sbox4 = 4'hF;
        4'h8: sbox4 = 4'h7;
        4'h9: sbox4 = 4'hA;
        4'hA: sbox4 = 4'h8;
        4'hB: sbox4 = 4'h5;
        4'hC: sbox4 = 4'h9;
        4'hD: sbox4 = 4'hC;
        4'hE: sbox4 = 4'h3;
        default: sbox4 = 4'h6;
      endcase
    end
  endfunction

  function automatic logic [SPONGENT_B_BITS-1:0] sbox_layer(
    input logic [SPONGENT_B_BITS-1:0] state_i
  );
    integer nibble_idx;
    logic [SPONGENT_B_BITS-1:0] out_v;
    begin
      out_v = '0;
      for (nibble_idx = 0; nibble_idx < SPONGENT_B_BITS/4; nibble_idx++) begin
        out_v[nibble_idx*4 +: 4] = sbox4(state_i[nibble_idx*4 +: 4]);
      end
      sbox_layer = out_v;
    end
  endfunction

  function automatic logic [SPONGENT_B_BITS-1:0] player(
    input logic [SPONGENT_B_BITS-1:0] state_i
  );
    integer bit_idx;
    integer new_pos;
    localparam int LAST = SPONGENT_B_BITS - 1;
    localparam int STEP = SPONGENT_B_BITS / 4;
    logic [SPONGENT_B_BITS-1:0] out_v;
    begin
      out_v = '0;
      for (bit_idx = 0; bit_idx < SPONGENT_B_BITS; bit_idx++) begin
        if (bit_idx == LAST) begin
          new_pos = LAST;
        end else begin
          new_pos = (bit_idx * STEP) % LAST;
        end
        out_v[new_pos] = state_i[bit_idx];
      end
      player = out_v;
    end
  endfunction

  function automatic logic [SPONGENT_B_BITS-1:0] spongent_round(
    input logic [SPONGENT_B_BITS-1:0] state_i,
    input logic [SPONGENT_LFSR_BITS-1:0] counter_i
  );
    logic [SPONGENT_B_BITS-1:0] mixed_v;
    begin
      mixed_v = state_i;
      mixed_v[SPONGENT_LFSR_BITS-1:0] =
          mixed_v[SPONGENT_LFSR_BITS-1:0] ^ counter_i;
      mixed_v[SPONGENT_B_BITS-1 -: SPONGENT_LFSR_BITS] =
          mixed_v[SPONGENT_B_BITS-1 -: SPONGENT_LFSR_BITS] ^ reverse_bits7(counter_i);
      spongent_round = player(sbox_layer(mixed_v));
    end
  endfunction

  function automatic logic [7:0] checksum_prefix_byte(input int idx_i);
    begin
      checksum_prefix_byte = CHECKSUM_PREFIX[((CHECKSUM_PREFIX_BYTES-1-idx_i)*8) +: 8];
    end
  endfunction

  function automatic logic [7:0] spongent_brand_byte(input int idx_i);
    begin
      spongent_brand_byte = SPONGENT_BRAND[((SPONGENT_BRAND_BYTES-1-idx_i)*8) +: 8];
    end
  endfunction

  function automatic logic [7:0] kdf_domain_byte(input int idx_i);
    begin
      kdf_domain_byte = KDF_DOMAIN[((KDF_DOMAIN_BYTES-1-idx_i)*8) +: 8];
    end
  endfunction

  function automatic logic [7:0] fe_kdf_label_byte(input int idx_i);
    begin
      fe_kdf_label_byte = FE_KDF_LABEL[((FE_KDF_LABEL_BYTES-1-idx_i)*8) +: 8];
    end
  endfunction

  function automatic logic [7:0] rv_label_byte(input int idx_i);
    begin
      rv_label_byte = RV_LABEL[((RV_LABEL_BYTES-1-idx_i)*8) +: 8];
    end
  endfunction

  function automatic logic [7:0] sk_label_byte(input int idx_i);
    begin
      sk_label_byte = SK_LABEL[((SK_LABEL_BYTES-1-idx_i)*8) +: 8];
    end
  endfunction

  function automatic logic [7:0] htag_label_byte(input int idx_i);
    begin
      htag_label_byte = HTAG_LABEL[((HTAG_LABEL_BYTES-1-idx_i)*8) +: 8];
    end
  endfunction

  function automatic logic [7:0] srv_label_byte(input int idx_i);
    begin
      srv_label_byte = SRV_LABEL[((SRV_LABEL_BYTES-1-idx_i)*8) +: 8];
    end
  endfunction

  function automatic logic [7:0] message_bits_byte(input int idx_i);
    integer bit_idx;
    integer src_idx;
    logic [7:0] out_v;
    begin
      out_v = 8'h00;
      for (bit_idx = 0; bit_idx < 8; bit_idx++) begin
        src_idx = idx_i*8 + bit_idx;
        if (src_idx < MSG_W) begin
          out_v[7-bit_idx] = message_bits_i[src_idx];
        end
      end
      message_bits_byte = out_v;
    end
  endfunction

  function automatic logic [7:0] be_key_byte(
    input logic [KEY_W-1:0] value_i,
    input int               idx_i
  );
    begin
      be_key_byte = value_i[((KEY_BYTES-1-idx_i)*8) +: 8];
    end
  endfunction

  function automatic logic [7:0] be_device_id_byte(input int idx_i);
    begin
      be_device_id_byte = device_id_i[((DEVICE_ID_BYTES-1-idx_i)*8) +: 8];
    end
  endfunction

  function automatic logic [7:0] be_salt_byte(input int idx_i);
    begin
      be_salt_byte = salt_i[((SALT_BYTES-1-idx_i)*8) +: 8];
    end
  endfunction

  function automatic logic [7:0] be_nonce_d_byte(input int idx_i);
    begin
      be_nonce_d_byte = nonce_d_i[((NONCE_BYTES-1-idx_i)*8) +: 8];
    end
  endfunction

  function automatic logic [7:0] be_nonce_s_byte(input int idx_i);
    begin
      be_nonce_s_byte = nonce_s_i[((NONCE_BYTES-1-idx_i)*8) +: 8];
    end
  endfunction

  function automatic logic [7:0] be_v_byte(input int idx_i);
    begin
      be_v_byte = v_i_i[((V_BYTES-1-idx_i)*8) +: 8];
    end
  endfunction

  function automatic logic [7:0] be_c_init_byte(input int idx_i);
    begin
      be_c_init_byte = c_init_i[((C_INIT_BYTES-1-idx_i)*8) +: 8];
    end
  endfunction

  function automatic int label_len(input phase_t phase_i);
    begin
      unique case (phase_i)
        PH_FE_KDF   : label_len = FE_KDF_LABEL_BYTES;
        PH_R_VIRTUAL: label_len = RV_LABEL_BYTES;
        PH_SK       : label_len = SK_LABEL_BYTES;
        PH_H_TAG    : label_len = HTAG_LABEL_BYTES;
        default     : label_len = SRV_LABEL_BYTES;
      endcase
    end
  endfunction

  function automatic logic is_protocol_phase(input phase_t phase_i);
    begin
      is_protocol_phase = (phase_i == PH_R_VIRTUAL) ||
                          (phase_i == PH_SK) ||
                          (phase_i == PH_H_TAG) ||
                          (phase_i == PH_S_TAG);
    end
  endfunction

  function automatic seg_t protocol_prefix_segment(
    input logic [SEG_STEP_W-1:0] step_i
  );
    begin
      unique case (step_i)
        5'd0 : protocol_prefix_segment = SEG_LEN_BRAND;
        5'd1 : protocol_prefix_segment = SEG_BRAND;
        5'd2 : protocol_prefix_segment = SEG_LEN_DOMAIN;
        5'd3 : protocol_prefix_segment = SEG_DOMAIN;
        5'd4 : protocol_prefix_segment = SEG_LEN_KEY;
        5'd5 : protocol_prefix_segment = SEG_KEY;
        5'd6 : protocol_prefix_segment = SEG_LEN_LABEL;
        5'd7 : protocol_prefix_segment = SEG_LABEL;
        5'd8 : protocol_prefix_segment = SEG_LEN_ONE;
        default: protocol_prefix_segment = SEG_VAL_ZERO;
      endcase
    end
  endfunction

  function automatic seg_t protocol_tail_segment(
    input phase_t                phase_i,
    input logic [SEG_STEP_W-1:0] step_i
  );
    begin
      unique case (phase_i)
        PH_R_VIRTUAL: begin
          unique case (step_i)
            5'd0: protocol_tail_segment = SEG_LEN_V;
            5'd1: protocol_tail_segment = SEG_V;
            5'd2: protocol_tail_segment = SEG_LEN_C_INIT;
            5'd3: protocol_tail_segment = SEG_C_INIT;
            default: protocol_tail_segment = SEG_PAD;
          endcase
        end

        PH_SK: begin
          unique case (step_i)
            5'd0: protocol_tail_segment = SEG_LEN_NONCE;
            5'd1: protocol_tail_segment = SEG_NONCE_S;
            5'd2: protocol_tail_segment = SEG_LEN_NONCE;
            5'd3: protocol_tail_segment = SEG_NONCE_D;
            5'd4: protocol_tail_segment = SEG_LEN_C_INIT;
            5'd5: protocol_tail_segment = SEG_C_INIT;
            default: protocol_tail_segment = SEG_PAD;
          endcase
        end

        PH_H_TAG: begin
          unique case (step_i)
            5'd0: protocol_tail_segment = SEG_LEN_NONCE;
            5'd1: protocol_tail_segment = SEG_NONCE_S;
            5'd2: protocol_tail_segment = SEG_LEN_NONCE;
            5'd3: protocol_tail_segment = SEG_NONCE_D;
            default: protocol_tail_segment = SEG_PAD;
          endcase
        end

        default: protocol_tail_segment = SEG_PAD;
      endcase
    end
  endfunction

  function automatic seg_t active_segment(
    input phase_t                phase_i,
    input logic [SEG_STEP_W-1:0] step_i
  );
    begin
      unique case (phase_i)
        PH_CHECKSUM: begin
          unique case (step_i)
            5'd0: active_segment = SEG_CSUM_PREFIX;
            5'd1: active_segment = SEG_DEVICE_ID;
            5'd2: active_segment = SEG_NEWLINE;
            5'd3: active_segment = SEG_SALT;
            5'd4: active_segment = SEG_MSG_BITS;
            default: active_segment = SEG_PAD;
          endcase
        end

        PH_FE_KDF: begin
          unique case (step_i)
            5'd0 : active_segment = SEG_LEN_BRAND;
            5'd1 : active_segment = SEG_BRAND;
            5'd2 : active_segment = SEG_LEN_DOMAIN;
            5'd3 : active_segment = SEG_DOMAIN;
            5'd4 : active_segment = SEG_LEN_MSG;
            5'd5 : active_segment = SEG_MSG_BITS;
            5'd6 : active_segment = SEG_LEN_LABEL;
            5'd7 : active_segment = SEG_LABEL;
            5'd8 : active_segment = SEG_LEN_ONE;
            5'd9 : active_segment = SEG_VAL_ZERO;
            5'd10: active_segment = SEG_LEN_DEVICE_ID;
            5'd11: active_segment = SEG_DEVICE_ID;
            5'd12: active_segment = SEG_LEN_SALT;
            5'd13: active_segment = SEG_SALT;
            5'd14: active_segment = SEG_LEN_ONE;
            5'd15: active_segment = SEG_VAL_B0;
            default: active_segment = SEG_PAD;
          endcase
        end

        default: begin
          if (is_protocol_phase(phase_i)) begin
            if (step_i < 5'd10) begin
              active_segment = protocol_prefix_segment(step_i);
            end else begin
              active_segment = protocol_tail_segment(phase_i, step_i - 5'd10);
            end
          end else begin
            active_segment = SEG_PAD;
          end
        end
      endcase
    end
  endfunction

  function automatic int len_field_value(input phase_t phase_i, input seg_t seg_i);
    begin
      unique case (seg_i)
        SEG_LEN_BRAND    : len_field_value = SPONGENT_BRAND_BYTES;
        SEG_LEN_DOMAIN   : len_field_value = KDF_DOMAIN_BYTES;
        SEG_LEN_MSG      : len_field_value = MSG_BYTES;
        SEG_LEN_KEY      : len_field_value = KEY_BYTES;
        SEG_LEN_LABEL    : len_field_value = label_len(phase_i);
        SEG_LEN_ONE      : len_field_value = 1;
        SEG_LEN_NONCE    : len_field_value = NONCE_BYTES;
        SEG_LEN_V        : len_field_value = V_BYTES;
        SEG_LEN_C_INIT   : len_field_value = C_INIT_BYTES;
        SEG_LEN_SALT     : len_field_value = SALT_BYTES;
        SEG_LEN_DEVICE_ID: len_field_value = DEVICE_ID_BYTES;
        default          : len_field_value = MSG_BYTES;
      endcase
    end
  endfunction

  function automatic int segment_len(input phase_t phase_i, input seg_t seg_i);
    begin
      unique case (seg_i)
        SEG_CSUM_PREFIX : segment_len = CHECKSUM_PREFIX_BYTES;
        SEG_DEVICE_ID   : segment_len = DEVICE_ID_BYTES;
        SEG_NEWLINE     : segment_len = 1;
        SEG_SALT        : segment_len = SALT_BYTES;
        SEG_MSG_BITS    : segment_len = MSG_BYTES;
        SEG_BRAND       : segment_len = SPONGENT_BRAND_BYTES;
        SEG_DOMAIN      : segment_len = KDF_DOMAIN_BYTES;
        SEG_LEN_BRAND,
        SEG_LEN_DOMAIN,
        SEG_LEN_MSG,
        SEG_LEN_KEY,
        SEG_LEN_LABEL,
        SEG_LEN_ONE,
        SEG_LEN_NONCE,
        SEG_LEN_V,
        SEG_LEN_C_INIT,
        SEG_LEN_SALT,
        SEG_LEN_DEVICE_ID: segment_len = 2;
        SEG_KEY         : segment_len = KEY_BYTES;
        SEG_LABEL       : segment_len = label_len(phase_i);
        SEG_VAL_ZERO,
        SEG_VAL_B0,
        SEG_PAD         : segment_len = 1;
        SEG_NONCE_S,
        SEG_NONCE_D     : segment_len = NONCE_BYTES;
        SEG_V           : segment_len = V_BYTES;
        default         : segment_len = C_INIT_BYTES;
      endcase
    end
  endfunction

  function automatic logic [7:0] label_byte(input phase_t phase_i, input int idx_i);
    begin
      unique case (phase_i)
        PH_FE_KDF   : label_byte = fe_kdf_label_byte(idx_i);
        PH_R_VIRTUAL: label_byte = rv_label_byte(idx_i);
        PH_SK       : label_byte = sk_label_byte(idx_i);
        PH_H_TAG    : label_byte = htag_label_byte(idx_i);
        default     : label_byte = srv_label_byte(idx_i);
      endcase
    end
  endfunction

  function automatic logic [7:0] active_key_byte(input phase_t phase_i, input int idx_i);
    begin
      active_key_byte = be_key_byte(phase_key_q, idx_i);
    end
  endfunction

  function automatic logic [7:0] active_absorb_byte(
    input phase_t                  phase_i,
    input seg_t                    seg_i,
    input logic [SEG_BYTE_W-1:0]   idx_i
  );
    begin
      unique case (seg_i)
        SEG_CSUM_PREFIX : active_absorb_byte = checksum_prefix_byte(idx_i);
        SEG_DEVICE_ID   : active_absorb_byte = be_device_id_byte(idx_i);
        SEG_NEWLINE     : active_absorb_byte = 8'h0A;
        SEG_SALT        : active_absorb_byte = be_salt_byte(idx_i);
        SEG_MSG_BITS    : active_absorb_byte = message_bits_byte(idx_i);
        SEG_LEN_BRAND,
        SEG_LEN_DOMAIN,
        SEG_LEN_MSG,
        SEG_LEN_KEY,
        SEG_LEN_LABEL,
        SEG_LEN_ONE,
        SEG_LEN_NONCE,
        SEG_LEN_V,
        SEG_LEN_C_INIT,
        SEG_LEN_SALT,
        SEG_LEN_DEVICE_ID: begin
          if (idx_i == 0) begin
            active_absorb_byte = 8'h00;
          end else begin
            active_absorb_byte = len_field_value(phase_i, seg_i);
          end
        end
        SEG_BRAND       : active_absorb_byte = spongent_brand_byte(idx_i);
        SEG_DOMAIN      : active_absorb_byte = kdf_domain_byte(idx_i);
        SEG_KEY         : active_absorb_byte = active_key_byte(phase_i, idx_i);
        SEG_LABEL       : active_absorb_byte = label_byte(phase_i, idx_i);
        SEG_VAL_ZERO    : active_absorb_byte = 8'h00;
        SEG_NONCE_S     : active_absorb_byte = be_nonce_s_byte(idx_i);
        SEG_NONCE_D     : active_absorb_byte = be_nonce_d_byte(idx_i);
        SEG_V           : active_absorb_byte = be_v_byte(idx_i);
        SEG_C_INIT      : active_absorb_byte = be_c_init_byte(idx_i);
        SEG_VAL_B0      : active_absorb_byte = 8'hB0;
        default         : active_absorb_byte = 8'h80;
      endcase
    end
  endfunction

  logic [KEY_W-1:0] digest_next;
  logic [7:0]       squeeze_byte;
  logic [7:0]       absorb_byte;
  logic [SPONGENT_B_BITS-1:0] sponge_after_round;
  logic             last_round;
  logic             last_absorb_byte;
  logic             last_digest_byte;
  logic             last_segment_byte;
  seg_t             active_seg_q;
  logic [SEG_BYTE_W-1:0] segment_len_q;

  assign squeeze_byte       = sponge_state_q[7:0];
  assign digest_next        = {digest_q[KEY_W-9:0], squeeze_byte};
  assign active_seg_q       = active_segment(phase_q, seg_step_q);
  assign segment_len_q      = segment_len(phase_q, active_seg_q);
  assign last_segment_byte  = (seg_byte_idx_q == (segment_len_q - 1'b1));
  assign absorb_byte        = active_absorb_byte(phase_q, active_seg_q, seg_byte_idx_q);
  assign sponge_after_round = spongent_round(sponge_state_q, lfsr_q);
  assign last_round         = (round_idx_q == SPONGENT_ROUNDS-1);
  assign last_absorb_byte   = (active_seg_q == SEG_PAD) && last_segment_byte;
  assign last_digest_byte   = (digest_idx_q == TAG_BYTES-1);

  always_comb begin
    state_d          = state_q;
    phase_d          = phase_q;
    op_d             = op_q;
    sponge_state_d   = sponge_state_q;
    lfsr_d           = lfsr_q;
    round_idx_d      = round_idx_q;
    seg_step_d       = seg_step_q;
    seg_byte_idx_d   = seg_byte_idx_q;
    digest_idx_d     = digest_idx_q;
    digest_d         = digest_q;
    key_d            = key_q;
    r_virtual_d      = r_virtual_q;
    sk_d             = sk_q;
    phase_key_d      = phase_key_q;
    h_tag_d          = h_tag_q;
    checksum_match_d = checksum_match_q;
    auth_pass_d      = auth_pass_q;
    done_d           = 1'b0;

    unique case (state_q)
      ST_IDLE: begin
        if (start_i) begin
          state_d          = ST_ABSORB;
          phase_d          = PH_CHECKSUM;
          op_d             = OP_ABSORB;
          sponge_state_d   = '0;
          lfsr_d           = SPONGENT_LFSR_IV;
          round_idx_d      = '0;
          seg_step_d       = '0;
          seg_byte_idx_d   = '0;
          digest_idx_d     = '0;
          digest_d         = '0;
          key_d            = '0;
          r_virtual_d      = '0;
          sk_d             = '0;
          phase_key_d      = '0;
          h_tag_d          = '0;
          checksum_match_d = 1'b0;
          auth_pass_d      = 1'b0;
        end
      end

      ST_ABSORB: begin
        sponge_state_d[7:0] = sponge_state_q[7:0] ^ absorb_byte;
        lfsr_d              = SPONGENT_LFSR_IV;
        round_idx_d         = '0;
        state_d             = ST_PERMUTE;
      end

      ST_PERMUTE: begin
        sponge_state_d = sponge_after_round;
        lfsr_d         = lfsr_step(lfsr_q);
        if (last_round) begin
          if (op_q == OP_ABSORB) begin
            if (last_absorb_byte) begin
              digest_d       = '0;
              digest_idx_d   = '0;
              op_d           = OP_SQUEEZE;
              state_d        = ST_SQUEEZE;
            end else if (last_segment_byte) begin
              seg_step_d     = seg_step_q + 1'b1;
              seg_byte_idx_d = '0;
              state_d        = ST_ABSORB;
            end else begin
              seg_byte_idx_d = seg_byte_idx_q + 1'b1;
              state_d        = ST_ABSORB;
            end
          end else begin
            state_d = ST_SQUEEZE;
          end
        end else begin
          round_idx_d = round_idx_q + 1'b1;
        end
      end

      ST_SQUEEZE: begin
        digest_d = digest_next;
        if (last_digest_byte) begin
          unique case (phase_q)
            PH_CHECKSUM: begin
              checksum_match_d = (digest_next == checksum_i);
              phase_d          = PH_FE_KDF;
              op_d             = OP_ABSORB;
              sponge_state_d   = '0;
              lfsr_d           = SPONGENT_LFSR_IV;
              round_idx_d      = '0;
              seg_step_d       = '0;
              seg_byte_idx_d   = '0;
              digest_idx_d     = '0;
              digest_d         = '0;
              state_d          = ST_ABSORB;
            end

            PH_FE_KDF: begin
              key_d          = digest_next;
              phase_key_d    = digest_next;
              phase_d        = PH_R_VIRTUAL;
              op_d           = OP_ABSORB;
              sponge_state_d = '0;
              lfsr_d         = SPONGENT_LFSR_IV;
              round_idx_d    = '0;
              seg_step_d     = '0;
              seg_byte_idx_d = '0;
              digest_idx_d   = '0;
              digest_d       = '0;
              state_d        = ST_ABSORB;
            end

            PH_R_VIRTUAL: begin
              r_virtual_d    = digest_next;
              phase_key_d    = digest_next;
              phase_d        = PH_SK;
              op_d           = OP_ABSORB;
              sponge_state_d = '0;
              lfsr_d         = SPONGENT_LFSR_IV;
              round_idx_d    = '0;
              seg_step_d     = '0;
              seg_byte_idx_d = '0;
              digest_idx_d   = '0;
              digest_d       = '0;
              state_d        = ST_ABSORB;
            end

            PH_SK: begin
              sk_d           = digest_next;
              phase_key_d    = r_virtual_q;
              phase_d        = PH_H_TAG;
              op_d           = OP_ABSORB;
              sponge_state_d = '0;
              lfsr_d         = SPONGENT_LFSR_IV;
              round_idx_d    = '0;
              seg_step_d     = '0;
              seg_byte_idx_d = '0;
              digest_idx_d   = '0;
              digest_d       = '0;
              state_d        = ST_ABSORB;
            end

            PH_H_TAG: begin
              h_tag_d        = digest_next;
              phase_key_d    = sk_q;
              phase_d        = PH_S_TAG;
              op_d           = OP_ABSORB;
              sponge_state_d = '0;
              lfsr_d         = SPONGENT_LFSR_IV;
              round_idx_d    = '0;
              seg_step_d     = '0;
              seg_byte_idx_d = '0;
              digest_idx_d   = '0;
              digest_d       = '0;
              state_d        = ST_ABSORB;
            end

            default: begin
              auth_pass_d = checksum_match_q && (digest_next == s_tag_i);
              done_d      = 1'b1;
              state_d     = ST_DONE;
            end
          endcase
        end else begin
          digest_idx_d = digest_idx_q + 1'b1;
          lfsr_d       = SPONGENT_LFSR_IV;
          round_idx_d  = '0;
          state_d      = ST_PERMUTE;
        end
      end

      ST_DONE: begin
        state_d = ST_IDLE;
      end

      default: begin
        state_d = ST_IDLE;
      end
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q          <= ST_IDLE;
      phase_q          <= PH_CHECKSUM;
      op_q             <= OP_ABSORB;
      sponge_state_q   <= '0;
      lfsr_q           <= SPONGENT_LFSR_IV;
      round_idx_q      <= '0;
      seg_step_q       <= '0;
      seg_byte_idx_q   <= '0;
      digest_idx_q     <= '0;
      digest_q         <= '0;
      key_q            <= '0;
      r_virtual_q      <= '0;
      sk_q             <= '0;
      phase_key_q      <= '0;
      h_tag_q          <= '0;
      checksum_match_q <= 1'b0;
      auth_pass_q      <= 1'b0;
      key_o            <= '0;
      h_tag_o          <= '0;
      checksum_match_o <= 1'b0;
      auth_pass_o      <= 1'b0;
      done_o           <= 1'b0;
    end else begin
      state_q          <= state_d;
      phase_q          <= phase_d;
      op_q             <= op_d;
      sponge_state_q   <= sponge_state_d;
      lfsr_q           <= lfsr_d;
      round_idx_q      <= round_idx_d;
      seg_step_q       <= seg_step_d;
      seg_byte_idx_q   <= seg_byte_idx_d;
      digest_idx_q     <= digest_idx_d;
      digest_q         <= digest_d;
      key_q            <= key_d;
      r_virtual_q      <= r_virtual_d;
      sk_q             <= sk_d;
      phase_key_q      <= phase_key_d;
      h_tag_q          <= h_tag_d;
      checksum_match_q <= checksum_match_d;
      auth_pass_q      <= auth_pass_d;

      key_o            <= key_d;
      h_tag_o          <= h_tag_d;
      checksum_match_o <= checksum_match_d;
      auth_pass_o      <= auth_pass_d;
      done_o           <= done_d;
    end
  end

endmodule
