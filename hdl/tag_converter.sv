/**
 * User Sample Design for high bandwidth applications
 *
 * This file is part of the Time Tagger software defined digital data
 * acquisition FPGA-link reference design.
 *
 * Copyright (C) 2023 Swabian Instruments, All Rights Reserved
 *
 * Authors:
 * - 2023 David Sawatzke <david@swabianinstruments.com>
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

// This module parses tags in the internal TimeTagger format to make it easier to process them
// This one can output more than one tag per cycle, making it ideal for usage with high bandwidth
// scenarios like 40 Gig Ethernet

module si_tag_converter #(
    // This is the internal channel count and should be kept at 20 for the TTX
    parameter CHANNEL_COUNT = 20,

    parameter DATA_WIDTH_IN   = 128,
    parameter KEEP_WIDTH_IN   = (DATA_WIDTH_IN + 7) / 8,
    parameter NUMBER_OF_WORDS = (DATA_WIDTH_IN + 31) / 32
) (
    input wire clk,
    input wire rst,

    input  wire                     s_axis_tvalid,
    output wire                     s_axis_tready,
    input  wire [DATA_WIDTH_IN-1:0] s_axis_tdata,
    input  wire                     s_axis_tlast,
    input  wire [KEEP_WIDTH_IN-1:0] s_axis_tkeep,
    input  wire [           32-1:0] s_axis_tuser,   // Rollover time

    output wire                 m_axis_tvalid,
    input  wire                 m_axis_tready,
    // The time the tag was captured at
    // In 1/3 ps since the startup of the TTX
    output wire        [64-1:0] m_axis_tagtime[NUMBER_OF_WORDS-1:0],
    // channel number: 1 to 18 for rising edge and -1 to -18 for falling edge
    output wire signed [   5:0] m_axis_channel[NUMBER_OF_WORDS-1:0],

    output wire [NUMBER_OF_WORDS-1:0] m_axis_tkeep
);

    assign s_axis_tready = m_axis_tready || !m_axis_tvalid;

    // Handle rollover of t_axis_tuser, should happen roughly every 6.5 hours
    reg [31:0] rollover_time = 0;
    reg [31:0] rollover_time_p;
    reg [31:0] s_axis_tuser_p;

    always @(posedge clk) begin
        if (rst == 1) begin
            rollover_time <= 0;
            rollover_time_p <= 0;
        end else begin
             rollover_time_p <= rollover_time;
             if(s_axis_tready & (s_axis_tvalid != 0) & (s_axis_tkeep != 0)) begin
                  s_axis_tuser_p <= s_axis_tuser;
                  // Rollover occurred
                  if (s_axis_tuser_p > s_axis_tuser) begin
                       rollover_time <= rollover_time + 1;
                  end
             end
        end
    end

    genvar i;
    generate
        for (i = 0; i < NUMBER_OF_WORDS; i += 1) begin
            wire valid_tag;
            wire [63:0] tagtime;
            wire [1:0] event_type;
            wire [5:0] channel_number;
            reg signed [5:0] channel;
            wire [11:0] subtime;
            wire [11:0] counter;
            reg [63:0] tagtime_p;
            reg [63:0] tagtime_p2;
            reg [63:0] tagtime_p3;
            reg [63:0] tagtime_p4;
            reg [31:0] tdata_p;
            reg [31:0] tdata_p2;
            reg [31:0] tdata_p3;
            reg [31:0] tdata_p4;
            reg [31:0] tdata_p5;
            reg [31:0] tdata_p6;
            reg [31:0] wrap_count_p;
            reg [31:0] wrap_count_p2;

            assign counter = tdata_p2[11:0];
            assign subtime = tdata_p4[23:12];
            always @(posedge clk) begin
                if (rst == 1) begin
                    tagtime_p <= 0;
                    tagtime_p2 <= 0;
                    tagtime_p3 <= 0;
                    tagtime_p4 <= 0;
                    wrap_count_p <= 0;
                    wrap_count_p2 <= 0;
                    tdata_p <= 0;
                    tdata_p2 <= 0;
                    tdata_p3 <= 0;
                    tdata_p4 <= 0;
                    tdata_p5 <= 0;
                    tdata_p6 <= 0;
                end else if (s_axis_tready) begin
                    tagtime_p <= {rollover_time_p, wrap_count_p2, counter} * 4000;
                    tagtime_p2 <= tagtime_p;
                    tagtime_p3 <= tagtime_p2 + subtime;
                    tagtime_p4 <= tagtime_p3;
                    // Clear data if it's invalid
                    tdata_p <= (s_axis_tvalid & (s_axis_tkeep[4*i+:4] == 4'hF)) ? s_axis_tdata[32*i+:32] : 0;
                    wrap_count_p <= s_axis_tuser;
                    wrap_count_p2 <= wrap_count_p;
                    tdata_p2 <= tdata_p;
                    tdata_p3 <= tdata_p2;
                    tdata_p4 <= tdata_p3;
                    tdata_p5 <= tdata_p4;
                    tdata_p6 <= tdata_p5;
                end
            end

            assign event_type = tdata_p6[31:30];
            assign channel_number = tdata_p6[29:24];
            assign valid_tag = (event_type == 2'b01) && (channel_number < (2 * CHANNEL_COUNT));
            assign tagtime = tagtime_p4;

            always @(*) begin
                if (channel_number < CHANNEL_COUNT) begin
                    channel = channel_number + 1;
                end else begin
                    channel = CHANNEL_COUNT - 1 - channel_number;
                end
            end

            assign m_axis_tagtime[i] = tagtime;
            assign m_axis_channel[i] = channel;
            assign m_axis_tkeep[i]   = valid_tag;
        end
    endgenerate
    assign m_axis_tvalid = |m_axis_tkeep;
endmodule
