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
This module stores the full lane inputs i.e. LANE=4 in the FIFO and readout by one-word.
*/

// verilog_format: off
`resetall
`timescale 1ns / 1ps
`default_nettype none
// verilog_format: on

module lane_reduction #(
    parameter LANE = 4,
    parameter WIDTH = 16,
    parameter FIFO_DEPTH = 8192
) (
    input  wire             rst,
    input  wire             clk,
    input  wire [ LANE-1:0] data_in_vd,
    input  wire [WIDTH-1:0] data_in    [LANE-1:0],
    input  wire             read_en,
    output wire             data_out_vd,
    output wire [WIDTH-1:0] data_out,
    output wire             o_overflow,
    output wire             fifo_empty
);

    logic wr_en_fifo;
    logic [LANE*(WIDTH+2)-1:0] data_in_fifo;
    logic data_valid;
    logic [(WIDTH+2)-1:0] dout_fifo;
    logic empty, rd_en_fifo, full, overflow;
    logic overflow_ff;

    always_ff @(posedge clk) begin : writing
        wr_en_fifo <= '0;
        if (|data_in_vd == 1) begin
            wr_en_fifo <= 1;

        end
        for (int i = 0; i < LANE; i++) begin
            data_in_fifo[(WIDTH+2)*i+:WIDTH+2] <= {overflow_ff, data_in_vd[i], data_in[i]};
        end

        if ((wr_en_fifo && !full) || overflow || rst) begin
            overflow_ff <= overflow;
        end
    end : writing

    assign rd_en_fifo = ~empty & read_en;
    assign data_out_vd = data_valid && dout_fifo[WIDTH];
    assign data_out = dout_fifo[WIDTH-1 : 0];
    assign o_overflow = data_valid && dout_fifo[WIDTH+1];
    assign fifo_empty = empty;

    xpm_fifo_sync #(
        .FIFO_READ_LATENCY(2),
        .FIFO_WRITE_DEPTH (FIFO_DEPTH / LANE),
        .FULL_RESET_VALUE (0),
        .PROG_EMPTY_THRESH(10),
        .PROG_FULL_THRESH (FIFO_DEPTH / LANE - 10),
        .READ_DATA_WIDTH  (WIDTH + 2),
        .USE_ADV_FEATURES ("1707"),
        .WRITE_DATA_WIDTH (LANE * (WIDTH + 2))
    ) xpm_fifo_async_inst (
        .data_valid(data_valid),
        .dout(dout_fifo),
        .empty(empty),
        .full(full),
        .overflow(overflow),
        .din(data_in_fifo),
        .rd_en(rd_en_fifo),
        .rst(rst),
        .wr_clk(clk),
        .wr_en(wr_en_fifo)
    );

endmodule
