/*
 * wide_divider
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

module wide_divider #(
    parameter DIVIDEND_WIDTH = 100,
    parameter DIVISOR_WIDTH  = 30
) (
    input wire clk,
    input wire start,
    output reg ready,
    input wire [DIVIDEND_WIDTH - 1 : 0] dividend,
    input wire [DIVISOR_WIDTH - 1 : 0] divisor,
    output reg [DIVIDEND_WIDTH - 1 : 0] quotient,
    output reg [DIVISOR_WIDTH - 1 : 0] remainder,
    output reg validout
);

    localparam TOTAL_WIDTH = DIVIDEND_WIDTH + DIVISOR_WIDTH;
    localparam CNT_WIDTH = $clog2(DIVIDEND_WIDTH + 1);

    logic [TOTAL_WIDTH - 1 : 0] divident_1;
    logic [TOTAL_WIDTH - 1 : 0] divisor_1;
    logic [CNT_WIDTH - 1 : 0] counter;
    logic process_en = 0;

    logic [TOTAL_WIDTH : 0] difference;
    assign difference = $signed({1'b0, divident_1}) - $signed({1'b0, divisor_1});

    logic [DIVIDEND_WIDTH - 1 : 0] result_reg;
    logic finished;

    always @(posedge clk) begin
        finished <= 0;
        ready <= process_en || start ? 0 : 1;
        divisor_1 <= 'X;
        divident_1 <= 'X;
        counter <= 'X;
        result_reg <= 'X;
        if (process_en) begin
            divisor_1 <= divisor_1 >> 1;
            divident_1 <= difference[TOTAL_WIDTH] ? divident_1 : difference;
            counter <= counter - 1;
            result_reg <= {result_reg[DIVIDEND_WIDTH-2 : 0], ~difference[TOTAL_WIDTH]};
            if (counter == 0) begin
                process_en <= 0;
                ;
                finished <= 1;
            end
        end else if (start) begin
            process_en <= 1;
            divident_1 <= {{DIVISOR_WIDTH{1'b0}}, dividend};
            divisor_1 <= {divisor, {DIVIDEND_WIDTH{1'b0}}};
            counter <= DIVIDEND_WIDTH;
            result_reg <= 0;
            ready <= 0;
        end

        quotient  <= 'X;
        remainder <= 'X;
        if (finished) begin
            remainder <= divident_1[0+:DIVISOR_WIDTH];
            quotient  <= result_reg;
        end
        validout <= finished;
    end

endmodule
