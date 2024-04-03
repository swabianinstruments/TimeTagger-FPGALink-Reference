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
 * - 2024 Ehsan Jokar <ehsan@swabianinstruments.com>
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
// the first 256 bits and extracting m_axis.tuser from it
module si_header_detacher (
    axis_interface.slave  s_axis,
    axis_interface.master m_axis
);
    initial begin
        // Some sanity checks:

        // - ensure that the data-width is 256 bits or less, shifting isn't supported by this module
        if (s_axis.DATA_WIDTH > 256) begin
            $error("Error: data-width needs to be 256 bits or less");
            $finish;
        end
        // - ensure that the rollover count is in a single word
        if (s_axis.DATA_WIDTH % 32 != 0) begin
            $error("Error: data-width needs to be a multiple of 32 bits");
            $finish;
        end
        // - ensure that the DATA_WIDTH can cleanly divide 256
        if (256 % s_axis.DATA_WIDTH != 0) begin
            $error("Error: data-width needs to be a divisor of 256");
            $finish;
        end
    end

    reg [$clog2(256/s_axis.DATA_WIDTH+1)-1:0] remaining_header_words;
    always @(posedge s_axis.clk) begin
        if (s_axis.rst == 1) begin
            remaining_header_words <= 256 / s_axis.DATA_WIDTH;
        end else if (s_axis.tvalid && s_axis.tready) begin
            if (s_axis.tlast) begin
                remaining_header_words <= 256 / s_axis.DATA_WIDTH;
            end else if (remaining_header_words > 0) begin
                remaining_header_words <= remaining_header_words - 1;
            end
            if (remaining_header_words == 1) begin
                m_axis.tuser <= s_axis.tdata[32*(s_axis.DATA_WIDTH/32-1)+:32];  // Extract rollover count here
            end
        end
    end

    always_comb begin
        if (remaining_header_words > 0) begin
            s_axis.tready <= 1;
            m_axis.tvalid <= 0;
            m_axis.tdata  <= 0;
            m_axis.tlast  <= 0;
            m_axis.tkeep  <= 0;
        end else begin
            s_axis.tready <= m_axis.tready;
            m_axis.tvalid <= s_axis.tvalid;
            m_axis.tdata  <= s_axis.tdata;
            m_axis.tlast  <= s_axis.tlast;
            m_axis.tkeep  <= s_axis.tkeep;
        end
    end

endmodule
