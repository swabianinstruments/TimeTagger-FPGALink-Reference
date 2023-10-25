/**
 * Statistics gathering module
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

// This module provides various statistics over wishbone over the received data. For this purpose, two axi streams inside the data_channel are sniffed.
//
// Register map
//
// | Address | Name                | Purpose                                                                               |
// |---------+---------------------+---------------------------------------------------------------------------------------|
// |       0 | Presence Indicator  | Reads one, for detecting presence of this module                                      |
// |       4 | statistics_control  | None                                                                                  |
// |      12 | packet_rate         | (Valid) Packets received over the last second. Updates every second.                  |
// |      16 | word_rate           | Words (128 bit) in valid Packets received over the last second. Updates every second. |
// |      20 | received_packets    | Number of (valid) packets received in total                                           |
// |      24 | received_words      | Number of words in valid packets received in total. Can wrap in a few minutes.        |
// |      28 | size_of_last_packet | Number of Words in the last valid packet                                              |
// |      32 | packet_loss         | If `1` indicates a lost packet                                                        |
// |      36 | invalid_packets     | Invalid Packets received in total. Also counts (for example) ARP and similar.         |
//
// Note: All statistics include the header with a size of 128 bit. A word might only be partially used, this reduces "real" data rate
module si_statistics_wb
  #(
    parameter ETH_CLK_FREQ = 156250000)
   (
    input wire         eth_clk,
    input wire         eth_rst,

   // AXI-Stream before the header parser
    input wire         pre_axis_tvalid,
    input wire         pre_axis_tready,
    input wire         pre_axis_tlast,

   // Signals from the header parser
    input wire         lost_packet,
    input wire         invalid_packet,

   // AXI-Stream after the header parser
    input wire         post_axis_tvalid,
    input wire         post_axis_tready,
    input wire         post_axis_tlast,

    // Wishbone interface for control & status
    input wire         wb_clk,
    input wire         wb_rst,
    input wire [7:0]   wb_adr_i,
    input wire [31:0]  wb_dat_i,
    input wire         wb_we_i,
    input wire         wb_stb_i,
    input wire         wb_cyc_i,
    output reg [31:0]  wb_dat_o = 0,
    output reg         wb_ack_o
    );

   // Timer to determine the length of a second
   reg [31:0]          second_timer;

   reg [31:0]          invalid_packet_counter;
   reg [31:0]          size_of_last_packet_counter;
   reg [31:0]          size_of_last_packet;
   reg [31:0]          word_rate_counter;
   reg [31:0]          word_rate_latched;
   reg [31:0]          packet_rate_counter;
   reg [31:0]          packet_rate_latched;
   reg [31:0]          received_words;
   reg [31:0]          received_packets;



   always @(posedge eth_clk) begin
      if (eth_rst) begin
         second_timer <= ETH_CLK_FREQ - 1;
      end else begin
         if (pre_axis_tvalid && pre_axis_tready && pre_axis_tlast && invalid_packet) begin
            invalid_packet_counter <= invalid_packet_counter + 1;
         end

         if (post_axis_tvalid && post_axis_tready) begin
            received_words <= received_words + 1;
            word_rate_counter <= word_rate_counter + 1;
            size_of_last_packet_counter <= size_of_last_packet_counter + 1;

            if (post_axis_tlast) begin
                received_packets <= received_packets + 1;
                packet_rate_counter <= packet_rate_counter + 1;
                size_of_last_packet <= size_of_last_packet_counter;
                size_of_last_packet_counter <= 1; // The last word doesn't get counted otherwise
            end
         end

         if (second_timer == 0) begin
            second_timer <= ETH_CLK_FREQ - 1;

            // Latch & reset the rate counters
            word_rate_latched <= word_rate_counter;
            word_rate_counter <= 0;

            packet_rate_latched <= packet_rate_counter;
            packet_rate_counter <= 0;
         end else begin
            second_timer <= second_timer - 1;
         end
      end
   end

   reg [31:0]          invalid_packet_counter_wb;
   reg [31:0]          size_of_last_packet_wb;
   reg [31:0]          word_rate_wb;
   reg [31:0]          packet_rate_wb;
   reg [31:0]          received_words_wb;
   reg [31:0]          received_packets_wb;
   reg                 packet_loss_wb;

   // This isn't a great module for this purpose, because inter-bit dependencies aren't maintained.
   // This doesn't serve any critical function, so that's acceptable
   xpm_cdc_array_single #(
                          .DEST_SYNC_FF(4),
                          .INIT_SYNC_FF(0),
                          .SIM_ASSERT_CHK(0),
                          // Do not register inputs (required for asynchronous signals)
                          .SRC_INPUT_REG(1),
                          .WIDTH($bits({invalid_packet_counter, size_of_last_packet, word_rate_latched, packet_rate_latched, received_words, received_packets, lost_packet})))
   sfpp_eth_10g_status_cdc (
                            .dest_out({invalid_packet_counter_wb, size_of_last_packet_wb, word_rate_wb, packet_rate_wb, received_words_wb, received_packets_wb, packet_loss_wb}),
                            .dest_clk(wb_clk),
                            .src_clk(eth_clk),
                            .src_in({invalid_packet_counter, size_of_last_packet, word_rate_latched, packet_rate_latched, received_words, received_packets, lost_packet}));

   reg [31:0]          statistics_control_wb; // TODO hook this up to reset the currently running statistics

   always @(posedge wb_clk) begin
      wb_ack_o <= 0;
      if (wb_rst) begin
         wb_dat_o <= 0;
         statistics_control_wb <= 0;
      end else if (wb_cyc_i && wb_stb_i) begin
         wb_ack_o <= 1;
         if (wb_we_i) begin
            // Write
            casez (wb_adr_i)
              8'b000001??: statistics_control_wb <= wb_dat_i;
            endcase
         end else begin
            // Read
            casez (wb_adr_i)
              // Indicate the Debug bus slave is present in the design
              8'b000000??: wb_dat_o <= 1;
              8'b000001??: wb_dat_o <= statistics_control_wb;
              //8'b000010??: wb_data_o <= ; // Unused
              8'b000011??: wb_dat_o <= packet_rate_wb;
              8'b000100??: wb_dat_o <= word_rate_wb;
              8'b000101??: wb_dat_o <= received_packets_wb;
              8'b000110??: wb_dat_o <= received_words_wb;
              8'b000111??: wb_dat_o <= size_of_last_packet_wb;
              8'b001000??: wb_dat_o <= packet_loss_wb;
              8'b001001??: wb_dat_o <= invalid_packet_counter_wb;
              default: wb_dat_o <= 32'h00000000;
            endcase
         end
      end else begin
         wb_dat_o <= 0;
      end
   end
endmodule

`resetall
