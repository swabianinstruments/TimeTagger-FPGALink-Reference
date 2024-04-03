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

    // XGMII RX
    input wire [DATA_WIDTH-1:0] xgmii_rx_data,
    input wire [CTRL_WIDTH-1:0] xgmii_rx_ctrl,

    // XGMII TX
    output wire [DATA_WIDTH-1:0] xgmii_tx_data,
    output wire [CTRL_WIDTH-1:0] xgmii_tx_ctrl,

    axis_interface.master axis_rx,
    axis_interface.slave  axis_tx,

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
        .axis(axis_rx),

        .xgmii_data(xgmii_rx_data),
        .xgmii_ctrl(xgmii_rx_ctrl),

        .error_ready(rx_error_ready),
        .error_preamble(rx_error_preamble),
        .error_xgmii(rx_error_xgmii)
    );

    // 64-bit TX bridge instantiation
    xgmii_axis_bridge_tx_64b xgmii_axis_bridge_tx (
        .axis(axis_tx),

        .xgmii_data(xgmii_tx_data),
        .xgmii_ctrl(xgmii_tx_ctrl),

        .error_tlast_tkeep(tx_error_tlast_tkeep)
    );

endmodule
