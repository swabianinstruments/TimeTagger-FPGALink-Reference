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
This module packs the received inputs to a full lane
*/

// verilog_format: off
`resetall
`timescale 1ns / 1ps
`default_nettype none
// verilog_format: on

module lane_packing #(
    parameter LANE  = 4,
    parameter WIDTH = 16
) (
    input  wire             rst,
    input  wire             clk,
    input  wire             flush,
    input  wire [ LANE-1:0] data_in_vd,
    input  wire [WIDTH-1:0] data_in    [LANE-1:0],
    output reg  [ LANE-1:0] data_out_vd,
    output reg  [WIDTH-1:0] data_out   [LANE-1:0]
);

    generate
        if (LANE == 1) begin : no_change
            assign data_out_vd = data_in_vd;
            assign data_out = data_in;

        end else begin : packing_lanes
            logic [WIDTH-1:0] data_buffer_comb    [LANE-1:0];
            logic [ LANE-1:0] data_vd_buffer_comb;
            always @(posedge clk) begin
                data_out_vd <= '{default: '0};
                data_out    <= '{default: 'X};
                if (rst) begin
                    data_vd_buffer_comb = 0;
                    data_buffer_comb    = '{default: 'X};
                end else begin
                    automatic logic flushed = 0;
                    for (int i = 0; i < LANE; i = i + 1) begin
                        if (data_in_vd[i]) begin
                            data_buffer_comb[LANE-2:0]    = data_buffer_comb[LANE-1:1];
                            data_buffer_comb[LANE-1]      = data_in[i];

                            data_vd_buffer_comb[LANE-2:0] = data_vd_buffer_comb[LANE-1:1];
                            data_vd_buffer_comb[LANE-1]   = 1;
                        end
                        if (data_vd_buffer_comb == '1 || (flush && i == LANE - 1 && !flushed)) begin
                            data_out_vd <= data_vd_buffer_comb;
                            data_out    <= data_buffer_comb;
                            data_vd_buffer_comb = '0;
                            data_buffer_comb    = '{default: 'X};
                            flushed = 1;
                        end
                    end
                end
            end
        end
    endgenerate
endmodule
