/**
 * This file is part of the Time Tagger software defined digital data
 * acquisition FPGA-link reference design.
 *
 * Copyright (C) 2022-2024 Swabian Instruments, All Rights Reserved
 *
 * Authors:
 * - 2023 Loghman Rahimzadeh <loghman@swabianinstruments.com>
 *
 * This file is provided under the terms and conditions of the BSD 3-Clause
 * license, accessible under https://opensource.org/licenses/BSD-3-Clause.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

/*
This module counts the number of bits per combination and filters the combination based on number of bits(number of channels)
Maximum and minimum number of allowed channels per combination should be configured by user before running combination
*/

// verilog_format: off
`resetall
`timescale 1ns / 1ps
`default_nettype none
// verilog_format: on

module filter_combination #(
    parameter LANE  = 4,
    parameter WIDTH = 16
) (
    input  wire                       rst,
    input  wire                       clk,
    input  wire [$clog2(WIDTH+1)-1:0] filter_min,
    input  wire [$clog2(WIDTH+1)-1:0] filter_max,
    input  wire [           LANE-1:0] data_in_vd,
    input  wire [          WIDTH-1:0] data_in    [LANE-1:0],
    output reg  [           LANE-1:0] data_out_vd,
    output reg  [          WIDTH-1:0] data_out   [LANE-1:0]
);

    always @(posedge clk) begin
        data_out_vd <= 0;
        data_out    <= '{default: 'X};
        if (!rst) begin
            for (int i = 0; i < LANE; i++) begin
                if (data_in_vd[i]) begin
                    if ($countones(data_in[i]) >= filter_min && $countones(data_in[i]) <= filter_max) begin
                        data_out[i]    <= data_in[i];
                        data_out_vd[i] <= data_in_vd[i];
                    end
                end
            end
        end
    end

endmodule
