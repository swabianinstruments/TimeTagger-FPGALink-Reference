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
`resetall
`timescale 1ns / 1ps
`default_nettype none

module user_sample_tb
  #(
    parameter channels = 3,    // Channels for which events will be generated
    parameter event_gap = 4000 // The time between each event in 1/3 ps
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

   reg         valid_tag;
   reg [63:0]  tagtime = 0;
   reg [4:0]   channel;
   reg         rising_edge;

   user_sample sample (
                       .clk(clk),
                       .rst(rst),

                       .valid_tag(valid_tag),
                       .tagtime(tagtime),
                       .channel(channel),
                       .rising_edge(rising_edge),

                       // Deliberately unused
                       .wb_clk(),
                       .wb_rst(),
                       .wb_adr_i(),
                       .wb_dat_i(),
                       .wb_we_i(),
                       .wb_stb_i(),
                       .wb_cyc_i(),
                       .wb_dat_o(),
                       .wb_ack_o(),
                       .led());

   always @(posedge clk) begin
      if ($urandom % 2) begin
         valid_tag <= 1;
         tagtime <= tagtime + event_gap;
         channel <= $urandom % channels;
         // This can generate e.g. multiple rising edges for the same channel without falling ones in between
         // The Time Tagger will behave in the same way if only the channel with rising edges is used
         rising_edge <= $urandom % 2;
      end else begin
         valid_tag <= 0;
      end
   end

endmodule
