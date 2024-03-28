/**
 * Wishbone Crossbar.
 *
 * This file is part of the Time Tagger software defined digital data
 * acquisition FPGA-link reference design.
 *
 * Copyright (C) 2022-2024 Swabian Instruments, All Rights Reserved
 *
 * Authors:
 * - 2024 Ehsan Jokar <ehsan@swabianinstruments.com>
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

interface wb_interface #(
    DATA_WIDTH = 32,
    ADDRESS_WIDTH = 32
);

    logic                         clk;
    logic                         rst;
    logic [ADDRESS_WIDTH - 1 : 0] adr;
    logic [   DATA_WIDTH - 1 : 0] dat_o;  // data from the instances
    logic [   DATA_WIDTH - 1 : 0] dat_i;  // data to the instances
    logic                         we;
    logic                         stb;
    logic                         cyc;
    logic                         ack;

    modport master(input dat_o, ack, output clk, rst, adr, dat_i, we, stb, cyc);

    modport slave(input clk, rst, adr, dat_i, we, stb, cyc, output dat_o, ack);

endinterface

module wb_interconnect #(
    parameter integer INSTANCES = 2,
    parameter integer BASE_ADDRESS[INSTANCES] = '{0, 1024},
    parameter integer MEMORY_SPACE[INSTANCES] = '{256, 256}
) (
    wb_interface.slave  s_wb,
    wb_interface.master m_wb[INSTANCES]
);

    initial begin
        for (integer j = 0; j < INSTANCES; j = j + 1) begin
            for (integer k = 0; k < INSTANCES; k = k + 1) begin
                if (j != k) begin
                    if (($unsigned(
                            BASE_ADDRESS[k]
                        ) < ($unsigned(
                            BASE_ADDRESS[j]
                        ) + $unsigned(
                            MEMORY_SPACE[j]
                        ))) & ($unsigned(
                            BASE_ADDRESS[k] >= $unsigned(BASE_ADDRESS[j])
                        ))) begin
                        $error("Error: Overlapping memory spaces for instances %0d and %0d", j, k);
                        $finish;
                    end
                end
            end
        end

        for (integer j = 0; j < INSTANCES; j = j + 1) begin
            if (BASE_ADDRESS[j] & (MEMORY_SPACE[j] - 1)) begin
                $error("Error: Base address is not aligned at instance %0d.", j);
                $finish;
            end
            if (MEMORY_SPACE[j] & (MEMORY_SPACE[j] - 1)) begin
                $error("Error: Memory space is not power of two at instance %0d.", j);
                $finish;
            end
        end
    end


    localparam ADDR_WIDTH = $bits(s_wb.adr);
    genvar j;
    generate
        for (j = 0; j < INSTANCES; j = j + 1) begin
            localparam MEM_WIDTH = $clog2(MEMORY_SPACE[j]);

            assign m_wb[j].clk = s_wb.clk;
            assign m_wb[j].rst = s_wb.rst;

            assign m_wb[j].dat_i = s_wb.dat_i;  // data to the instances
            assign m_wb[j].adr = {{(ADDR_WIDTH - MEM_WIDTH) {1'b0}}, s_wb.adr[MEM_WIDTH-1 : 0]};
            assign m_wb[j].we = s_wb.we;
            assign m_wb[j].stb   = (s_wb.adr[ADDR_WIDTH - 1 : MEM_WIDTH] == BASE_ADDRESS[j][ADDR_WIDTH - 1 : MEM_WIDTH])? s_wb.stb : 0;
            assign m_wb[j].cyc   = (s_wb.adr[ADDR_WIDTH - 1 : MEM_WIDTH] == BASE_ADDRESS[j][ADDR_WIDTH - 1 : MEM_WIDTH])? s_wb.cyc : 0;

            // data from the instances
            assign s_wb.dat_o    = (s_wb.adr[ADDR_WIDTH - 1 : MEM_WIDTH] == BASE_ADDRESS[j][ADDR_WIDTH - 1 : MEM_WIDTH])? m_wb[j].dat_o : 'Z;
            assign s_wb.ack      = (s_wb.adr[ADDR_WIDTH - 1 : MEM_WIDTH] == BASE_ADDRESS[j][ADDR_WIDTH - 1 : MEM_WIDTH])? m_wb[j].ack : 'Z;

        end
    endgenerate

endmodule
