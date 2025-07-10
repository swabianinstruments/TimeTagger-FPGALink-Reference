/**
 * This file is part of the Time Tagger software defined digital data
 * acquisition FPGA-link reference design.
 *
 * Copyright (C) 2022-2024 Swabian Instruments, All Rights Reserved
 *
 * Authors:
 * - 2024 Loghman Rahimzadeh <loghman@swabianinstruments.com>
 *
 * This file is provided under the terms and conditions of the BSD 3-Clause
 * license, accessible under https://opensource.org/licenses/BSD-3-Clause.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

/*
This module maps the input channels to to the existing
processing channel. Usually the input channels can range from -18-1 and 1-18,
which this module looks up in the `LUT` look up table and maps to one of our 16
virtual channels.

The look up table can be set freely by the user/host during runtime.
*/

// verilog_format: off
`resetall
`timescale 1ns / 1ps
`default_nettype none
// verilog_format: on

module channel_selector #(
    parameter WIDTH = 64,
    parameter LANE = 4,
    parameter CHANNEL_INP_WIDTH = 6,
    // unsigned output, to eliminate the distinction between positive (rising)
    // and negative (falling) channels
    parameter CHANNEL_OUTP_WIDTH = 4
) (
    input wire clk,
    input wire rst,

    input  wire                                s_axis_tvalid,
    output wire                                s_axis_tready,
    input  wire        [             LANE-1:0] s_axis_tkeep,
    input  wire        [            WIDTH-1:0] s_axis_tagtime[LANE-1:0],
    input  wire signed [CHANNEL_INP_WIDTH-1:0] s_axis_channel[LANE-1:0],

    output reg m_axis_tvalid,
    input wire m_axis_tready,
    output reg [LANE-1:0] m_axis_tkeep,
    output reg [WIDTH-1:0] m_axis_tagtime[LANE-1:0],
    output reg [CHANNEL_OUTP_WIDTH-1:0] m_axis_channel[LANE-1:0],
    // To report the end of reset
    output reg reset_comb_done,
    //To configuring channel look-up table
    output reg lut_ack,
    input wire [1:0] lut_WrRd,  // 2'b10: writing, 2'b01: reading
    input wire [CHANNEL_INP_WIDTH-1:0] lut_addr,
    input  wire [CHANNEL_OUTP_WIDTH:0]  lut_dat_i,// (CHANNEL_OUTP_WIDTH-1) bits for stored channel index and one bit for storing valid
    output reg [CHANNEL_OUTP_WIDTH:0] lut_dat_o
);

    logic [CHANNEL_OUTP_WIDTH:0] LUT[2**CHANNEL_INP_WIDTH];
    logic [CHANNEL_INP_WIDTH-1:0] lut_addr_rst;
    // Interface to set/read the look up table (from the host via WB)
    always_ff @(posedge clk) begin
        lut_ack         <= 0;
        lut_dat_o       <= 'X;
        lut_addr_rst    <= 0;
        reset_comb_done <= 0;
        if (rst) begin
            LUT[lut_addr_rst] <= 0;
            lut_addr_rst      <= lut_addr_rst + 1;
            if (lut_addr_rst == '1) begin
                reset_comb_done <= 1;
            end
        end else if (!lut_ack) begin
            if (lut_WrRd[1]) begin
                LUT[lut_addr] <= lut_dat_i;
                lut_ack       <= 1;
            end
            if (lut_WrRd[0]) begin
                lut_dat_o <= LUT[lut_addr];
                lut_ack   <= 1;
            end
        end
    end

    assign s_axis_tready = m_axis_tready || !m_axis_tvalid;

    always_ff @(posedge clk) begin
        if (rst) begin
            m_axis_tvalid  <= 0;
            m_axis_tkeep   <= 0;
            m_axis_channel <= '{default: 'X};
            m_axis_tagtime <= '{default: 'X};
        end else if (s_axis_tready) begin
            m_axis_tvalid  <= 0;
            m_axis_tkeep   <= 0;
            m_axis_channel <= '{default: 'X};
            m_axis_tagtime <= '{default: 'X};
            for (int i = 0; i < LANE; i = i + 1) begin
                if (s_axis_tvalid && s_axis_tkeep[i]) begin
                    m_axis_tvalid     <= 1;
                    m_axis_tkeep[i]   <= LUT[$unsigned(s_axis_channel[i])][CHANNEL_OUTP_WIDTH];
                    m_axis_channel[i] <= LUT[$unsigned(s_axis_channel[i])][CHANNEL_OUTP_WIDTH-1:0];
                    m_axis_tagtime[i] <= s_axis_tagtime[i];
                end
            end
        end
    end

endmodule
