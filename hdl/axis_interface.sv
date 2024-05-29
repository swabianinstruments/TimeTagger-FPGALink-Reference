/**
 * AXI-Stream interface for time tag streaming
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

interface axis_interface #(
    parameter integer DATA_WIDTH = 64,
    parameter integer USER_WIDTH = 32,
    parameter integer KEEP_WIDTH = ((DATA_WIDTH + 7) / 8)
) (
    input wire clk,
    input wire rst
);
    logic                      tvalid;
    logic [  DATA_WIDTH - 1:0] tdata;
    logic [  KEEP_WIDTH - 1:0] tkeep;
    logic [USER_WIDTH - 1 : 0] tuser;
    logic                      tlast;
    logic                      tready;

    modport master(input clk, rst, tready, output tvalid, tdata, tkeep, tlast, tuser);
    modport slave(input clk, rst, tvalid, tdata, tkeep, tlast, tuser, output tready);
endinterface
