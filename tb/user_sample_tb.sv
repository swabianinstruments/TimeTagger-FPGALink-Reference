/**
 * Test bench for user_sample
 *
 * Creates (kind of) plausible tags to verify parts of user_sample in simulation
 *
 * This file is part of the Time Tagger software defined digital data
 * acquisition FPGA-link reference design.
 *
 * Copyright (C) 2023 Swabian Instruments, All Rights Reserved
 *
 * Authors:
 * - 2023 David Sawatzke <david@swabianinstruments.com>
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

module user_sample_tb #(
    parameter WORD_WIDTH = 2,    // Amount of events processed in one clock period
    parameter channels   = 3,    // Channels for which events will be generated
    parameter event_gap  = 4000  // The time between each event in 1/3 ps
) ();


    reg clk;
    reg rst;

    initial begin
        clk <= 0;
        rst <= 1;

        #10 rst <= 0;
    end

    always begin
        #1 clk = ~clk;
    end

    reg [             4:0] channel    [WORD_WIDTH-1 : 0];
    reg                    rising_edge[WORD_WIDTH-1 : 0];
    reg [            63:0] tagtime    [WORD_WIDTH-1 : 0];
    reg [WORD_WIDTH-1 : 0] tkeep;

    user_sample #(
        .WORD_WIDTH(WORD_WIDTH)
    ) user_design (
        .clk(clk),
        .rst(rst),

        .s_axis_tvalid(|tkeep),
        .s_axis_tready(),
        .s_axis_tkeep(tkeep),
        .s_axis_channel(channel),
        .s_axis_tagtime(tagtime),
        .s_axis_rising_edge(rising_edge),

        // Deliberately unused
        .wb_clk  (clk),  // fake clk
        .wb_rst  (1),
        .wb_adr_i(),
        .wb_dat_i(),
        .wb_dat_o(),
        .wb_we_i (),
        .wb_stb_i(),
        .wb_cyc_i(),
        .wb_ack_o(),

        .led()
    );

    reg [63:0] prev_tagtime;
    always @(posedge clk) begin
        if (rst) begin
            prev_tagtime = 0;
        end else begin
            for (int i = 0; i < WORD_WIDTH; i += 1) begin
                if ($urandom % 2) begin
                    prev_tagtime = prev_tagtime + event_gap;
                    tkeep[i] <= 1;
                    tagtime[i] <= prev_tagtime;
                    channel[i] <= $urandom % channels;
                    // This can generate e.g. multiple rising edges for the same channel without falling ones in between
                    // The Time Tagger will behave in the same way if only the channel with rising edges is used
                    rising_edge[i] <= $urandom % 2;
                end else begin
                    tkeep[i] <= 0;
                    tagtime[i] <= 'x;
                    channel[i] <= 'x;
                    rising_edge[i] <= 'x;
                end
            end
        end
    end

endmodule
