`timescale 1ns / 1ps
`default_nettype none

module apuf64_enhanced #(
    parameter integer CHALLENGE_WIDTH = 64,
    parameter integer CHIP_ID         = 0,
    parameter integer NOISE_ENABLE    = 0,
    parameter integer NOISE_WINDOW    = 2,
    parameter integer NOISE_PCT       = 20,
    parameter integer NOISE_SEED      = 1
) (
    input  wire                       rst_n,
    input  wire                       launch,
    input  wire [CHALLENGE_WIDTH-1:0] challenge,
    output reg                        response,
    output reg                        valid,
    output reg                        done,
    output reg                        resp_a,
    output reg                        resp_b
);
    wire [CHALLENGE_WIDTH:0] top_path;
    wire [CHALLENGE_WIDTH:0] bot_path;
    reg  [31:0]              sample_count;

    assign top_path[0] = launch;
    assign bot_path[0] = launch;

    function integer stage_delay;
        input integer stage_idx;
        input integer tap_idx;
        reg [31:0] x;
        begin
            x = (CHIP_ID + 1) * 32'h9E37_79B9;
            x = x ^ ((stage_idx + 1) * 32'h85EB_CA6B);
            x = x ^ ((tap_idx + 1) * 32'hC2B2_AE35);
            x = x ^ (x >> 16);
            x = x * 32'h7FEB_352D;
            x = x ^ (x >> 15);
            x = x * 32'h846C_A68B;
            x = x ^ (x >> 16);
            stage_delay = 15 + (x % 11);
        end
    endfunction

    function integer delay_margin;
        input [CHALLENGE_WIDTH-1:0] challenge_value;
        integer stage_idx;
        integer top_delay;
        integer bot_delay;
        integer next_top_delay;
        integer next_bot_delay;
        begin
            top_delay = 0;
            bot_delay = 0;

            for (stage_idx = 0; stage_idx < CHALLENGE_WIDTH; stage_idx = stage_idx + 1) begin
                if (challenge_value[stage_idx]) begin
                    next_top_delay = bot_delay + stage_delay(stage_idx, 2);
                    next_bot_delay = top_delay + stage_delay(stage_idx, 3);
                end else begin
                    next_top_delay = top_delay + stage_delay(stage_idx, 0);
                    next_bot_delay = bot_delay + stage_delay(stage_idx, 1);
                end

                top_delay = next_top_delay;
                bot_delay = next_bot_delay;
            end

            delay_margin = bot_delay - top_delay;
        end
    endfunction

    function [31:0] noise_hash;
        input [CHALLENGE_WIDTH-1:0] challenge_value;
        input [31:0] sample_idx;
        reg [31:0] x;
        begin
            x = challenge_value[31:0] ^ challenge_value[63:32];
            x = x ^ sample_idx ^ ((CHIP_ID + 1) * 32'hA5A5_1F3D);
            x = x ^ (NOISE_SEED * 32'h3C6E_F372);
            x = x ^ (x >> 16);
            x = x * 32'h7FEB_352D;
            x = x ^ (x >> 15);
            x = x * 32'h846C_A68B;
            x = x ^ (x >> 16);
            noise_hash = x;
        end
    endfunction

    function noisy_sample;
        input raw_response;
        input [CHALLENGE_WIDTH-1:0] challenge_value;
        input [31:0] sample_idx;
        integer margin;
        integer abs_margin;
        reg value;
        begin
            value = raw_response;

            if (NOISE_ENABLE != 0) begin
                margin = delay_margin(challenge_value);
                abs_margin = (margin < 0) ? -margin : margin;

                if ((abs_margin <= NOISE_WINDOW) &&
                    ((noise_hash(challenge_value, sample_idx) % 100) < NOISE_PCT)) begin
                    value = ~value;
                end
            end

            noisy_sample = value;
        end
    endfunction

    genvar i;
    generate
        for (i = 0; i < CHALLENGE_WIDTH; i = i + 1) begin : gen_apuf_stage
            localparam integer D_TS = stage_delay(i, 0);
            localparam integer D_BS = stage_delay(i, 1);
            localparam integer D_TC = stage_delay(i, 2);
            localparam integer D_BC = stage_delay(i, 3);

            apuf_stage_sim #(
                .D_TOP_STRAIGHT(D_TS),
                .D_BOT_STRAIGHT(D_BS),
                .D_TOP_CROSS(D_TC),
                .D_BOT_CROSS(D_BC)
            ) u_stage (
                .top_in(top_path[i]),
                .bot_in(bot_path[i]),
                .challenge_bit(challenge[i]),
                .top_out(top_path[i+1]),
                .bot_out(bot_path[i+1])
            );
        end
    endgenerate

    reg raw_response;
    reg sample_a;
    reg sample_b;

    always @(posedge top_path[CHALLENGE_WIDTH] or negedge rst_n) begin
        if (!rst_n) begin
            response <= 1'b0;
            valid <= 1'b0;
            done <= 1'b0;
            resp_a <= 1'b0;
            resp_b <= 1'b0;
            sample_count <= 32'd0;
        end else begin
            raw_response = bot_path[CHALLENGE_WIDTH];
            sample_a = noisy_sample(raw_response, challenge, sample_count << 1);
            sample_b = noisy_sample(raw_response, challenge, (sample_count << 1) + 32'd1);

            response <= sample_a;
            resp_a <= sample_a;
            resp_b <= sample_b;
            valid <= (sample_a == sample_b);
            done <= 1'b1;
            sample_count <= sample_count + 32'd1;
        end
    end
endmodule

`default_nettype wire
