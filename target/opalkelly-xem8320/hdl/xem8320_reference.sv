/**
 * XEM8320 Time Tagger FPGALink Reference Design Top-Level Module.
 * 
 * This file is part of the Time Tagger software defined digital data
 * acquisition FPGA-link reference design.
 *
 * Copyright (C) 2022 Swabian Instruments, All Rights Reserved
 *
 * Authors:
 * - 2022 Leon Schuermann <leon@swabianinstruments.com>
 * - 2022 David Sawatzke <david@swabianinstruments.com>
 *
 * This file is provided under the terms and conditions of the BSD 3-Clause
 * license, accessible under https://opensource.org/licenses/BSD-3-Clause.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

`timescale 1ns / 1ps
`default_nettype none

module xem8320_reference (
    // OpalKelly USB Host Interface
    input wire [4:0]  okUH,
    output wire [2:0] okHU,
    inout wire [31:0] okUHU,
    inout wire        okAA,

    // SFP+ Transceiver Common Reference Clock
    input wire        sfpp_mgtrefclk_p,
    input wire        sfpp_mgtrefclk_n,

    // SFP+ Port 1 I2C Management Interface
    inout wire        sfpp1_i2c_sda,
    inout wire        sfpp1_i2c_scl,
    output wire       sfpp1_rs0,
    output wire       sfpp1_rs1,
    input wire        sfpp1_mod_abs,
    input wire        sfpp1_rc_los,
    output wire       sfpp1_tx_disable,
    input wire        sfpp1_tx_fault,

    // SFP+ Port 1 Lanes
    output wire       sfpp1_tx_p,
    output wire       sfpp1_tx_n,
    input wire        sfpp1_rx_p,
    input wire        sfpp1_rx_n,

    output wire [5:0] led
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
    wb_interface #(.SLAVES(5)) wb();
    // Always ACK Machine (required for the wb_pipe_bridge)
    assign wb.slave_wb_adr[0]  = 24'b100000000000000000000000;
    // SFP+ I2C Management Interface
    assign wb.slave_wb_adr[1]  = 24'b100000000000000000000010;
    // SFP+ 10G Ethernet Core (Port 1)
    assign wb.slave_wb_adr[2]  = 24'b100000000000000000010101;
    // QSFP+ 40G Ethernet
    // assign wb.slave_wb_adr[3]  = 24'b100000000000000000010110;
    // Statistics module
    assign wb.slave_wb_adr[3]  = 24'b100000000000000001010001;
    // User design interface
    assign wb.slave_wb_adr[4]  = 24'b100000000000000001010010;

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

    // ---------- SFP+ PORT 1 MANAGEMENT INTERFACE I2C-WB CORE ----------
    wire sfpp1_i2c_scl_in;
    wire sfpp1_i2c_scl_out;
    wire sfpp1_i2c_scl_out_en;
    wire sfpp1_i2c_sda_in;
    wire sfpp1_i2c_sda_out;
    wire sfpp1_i2c_sda_out_en;

    IOBUF sfpp1_i2c_scl_iobuf (
        .O(sfpp1_i2c_scl_in),
        .IO(sfpp1_i2c_scl),
        .I(sfpp1_i2c_scl_out),
        .T(sfpp1_i2c_scl_out_en));

    IOBUF sfpp1_i2c_sda_iobuf (
        .O(sfpp1_i2c_sda_in),
        .IO(sfpp1_i2c_sda),
        .I(sfpp1_i2c_sda_out),
        .T(sfpp1_i2c_sda_out_en));

    i2c_master_top i2c_sfpp (
        .wb_clk_i(okClk),
        .wb_rst_i(okRst),
        .arst_i(1),
        .wb_adr_i(wb.slave_adr_i[2:0]),
        .wb_dat_i(wb.slave_dat_i),
        .wb_dat_o(wb.slave_dat_o[1]),
        .wb_we_i(wb.slave_we_i[1]),
        .wb_stb_i(wb.slave_stb_i[1]),
        .wb_cyc_i(wb.slave_cyc_i[1]),
        .wb_ack_o(wb.slave_ack_o[1]),
        .wb_inta_o(),
        .scl_pad_i(sfpp1_i2c_scl_in),
        .scl_pad_o(sfpp1_i2c_scl_out),
        .scl_padoen_o(sfpp1_i2c_scl_out_en),
        .sda_pad_i(sfpp1_i2c_sda_in),
        .sda_pad_o(sfpp1_i2c_sda_out),
        .sda_padoen_o(sfpp1_i2c_sda_out_en));

    // ---------- SFP+ PORT 1 (incl. TRANSCEIVER + PHY + AXI4-STREAM) ----------
    assign sfpp1_tx_disable = 0;
    assign sfpp1_rs0 = 1;
    assign sfpp1_rs1 = 1;

    wire sfpp_mgtrefclk;

    IBUFDS_GTE4 #(
        .REFCLK_EN_TX_PATH(1'b0),
        .REFCLK_HROW_CK_SEL(2'b00), // UG576 p28
        .REFCLK_ICNTL_RX(2'b00))
    qsfp_mgtrefclk_inbuf (
        .O(sfpp_mgtrefclk),
        .ODIV2(),
        .CEB(0),
        .I(sfpp_mgtrefclk_p),
        .IB(sfpp_mgtrefclk_n));

    wire        sfpp1_eth_10g_axis_tx_clk;
    wire        sfpp1_eth_10g_axis_tx_rst;
    wire        sfpp1_eth_10g_axis_tx_tready;
    wire        sfpp1_eth_10g_axis_tx_tvalid;
    wire [63:0] sfpp1_eth_10g_axis_tx_tdata;
    wire        sfpp1_eth_10g_axis_tx_tlast;
    wire [7:0]  sfpp1_eth_10g_axis_tx_tkeep;

    wire        sfpp1_eth_10g_axis_rx_clk;
    wire        sfpp1_eth_10g_axis_rx_rst;
    wire        sfpp1_eth_10g_axis_rx_tready;
    wire        sfpp1_eth_10g_axis_rx_tvalid;
    wire [63:0] sfpp1_eth_10g_axis_rx_tdata;
    wire        sfpp1_eth_10g_axis_rx_tlast;
    wire [7:0]  sfpp1_eth_10g_axis_rx_tkeep;

    assign sfpp1_eth_10g_axis_tx_tvalid = 0;

    sfpp1_eth_10g_axis sfpp1_eth_10g_axis_inst (
        .wb_clk(okClk),
        .wb_rst(okRst),
        .wb_adr_i(wb.slave_adr_i[7:0]),
        .wb_dat_i(wb.slave_dat_i),
        .wb_dat_o(wb.slave_dat_o[2]),
        .wb_we_i(wb.slave_we_i[2]),
        .wb_stb_i(wb.slave_stb_i[2]),
        .wb_cyc_i(wb.slave_cyc_i[2]),
        .wb_ack_o(wb.slave_ack_o[2]),

        .freerun_clk(okClk),
        .freerun_rst(okRst),

        .mgtrefclk(sfpp_mgtrefclk),
        .pll_lock(1'b1), // no PLL

        .sfpp_rx_p(sfpp1_rx_p),
        .sfpp_rx_n(sfpp1_rx_n),
        .sfpp_tx_p(sfpp1_tx_p),
        .sfpp_tx_n(sfpp1_tx_n),

        .axis_tx_clk(sfpp1_eth_10g_axis_tx_clk),
        .axis_tx_rst(sfpp1_eth_10g_axis_tx_rst),
        .axis_tx_tready(sfpp1_eth_10g_axis_tx_tready),
        .axis_tx_tvalid(sfpp1_eth_10g_axis_tx_tvalid),
        .axis_tx_tdata(sfpp1_eth_10g_axis_tx_tdata),
        .axis_tx_tlast(sfpp1_eth_10g_axis_tx_tlast),
        .axis_tx_tkeep(sfpp1_eth_10g_axis_tx_tkeep),

        .axis_rx_clk(sfpp1_eth_10g_axis_rx_clk),
        .axis_rx_rst(sfpp1_eth_10g_axis_rx_rst),
        .axis_rx_tready(sfpp1_eth_10g_axis_rx_tready),
        .axis_rx_tvalid(sfpp1_eth_10g_axis_rx_tvalid),
        .axis_rx_tdata(sfpp1_eth_10g_axis_rx_tdata),
        .axis_rx_tlast(sfpp1_eth_10g_axis_rx_tlast),
        .axis_rx_tkeep(sfpp1_eth_10g_axis_rx_tkeep));

   wire         wide_rx_data_tready;
   wire         wide_rx_data_tvalid;
   wire [127:0] wide_rx_data_tdata;
   wire         wide_rx_data_tlast;
   wire [15:0]  wide_rx_data_tkeep;

   axis_adapter #(.S_DATA_WIDTH(64), .M_DATA_WIDTH(128), .USER_ENABLE(0)) adapter
     (
        .clk(sfpp1_eth_10g_axis_rx_clk),
        .rst(sfpp1_eth_10g_axis_rx_rst),

        .s_axis_tready(sfpp1_eth_10g_axis_rx_tready),
        .s_axis_tvalid(sfpp1_eth_10g_axis_rx_tvalid),
        .s_axis_tdata(sfpp1_eth_10g_axis_rx_tdata),
        .s_axis_tlast(sfpp1_eth_10g_axis_rx_tlast),
        .s_axis_tkeep(sfpp1_eth_10g_axis_rx_tkeep),

        .m_axis_tready(wide_rx_data_tready),
        .m_axis_tvalid(wide_rx_data_tvalid),
        .m_axis_tdata(wide_rx_data_tdata),
        .m_axis_tlast(wide_rx_data_tlast),
        .m_axis_tkeep(wide_rx_data_tkeep)
    );


   wire         data_stream_tready;
   wire         data_stream_tvalid;
   wire [127:0] data_stream_tdata;
   wire         data_stream_tlast;
   wire [15:0]  data_stream_tkeep;

   eth_axis_fcs_checker_128b
     (
      .clk(sfpp1_eth_10g_axis_rx_clk),
      .rst(sfpp1_eth_10g_axis_rx_rst),

      .s_axis_tready(wide_rx_data_tready),
      .s_axis_tvalid(wide_rx_data_tvalid),
      .s_axis_tdata(wide_rx_data_tdata),
      .s_axis_tlast(wide_rx_data_tlast),
      .s_axis_tkeep(wide_rx_data_tkeep),

      .m_axis_tready(data_stream_tready),
      .m_axis_tvalid(data_stream_tvalid),
      .m_axis_tdata(data_stream_tdata),
      .m_axis_tlast(data_stream_tlast),
      .m_axis_tkeep(data_stream_tkeep)
      );

   wire         tag_stream_tready;
   wire         tag_stream_tvalid;
   wire [31:0]  tag_stream_tdata;
   wire         tag_stream_tlast;
   wire [3:0]   tag_stream_tkeep;
   wire [31:0]  tag_stream_tuser; // Contains wrap count

   si_data_channel #(.DATA_WIDTH_IN(128), .DATA_WIDTH_OUT(32), .STATISTICS(1)) data_channel
     (
      .eth_clk(sfpp1_eth_10g_axis_rx_clk),
      .eth_rst(sfpp1_eth_10g_axis_rx_rst),

      .usr_clk(sfpp1_eth_10g_axis_rx_clk),
      .usr_rst(sfpp1_eth_10g_axis_rx_rst),

      .s_axis_tready(data_stream_tready),
      .s_axis_tvalid(data_stream_tvalid),
      .s_axis_tdata(data_stream_tdata),
      .s_axis_tlast(data_stream_tlast),
      .s_axis_tkeep(data_stream_tkeep),

      .m_axis_tready(tag_stream_tready),
      .m_axis_tvalid(tag_stream_tvalid),
      .m_axis_tdata(tag_stream_tdata),
      .m_axis_tlast(tag_stream_tlast),
      .m_axis_tkeep(tag_stream_tkeep),
      .m_axis_tuser(tag_stream_tuser),

      .wb_clk(okClk),
      .wb_rst(okRst),
      .wb_adr_i(wb.slave_adr_i[7:0]),
      .wb_dat_i(wb.slave_dat_i),
      .wb_dat_o(wb.slave_dat_o[3]),
      .wb_we_i(wb.slave_we_i[3]),
      .wb_stb_i(wb.slave_stb_i[3]),
      .wb_cyc_i(wb.slave_cyc_i[3]),
      .wb_ack_o(wb.slave_ack_o[3])
      );

   wire [4:0]  channel;
   wire        rising_edge;
   wire [63:0] tagtime;
   wire        valid_tag;

   // Adapt from axi stream since the following modules don't it
   assign tag_stream_tready = 1;
   si_tag_converter converter
     (
      .clk(sfpp1_eth_10g_axis_rx_clk),
      .rst(sfpp1_eth_10g_axis_rx_rst),
      .tag((tag_stream_tvalid && tag_stream_tready) ? tag_stream_tdata : 0),
      .wrap_count(tag_stream_tuser),

      .valid_tag(valid_tag),
      .tagtime(tagtime),
      .channel(channel),
      .rising_edge(rising_edge)
      );

   user_sample user_design
     (
      .clk(sfpp1_eth_10g_axis_rx_clk),
      .rst(sfpp1_eth_10g_axis_rx_rst),

      .valid_tag(valid_tag),
      .tagtime(tagtime),
      .channel(channel),
      .rising_edge(rising_edge),

      .wb_clk(okClk),
      .wb_rst(okRst),
      .wb_adr_i(wb.slave_adr_i[7:0]),
      .wb_dat_i(wb.slave_dat_i),
      .wb_dat_o(wb.slave_dat_o[4]),
      .wb_we_i(wb.slave_we_i[4]),
      .wb_stb_i(wb.slave_stb_i[4]),
      .wb_cyc_i(wb.slave_cyc_i[4]),
      .wb_ack_o(wb.slave_ack_o[4]),

      .led(led)
      );

endmodule

`resetall
