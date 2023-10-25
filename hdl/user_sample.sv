/**
 * User Sample Design Shell.
 * 
 * This file is part of the Time Tagger software defined digital data
 * acquisition FPGA-link reference design.
 *
 * Copyright (C) 2022 Swabian Instruments, All Rights Reserved
 *
 * Authors:
 * - 2022 David Sawatzke <david@swabianinstruments.com>
 *
 * This file is provided under the terms and conditions of the BSD 3-Clause
 * license, accessible under https://opensource.org/licenses/BSD-3-Clause.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

`resetall
`timescale 1ns / 1ps
`default_nettype none

// This module receives the tag stream and sets the first 2 leds based on the first 2 channels
// The data will arrive sorted from the timetagger, so the time & subtimes can be ignored for this purpose
//
// LED function:
// 0-1: State of the first 2 channels
// 2-4: Upper bits of the tag counter
// 5:   Interval exceeded counter
//
// It also provides a way to detect invalid tags by determining the time
// between two subsequent tags on a certain channel and checking if the time is
// inside a user-provided interval.
//
// Register map:
//
// | Address | Name                | Purpose                                                                               |
// |---------+---------------------+---------------------------------------------------------------------------------------|
// |       0 | Presence Indicator  | Reads one, for detecting presence of this module                                      |
// |       4 | user_control        | If a non-zero is written, the status is held in reset                                 |
// |       8 | channel_select      | Determines which channel to monitor                                                   |
// |      12 | lower_bound         | The lower bound of the expected interval                                              |
// |      16 | upper_bound         | The upper bound of the expected interval                                              |
// |      20 | failed_time         | The failing time. The upper bit is set if the value is valid                          |
//
// Note: You can replicate much of this functionality with the Vivado ILA and adding multiple ANDed triggers with comparators
module user_sample
   (
    input wire        clk,
    input wire        rst,

    // Tag Input
    // High if the current tag is valid and should actually be sampled
    input wire        valid_tag,
    // The time the tag was captured at
    // In 1/3 ps since the startup of the TTX
    input wire [63:0] tagtime,
    // The channel this event occured on
    // Starts at 0 while the actual channel numbering starts with 1! (if 'channel' is 2, it's actually the channel number 3)
    input wire [4:0]  channel,
    // 1 on rising edge, 0 on falling edge
    input wire        rising_edge,

    // Wishbone interface for control & status
    input wire        wb_clk,
    input wire        wb_rst,
    input wire [7:0]  wb_adr_i,
    input wire [31:0] wb_dat_i,
    input wire        wb_we_i,
    input wire        wb_stb_i,
    input wire        wb_cyc_i,
    output reg [31:0] wb_dat_o = 0,
    output reg        wb_ack_o,

    output reg [5:0]  led);

   reg [15:0] tag_counter;

   assign led[4:2] = tag_counter[15:13];

   always @(posedge clk) begin
      if (rst) begin
         led[0] <= 1'b0;
         tag_counter <= 0;
      end else begin
         if (valid_tag) begin
            case (channel)
              6'h00: begin led[0] <= rising_edge;
              end
              6'h01: begin led[1] <= rising_edge;
              end
              default: ;
            endcase
         end
         if (valid_tag) begin
            tag_counter <= tag_counter + 1;
         end
      end
   end

   reg [31:0] user_control_wb;
   reg [31:0] channel_select_wb;
   reg [31:0] lower_bound_wb;
   reg [31:0] upper_bound_wb;
   wire [31:0] failed_wb;
   wire [31:0] user_control;
   wire [31:0] channel_select;
   wire [31:0] lower_bound;
   wire [31:0] upper_bound;
   reg [31:0]  failed;

   xpm_cdc_array_single #(
                          .DEST_SYNC_FF(4),
                          .INIT_SYNC_FF(0),
                          .SIM_ASSERT_CHK(0),
                          // Do not register inputs (required for asynchronous signals)
                          .SRC_INPUT_REG(1),
                          .WIDTH($bits({user_control_wb, channel_select_wb, lower_bound_wb, upper_bound_wb})))
   user_wb_in (
               .dest_out({user_control, channel_select, lower_bound, upper_bound}),
               .dest_clk(clk),
               .src_clk(wb_clk),
               .src_in({user_control_wb, channel_select_wb, lower_bound_wb, upper_bound_wb}));
   xpm_cdc_array_single #(
                          .DEST_SYNC_FF(4),
                          .INIT_SYNC_FF(0),
                          .SIM_ASSERT_CHK(0),
                          // Do not register inputs (required for asynchronous signals)
                          .SRC_INPUT_REG(1),
                          .WIDTH($bits({failed})))
   user_wb_out (
                .dest_out({failed_wb}),
                .dest_clk(wb_clk),
                .src_clk(clk),
                .src_in({failed}));

   reg         valid_tag_p;
   reg [4:0]   channel_p;
   reg [63:0]  prev_tagtime;
   reg [63:0]  tagtime_diff;
   reg         init;

   always @(posedge clk) begin
      if (rst || (user_control != 0)) begin
         led[5] <= 1'b0;
         failed <= 0;
         valid_tag_p <= 0;
         channel_p <= 0;
         init <= 0;
         prev_tagtime <= 0;
         tagtime_diff <= 0;

      end else begin
         valid_tag_p <= valid_tag;
         channel_p <= channel;

         if (valid_tag && (channel_select == channel)) begin
            prev_tagtime <= tagtime;
            tagtime_diff <= tagtime - prev_tagtime;
            if ((prev_tagtime != 0)) begin
               // Avoid sampling a non-valid timeframe
               init <= 1;
            end
         end
         if (init && valid_tag_p && (channel_select == channel_p)) begin
            if ((tagtime_diff < lower_bound) || (tagtime_diff > upper_bound)) begin
               failed[30:0] <= tagtime_diff[30:0];
               failed[31] <= 1;
               led[5] <= 1'b1;
            end
         end
      end
   end

   always @(posedge wb_clk) begin
      wb_ack_o <= 0;
      if (wb_rst) begin
         wb_dat_o <= 0;
         channel_select_wb <= 0;
         lower_bound_wb <= 32'h00330000;
         upper_bound_wb <= 32'h00340000;
      end else if (wb_cyc_i && wb_stb_i) begin
         wb_ack_o <= 1;
         if (wb_we_i) begin
            // Write
            casez (wb_adr_i)
              8'b000001??: user_control_wb <= wb_dat_i;
              8'b000010??: channel_select_wb <= wb_dat_i;
              8'b000011??: lower_bound_wb <= wb_dat_i;
              8'b000100??: upper_bound_wb <= wb_dat_i;
            endcase
         end else begin
            // Read
            casez (wb_adr_i)
              // Indicate the bus slave is present in the design
              8'b000000??: wb_dat_o <= 1;
              8'b000001??: wb_dat_o <= user_control_wb;
              8'b000010??: wb_dat_o <= channel_select_wb;
              8'b000011??: wb_dat_o <= lower_bound_wb;
              8'b000100??: wb_dat_o <= upper_bound_wb;
              8'b000101??: wb_dat_o <= failed_wb;
              default: wb_dat_o <= 32'h00000000;
            endcase
         end
      end else begin
         wb_dat_o <= 0;
      end
   end
endmodule // user_sample
`resetall
