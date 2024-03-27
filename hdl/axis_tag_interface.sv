/**
 * AXI-Stream interface for time tag streaming
 *
 * This file is part of the Time Tagger software defined digital data
 * acquisition FPGA-link reference design.
 *
 * Copyright (C) 2022-2024 Swabian Instruments, All Rights Reserved
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

interface axis_tag_interface #(
    parameter integer WORD_WIDTH = 4,
    parameter integer TIME_WIDTH = 64,
    parameter integer CHANNEL_WIDTH = 6
);
    logic                            clk;
    logic                            rst;

    // 1 if the word is valid and tkeep needs to be checked, 0 if the full word is invalid
    logic                            tvalid;
    // The time the tag was captured at in 1/3 ps since the startup of the TTX
    logic        [   TIME_WIDTH-1:0] tagtime           [WORD_WIDTH-1:0];
    // channel number: 1 to 18 for rising edge and -1 to -18 for falling edge
    logic signed [CHANNEL_WIDTH-1:0] channel           [WORD_WIDTH-1:0];
    // Each bit in s_axis_tkeep represents the validity of an event:
    // 1 for a valid event, 0 for no event in the corresponding bit position.
    logic        [   WORD_WIDTH-1:0] tkeep;

    // Output of the lowest expected time for the next channels, to be able
    // to know that in certain time frame events *didn't* occur. Same format as tagtime
    logic        [   TIME_WIDTH-1:0] lowest_time_bound;

    // 1 if this module is able to accept new data in this clock period. Must always be 1
    logic                            tready;

    modport master(input tready, output clk, rst, tvalid, tagtime, channel, tkeep, lowest_time_bound);
    modport slave(input clk, rst, tvalid, tagtime, channel, tkeep, lowest_time_bound, output tready);
endinterface
