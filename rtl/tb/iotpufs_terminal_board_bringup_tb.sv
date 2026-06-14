`timescale 1ns/1ps

module iotpufs_terminal_board_bringup_tb;
  import iotpufs_pkg::*;

  localparam logic [CHECKSUM_W-1:0] CHECKSUM_BAD = 128'h28f6_a05b_4331_99f5_a0d4_801f_2393_9cf1;
  localparam logic [TAG_W-1:0]      S_TAG_BAD    = 128'h6be0_336c_ea1f_cf61_d899_f68d_71cb_04e8;

  logic clk_i;
  logic rst_ni;
  logic start_i;
  logic puf_resp_i;
  logic puf_resp_valid_i;
  logic sample_req_o;
  logic session_busy_o;
  logic auth_done_o;
  logic auth_pass_o;
  logic recover_success_o;
  logic checksum_match_o;

  int sample_counter_q;
  int failure_count_q;
  string current_case_name_q;

  iotpufs_terminal_board_synth_top u_dut (
    .clk_i             (clk_i),
    .rst_ni            (rst_ni),
    .start_i           (start_i),
    .puf_resp_i        (puf_resp_i),
    .puf_resp_valid_i  (puf_resp_valid_i),
    .sample_req_o      (sample_req_o),
    .session_busy_o    (session_busy_o),
    .auth_done_o       (auth_done_o),
    .auth_pass_o       (auth_pass_o),
    .recover_success_o (recover_success_o),
    .checksum_match_o  (checksum_match_o)
  );

  initial begin
    clk_i = 1'b0;
    forever #5 clk_i = ~clk_i;
  end

  task automatic pulse_reset;
    begin
      rst_ni = 1'b0;
      repeat (4) @(posedge clk_i);
      rst_ni = 1'b1;
      repeat (2) @(posedge clk_i);
    end
  endtask

  task automatic pulse_start;
    begin
      start_i = 1'b1;
      @(posedge clk_i);
      start_i = 1'b0;
    end
  endtask

  task automatic wait_busy_high(output bit timed_out);
    int cyc;
    begin : wait_loop
      timed_out = 1'b1;
      for (cyc = 0; cyc < 2000; cyc = cyc + 1) begin
        @(posedge clk_i);
        if (session_busy_o) begin
          timed_out = 1'b0;
          disable wait_loop;
        end
      end
    end
  endtask

  task automatic wait_auth_done(output bit timed_out);
    int cyc;
    begin : wait_loop
      timed_out = 1'b1;
      for (cyc = 0; cyc < 120000; cyc = cyc + 1) begin
        @(posedge clk_i);
        if (auth_done_o) begin
          timed_out = 1'b0;
          disable wait_loop;
        end
      end
    end
  endtask

  task automatic print_case_result(input string case_name);
    begin
      $display(
        "[BRINGUP][%s] auth_done=%0d checksum_match=%0d auth_pass=%0d recover_success=%0d samples=%0d",
        case_name,
        auth_done_o,
        checksum_match_o,
        auth_pass_o,
        recover_success_o,
        sample_counter_q
      );
    end
  endtask

  task automatic expect_bit(
    input string case_name,
    input string label_s,
    input logic actual_v,
    input logic expect_v
  );
    begin
      if (actual_v !== expect_v) begin
        failure_count_q = failure_count_q + 1;
        $display(
          "[BRINGUP][FAIL][%s] %s actual=%0d expect=%0d",
          case_name,
          label_s,
          actual_v,
          expect_v
        );
      end
    end
  endtask

  task automatic run_good_case(input string case_name);
    bit timed_out;
    begin
      current_case_name_q = case_name;
      pulse_reset();
      pulse_start();
      wait_auth_done(timed_out);
      if (timed_out) begin
        failure_count_q = failure_count_q + 1;
        $display("[BRINGUP][FAIL][%s] timeout before auth_done", case_name);
      end else begin
        print_case_result(case_name);
        expect_bit(case_name, "auth_done", auth_done_o, 1'b1);
        expect_bit(case_name, "checksum_match", checksum_match_o, 1'b1);
        expect_bit(case_name, "auth_pass", auth_pass_o, 1'b1);
      end
      repeat (5) @(posedge clk_i);
    end
  endtask

  task automatic run_wrong_checksum_case;
    bit timed_out;
    begin
      current_case_name_q = "wrong_checksum_board";
      pulse_reset();
      force u_dut.checksum_q = CHECKSUM_BAD;
      pulse_start();
      wait_auth_done(timed_out);
      if (timed_out) begin
        failure_count_q = failure_count_q + 1;
        $display("[BRINGUP][FAIL][wrong_checksum_board] timeout before auth_done");
      end else begin
        print_case_result("wrong_checksum_board");
        expect_bit("wrong_checksum_board", "auth_done", auth_done_o, 1'b1);
        expect_bit("wrong_checksum_board", "checksum_match", checksum_match_o, 1'b0);
        expect_bit("wrong_checksum_board", "auth_pass", auth_pass_o, 1'b0);
      end
      release u_dut.checksum_q;
      repeat (5) @(posedge clk_i);
    end
  endtask

  task automatic run_wrong_s_tag_case;
    bit timed_out;
    begin
      current_case_name_q = "wrong_s_tag_board";
      pulse_reset();
      force u_dut.u_iotpufs_terminal_top.s_tag_i = S_TAG_BAD;
      pulse_start();
      wait_auth_done(timed_out);
      if (timed_out) begin
        failure_count_q = failure_count_q + 1;
        $display("[BRINGUP][FAIL][wrong_s_tag_board] timeout before auth_done");
      end else begin
        print_case_result("wrong_s_tag_board");
        expect_bit("wrong_s_tag_board", "auth_done", auth_done_o, 1'b1);
        expect_bit("wrong_s_tag_board", "checksum_match", checksum_match_o, 1'b1);
        expect_bit("wrong_s_tag_board", "auth_pass", auth_pass_o, 1'b0);
      end
      release u_dut.u_iotpufs_terminal_top.s_tag_i;
      repeat (5) @(posedge clk_i);
    end
  endtask

  task automatic run_repeat_start_while_busy_case;
    bit timed_out;
    bit busy_timeout;
    begin
      current_case_name_q = "repeat_start_while_busy";
      pulse_reset();
      pulse_start();
      wait_busy_high(busy_timeout);
      if (busy_timeout) begin
        failure_count_q = failure_count_q + 1;
        $display("[BRINGUP][FAIL][repeat_start_while_busy] busy never asserted");
      end else begin
        pulse_start();
        wait_auth_done(timed_out);
        if (timed_out) begin
          failure_count_q = failure_count_q + 1;
          $display("[BRINGUP][FAIL][repeat_start_while_busy] timeout before auth_done");
        end else begin
          print_case_result("repeat_start_while_busy");
          expect_bit("repeat_start_while_busy", "auth_done", auth_done_o, 1'b1);
          expect_bit("repeat_start_while_busy", "checksum_match", checksum_match_o, 1'b1);
          expect_bit("repeat_start_while_busy", "auth_pass", auth_pass_o, 1'b1);
        end
      end
      repeat (5) @(posedge clk_i);
    end
  endtask

  task automatic run_restart_after_done_case;
    bit timed_out;
    begin
      current_case_name_q = "restart_after_done";
      pulse_reset();
      pulse_start();
      wait_auth_done(timed_out);
      if (timed_out) begin
        failure_count_q = failure_count_q + 1;
        $display("[BRINGUP][FAIL][restart_after_done] first run timeout");
      end else begin
        print_case_result("restart_after_done_first");
        expect_bit("restart_after_done_first", "auth_pass", auth_pass_o, 1'b1);
        repeat (5) @(posedge clk_i);
        pulse_start();
        wait_auth_done(timed_out);
        if (timed_out) begin
          failure_count_q = failure_count_q + 1;
          $display("[BRINGUP][FAIL][restart_after_done] second run timeout");
        end else begin
          print_case_result("restart_after_done_second");
          expect_bit("restart_after_done_second", "auth_done", auth_done_o, 1'b1);
          expect_bit("restart_after_done_second", "checksum_match", checksum_match_o, 1'b1);
          expect_bit("restart_after_done_second", "auth_pass", auth_pass_o, 1'b1);
        end
      end
      repeat (5) @(posedge clk_i);
    end
  endtask

  task automatic run_reset_midrun_case;
    bit busy_timeout;
    bit timed_out;
    begin
      current_case_name_q = "reset_midrun";
      pulse_reset();
      pulse_start();
      wait_busy_high(busy_timeout);
      if (busy_timeout) begin
        failure_count_q = failure_count_q + 1;
        $display("[BRINGUP][FAIL][reset_midrun] busy never asserted");
      end else begin
        repeat (20) @(posedge clk_i);
        rst_ni = 1'b0;
        repeat (4) @(posedge clk_i);
        expect_bit("reset_midrun_after_reset", "session_busy", session_busy_o, 1'b0);
        expect_bit("reset_midrun_after_reset", "auth_done", auth_done_o, 1'b0);
        expect_bit("reset_midrun_after_reset", "auth_pass", auth_pass_o, 1'b0);
        rst_ni = 1'b1;
        repeat (2) @(posedge clk_i);
        pulse_start();
        wait_auth_done(timed_out);
        if (timed_out) begin
          failure_count_q = failure_count_q + 1;
          $display("[BRINGUP][FAIL][reset_midrun] timeout after restart");
        end else begin
          print_case_result("reset_midrun_restarted");
          expect_bit("reset_midrun_restarted", "auth_done", auth_done_o, 1'b1);
          expect_bit("reset_midrun_restarted", "checksum_match", checksum_match_o, 1'b1);
          expect_bit("reset_midrun_restarted", "auth_pass", auth_pass_o, 1'b1);
        end
      end
      repeat (5) @(posedge clk_i);
    end
  endtask

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      puf_resp_valid_i <= 1'b0;
      puf_resp_i       <= 1'b0;
      sample_counter_q <= 0;
    end else begin
      puf_resp_valid_i <= 1'b0;
      if (sample_req_o) begin
        puf_resp_valid_i <= 1'b1;
        puf_resp_i       <= sample_counter_q[0];
        sample_counter_q <= sample_counter_q + 1;
      end
    end
  end

  initial begin
    rst_ni          = 1'b0;
    start_i         = 1'b0;
    failure_count_q = 0;

    run_good_case("correct_path_board");
    run_repeat_start_while_busy_case();
    run_restart_after_done_case();
    run_reset_midrun_case();
    run_wrong_checksum_case();
    run_wrong_s_tag_case();

    if (failure_count_q == 0) begin
      $display("[BRINGUP][PASS] all bring-up cases passed");
      #10;
      $finish;
    end else begin
      $fatal(1, "[BRINGUP][FAIL] failures=%0d", failure_count_q);
    end
  end

endmodule
