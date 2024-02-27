/*
 * Hist_1lane
 *
 * This file is part of the Time Tagger software defined digital data
 * acquisition FPGA-link reference design.
 *
 * Copyright (C) 2023 Swabian Instruments, All Rights Reserved
 *
 * Authors:
 * - 2023 Ehsan Jokar <ehsan@swabianinstruments.com>
 *
 * This file is provided under the terms and conditions of the BSD 3-Clause
 * license, accessible under https://opensource.org/licenses/BSD-3-Clause.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

 `resetall
 `timescale 1ns / 1ps
 `default_nettype none


module Hist_1lane#(
    parameter HIST_MEM_DEPTH = 4096,
    parameter HIST_WORD_SIZE = 32,
    parameter HIST_MEM_ADDR_WIDTH = $clog2(HIST_MEM_DEPTH)
)
(
    input wire clk,
    input wire [HIST_MEM_ADDR_WIDTH - 1 : 0] address_in,
    input wire valid_in,
    input wire hist_read,
    input wire hist_rst,
    output reg [HIST_WORD_SIZE - 1 : 0] data_out,
    output reg valid_out,
    output reg last_sample
    );


    // defining the memory ports
    logic [HIST_MEM_ADDR_WIDTH - 1 : 0] addra, addrb;
    logic [HIST_WORD_SIZE - 1 : 0] dina, doutb;
    logic ena, wea, enb;

    // xpm_memory_sdpram: Simple Dual Port RAM
    // Xilinx Parameterized Macro, version 2023.2

    xpm_memory_sdpram #(
        .ADDR_WIDTH_A(HIST_MEM_ADDR_WIDTH),
        .ADDR_WIDTH_B(HIST_MEM_ADDR_WIDTH),
        .BYTE_WRITE_WIDTH_A(HIST_WORD_SIZE),
        .CLOCKING_MODE("common_clock"),
        .MEMORY_OPTIMIZATION("true"),
        .MEMORY_SIZE(HIST_MEM_DEPTH*HIST_WORD_SIZE),
        .READ_DATA_WIDTH_B(HIST_WORD_SIZE),
        .READ_LATENCY_B (1),
        .WRITE_DATA_WIDTH_A (HIST_WORD_SIZE),
        .WRITE_PROTECT(1)
    )
    xpm_memory_sdpram_inst (
        .doutb(doutb), // READ_DATA_WIDTH_B-bit output: Data output for port B read operations.
        .addra(addra), // ADDR_WIDTH_A-bit input: Address for port A write operations.
        .addrb(addrb), // ADDR_WIDTH_B-bit input: Address for port B read operations.
        .clka(clk), // 1-bit input: Clock signal for port A. Also clocks port B when
                    // parameter CLOCKING_MODE is "common_clock".

        .dina(dina), // WRITE_DATA_WIDTH_A-bit input: Data input for port A write operations.
        .ena (ena),  // 1-bit input: Memory enable signal for port A. Must be high on clock
                     // cycles when write operations are initiated. Pipelined internally.

        .enb (enb), // 1-bit input: Memory enable signal for port B. Must be high on clock
                    // cycles when read operations are initiated. Pipelined internally.

        .regceb (1), // 1-bit input: Clock Enable for the last register stage on the output
                     // data path.
        .wea (wea)
     );

    // End of xpm_memory_sdpram_inst instantiation

    // registering the input address and the corresponding valid
    logic [HIST_MEM_ADDR_WIDTH - 1 : 0] r1address_in;
    logic r1valid_in;
    always_ff @(posedge clk) begin
        r1valid_in <= valid_in;
        r1address_in <= address_in;
    end

    // reading data from the memory
    // When valid_in is asserted, we read the data from the corresponding
    // address if we have not received the same address in the last
    // clock. It means that if we receive an address in which we've received
    // it in the last clock cycle, we haven't yet write back the corresponding
    // result into the memory. Therefore, we don't read again from the same
    // address. In other words, we don't read from the same address until
    // it's repeated in consecutive clock cycles.
    assign enb = (r1valid_in && (address_in == r1address_in)) ? 0 : valid_in;
    // assign addrb  = address_in;
    assign addrb = enb ? address_in : 'X;

    // writing back data into the memory
    // When we read a data from an address, the incremented data is expected to
    // be written back into the memory in the next two clock cycles. However,
    // a data is not written into an address if we receive the same address in
    // the next clock cycle. It means that we don't write a data
    // into an address while we receive the same address in consecutive clock cycles.
    // In addition, when the memory is read out, and the hist_rst is not asserted,
    // no data should be written into the memory.
    assign ena = ((valid_in && (r1address_in == address_in)) ||
                  (hist_read && !hist_rst))? 0 : r1valid_in;
    assign wea = ena;

    // writing data into the memory
    logic [HIST_WORD_SIZE - 1: 0] counter, counter_reg;
    logic r1enb;
    // registering the value of counter and enb
    always_ff @(posedge clk) begin
        counter_reg <= counter;
        r1enb <= enb;
    end
    // when r1enb is one, the new data has been read from the memory; so, the counter
    // should be initialized with this data added by one. Otherwise, the counter should
    // be incremented.
    assign counter = r1enb ? doutb + 1 : r1valid_in ? counter_reg + 1 : 'X;
    // the counter should be write into the BRAM
    assign dina = hist_rst ? 0 : ena ? counter : 'X;
    assign addra = ena ? r1address_in : 'X;

    // generarting the output
    always_ff @(posedge clk) begin
        valid_out <= hist_read ? r1enb   : 0;
        data_out <= (hist_read && r1enb)? doutb : 'X;
        last_sample <= 0;
        if(hist_read && r1enb && r1address_in == HIST_MEM_DEPTH - 1)
            last_sample <= 1;
    end

endmodule
