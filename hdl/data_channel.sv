/**
 * Ethernet data processing channel
 *
 * This file is part of the Time Tagger software defined digital data
 * acquisition FPGA-link reference design.
 *
 * Copyright (C) 2022 Swabian Instruments, All Rights Reserved
 *
 * Authors:
 * - 2022-2024 David Sawatzke <david@swabianinstruments.com>
 * - 2023-2024 Ehsan Jokar <ehsan@swabianinstruments.com>
 *
 * This file is provided under the terms and conditions of the BSD 3-Clause
 * license, accessible under https://opensource.org/licenses/BSD-3-Clause.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */
`resetall
`timescale 1ns / 1ps
`default_nettype none
module si_data_channel
  #(
    parameter DATA_WIDTH_IN = 128,
    parameter KEEP_WIDTH_IN = (DATA_WIDTH_IN + 7) / 8,
    parameter DATA_WIDTH_OUT = 32,
    parameter KEEP_WIDTH_OUT = (DATA_WIDTH_OUT + 7) / 8,
    parameter STATISTICS = 0
    ) (
       input wire                       clk,
       input wire                       rst,

       // Ethernet data *after* the MAC, without CRC or preamble, clk
       input wire                       s_axis_tvalid,
       output wire                      s_axis_tready,
       input wire [DATA_WIDTH_IN-1:0]   s_axis_tdata,
       input wire                       s_axis_tlast,
       input wire [KEEP_WIDTH_IN-1:0]   s_axis_tkeep,

       // Tag data clk
       output wire                      m_axis_tvalid,
       input wire                       m_axis_tready,
       output wire [DATA_WIDTH_OUT-1:0] m_axis_tdata,
       output wire                      m_axis_tlast,
       output wire [KEEP_WIDTH_OUT-1:0] m_axis_tkeep,
       output wire [32-1:0]             m_axis_tuser, // Rollover time

        // Wishbone interface for statistics. Has adresses for 0-39
       input wire [7:0]                 wb_adr_i,
       input wire [31:0]                wb_dat_i,
       input wire                       wb_we_i,
       input wire                       wb_stb_i,
       input wire                       wb_cyc_i,
       output reg [31:0]                wb_dat_o,
       output reg                       wb_ack_o
       );
   initial begin

      // Some sanity checks:

      // - ensure that the input data-width is 128 bits, this is the only width supported by this module
      if (DATA_WIDTH_IN != 128) begin
         $error("Error: DATA_WIDTH_IN needs to be 128 bits");
         $finish;
      end
      // - ensure that the output data-width is a multiple of 32 bits, to not split tags
      if ((DATA_WIDTH_OUT % 32) != 0) begin
         $error("Error: DATA_WIDTH_OUT needs to be a multpile of 32 bits");
         $finish;
      end
   end

   wire [DATA_WIDTH_IN-1:0]  filtered_axis_tdata;
   wire [KEEP_WIDTH_IN-1:0]  filtered_axis_tkeep;
   wire                      filtered_axis_tvalid;
   wire                      filtered_axis_tready;
   wire                      filtered_axis_tlast;

   wire                      lost_packet;
   wire                      invalid_packet;

   // This component filters out invalid frames (or non-recognized ones, like ARP)
   si_header_parser #(.DATA_WIDTH(DATA_WIDTH_IN)) header_parser
     (
      .clk(clk),
      .rst(rst),

      .s_axis_tvalid(s_axis_tvalid),
      .s_axis_tready(s_axis_tready),
      .s_axis_tdata(s_axis_tdata),
      .s_axis_tlast(s_axis_tlast),
      .s_axis_tkeep(s_axis_tkeep),

      .m_axis_tvalid(filtered_axis_tvalid),
      .m_axis_tready(filtered_axis_tready),
      .m_axis_tdata(filtered_axis_tdata),
      .m_axis_tlast(filtered_axis_tlast),
      .m_axis_tkeep(filtered_axis_tkeep),

      .lost_packet(lost_packet),
      .invalid_packet(invalid_packet));

   wire [DATA_WIDTH_IN-1:0]  unpacked_axis_tdata;
   wire [KEEP_WIDTH_IN-1:0]  unpacked_axis_tkeep;
   wire                      unpacked_axis_tvalid;
   wire                      unpacked_axis_tready;
   wire                      unpacked_axis_tlast;
   wire [32-1:0]             unpacked_axis_tuser;


   si_header_detacher #(.DATA_WIDTH(DATA_WIDTH_IN)) header_detacher
     (
      .clk(clk),
      .rst(rst),

      .s_axis_tvalid(filtered_axis_tvalid),
      .s_axis_tready(filtered_axis_tready),
      .s_axis_tdata(filtered_axis_tdata),
      .s_axis_tlast(filtered_axis_tlast),
      .s_axis_tkeep(filtered_axis_tkeep),

      .m_axis_tvalid(unpacked_axis_tvalid),
      .m_axis_tready(unpacked_axis_tready),
      .m_axis_tdata(unpacked_axis_tdata),
      .m_axis_tlast(unpacked_axis_tlast),
      .m_axis_tkeep(unpacked_axis_tkeep),
      .m_axis_tuser(unpacked_axis_tuser)
      );


   axis_adapter
     #(.S_DATA_WIDTH(DATA_WIDTH_IN), .M_DATA_WIDTH(DATA_WIDTH_OUT), .USER_WIDTH(32))
   width_adpter
     (
      .clk(clk),
      .rst(rst),

      .s_axis_tvalid(unpacked_axis_tvalid),
      .s_axis_tready(unpacked_axis_tready),
      .s_axis_tdata(unpacked_axis_tdata),
      .s_axis_tlast(unpacked_axis_tlast),
      .s_axis_tkeep(unpacked_axis_tkeep),
      .s_axis_tuser(unpacked_axis_tuser),

      .m_axis_tvalid(m_axis_tvalid),
      .m_axis_tready(m_axis_tready),
      .m_axis_tdata(m_axis_tdata),
      .m_axis_tlast(m_axis_tlast),
      .m_axis_tkeep(m_axis_tkeep),
      .m_axis_tuser(m_axis_tuser)
      );


   generate if (STATISTICS == 1) begin
      si_statistics_wb
        #(.DATA_WIDTH(DATA_WIDTH_IN))
      statistics
        (
         .clk(clk),
         .rst(rst),
         .pre_axis_tvalid(s_axis_tvalid),
         .pre_axis_tready(s_axis_tready),
         .pre_axis_tlast(s_axis_tlast),
         .post_axis_tvalid(unpacked_axis_tvalid),
         .post_axis_tdata(unpacked_axis_tdata),
         .post_axis_tkeep(unpacked_axis_tkeep),
         .post_axis_tready(unpacked_axis_tready),
         .post_axis_tlast(unpacked_axis_tlast),

         .lost_packet(lost_packet),
         .invalid_packet(invalid_packet),

         .wb_adr_i(wb_adr_i),
         .wb_dat_i(wb_dat_i),
         .wb_we_i(wb_we_i),
         .wb_stb_i(wb_stb_i),
         .wb_cyc_i(wb_cyc_i),
         .wb_dat_o(wb_dat_o),
         .wb_ack_o(wb_ack_o)
         );

   end
   endgenerate

endmodule // si_data_channel

`resetall
