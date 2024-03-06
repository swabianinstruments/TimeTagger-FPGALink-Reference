/*
 * wide_mult
 *
 * This file is part of the Time Tagger software defined digital data
 * acquisition FPGA-link reference design.
 *
 * Copyright (C) 2023 Swabian Instruments, All Rights Reserved
 *
 * Authors:
 * - 2023 Ehsan Jokar <ehsan@swabianinstruments.com>
 *
 * This file is provided under the terms and conditions of the BSD 3-Clause
 * license, accessible under https://opensource.org/licenses/BSD-3-Clause.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

// verilog_format: off
 `resetall
 `timescale 1ns / 1ps
 `default_nettype none
// verilog_format: on

module wide_mult #(
    parameter INPUT1_WIDTH    = 24,
    parameter INPUT1_UNSIGNED = 1, // 1 == unsigned, 0 == signed
    parameter INPUT2_WIDTH = 34,
    parameter INPUT2_UNSIGNED = 1, // 1 == unsigned, 0 == signed
    parameter OUTPUT_WIDTH = INPUT1_WIDTH + INPUT2_WIDTH,
    parameter LATENCY = 6  // at least two clock cycles
) (
    input wire clk,
    input wire [INPUT1_WIDTH - 1 : 0] din1,
    input wire [INPUT2_WIDTH - 1 : 0] din2,
    output wire [OUTPUT_WIDTH - 1 : 0] dout  // The output would be unsigned if both inputs are unsigned
                                             // otherwise, the output would be signed
);
    initial begin
        if (!((INPUT1_UNSIGNED == 0) || (INPUT1_UNSIGNED == 1))) begin
            $error("Error: INPUT1_UNSIGNED should be zero or one.");
            $finish;
        end
        if (!((INPUT2_UNSIGNED == 0) || (INPUT2_UNSIGNED == 1))) begin
            $error("Error: INPUT2_UNSIGNED should be zero or one.");
            $finish;
        end
        if (LATENCY < 2) begin
            $error("Error: LATENCY should be at least 2.");
            $finish;
        end
    end

    localparam INP1_WIDTH = INPUT1_WIDTH + INPUT1_UNSIGNED;
    logic [INP1_WIDTH - 1 : 0] r0din1;

    localparam INP2_WIDTH = INPUT2_WIDTH + INPUT2_UNSIGNED;
    logic [INPUT2_WIDTH + INPUT2_UNSIGNED - 1 : 0] r0din2;

    generate
        if (INPUT1_UNSIGNED) begin
            assign r0din1 = {1'b0, din1};
        end else begin
            assign r0din1 = din1;
        end
        if (INPUT2_UNSIGNED) begin
            assign r0din2 = {1'b0, din2};
        end else begin
            assign r0din2 = din2;
        end
    endgenerate

    localparam MULT_WIDTH = INP1_WIDTH + INP2_WIDTH;
    logic [MULT_WIDTH - 1 : 0] mult;
    logic [MULT_WIDTH - 1 : 0] delay_buf[LATENCY - 1];

    always @(posedge clk) begin
        mult <= $signed(r0din1) * $signed(r0din2);
        delay_buf[0] <= mult;
        for (int i = 1; i < LATENCY - 1; i++) begin
            delay_buf[i] <= delay_buf[i-1];
        end
    end
    // The real output size should be INPUT1_WIDTH + INPUT2_WIDTH.
    // If the required size is smaller, the upper bits will be selected.
    assign dout = delay_buf[LATENCY-2][INPUT1_WIDTH+INPUT2_WIDTH-1-:OUTPUT_WIDTH];

endmodule
