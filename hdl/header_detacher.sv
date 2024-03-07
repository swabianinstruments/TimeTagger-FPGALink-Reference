/**
 * AXI4-Stream Time Tag Packet Header Detacher
 *
 * This file is part of the Time Tagger software defined digital data
 * acquisition FPGA-link reference design.
 *
 * Copyright (C) 2022-2023 Swabian Instruments, All Rights Reserved
 *
 * Authors:
 * - 2022-2023 David Sawatzke <david@swabianinstruments.com>
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

// This module removes the header from the timetag data stream, throwing away
// the first 256 bits and extracting m_axis_tuser from it
module si_header_detacher #(
    parameter DATA_WIDTH = 128,
    parameter KEEP_WIDTH = (DATA_WIDTH + 7) / 8
) (
    input wire clk,
    input wire rst,

    input  wire                  s_axis_tvalid,
    output reg                   s_axis_tready,
    input  wire [DATA_WIDTH-1:0] s_axis_tdata,
    input  wire                  s_axis_tlast,
    input  wire [KEEP_WIDTH-1:0] s_axis_tkeep,

    output reg                   m_axis_tvalid,
    input  wire                  m_axis_tready,
    output reg  [DATA_WIDTH-1:0] m_axis_tdata,
    output reg                   m_axis_tlast,
    output reg  [KEEP_WIDTH-1:0] m_axis_tkeep,
    output reg  [          31:0] m_axis_tuser
);
    initial begin
        // Some sanity checks:

        // - ensure that the data-width is 256 bits or less, shifting isn't supported by this module
        if (DATA_WIDTH > 256) begin
            $error("Error: data-width needs to be 256 bits or less");
            $finish;
        end
        // - ensure that the rollover count is in a single word
        if (DATA_WIDTH % 32 != 0) begin
            $error("Error: data-width needs to be a multiple of 32 bits");
            $finish;
        end
        // - ensure that the DATA_WIDTH can cleanly divide 256
        if (256 % DATA_WIDTH != 0) begin
            $error("Error: data-width needs to be a divisor of 256");
            $finish;
        end
    end

    reg [$clog2(256/DATA_WIDTH+1)-1:0] remaining_header_words;
    always @(posedge clk) begin
        if (rst == 1) begin
            remaining_header_words <= 256 / DATA_WIDTH;
        end else if (s_axis_tvalid && s_axis_tready) begin
            if (s_axis_tlast) begin
                remaining_header_words <= 256 / DATA_WIDTH;
            end else if (remaining_header_words > 0) begin
                remaining_header_words <= remaining_header_words - 1;
            end
            if (remaining_header_words == 1) begin
                m_axis_tuser <= s_axis_tdata[32*(DATA_WIDTH/32-1)+:32];  // Extract rollover count here
            end
        end
    end

    always @(*) begin
        if (remaining_header_words > 0) begin
            s_axis_tready <= 1;
            m_axis_tvalid <= 0;
            m_axis_tdata  <= 0;
            m_axis_tlast  <= 0;
            m_axis_tkeep  <= 0;
        end else begin
            s_axis_tready <= m_axis_tready;
            m_axis_tvalid <= s_axis_tvalid;
            m_axis_tdata  <= s_axis_tdata;
            m_axis_tlast  <= s_axis_tlast;
            m_axis_tkeep  <= s_axis_tkeep;
        end
    end

endmodule

`resetall
