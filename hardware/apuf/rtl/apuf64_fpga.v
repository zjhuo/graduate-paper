`timescale 1ns / 1ps
`default_nettype none

module apuf_stage_fpga (
    input  wire top_in,
    input  wire bot_in,
    input  wire challenge_bit,
    output wire top_out,
    output wire bot_out
);
    (* KEEP = "TRUE" *) wire top_mux;
    (* KEEP = "TRUE" *) wire bot_mux;

    assign top_mux = challenge_bit ? bot_in : top_in;
    assign bot_mux = challenge_bit ? top_in : bot_in;

    assign top_out = top_mux;
    assign bot_out = bot_mux;
endmodule

module apuf64_fpga #(
    parameter integer CHALLENGE_WIDTH = 64
) (
    input  wire                       rst_n,
    input  wire                       launch,
    input  wire [CHALLENGE_WIDTH-1:0] challenge,
    output reg                        response
);
    (* KEEP = "TRUE" *) wire [CHALLENGE_WIDTH:0] top_path;
    (* KEEP = "TRUE" *) wire [CHALLENGE_WIDTH:0] bot_path;

    assign top_path[0] = launch;
    assign bot_path[0] = launch;

    genvar i;
    generate
        for (i = 0; i < CHALLENGE_WIDTH; i = i + 1) begin : gen_apuf_stage
            (* DONT_TOUCH = "TRUE" *) apuf_stage_fpga u_stage (
                .top_in(top_path[i]),
                .bot_in(bot_path[i]),
                .challenge_bit(challenge[i]),
                .top_out(top_path[i+1]),
                .bot_out(bot_path[i+1])
            );
        end
    endgenerate

    always @(posedge top_path[CHALLENGE_WIDTH] or negedge rst_n) begin
        if (!rst_n) begin
            response <= 1'b0;
        end else begin
            response <= bot_path[CHALLENGE_WIDTH];
        end
    end
endmodule

`default_nettype wire
