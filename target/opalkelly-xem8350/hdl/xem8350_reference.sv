/**
 * XEM8350 Time Tagger FPGALink Reference Design Top-Level Module.
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

`timescale 1ns / 1ps
`default_nettype none

module xem8350_reference (
    // OpalKelly USB Host Interface
    input wire [4:0]  okUH,
    output wire [2:0] okHU,
    inout wire [31:0] okUHU,
    inout wire        okAA,

    // QSFP+ Transceiver Common Reference Clock (Quad 225 Clock 0)
    input wire        qsfpp_mgtrefclk_p,
    input wire        qsfpp_mgtrefclk_n,

    // QSFP+ Port 2 Lane 2 Diffpairs
    output wire       qsfpp2_2_tx_p,
    output wire       qsfpp2_2_tx_n,
    input wire        qsfpp2_2_rx_p,
    input wire        qsfpp2_2_rx_n,

    inout wire        si5338b_i2c_scl,
    inout wire        si5338b_i2c_sda
);

    // ---------- OPALKELLY INTERFACE ----------
    // Target interface bus
    wire              okClk;
    wire [112:0]      okHE;
    wire [64:0]       okEH;

    // Instantiate the okHost and connect endpoints
    okHost okHI(
        .okUH(okUH),
        .okHU(okHU),
        .okUHU(okUHU),
        .okAA(okAA),
        .okClk(okClk),
        .okHE(okHE),
        .okEH(okEH));

    // OpalKelly WireOr to connect the various outputs
    wire [64:0]       okEH_wb_pipe_bridge;
    okWireOR #(
        .N(1))
    okWireOR_inst (
        .okEH(okEH),
        .okEHx({
            okEH_wb_pipe_bridge
        }));

    // Central synchronous okClk reset
    wire okRst;
    xpm_cdc_sync_rst #(
        .DEST_SYNC_FF(2),
        .INIT(1))
    xpm_cdc_sync_rst_inst (
        .dest_rst(okRst),
        .dest_clk(okClk),
        .src_rst(1'b0));

    // ---------- WISHBONE CROSSBAR & OK BRIDGE ----------
    // Wishbone crossbar to connect the various design components
    wb_interface #(.SLAVES(6)) wb();
    // Always ACK Machine (required for the wb_pipe_bridge)
    assign wb.slave_wb_adr[0]  = 24'b100000000000000000000000;
    // Si5338B onboard PLL I2C to Wishbone bridge (with blocking ACKs)
    assign wb.slave_wb_adr[1]  = 24'b100000000000000000000001;
    // QSFP+ I2C Management Interface, Port 2 (lane 2 used as 10Gb/s port)
    assign wb.slave_wb_adr[2]  = 24'b100000000000000000000010;
    // QSFP+ I2C Management Interface, Port 1
    assign wb.slave_wb_adr[3]  = 24'b100000000000000000000011;
    // SFP+ 10G Ethernet Core (on QSFP+ Port 2, Lane 2)
    assign wb.slave_wb_adr[4]  = 24'b100000000000000000010101;
    // QSFP+ 40G Ethernet (QSFP+ Port 1)
    assign wb.slave_wb_adr[5]  = 24'b100000000000000000010110;

    // Wishbone Always ACK Machine, required for OpalKelly Pipe-based Wishbone Bridge
    always @(posedge okClk) begin
        if (okRst) begin
            wb.slave_ack_o[0] <= 1'b0;
            wb.slave_dat_o[0] <= 32'b0;
        end else if (wb.slave_cyc_i[0] && wb.slave_stb_i[0]) begin
            wb.slave_ack_o[0] <= 1'b1;
        end else begin
            wb.slave_ack_o[0] <= 1'b0;
        end
    end

    wb_pipe_bridge #(
        .BLOCK_CNT(4),
        .BTPIPEIN_ADDR(8'h83),
        .BTPIPEOUT_ADDR(8'ha4))
    wb_pipe_bridge_inst (
       .okClk(okClk),
       .okRst(okRst),
       .okHE(okHE),
       .okEH(okEH_wb_pipe_bridge),
       .wb_master(wb.master_port));

    // ---------- Si5338B PLL I2C-WB CORE ----------
    wire si5338b_i2c_scl_in;
    wire si5338b_i2c_scl_out;
    wire si5338b_i2c_scl_out_en;
    wire si5338b_i2c_sda_in;
    wire si5338b_i2c_sda_out;
    wire si5338b_i2c_sda_out_en;

    IOBUF si5338b_i2c_scl_iobuf (
        .O(si5338b_i2c_scl_in),
        .IO(si5338b_i2c_scl),
        .I(si5338b_i2c_scl_out),
        .T(si5338b_i2c_scl_out_en));

    IOBUF si5338b_i2c_sda_iobuf (
        .O(si5338b_i2c_sda_in),
        .IO(si5338b_i2c_sda),
        .I(si5338b_i2c_sda_out),
        .T(si5338b_i2c_sda_out_en));

    // Instantiate the regular I2C slave, with the appropriate switched signals:
    i2c_master_blocking i2c_ok_pll (
        .wb_clk_i(okClk),
        .wb_rst_i(okRst),
        // .arst_i(1),
        .wb_adr_i(wb.slave_adr_i[2:0]),
        .wb_dat_i(wb.slave_dat_i),
        .wb_dat_o(wb.slave_dat_o[1]),
        .wb_we_i(wb.slave_we_i[1]),
        .wb_stb_i(wb.slave_stb_i[1]),
        .wb_cyc_i(wb.slave_cyc_i[1]),
        .wb_ack_o(wb.slave_ack_i[1]),
        .wb_inta_o(),
        .scl_pad_i(si5338b_i2c_scl_in),
        .scl_pad_o(si5338b_i2c_scl_out),
        .scl_padoen_o(si5338b_i2c_scl_out_en),
        .sda_pad_i(si5338b_i2c_sda_in),
        .sda_pad_o(si5338b_i2c_sda_out),
        .sda_padoen_o(si5338b_i2c_sda_out_en));


    // ---------- QSFP+ PORT 2 LANE 2 10Gbit/s GT + PHY + AXI4-STREAM ----------
    wire qsfpp_mgtrefclk;

    IBUFDS_GTE3 #(
        .REFCLK_EN_TX_PATH(1'b0),
        .REFCLK_HROW_CK_SEL(2'b00), // UG576 p28
        .REFCLK_ICNTL_RX(2'b00))
    qsfp_mgtrefclk_inbuf (
        .O(qsfpp_mgtrefclk),
        .ODIV2(),
        .CEB(0),
        .I(qsfpp_mgtrefclk_p),
        .IB(qsfpp_mgtrefclk_n));

    wire        qsfpp2_2_eth_10g_axis_tx_clk;
    wire        qsfpp2_2_eth_10g_axis_tx_rst;
    wire        qsfpp2_2_eth_10g_axis_tx_tready;
    wire        qsfpp2_2_eth_10g_axis_tx_tvalid;
    wire [63:0] qsfpp2_2_eth_10g_axis_tx_tdata;
    wire        qsfpp2_2_eth_10g_axis_tx_tlast;
    wire [7:0]  qsfpp2_2_eth_10g_axis_tx_tkeep;

    wire        qsfpp2_2_eth_10g_axis_rx_clk;
    wire        qsfpp2_2_eth_10g_axis_rx_rst;
    wire        qsfpp2_2_eth_10g_axis_rx_tready;
    wire        qsfpp2_2_eth_10g_axis_rx_tvalid;
    wire [63:0] qsfpp2_2_eth_10g_axis_rx_tdata;
    wire        qsfpp2_2_eth_10g_axis_rx_tlast;
    wire [7:0]  qsfpp2_2_eth_10g_axis_rx_tkeep;

    assign qsfpp2_2_eth_10g_axis_rx_tready = 1;
    assign qsfpp2_2_eth_10g_axis_tx_tvalid = 0;

    qsfpp2_2_eth_10g_axis qsfpp2_2_eth_10g_axis_inst (
        .wb_clk(okClk),
        .wb_rst(okRst),
        .wb_adr(wb.slave_adr_i[7:0]),
        .wb_dat_i(wb.slave_dat_i),
        .wb_dat_o(wb.slave_dat_o[4]),
        .wb_we_i(wb.slave_we_i[4]),
        .wb_stb_i(wb.slave_stb_i[4]),
        .wb_cyc_i(wb.slave_cyc_i[4]),
        .wb_ack_o(wb.slave_ack_i[4]),

        .freerun_clk(okClk),
        .freerun_rst(okRst),

        .mgtrefclk(qsfpp_mgtrefclk),
        .pll_lock(1'b1), // no PLL

        // This module expects to be passed SFP+ diffpairs, hence the signal name
        .sfpp_rx_p(qsfpp2_2_rx_p),
        .sfpp_rx_n(qsfpp2_2_rx_n),
        .sfpp_tx_p(qsfpp2_2_tx_p),
        .sfpp_tx_n(qsfpp2_2_tx_n),

        .axis_tx_clk(qsfpp2_2_eth_10g_axis_tx_clk),
        .axis_tx_rst(qsfpp2_2_eth_10g_axis_tx_rst),
        .axis_tx_tready(qsfpp2_2_eth_10g_axis_tx_tready),
        .axis_tx_tvalid(qsfpp2_2_eth_10g_axis_tx_tvalid),
        .axis_tx_tdata(qsfpp2_2_eth_10g_axis_tx_tdata),
        .axis_tx_tlast(qsfpp2_2_eth_10g_axis_tx_tlast),
        .axis_tx_tkeep(qsfpp2_2_eth_10g_axis_tx_tkeep),

        .axis_rx_clk(qsfpp2_2_eth_10g_axis_rx_clk),
        .axis_rx_rst(qsfpp2_2_eth_10g_axis_rx_rst),
        .axis_rx_tready(qsfpp2_2_eth_10g_axis_rx_tready),
        .axis_rx_tvalid(qsfpp2_2_eth_10g_axis_rx_tvalid),
        .axis_rx_tdata(qsfpp2_2_eth_10g_axis_rx_tdata),
        .axis_rx_tlast(qsfpp2_2_eth_10g_axis_rx_tlast),
        .axis_rx_tkeep(qsfpp2_2_eth_10g_axis_rx_tkeep));

endmodule

`resetall
