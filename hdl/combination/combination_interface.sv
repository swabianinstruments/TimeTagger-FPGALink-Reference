/**
 * AXI-Stream interface for time tag streaming
 *
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
 `timescale 1ns / 1ps
 `default_nettype none
// verilog_format: on

interface combination_interface #(
    parameter integer TIME_WIDTH = 64,
    parameter integer CHANNELS_IN_WIDTH = 6,
    parameter integer CHANNELS = 16,
    parameter integer ACC_WIDTH = 32
) ();
    logic [        TIME_WIDTH-1:0] window;
    logic [$clog2(CHANNELS+1)-1:0] filter_max;
    logic [$clog2(CHANNELS+1)-1:0] filter_min;
    logic                          ready_i;
    logic                          ready_o;
    logic                          capture_enable;
    logic                          start_reading;
    logic [                   1:0] select_comb_fifo;
    logic                          reset_comb;
    logic                          reset_comb_done;
    logic                          lut_ack;
    logic [                   1:0] lut_WrRd;  // 2'b10: writing, 2'b01: reading
    logic [ CHANNELS_IN_WIDTH-1:0] lut_addr;
    logic [$clog2(CHANNELS)+1-1:0] lut_dat_i;  // one bit for valid and others for channel number
    logic [$clog2(CHANNELS)+1-1:0] lut_dat_o;
    logic                          overflow;
    logic                          comb_out_vd;
    logic [          CHANNELS-1:0] comb_value;
    logic [         ACC_WIDTH-1:0] comb_count;

    modport master(
        input ready_o, reset_comb_done, overflow, comb_out_vd, comb_value, comb_count, lut_dat_o, lut_ack,
        output ready_i, window, filter_max, filter_min, capture_enable, start_reading, select_comb_fifo, reset_comb, lut_WrRd, lut_addr, lut_dat_i
    );
    modport slave(
        input  ready_i, window, filter_max, filter_min, capture_enable, start_reading, select_comb_fifo, reset_comb, lut_WrRd, lut_addr, lut_dat_i,
        output ready_o, overflow, comb_out_vd, comb_value, comb_count, reset_comb_done, lut_dat_o, lut_ack
    );

endinterface
