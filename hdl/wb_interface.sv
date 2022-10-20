/**
 * Wishbone Crossbar.
 * 
 * This file is part of the Time Tagger software defined digital data
 * acquisition FPGA-link reference design.
 *
 * Copyright (C) 2022 Swabian Instruments, All Rights Reserved
 *
 * Authors:
 * - 2022 Niklas Miller <niklas@swabianinstruments.com>
 * - 2022 Leon Schuermann <leon@swabianinstruments.com>
 *
 * This file is provided under the terms and conditions of the BSD 3-Clause
 * license, accessible under https://opensource.org/licenses/BSD-3-Clause.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

`resetall
`timescale 1ns / 1ps
`default_nettype none

//////////////////////////////////////////////////////////////////////////////////
// WishBone Interface
// Here all WishBone slaves get connected to the main bus.
// The master port is a system verilog modport.
//////////////////////////////////////////////////////////////////////////////////
interface wb_interface #(parameter SLAVES = 2);

    logic        clk;
    logic        rst;
    logic [31:0] wb_adr_o;
    logic [31:0] wb_dat_o;
    logic [31:0] wb_dat_i;
    logic        wb_we_o;
    logic        wb_stb_o;
    logic        wb_cyc_o;
    logic        wb_ack_i;

    logic [31:0] slave_adr_i;
    logic [31:0] slave_dat_i;
    logic [31:0] slave_dat_o [SLAVES];
    logic        slave_we_i [SLAVES];
    logic        slave_stb_i [SLAVES];
    logic        slave_cyc_i [SLAVES];
    logic        slave_ack_o [SLAVES];
    logic [23:0] slave_wb_adr [SLAVES];


    modport master_port(
        output clk,
        output rst,
        output wb_adr_o,
        output wb_dat_o,
        input  wb_dat_i,
        output wb_we_o,
        output wb_stb_o,
        output wb_cyc_o,
        input  wb_ack_i
    );

    genvar i;
    generate
        for (i=0;i<SLAVES;i=i+1) begin: slave
            assign wb_dat_i       = wb_adr_o[31:8] == slave_wb_adr[i] ? slave_dat_o[i] : 32'bz;
            assign wb_ack_i       = wb_adr_o[31:8] == slave_wb_adr[i] ? slave_ack_o[i] : 1'bz;
            assign slave_we_i[i]  = wb_adr_o[31:8] == slave_wb_adr[i] ? wb_we_o : 0;
            assign slave_stb_i[i] = wb_adr_o[31:8] == slave_wb_adr[i] ? wb_stb_o : 0;
            assign slave_cyc_i[i] = wb_adr_o[31:8] == slave_wb_adr[i] ? wb_cyc_o : 0;
        end
    endgenerate

    assign slave_adr_i = wb_adr_o;
    assign slave_dat_i = wb_dat_o;
endinterface

`resetall
