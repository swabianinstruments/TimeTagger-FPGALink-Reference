`resetall
`timescale 1ns / 1ps
`default_nettype none

// This module removes the header from the timetag data stream
// Namely, throwing away the first 256 bit word
module si_header_detacher
  #(
    parameter DATA_WIDTH = 128,
    parameter KEEP_WIDTH = (DATA_WIDTH + 7) / 8
    ) (
       input wire                    clk,
       input wire                    rst,

       input wire                    s_axis_tvalid,
       output reg                    s_axis_tready,
       input wire [DATA_WIDTH-1:0]   s_axis_tdata,
       input wire                    s_axis_tlast,
       input wire [KEEP_WIDTH-1:0]   s_axis_tkeep,

       output reg                    m_axis_tvalid,
       input wire                    m_axis_tready,
       output reg [DATA_WIDTH-1:0]   m_axis_tdata,
       output reg                    m_axis_tlast,
       output reg [KEEP_WIDTH-1:0]   m_axis_tkeep,
       output reg [31:0]             m_axis_tuser
    );
   initial begin
      // Some sanity checks:

      // - ensure that the data-width is 256 bits, this is the only width supported by this module
      if (DATA_WIDTH != 128) begin
         $error("Error: data-width needs to be 128 bits");
         $finish;
      end
   end

   reg first_word;
   always @(posedge clk) begin
      if (rst == 1) begin
         first_word <= 1;
      end else if (s_axis_tvalid && s_axis_tready) begin
         if (s_axis_tlast) begin
            first_word <= 1;
         end else begin
            first_word <= 0;
         end
         if (first_word) begin
            m_axis_tuser <= s_axis_tdata[32 * 7 +: 32]; // Extract wrap count here
         end
      end
   end

   always @(*) begin
      if (first_word) begin
         s_axis_tready <= 1;
         m_axis_tvalid <= 0;
         m_axis_tdata <= 0;
         m_axis_tlast <= 0;
         m_axis_tkeep <= 0;
      end else begin
         s_axis_tready <= m_axis_tready;
         m_axis_tvalid <= s_axis_tvalid;
         m_axis_tdata <= s_axis_tdata;
         m_axis_tlast <= s_axis_tlast;
         m_axis_tkeep <= s_axis_tkeep;
      end
   end

endmodule

`resetall
