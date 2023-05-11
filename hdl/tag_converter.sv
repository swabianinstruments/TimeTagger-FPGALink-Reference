`resetall
`timescale 1ns / 1ps
`default_nettype none

// This module parses tags in the internal TimeTagger format to make it easier to process them

// TODO Should be converted to axis interface
module si_tag_converter
  #(parameter CHANNEL_COUNT = 20) // This is the internal channel count and should be kept at 20 for the TTX
   (
    input wire         clk,
    input wire         rst,

    input wire [31:0]  tag,
    input wire [31:0]  wrap_count,

    output wire        valid_tag,
    // The time of the signal inside the clock cycle.
    // In 1/3 ps
    output wire [63:0] tagtime,
    // The channel this event occured on
    output reg [4:0]   channel,
    output reg         rising_edge // 1 on rising edge, 0 on falling edge
    );

   wire [1:0]          event_type;
   wire [5:0]          channel_number;
   wire [11:0]         subtime;
   wire [11:0]         counter;


   reg [63:0]          tagtime_p;
   reg [63:0]          tagtime_pp;
   reg [63:0]          tagtime_ppp;
   reg [63:0]          tagtime_pppp;
   reg [63:0]          tagtime_ppppp;
   reg [31:0]          tag_p;
   reg [31:0]          tag_pp;
   reg [31:0]          tag_ppp;
   reg [31:0]          tag_pppp;
   reg [31:0]          tag_ppppp;

   assign counter = tag[11:0];
   assign subtime = tag_pppp[23:12];
   always @(posedge clk) begin
      if (rst == 1) begin
         tagtime_p <= 0;
         tagtime_pp <= 0;
         tagtime_ppp <= 0;
         tagtime_pppp <= 0;
         tagtime_ppppp <= 0;
         tag_p <= 0;
         tag_pp <= 0;
         tag_ppp <= 0;
         tag_pppp <= 0;
         tag_ppppp <= 0;
      end else begin
         // Delay the signal 4 cycles so Vivado can infer DSPs if it chooses to
         tagtime_p <= {wrap_count, counter} * 4000;
         tagtime_pp <= tagtime_p;
         tagtime_ppp <= tagtime_pp;
         tagtime_pppp <= tagtime_ppp;
         tagtime_ppppp <= tagtime_pppp + subtime;
         tag_p <= tag;
         tag_pp <= tag_p;
         tag_ppp <= tag_pp;
         tag_pppp <= tag_ppp;
         tag_ppppp <= tag_pppp;
      end
   end

   assign event_type  = tag_ppppp[31:30];
   assign channel_number = tag_ppppp[29:24];
   assign valid_tag = (event_type == 2'b01) ? 1 : 0;
   assign tagtime = tagtime_ppppp;

   always @(*) begin
      if (channel_number < CHANNEL_COUNT) begin
         channel = channel_number;
         rising_edge = 1;
      end else begin
         channel = (channel_number - CHANNEL_COUNT);
         rising_edge = 0;
      end
   end

endmodule

`resetall
