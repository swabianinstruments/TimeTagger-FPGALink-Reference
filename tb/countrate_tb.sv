/**
 * Testbench for the countrate module
 *
 * This file is part of the Time Tagger software defined digital data
 * acquisition FPGA-link reference design.
 *
 * Copyright (C) 2022 Swabian Instruments, All Rights Reserved
 *
 * Authors:
 * - 2023-2024 Ehsan Jokar <ehsan@swabianinstruments.com>
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

module countrate_tb;
    // (* dont_touch="true" *)
    // Parameters
    localparam TAG_WIDTH = 64;
    localparam NUM_OF_TAGS = 4;
    localparam CHANNEL_WIDTH = 6;
    localparam WINDOW_WIDTH = TAG_WIDTH;
    localparam NUM_OF_CHANNELS = 4;
    localparam COUNTER_WIDTH = 32;
    localparam INPUT_FIFO_DEPTH = 1024;
    localparam TOT_TAGS_WIDTH = TAG_WIDTH * NUM_OF_TAGS;
    localparam TOT_CHANNELS_WIDTH = CHANNEL_WIDTH * NUM_OF_TAGS;

    reg clk = 0;
    reg rst = 0;
    // wb signal for later tests
    logic wb_clk = 0, wb_rst = 1;
    logic [31 : 0] wb_data_i, wb_data_o;
    logic wb_we, wb_stb, wb_cyc, wb_ack;
    logic [7:0] wb_addr;

    reg [NUM_OF_TAGS - 1 : 0] valid_tag;
    reg [TOT_TAGS_WIDTH - 1 : 0] tagtime;
    reg [TOT_CHANNELS_WIDTH - 1 : 0] channel;
    reg [WINDOW_WIDTH - 1 : 0] window_size = 50000;
    reg start_counting;
    reg reset_counting;
    wire [COUNTER_WIDTH - 1 : 0] count_data[NUM_OF_CHANNELS];
    wire count_valid;

    countrate #(
        .TAG_WIDTH(TAG_WIDTH),
        .NUM_OF_TAGS(NUM_OF_TAGS),
        .CHANNEL_WIDTH(CHANNEL_WIDTH),
        .WINDOW_WIDTH(WINDOW_WIDTH),
        .NUM_OF_CHANNELS(NUM_OF_CHANNELS),
        .COUNTER_WIDTH(COUNTER_WIDTH),
        .INPUT_FIFO_DEPTH(INPUT_FIFO_DEPTH)
    ) countrate_inst (
        .clk(clk),
        .rst(rst),
        .valid_tag(valid_tag),
        .tagtime(tagtime),
        .channel(channel),
        .window_size(window_size),
        .start_counting(start_counting),
        .reset_counting(reset_counting),
        // .count_data(count_data),
        .count_valid(count_valid)
    );

    always #1.5  clk = !clk;  // 333.33 Mhz
    always #5 wb_clk = !wb_clk;  // 100 Mhz
    initial begin
        #542 wb_rst = 0;
        //      rst = 0;
    end

    bit [31 : 0] rand1, rand2, rand3, rand4;

    logic [3 : 0] big_data;

    logic [TAG_WIDTH - 1 : 0] tag1 = 0, tag2 = 0, tag3 = 0, tag4 = 0;
    logic [TAG_WIDTH - 1 : 0] r1tag1, r1tag2, r1tag3, r1tag4;
    logic [TAG_WIDTH - 1 : 0] r0tag1, r0tag2, r0tag3, r0tag4;
    logic [CHANNEL_WIDTH - 1 : 0] channel1 = 0, channel2 = 0, channel3 = 0, channel4 = 0;
    logic [CHANNEL_WIDTH - 1 : 0] r0channel1, r0channel2, r0channel3, r0channel4;
    logic valid1, valid2, valid3, valid4;

    assign r0channel1 = valid1 ? channel1 : 'X;
    assign r0channel2 = valid2 ? channel2 : 'X;
    assign r0channel3 = valid3 ? channel3 : 'X;
    assign r0channel4 = valid4 ? channel4 : 'X;

    assign r0tag1 = valid1 ? tag1 : 'X;
    assign r0tag2 = valid2 ? tag2 : 'X;
    assign r0tag3 = valid3 ? tag3 : 'X;
    assign r0tag4 = valid4 ? tag4 : 'X;

    assign channel = {r0channel4, r0channel3, r0channel2, r0channel1};
    assign tagtime = {r0tag4, r0tag3, r0tag2, r0tag1};
    assign valid_tag = {valid4, valid3, valid2, valid1};
    logic [31:0] cnt = 0;
    logic new_data;
    // the lower channel, the higher chance of receiving data
    // on the start and click channel
    always_ff @(posedge clk) begin
        cnt <= cnt + 1;
        rst <= 1;
        if (cnt >= 5 || cnt <= 3) rst <= 0;

        if ((rst == 1) || cnt < 10 || (cnt >= 3000 && cnt <= 5000) || !new_data) begin
            valid1 <= 0;
            valid2 <= 0;
            valid3 <= 0;
            valid4 <= 0;
        end else begin
            valid1 <= $urandom_range(1, 0);
            valid2 <= $urandom_range(1, 0);
            valid3 <= $urandom_range(1, 0);
            valid4 <= $urandom_range(1, 0);
        end

        new_data <= 0;
        if (!cnt[9]) new_data <= 1;

        rand1 <= 0;
        rand2 <= 0;
        rand3 <= 0;
        rand4 <= 0;
        if (new_data) begin
            rand1 <= $urandom_range(100, 1);
            rand2 <= cnt[5 : 0] == 0 ? $urandom_range(20000, 1) : $urandom_range(100, 1);
            rand3 <= cnt[7 : 0] == 0 ? $urandom_range(20000, 1) : $urandom_range(100, 1);
            rand4 <= $urandom_range(100, 1);
        end

        /////////////// multi-lane adder///////////////////
        tag1 <= tag4 + rand1;
        tag2 <= tag4 + rand1 + rand2;
        tag3 <= tag4 + rand1 + rand2 + rand3;
        tag4 <= tag4 + rand1 + rand2 + rand3 + rand4;
        channel1 <= $urandom_range(NUM_OF_CHANNELS - 1, 0);
        channel2 <= $urandom_range(NUM_OF_CHANNELS - 1, 0);
        channel3 <= $urandom_range(NUM_OF_CHANNELS - 1, 0);
        channel4 <= $urandom_range(NUM_OF_CHANNELS - 1, 0);

        start_counting <= 0;
        if (cnt == 49) start_counting <= 1;

        r1tag1 <= tag1;
        r1tag2 <= tag2;
        r1tag3 <= tag3;
        r1tag4 <= tag4;
    end

endmodule
