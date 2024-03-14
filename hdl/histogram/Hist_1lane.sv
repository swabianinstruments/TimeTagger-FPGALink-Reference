/*
 * Hist_1lane
 *
 * This file is part of the Time Tagger software defined digital data
 * acquisition FPGA-link reference design.
 *
 * Copyright (C) 2023 Swabian Instruments, All Rights Reserved
 *
 * Authors:
 * - 2023-2024 Ehsan Jokar <ehsan@swabianinstruments.com>
 *
 * This file is provided under the terms and conditions of the BSD 3-Clause
 * license, accessible under https://opensource.org/licenses/BSD-3-Clause.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

// verilog_format: off
 `resetall
 `timescale 1ns / 1ps
 `default_nettype none
// verilog_format: on

//////////////////////////////////////////////////////////////////////////////////

/* This module efficiently implements the accumulation operation "if(enable) array[index]++", offering rapid
   random access index and a one-cycle initiation interval for optimal performance.

   To optimize performance, it employs a pipelined infrastructure for fetching, forwarding, accumulating, and
   writing back data. The pipeline comprises the following stages, each serving distinct purposes and synchronized
    with input registers:

 1. BRAM read operation stage: Handles the retrieval of data from BRAM. (Inputs: valid_in, rd_addr)
 2. BRAM output registers and register forwarding analysis stage: Manages the output registers of BRAM and
    performs register forwarding analysis. (Inputs: r1valid_in, r1rd_addr)
 3. Early-forwarding stage (4:1 MUX): Utilizes a 4:1 multiplexer for early data forwarding.
    (Inputs: r2valid_in, r2rd_addr, BRAM_dout, forward_with_***_cycle_delay)
 4. Late-forwarding stage (2:1 MUX), shifter, and accumulator: Incorporates a 2:1 multiplexer, shifter,
    and accumulator for late data forwarding and accumulation. (Inputs: r3valid_in, r3rd_addr, DO_forward)
 5. Writeback stage: Manages the writing back of accumulated data. (Inputs: wt_en, wt_addr, BRAM_din)
 */

//////////////////////////////////////////////////////////////////////////////////

module Hist_1lane #(
    parameter HIST_MEM_DEPTH = 4096,
    parameter HIST_WORD_SIZE = 32,
    parameter HIST_MEM_ADDR_WIDTH = $clog2(HIST_MEM_DEPTH)
) (
    input wire clk,
    input wire [HIST_MEM_ADDR_WIDTH - 1 : 0] address_in,
    input wire valid_in,
    input wire hist_read,
    input wire hist_rst,
    output reg [HIST_WORD_SIZE - 1 : 0] data_out,
    output reg valid_out,
    output reg last_sample
);

    logic [HIST_MEM_ADDR_WIDTH-1:0] rd_addr;
    logic [     HIST_WORD_SIZE-1:0] DO_register;
    logic [     HIST_WORD_SIZE-1:0] BRAM_dout;
    logic [HIST_MEM_ADDR_WIDTH-1:0] wt_addr;
    logic [     HIST_WORD_SIZE-1:0] BRAM_din;
    logic                           wt_en;

    (* ram_style="block" *)reg   [ HIST_WORD_SIZE - 1 : 0] BRAM        [HIST_MEM_DEPTH] = '{default: '0};
    always @(posedge clk) begin
        if (wt_en) BRAM[wt_addr] <= BRAM_din;

        DO_register <= BRAM[rd_addr];
        BRAM_dout   <= DO_register;  // BRAM output register for better timing
    end

    logic [HIST_WORD_SIZE-1:0] r1BRAM_din, r2BRAM_din;
    logic r1valid_in, r2valid_in, r3valid_in;
    logic [HIST_MEM_ADDR_WIDTH-1:0] r1rd_addr, r2rd_addr, r3rd_addr;

    assign rd_addr = address_in;
    always @(posedge clk) begin
        r1BRAM_din <= BRAM_din;
        r2BRAM_din <= r1BRAM_din;

        r1valid_in <= valid_in;
        r2valid_in <= r1valid_in;
        r3valid_in <= r2valid_in;

        r1rd_addr <= rd_addr;
        r2rd_addr <= r1rd_addr;
        r3rd_addr <= r2rd_addr;

        wt_addr <= r3rd_addr;
        wt_en <= r3valid_in;
    end

    logic [HIST_WORD_SIZE-1:0] DO_forward;
    logic forward_with_one_cycle_delay;
    logic forward_with_two_cycle_delay;
    logic forward_with_three_cycle_delay;
    logic forward_with_four_cycle_delay_pre;
    logic forward_with_four_cycle_delay;
    logic [1:0] forward_mux_index;

    always @(posedge clk) begin
        /*If the location to be read was written within the last four clock cycles, refrain from reading from
            RAM and instead utilize the forwarded value. The following conditions always  wt_en && (wt_addr == rd_addr),
            with varying latencies as indicated by the forward_with variables' names.
           */
        forward_with_one_cycle_delay <= r2valid_in && (r2rd_addr == r1rd_addr);
        forward_with_two_cycle_delay <= r3valid_in && (r3rd_addr == r1rd_addr);
        forward_with_three_cycle_delay <= wt_en && (wt_addr == r1rd_addr);
        forward_with_four_cycle_delay_pre <= wt_en && (wt_addr == rd_addr);
        forward_with_four_cycle_delay <= forward_with_four_cycle_delay_pre;

        /* For forwards with more than one cycle delay, we can select the corresponding value one cycle earlier, thereby
            enhancing timing. Additionally, provide Vivado with the hint to implement this as a simple 4:1 MUX. This not only
            reduces resource utilization but also enhances timing after the BRAM data output ports.
            */
        forward_mux_index = forward_with_one_cycle_delay       ? 2'hX :
                                forward_with_two_cycle_delay   ? 2'h0 :
                                forward_with_three_cycle_delay ? 2'h1 :
                                forward_with_four_cycle_delay  ? 2'h2 :
                                                                 2'h3;

        DO_forward <= forward_mux_index == 2'h0 ?     BRAM_din   :
                          forward_mux_index == 2'h1 ? r1BRAM_din :
                          forward_mux_index == 2'h2 ? r2BRAM_din :
                          forward_mux_index == 2'h3 ? BRAM_dout  :
                          {HIST_WORD_SIZE{1'bX}};
    end

    logic [HIST_WORD_SIZE-1:0] var_DO_with_forwards;
    logic forward_with_one_cycle_delay_p;

    /* Late forwarding: The read address might remain constant for two clock cycles. Therefore, the selection between
    the value of the last clock cycle or the value of the forward engine must be implemented in the same stage as
    the accumulator to achieve the required one-cycle latency.
    */
    assign var_DO_with_forwards = forward_with_one_cycle_delay_p ? BRAM_din : DO_forward;

    logic r1hist_rst, r2hist_rst, r3hist_rst;
    always @(posedge clk) begin
        forward_with_one_cycle_delay_p <= forward_with_one_cycle_delay;

        r1hist_rst <= hist_rst;
        r2hist_rst <= r1hist_rst;
        r3hist_rst <= r2hist_rst;

        BRAM_din <= r3hist_rst ? 0 : var_DO_with_forwards + 1;

        valid_out <= hist_read ? r2valid_in : 0;
        data_out <= hist_read ? BRAM_dout : 'X;

        // This signal indicates the completion of reading out and resetting the block RAM
        last_sample <= hist_read && wt_en && wt_addr == HIST_MEM_DEPTH - 1;
    end
endmodule
