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
 *
 * This file is provided under the terms and conditions of the BSD 3-Clause
 * license, accessible under https://opensource.org/licenses/BSD-3-Clause.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

`resetall
`timescale 1ns / 1ps
`default_nettype none

// This module receives the tag stream and sets the LEDs on the XEM8320 based on the state of the first 5 channels on the TTX as an example
// LED 6 on the XEM8320 will be active if an event for the first five channels was received in the last 200ms

module user_sample_wide #(parameter WORD_WIDTH = 4)
        (
         input wire                  clk,
         input wire                  rst,

         // 1 if the word is valid and tkeep needs to be checked, 0 if the full word is invalid
         input wire                  s_axis_tvalid,
         // 1 if this module is able to accept new data in this clock period. Must always be 1
         output wire                 s_axis_tready,
         // The time the tag was captured at
         // In 1/3 ps since the startup of the TTX
         input wire [64-1:0]         s_axis_tagtime [WORD_WIDTH-1:0],
         // The channel this event occured on
         // Starts at 0 while the actual channel numbering starts with 1! (if 'channel' is 2, it's actually the channel number 3)
         input wire [4:0]            s_axis_channel [WORD_WIDTH-1:0],
         // 1 on rising edge, 0 on falling edge
         input wire                  s_axis_rising_edge [WORD_WIDTH-1:0],
         // 1 for a valid event, 0 for no event
         input wire [WORD_WIDTH-1:0] s_axis_tkeep,

         input wire                  wb_clk,
         input wire                  wb_rst,
         input wire [7:0]            wb_adr_i,
         input wire [31:0]           wb_dat_i,
         input wire                  wb_we_i,
         input wire                  wb_stb_i,
         input wire                  wb_cyc_i,
         output reg [31:0]           wb_dat_o = 0,
         output reg                  wb_ack_o,

         output reg [5:0]            led
         );
       assign s_axis_tready = 1;
       int                           i;
       logic [31 : 0] cnt;
        always @(posedge clk) begin
             for(i = 0; i < 4; i += 1) begin
                  if (s_axis_tvalid & s_axis_tkeep[i]) begin
                       if (s_axis_channel[i] < 5) begin
                            led[s_axis_channel[i]] <= s_axis_rising_edge[i];
                            cnt <= 31250000*2; // ~200ms
                       end
                  end
             end
            // keep the activity LED on for around 200ms
            if (cnt > 0) begin
                cnt <= cnt - 1;
                led[5] <= 1;
            end else begin
                led[5] <= 0;
            end
        end
endmodule
