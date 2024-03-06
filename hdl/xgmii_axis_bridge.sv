/**
 * XGMII to AXI4-Stream Bridge.
 *
 * This file is part of the Time Tagger software defined digital data
 * acquisition FPGA-link reference design.
 *
 * Copyright (C) 2022 Swabian Instruments, All Rights Reserved
 *
 * Authors:
 * - 2022 Leon Schuermann <leon@swabianinstruments.com>
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

module xgmii_axis_bridge #(
    parameter DATA_WIDTH = 64,
    parameter CTRL_WIDTH = (DATA_WIDTH / 8)
) (
    input wire rx_clk,
    input wire rx_rst,
    input wire tx_clk,
    input wire tx_rst,

    // XGMII RX
    input wire [DATA_WIDTH-1:0] xgmii_rx_data,
    input wire [CTRL_WIDTH-1:0] xgmii_rx_ctrl,

    // XGMII TX
    output wire [DATA_WIDTH-1:0] xgmii_tx_data,
    output wire [CTRL_WIDTH-1:0] xgmii_tx_ctrl,

    // RX AXI4-STREAM
    input  wire                      axis_rx_tready,
    output wire                      axis_rx_tvalid,
    output wire [    DATA_WIDTH-1:0] axis_rx_tdata,
    output wire                      axis_rx_tlast,
    output wire [(DATA_WIDTH/8)-1:0] axis_rx_tkeep,

    // TX AXI4-STREAM
    output wire                      axis_tx_tready,
    input  wire                      axis_tx_tvalid,
    input  wire [    DATA_WIDTH-1:0] axis_tx_tdata,
    input  wire                      axis_tx_tlast,
    input  wire [(DATA_WIDTH/8)-1:0] axis_tx_tkeep,

    // Error signals, asserted for one cycle respectively
    output wire rx_error_ready,
    output wire rx_error_preamble,
    output wire rx_error_xgmii,
    output wire tx_error_tlast_tkeep
);

    initial begin
        if ((DATA_WIDTH != 64)) begin
            $error("Error: XGMII data width must be 64-bit");
            $finish;
        end

        if (CTRL_WIDTH * 8 != DATA_WIDTH) begin
            $error("Error: XGMII control width must correspond to data width");
            $finish;
        end
    end

    // 64-bit RX bridge instantiation
    xgmii_axis_bridge_rx_64b xgmii_axis_bridge_rx (
        .clk(rx_clk),
        .rst(rx_rst),

        .xgmii_data(xgmii_rx_data),
        .xgmii_ctrl(xgmii_rx_ctrl),

        .axis_tready(axis_rx_tready),
        .axis_tvalid(axis_rx_tvalid),
        .axis_tdata (axis_rx_tdata),
        .axis_tlast (axis_rx_tlast),
        .axis_tkeep (axis_rx_tkeep),

        .error_ready(rx_error_ready),
        .error_preamble(rx_error_preamble),
        .error_xgmii(rx_error_xgmii)
    );

    // 64-bit TX bridge instantiation
    xgmii_axis_bridge_tx_64b xgmii_axis_bridge_tx (
        .clk(tx_clk),
        .rst(tx_rst),

        .xgmii_data(xgmii_tx_data),
        .xgmii_ctrl(xgmii_tx_ctrl),

        .axis_tready(axis_tx_tready),
        .axis_tvalid(axis_tx_tvalid),
        .axis_tdata (axis_tx_tdata),
        .axis_tlast (axis_tx_tlast),
        .axis_tkeep (axis_tx_tkeep),

        .error_tlast_tkeep(tx_error_tlast_tkeep)
    );

endmodule
