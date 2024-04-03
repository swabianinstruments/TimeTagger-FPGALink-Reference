/**
 * XLGMII to AXI4-Stream Bridge.
 *
 * This file is part of Time Tagger software defined digital data acquisition.
 *
 * Copyright (C) 2022-2023 Swabian Instruments, All Rights Reserved
 * Authors:
 *     2022 Leon Schuermann <leon@swabianinstruments.com>
 *     2023 David Sawatzke  <david@swabianinstruments.com>
 *
 * Unauthorized copying of this file is strictly prohibited.
 */


// verilog_format: off
 `resetall
 `timescale 1ns / 1ps
 `default_nettype none
// verilog_format: on

module xlgmii_axis_bridge #(
    parameter DATA_WIDTH = 128,
    parameter CTRL_WIDTH = (DATA_WIDTH / 8)
) (
    // XLGMII RX
    input wire [DATA_WIDTH-1:0] xlgmii_rx_data,
    input wire [CTRL_WIDTH-1:0] xlgmii_rx_ctrl,

    // XLGMII TX
    output wire [DATA_WIDTH-1:0] xlgmii_tx_data,
    output wire [CTRL_WIDTH-1:0] xlgmii_tx_ctrl,

    axis_interface.master axis_rx,
    axis_interface.slave  axis_tx,

    // Error signals, asserted for one cycle respectively
    output wire rx_error_ready,
    output wire rx_error_preamble,
    output wire rx_error_xlgmii,
    output wire tx_error_tlast_tkeep
);

    initial begin
        if ((DATA_WIDTH != 128)) begin
            $error("Error: XLGMII data width must 128-bit");
            $finish;
        end

        if (CTRL_WIDTH * 8 != DATA_WIDTH) begin
            $error("Error: XLGMII control width must correspond to data width");
            $finish;
        end
    end

    // 128-bit RX bridge instantiation
    xlgmii_axis_bridge_rx_128b xlgmii_axis_bridge_rx (
        .axis(axis_rx),

        .xgmii_data(xlgmii_rx_data),
        .xgmii_ctrl(xlgmii_rx_ctrl),

        .error_ready(rx_error_ready),
        .error_preamble(rx_error_preamble),
        .error_xgmii(rx_error_xlgmii)
    );

    // 128-bit TX bridge instantiation
    xlgmii_axis_bridge_tx_128b xlgmii_axis_bridge_tx (
        .axis(axis_tx),

        .xgmii_data(xlgmii_tx_data),
        .xgmii_ctrl(xlgmii_tx_ctrl),

        .error_tlast_tkeep(tx_error_tlast_tkeep)
    );

endmodule

`resetall
