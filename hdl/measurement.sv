/**
 * measurement module: Add all your modules here!
 *
 * This file is part of the Time Tagger software defined digital data
 * acquisition FPGA-link reference design.
 *
 * Copyright (C) 2022-2024 Swabian Instruments, All Rights Reserved
 *
 * Authors:
 * - 2024 Ehsan Jokar <ehsan@swabianinstruments.com>
 *
 * This file is provided under the terms and conditions of the BSD 3-Clause
 * license, accessible under https://opensource.org/licenses/BSD-3-Clause.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

`resetall
`timescale 1ns / 1ps
`default_nettype none

module measurement #(
    // WORD_WIDTH controls how many events are processed simultaneously
     parameter WORD_WIDTH = 4
) (
     input wire                  clk,
     input wire                  rst,

     // 1 if the word is valid and tkeep needs to be checked, 0 if the full word is invalid
     input wire                  s_axis_tvalid,
     // 1 if this module is able to accept new data in this clock period. Must always be 1
     output wire                 s_axis_tready,
     // The time the tag was captured at in 1/3 ps since the startup of the TTX
     input wire [64-1:0]         s_axis_tagtime [WORD_WIDTH-1:0],
     // The channel this event occured on. Starts at 0 while the actual channel numbering
     // starts with 1! (if 'channel' is 2, it's actually the channel number 3)
     input wire [4:0]            s_axis_channel [WORD_WIDTH-1:0],
     // 1 on rising edge, 0 on falling edge
     input wire                  s_axis_rising_edge [WORD_WIDTH-1:0],
     // Each bit in s_axis_tkeep represents the validity of an event:
     // 1 for a valid event, 0 for no event in the corresponding bit position.
     input wire [WORD_WIDTH-1:0] s_axis_tkeep,

     wb_interface.slave          wb_user_sample,

     output reg [5:0]            led
);

assign s_axis_tready = user_sample_inp_tready;

logic user_sample_inp_tready;
user_sample #(.WORD_WIDTH(WORD_WIDTH)) user_design
(
 .clk(clk),
 .rst(rst),

 .s_axis_tvalid(s_axis_tvalid),
 .s_axis_tready(user_sample_inp_tready),
 .s_axis_tkeep(s_axis_tkeep),
 .s_axis_channel(s_axis_channel),
 .s_axis_tagtime(s_axis_tagtime),
 .s_axis_rising_edge(s_axis_rising_edge),

 .wb(wb_user_sample),

 .led(led)
 );

endmodule
