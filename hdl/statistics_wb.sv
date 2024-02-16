/**
 * Statistics gathering module
 *
 * This file is part of the Time Tagger software defined digital data
 * acquisition FPGA-link reference design.
 *
 * Copyright (C) 2022-2024 Swabian Instruments, All Rights Reserved
 *
 * Authors:
 * - 2022-2024 David Sawatzke <david@swabianinstruments.com>
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

// This module provides various statistics over wishbone over the received data. For this purpose, two axi streams inside the data_channel are sniffed.
//
// Register map
//
// | Address | Name                | Purpose                                                                                       |
// |---------+---------------------+-----------------------------------------------------------------------------------------------|
// |       0 | Presence Indicator  | Reads one, for detecting presence of this module                                              |
// |       4 | statistics_control  | None                                                                                          |
// |       8 | statistics_reset    | Resets various parts. 0: Reset received_* statistics 1: Reset packet_loss. 2: Reset overflow. |
// |      12 | packet_rate         | (Valid) Packets received over the last second. Updates every second.                          |
// |      16 | word_rate           | Data Words (128 bit) in Packets received over the last second. Updates every second.          |
// |      20 | received_packets    | Number of (valid) packets received in total                                                   |
// |      24 | received_words      | Number of words in valid packets received in total. Can wrap in a few minutes.                |
// |      28 | size_of_last_packet | Number of Words in the last valid packet                                                      |
// |      32 | packet_loss         | If `1` indicates a lost packet                                                                |
// |      36 | invalid_packets     | Invalid Packets received in total. Also counts (for example) ARP and similar.                 |
// |      40 | tag_rate            | Tags received over the last second. Updates every second.                                     |
// |      44 | received_tags       | Number of tags received in total. Can wrap in a few seconds                                   |
// |      48 | overflowed          | If `1` indicates that an overflow has occured inside the TTX                                  |

// Note: All statistics exclude the header with a size of 128 bit.
module si_statistics_wb
  #(
    parameter DATA_WIDTH = 128,
    parameter KEEP_WIDTH = (DATA_WIDTH + 7) / 8,
    parameter CLK_FREQ   = 333333333)
   (
    input wire                  clk,
    input wire                  rst,

   // AXI-Stream before the header parser
    input wire                  pre_axis_tvalid,
    input wire                  pre_axis_tready,
    input wire                  pre_axis_tlast,

   // Signals from the header parser
    input wire                  lost_packet,
    input wire                  invalid_packet,

   // AXI-Stream after the header detacher
    input wire                  post_axis_tvalid,
    input wire [DATA_WIDTH-1:0] post_axis_tdata,
    input wire [KEEP_WIDTH-1:0] post_axis_tkeep,
    input wire                  post_axis_tready,
    input wire                  post_axis_tlast,

    // Wishbone interface for control & status
    wb_interface.slave          wb
    );

   // Timer to determine the length of a second
   reg [31:0]          second_timer;

   reg [31:0]          invalid_packet_counter;
   reg [31:0]          size_of_last_packet_counter;
   reg [31:0]          size_of_last_packet;
   reg [31:0]          tag_rate_counter;
   reg [31:0]          tag_rate_latched;
   reg [31:0]          word_rate_counter;
   reg [31:0]          word_rate_latched;
   reg [31:0]          packet_rate_counter;
   reg [31:0]          packet_rate_latched;
   reg [31:0]          received_words;
   reg [31:0]          received_packets;
   reg [31:0]          received_tags;
   reg                 overflow;

   reg                 reset_total_counters;


   always @(posedge clk) begin
      if (rst) begin
         second_timer <= CLK_FREQ - 1;
         second_timer <= 0;
         invalid_packet_counter <= 0;
         overflow <= 0;
         received_tags <= 0;
         received_words <= 0;
         received_packets <= 0;
         tag_rate_counter <= 0;
         word_rate_counter <= 0;
         packet_rate_counter <= 0;
         tag_rate_latched <= 0;
         word_rate_latched <= 0;
         packet_rate_latched <= 0;
         size_of_last_packet_counter <= 0;
      end else begin
         if (pre_axis_tvalid && pre_axis_tready && pre_axis_tlast && invalid_packet) begin
            invalid_packet_counter <= invalid_packet_counter + 1;
         end

         if (post_axis_tvalid && post_axis_tready) begin
            // Sniff for overflow!
            overflow <= 0;
            for (integer i = 0; i < (KEEP_WIDTH / 4); i += 1) begin
                if (post_axis_tkeep[3 + 4 * i] & ((post_axis_tdata[32 * i + 30 +:2] == 2'b10) || (post_axis_tdata[32 * i + 30 +: 2] == 2'b10))) begin
                     overflow <= 1;
                  end
            end

            received_tags <= received_tags + ($countones(post_axis_tkeep) >> 2);
            tag_rate_counter <= tag_rate_counter  + ($countones(post_axis_tkeep) >> 2);
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

         if (reset_total_counters) begin
              received_tags <= 0;
              received_words <= 0;
              received_packets <= 0;
         end

         if (second_timer == 0) begin
            second_timer <= CLK_FREQ - 1;

            // Latch & reset the rate counters
            tag_rate_latched <= tag_rate_counter;
            tag_rate_counter <= 0;

            word_rate_latched <= word_rate_counter;
            word_rate_counter <= 0;

            packet_rate_latched <= packet_rate_counter;
            packet_rate_counter <= 0;
         end else begin
            second_timer <= second_timer - 1;
         end
      end
   end

   reg                 packet_loss;
   reg                 overflowed;

   reg [31:0]          statistics_control;
   reg [31:0]          statistics_reset;

   assign reset_total_counters = statistics_reset[0];

   always @(posedge clk) begin
      wb.ack <= 0;
      statistics_reset <= 0;
      if (rst) begin
         wb.dat_o <= 0;
         statistics_control <= 0;
         statistics_reset <= 0;
         packet_loss <= 0;
         overflowed <= 0;
      end else if (wb.cyc && wb.stb) begin
         wb.ack <= 1;
         if (wb.we) begin
            // Write
            casez (wb.adr[7:0])
              8'b000001??: statistics_control <= wb.dat_i;
              8'b000010??: statistics_reset <= wb.dat_i;
            endcase
         end else begin
            // Read
            casez (wb.adr[7:0])
              // Indicate the Debug bus slave is present in the design
              8'b000000??: wb.dat_o <= 1;
              8'b000001??: wb.dat_o <= statistics_control;
              //8'b000010??: wb_data_o <= ; // Unused
              8'b000011??: wb.dat_o <= packet_rate_latched;
              8'b000100??: wb.dat_o <= word_rate_latched;
              8'b000101??: wb.dat_o <= received_packets;
              8'b000110??: wb.dat_o <= received_words;
              8'b000111??: wb.dat_o <= size_of_last_packet;
              8'b001000??: wb.dat_o <= packet_loss;
              8'b001001??: wb.dat_o <= invalid_packet_counter;
              8'b001010??: wb.dat_o <= tag_rate_latched;
              8'b001011??: wb.dat_o <= received_tags;
              8'b001100??: wb.dat_o <= overflowed;
              default: wb.dat_o <= 32'h00000000;
            endcase
         end
      end else begin
         wb.dat_o <= 0;
      end

      if (lost_packet) begin
          packet_loss <= 1;
      end else if (statistics_reset[1]) begin
          packet_loss <= 0;
      end
      if (overflow) begin
          overflowed <= 1;
      end else if (statistics_reset[2]) begin
          overflowed <= 0;
      end


   end
endmodule

`resetall
