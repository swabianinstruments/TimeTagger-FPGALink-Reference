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

    output wire                             m_axis_tvalid,
    input  wire                             m_axis_tready,
    // The time the tag was captured at
    // In 1/3 ps since the startup of the TTX
    output reg        [             64-1:0] m_axis_tagtime[NUMBER_OF_WORDS-1:0],
    // channel number: 1 to 18 for rising edge and -1 to -18 for falling edge
    output reg signed [                5:0] m_axis_channel[NUMBER_OF_WORDS-1:0],
    output reg        [NUMBER_OF_WORDS-1:0] m_axis_tkeep,

    // Output of the lowest expected time for the next channels, to be able
    // to know that in certain time frame events *didn't* occur. Same format as tagtime
    output reg [64-1:0] lowest_time_bound
);

    assign s_axis_tready = m_axis_tready || !m_axis_tvalid;

    // Handle a further rollover of t_axis_tuser (rollover_time), should happen roughly every 6.5 hours
    reg [31:0] extended_rollover_time = 0;
    reg [31:0] s_axis_tuser_p;
    reg [63:0] lowest_time_bound_p1;
    reg [63:0] lowest_time_bound_p2;
    reg [63:0] lowest_time_bound_p3;

    always @(posedge clk) begin
        if (rst == 1) begin
            extended_rollover_time <= 0;
            s_axis_tuser_p <= 0;
            lowest_time_bound <= 0;
            lowest_time_bound_p1 <= 0;
            lowest_time_bound_p2 <= 0;
            lowest_time_bound_p3 <= 0;
        end else if (s_axis_tready) begin
            if (s_axis_tvalid & (s_axis_tkeep != 0)) begin
                s_axis_tuser_p <= s_axis_tuser;
                // Extended rollover occurred
                if (s_axis_tuser_p > s_axis_tuser) begin
                    extended_rollover_time <= extended_rollover_time + 1;
                end

                lowest_time_bound_p1 <= {extended_rollover_time, s_axis_tuser_p, {12{1'b0}}} * 4000;
            end

            // Delay to match the processing of the tagtime
            lowest_time_bound_p2 <= lowest_time_bound_p1;
            lowest_time_bound_p3 <= lowest_time_bound_p2;

            if (lowest_time_bound_p3 > lowest_time_bound) begin
                lowest_time_bound <= lowest_time_bound_p3;
            end
            for (int i = 0; i < NUMBER_OF_WORDS; i += 1) begin
                if (m_axis_tkeep[i]) begin
                    // The tagtime is always equal or higher than lowest_time_bound_p3 and lowest_time_bound
                    // as it's sorted
                    lowest_time_bound <= m_axis_tagtime[i];
                end
            end
        end
    end

    genvar i;
    generate
        for (i = 0; i < NUMBER_OF_WORDS; i += 1) begin
            reg [ 1:0] event_type;
            reg [ 5:0] channel_number;
            reg [11:0] subtime;
            reg [63:0] tagtime_p;
            reg [31:0] tdata_p;
            reg [31:0] rollover_time_p;

            always @(posedge clk) begin
                if (rst == 1) begin
                    tagtime_p <= 0;
                    rollover_time_p <= 0;
                    tdata_p <= 0;
                end else if (s_axis_tready) begin
                    // Clear data if it's invalid
                    tdata_p <= (s_axis_tvalid & (s_axis_tkeep[4*i+:4] == 4'hF)) ? s_axis_tdata[32*i+:32] : 0;
                    rollover_time_p <= s_axis_tuser;

                    subtime <= tdata_p[23:12];
                    tagtime_p <= {extended_rollover_time, rollover_time_p, tdata_p[11:0]} * 4000;
                    event_type <= tdata_p[31:30];
                    channel_number <= tdata_p[29:24];

                    m_axis_tagtime[i] <= tagtime_p + subtime;
                    m_axis_tkeep[i] <= (event_type == 2'b01) && (channel_number < (2 * CHANNEL_COUNT));
                    if (channel_number < CHANNEL_COUNT) begin
                        m_axis_channel[i] <= channel_number + 1;
                    end else begin
                        m_axis_channel[i] <= CHANNEL_COUNT - 1 - channel_number;
                    end

                end
            end
        end
    endgenerate
    assign m_axis_tvalid = |m_axis_tkeep;
endmodule
