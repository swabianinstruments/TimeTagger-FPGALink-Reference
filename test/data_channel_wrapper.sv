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

// verilog_format: off
 `resetall
 `timescale 1ns / 1ps
 `default_nettype none
// verilog_format: on

module data_channel_wrapper #(
    parameter DATA_WIDTH_IN  = 128,
    parameter KEEP_WIDTH_IN  = (DATA_WIDTH_IN + 7) / 8,
    parameter DATA_WIDTH_OUT = 32,
    parameter KEEP_WIDTH_OUT = (DATA_WIDTH_OUT + 7) / 8
) (
    input wire clk,
    input wire rst,

    // Ethernet data *after* the MAC, without CRC or preamble, clk
    input  wire                     s_axis_tvalid,
    output wire                     s_axis_tready,
    input  wire [DATA_WIDTH_IN-1:0] s_axis_tdata,
    input  wire                     s_axis_tlast,
    input  wire [KEEP_WIDTH_IN-1:0] s_axis_tkeep,

    // Tag data clk
    output wire                      m_axis_tvalid,
    input  wire                      m_axis_tready,
    output wire [DATA_WIDTH_OUT-1:0] m_axis_tdata,
    output wire                      m_axis_tlast,
    output wire [KEEP_WIDTH_OUT-1:0] m_axis_tkeep,
    output wire [            32-1:0] m_axis_tuser    // Rollover time

);

    axis_interface #(
        .DATA_WIDTH(DATA_WIDTH_IN)
    ) data_stream (
        .clk(clk),
        .rst(rst)
    );

    axis_interface #(
        .DATA_WIDTH(DATA_WIDTH_OUT)
    ) tag_stream (
        .clk(clk),
        .rst(rst)
    );

    assign data_stream.tvalid = s_axis_tvalid;
    assign s_axis_tready = data_stream.tready;
    assign data_stream.tdata = s_axis_tdata;
    assign data_stream.tlast = s_axis_tlast;
    assign data_stream.tkeep = s_axis_tkeep;

    assign m_axis_tvalid = tag_stream.tvalid;
    assign tag_stream.tready = m_axis_tready;
    assign m_axis_tdata = tag_stream.tdata;
    assign m_axis_tlast = tag_stream.tlast;
    assign m_axis_tkeep = tag_stream.tkeep;
    assign m_axis_tuser = tag_stream.tuser;

    wb_interface wb ();

    si_data_channel #(
        .STATISTICS(0)
    ) data_channel (
        .s_axis(data_stream),
        .m_axis(tag_stream),

        .wb_statistics(wb)
    );


endmodule
