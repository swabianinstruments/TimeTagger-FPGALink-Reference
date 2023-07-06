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
  #(
    parameter DATA_WIDTH = 32,
    parameter KEEP_WIDTH = (DATA_WIDTH + 7) / 8)
   (
    input wire                  clk,
    input wire                  rst,

    // AXI-Stream 4 slave
    input wire                  s_axis_tvalid, // tdata, tlast, tkeep and tuser are only valid if tvalid & tready are asserted in the same cycle
    output reg                  s_axis_tready, // Set this output if your module is able to accept new data. WARNING: If this is disabled for a long time, data may be lost
    input wire [DATA_WIDTH-1:0] s_axis_tdata, // This contains the tag data
    input wire                  s_axis_tlast, // last is asserted in the last tag in every packet. tuser may only change after last was asserted
    input wire [KEEP_WIDTH-1:0] s_axis_tkeep, // Should always be 0b1111
    input wire [31:0]           s_axis_tuser, // Contains the upper bits of `counter`, wraps approx. every 6 hours

    // Wishbone interface for control & status
    input wire                  wb_clk,
    input wire                  wb_rst,
    input wire [7:0]            wb_adr_i,
    input wire [31:0]           wb_dat_i,
    input wire                  wb_we_i,
    input wire                  wb_stb_i,
    input wire                  wb_cyc_i,
    output reg [31:0]           wb_dat_o = 0,
    output reg                  wb_ack_o,

    output reg [5:0]            led);
   initial begin
      // Some sanity checks:

      // - ensure that the data-width is 32 bits, this is the only width supported by this module
      if (DATA_WIDTH != 32) begin
         $error("Error: data-width needs to be 32 bits");
         $finish;
      end
   end
   assign s_axis_tready = 1;

   wire [4:0] channel;
   wire       rising_edge;
   reg [63:0] tagtime;
   wire       valid_tag;

   // This module adapts the internal TimeTagger format and should not be modified
   si_tag_converter converter
     (
      .clk(clk),
      .rst(rst),
      .tag((s_axis_tvalid && s_axis_tready) ? s_axis_tdata : 0),
      .wrap_count(s_axis_tuser),
      .tagtime(tagtime),
      .valid_tag(valid_tag),
      .channel(channel),
      .rising_edge(rising_edge)
      );


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
         lower_bound_wb <= 32'h00190000;
         upper_bound_wb <= 32'h00200000;
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
