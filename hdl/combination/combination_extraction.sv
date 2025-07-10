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
This module will extract events in a specific window time, also no event should happen in specific time before and after the window(guard). For FPGA simplification Guard=Window
                              _______Window, events________
                             |                             |
                             |                             |
   ____Guard, no event_______|                             |________ Guard, no event______  WINDOW=GUARD

Output is a combinational of channels i.e. if a two events on channel 2 and 8 belongs to a combination, then the output will be 0x0104 = (2^2) | (2^8)
*/

// verilog_format: off
`resetall
`timescale 1ns / 1ps
`default_nettype none
// verilog_format: on

module combination_extraction #(
    parameter LANE = 4,
    parameter TIME_TAG_WIDTH = 64,
    parameter COMB_WIDTH = 16
) (
    //input information of channel
    input  wire [    TIME_TAG_WIDTH-1 : 0] window,
    input  wire [    TIME_TAG_WIDTH-1 : 0] Channel_TimeTag   [LANE-1:0],
    input  wire [$clog2(COMB_WIDTH)-1 : 0] Channel_Index     [LANE-1:0],
    input  wire [                LANE-1:0] Channel_In_Valid,
    input  wire                            clk,
    input  wire                            rst,
    output reg  [                    31:0] debug_comb_ext    [     2:0],
    output reg  [          COMB_WIDTH-1:0] out_channel_bitset[LANE-1:0],
    output reg  [                LANE-1:0] out_valid
);

    logic [TIME_TAG_WIDTH-1 : 0] Channel_TimeTag_r1      [LANE-1:0];
    logic [    COMB_WIDTH-1 : 0] Channel_Index_r1        [LANE-1:0];
    logic [            LANE-1:0] Channel_In_Valid_r1;
    //pre calculation
    logic [               0 : 0] diff_current_lastTag    [LANE-1:0];
    logic [TIME_TAG_WIDTH-1 : 0] prev_timeTag            [LANE-1:0];
    logic [TIME_TAG_WIDTH-1 : 0] prev_timeTag_r1         [LANE-1:0];
    logic [TIME_TAG_WIDTH-1 : 0] time_tag_last_lane;

    logic [      COMB_WIDTH-1:0] channel_bitset_comb = 0;
    logic [  TIME_TAG_WIDTH-1:0] first_tag_comb = 0;

    logic [      COMB_WIDTH-1:0] out_channel_bitset_comb [LANE-1:0];
    logic [            LANE-1:0] out_valid_comb;
    int                          i;

    // precalculation and pipelining to eliminate the critical path
    always @(posedge clk) begin
        Channel_TimeTag_r1   <= '{default: 'X};
        Channel_Index_r1     <= '{default: 'X};
        diff_current_lastTag <= '{default: '0};
        prev_timeTag_r1      <= '{default: 'X};
        if (rst) begin
            time_tag_last_lane  <= '0; // TODO: This might need a better initialization, but currently not worth the effort
            Channel_In_Valid_r1 <= '{default: '0};
        end else begin
            Channel_In_Valid_r1 <= Channel_In_Valid;
            for (i = 0; i < LANE; i++) begin
                if (Channel_In_Valid[i]) begin
                    Channel_TimeTag_r1[i] <= Channel_TimeTag[i];
                    Channel_Index_r1[i]   <= (1 << Channel_Index[i]);  // pipeline to decrease the critical path
                    time_tag_last_lane    <= Channel_TimeTag[i];
                    prev_timeTag_r1[i]    <= prev_timeTag[i];
                    if ($signed(Channel_TimeTag[i] - prev_timeTag[i]) >= window) begin
                        // precalculation to eliminate the delay of comparison in the critical path
                        diff_current_lastTag[i] <= 1;
                    end
                end
            end
        end
    end

    // Assign the timestamp of the last valid event. Inputs are packed, so always just pick the lane before, but for the first lane.
    assign prev_timeTag[0] = time_tag_last_lane;
    for (genvar gen_i = 1; gen_i < LANE; gen_i++) begin
        assign prev_timeTag[gen_i] = Channel_In_Valid[gen_i-1] ? Channel_TimeTag[gen_i-1] : 'X;
    end

    /// main process, calculating the combinations in a interlane way.
    /// As an example, combination 0xC5 = 2^7 + 2^6 + 2^2 + 2^0 means that the combination was on channel 7, 6, 2 and 0.
    always @(posedge clk) begin
        out_valid_comb <= '0;
        out_channel_bitset_comb <= '{default: 'X};
        if (rst) begin
            channel_bitset_comb = '0;
            first_tag_comb = '0;  // TODO: This might need a better initialization, but currently not worth the effort
            out_valid          <= '0;
            out_channel_bitset <= '{default: 'X};
        end else begin
            out_channel_bitset <= out_channel_bitset_comb;
            out_valid          <= out_valid_comb;
            for (int i = 0; i < LANE; i = i + 1) begin
                if (Channel_In_Valid_r1[i]) begin
                    if (diff_current_lastTag[i]) begin
                        // Commit last combination
                        if ($signed(prev_timeTag_r1[i] - first_tag_comb) < window && channel_bitset_comb != '0) begin
                            out_channel_bitset_comb[i] <= channel_bitset_comb;
                            out_valid_comb[i] <= 1;
                        end
                        channel_bitset_comb = Channel_Index_r1[i];
                        first_tag_comb = Channel_TimeTag_r1[i];
                    end else begin
                        channel_bitset_comb = channel_bitset_comb | Channel_Index_r1[i];
                    end
                end
            end
        end
    end

    ///// This part is only for debugging and reporting to the user
    // number of received time tags
    // number of unsorted time tag
    logic [63:0] cnt_timeTag;
    logic [31:0] cnt_timeDiff;

    always @(posedge clk) begin
        if (rst) begin
            cnt_timeTag <= 0;
            cnt_timeDiff = 0;
            debug_comb_ext <= '{default: 'x};
        end else begin
            debug_comb_ext[0] <= cnt_timeTag[31:0];
            debug_comb_ext[1] <= cnt_timeTag[63:32];
            debug_comb_ext[2] <= cnt_timeDiff;
            cnt_timeTag <= cnt_timeTag + $unsigned(
                $countones(Channel_In_Valid)
            );  /// counting number of timeTags(events)
            /// counting number of unsorted timeTags(events)
            for (int i = 0; i < LANE; i = i + 1) begin
                if (Channel_In_Valid[i]) begin
                    if ($signed(Channel_TimeTag[i] - prev_timeTag[i]) < 0) begin
                        cnt_timeDiff = cnt_timeDiff + 1;
                    end
                end
            end
        end
    end
endmodule
