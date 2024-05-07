/**
 * This file is part of the Time Tagger software defined digital data
 * acquisition FPGA-link reference design.
 *
 * Copyright (C) 2022-2024 Swabian Instruments, All Rights Reserved
 *
 * Authors:
 * - 2024 Loghman Rahimzadeh <loghman@swabianinstruments.com>
 *
 * This file is provided under the terms and conditions of the BSD 3-Clause
 * license, accessible under https://opensource.org/licenses/BSD-3-Clause.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

// verilog_format: off
 `resetall
 `timescale 1ps / 1ps
 `default_nettype none
// verilog_format: on

module tb_timeTagGenerator #(
    parameter integer NUM_OF_INPUT_CHANNELS = 64
) (
    input wire [NUM_OF_INPUT_CHANNELS-1:0] chx,

    // Main AXI stream of time tags
    axis_tag_interface.master m_time
);
    localparam integer DEPTH = 256;
    localparam integer WIDTH = m_time.CHANNEL_WIDTH + m_time.TIME_WIDTH;

    reg [WIDTH-1:0] fifo[DEPTH];  // write asynchronous ps, read synchronous ns

    logic [$clog2(DEPTH)-1:0] addr_wr = 0;
    logic [$clog2(DEPTH)-1:0] addr_rd = 0;
    logic [$clog2(DEPTH+1)-1:0] data_count = 0;
    initial begin
        fifo <= '{default: '0};
    end

    // 312.5 MHz, typical for the FPGA-link.
    logic clk = 0;
    always #1.6ns clk <= ~clk;
    assign m_time.clk = clk;

    // Reset for 10 ns
    logic rst = 1;
    initial #10ns rst <= 0;
    assign m_time.rst = rst;

    // This process wait until an edge change of the channels and then will detect the edge and save the results in the fifo
    generate
        for (genvar k = 0; k < NUM_OF_INPUT_CHANNELS; k++) begin : label_event_detection
            always @(chx[k]) begin
                if (data_count < DEPTH) begin
                    fifo[addr_wr][0+:m_time.TIME_WIDTH] = $time;
                    if (chx[k] == 1) begin  // rising edge
                        fifo[addr_wr][m_time.TIME_WIDTH+:m_time.CHANNEL_WIDTH] = k + 1;
                    end else if (chx[k] == 0) begin  // falling edge
                        fifo[addr_wr][m_time.TIME_WIDTH+:m_time.CHANNEL_WIDTH] = 2 ** m_time.CHANNEL_WIDTH - (k + 1);
                    end
                    addr_wr    = addr_wr + 1;
                    data_count = data_count + 1;
                end else begin
                    $error("FIFO overflow. Please reduce the data rate or increase the parameter DEPTH.");
                end
            end
        end
    endgenerate

    //This process will read out the stored events with system clock and it's output acts as input to the modules under test(sorted time tag, signed channel index)
    assign m_time.tvalid = |m_time.tkeep;
    reg [m_time.WORD_WIDTH-1:0] rand_read;

    always @(posedge m_time.clk) begin
        if (m_time.rst) begin
            m_time.tkeep   = 0;
            m_time.tagtime = '{default: 'X};
            m_time.channel = '{default: 'X};
            m_time.lowest_time_bound <= 0;
        end else if (m_time.tready || !m_time.tvalid) begin
            m_time.tkeep = 0;
            m_time.tagtime = '{default: 'X};
            m_time.channel = '{default: 'X};
            rand_read = $urandom_range(0, 2 ** m_time.WORD_WIDTH - 1);
            if (data_count >= $countones(rand_read)) begin
                for (integer m = 0; m < m_time.WORD_WIDTH; m++) begin
                    if (rand_read[m] && data_count > 0) begin  // falling edge
                        m_time.tagtime[m] = fifo[addr_rd][0+:m_time.TIME_WIDTH];
                        m_time.lowest_time_bound <= fifo[addr_rd][0+:m_time.TIME_WIDTH];
                        m_time.channel[m] = fifo[addr_rd][m_time.TIME_WIDTH+:m_time.CHANNEL_WIDTH];
                        m_time.tkeep[m]   = 1;
                        addr_rd           = addr_rd + 1;
                        data_count        = data_count - 1;
                    end
                end
            end
            if (data_count == 0) begin
                m_time.lowest_time_bound <= $time();
            end
        end
    end
endmodule
