/**
 * XEM8320 QSFP Time Tagger FPGALink Reference Design Top-Level Module.
 *
 * This file is part of the Time Tagger software defined digital data
 * acquisition FPGA-link reference design.
 *
 * Copyright (C) 2022 Swabian Instruments, All Rights Reserved
 *
 * Authors:
 * - 2022 Leon Schuermann <leon@swabianinstruments.com>
 * - 2022-2024 David Sawatzke <david@swabianinstruments.com>
 * - 2023-2024 Ehsan Jokar <ehsan@swabianinstruments.com>
 * - 2023-2024 Markus Wick <markus@swabianinstruments.com>
 *
 * This file is provided under the terms and conditions of the BSD 3-Clause
 * license, accessible under https://opensource.org/licenses/BSD-3-Clause.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

`resetall
`timescale 1ns / 1ps
`default_nettype none

module xem8320_reference_qsfp #(
    /* TC_WORD_WIDTH controls how many events are processed simultaneously by
    the tag converter and the modules that use its output, such as Histogram,
    coincidence, and countrate. */
    parameter TC_WORD_WIDTH = 4

)(
    // OpalKelly USB Host Interface
    input wire [4:0]  okUH,
    output wire [2:0] okHU,
    inout wire [31:0] okUHU,
    inout wire        okAA,
    input wire        reset,

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

    // sys_clk
    input wire        sys_clkp,
    input wire        sys_clkn,

    output wire [5:0] led
);

    // --------------------------------------------------- //
    // --------------- OPALKELLY INTERFACE --------------- //
    // --------------------------------------------------- //

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
    wire [64:0]       okEH_PipeIn;
    wire [64:0]       okEH_PipeOut;

    okWireOR #(.N(2))
    okWireOR_inst (
        .okEH(okEH),
        .okEHx({ okEH_PipeIn, okEH_PipeOut})
        );

    // Central synchronous okClk reset
    wire okRst;
    xpm_cdc_sync_rst #(
        .DEST_SYNC_FF(2),
        .INIT(1))
    xpm_cdc_sync_rst_inst (
        .dest_rst(okRst),
        .dest_clk(okClk),
        .src_rst(reset));

    // --------------------------------------------------- //
    // --------------- Generating sys_clk- --------------- //
    // --------------------------------------------------- //

    wire sys_clk, sys_clk_locked;
    clk_core clk_core_inst (sys_clk, sys_clk_locked, sys_clkp, sys_clkn);

    wire sys_clk_rst;
    xpm_cdc_single #(
        .DEST_SYNC_FF(4),
        .INIT_SYNC_FF(0))
    sys_clk_rst_cdc (
        .dest_out(sys_clk_rst),
        .dest_clk(sys_clk),
        .src_clk(),
        .src_in(okRst || !sys_clk_locked));
    // --------------------------------------------------- //
    // ---------- WISHBONE CROSSBAR & OK BRIDGE -----------//
    // --------------------------------------------------- //

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
    always @(posedge sys_clk) begin
        if (sys_clk_rst) begin
            wb.slave_ack_o[0] <= 1'b0;
            wb.slave_dat_o[0] <= 32'b0;
        end else if (wb.slave_cyc_i[0] && wb.slave_stb_i[0]) begin
            wb.slave_ack_o[0] <= 1'b1;
        end else begin
            wb.slave_ack_o[0] <= 1'b0;
        end
    end

    wire        receive_ready;
    wire        ep_write;
    wire        wr_strobe;
    wire [31:0] pipein_fifo_data;
    wire [31:0] pipeout_fifo_data;
    wire        send_ready;
    wire        rd_strobe;
    wire        ep_read;

    okBTPipeIn okBTPipeIn_83 (
      .okHE(okHE),
      .okEH(okEH_PipeIn),
      .ep_addr(8'h83),
      .ep_dataout(pipein_fifo_data),
      .ep_write(ep_write),
      .ep_blockstrobe(wr_strobe),
      .ep_ready(receive_ready)
    );

    okBTPipeOut okBTPipeOut_A4 (
      .okHE(okHE),
      .okEH(okEH_PipeOut),
      .ep_addr(8'ha4),
      .ep_datain(pipeout_fifo_data),
      .ep_read(ep_read),
      .ep_blockstrobe(rd_strobe),
      .ep_ready(send_ready)
    );

    wb_master #(
        .FIFO_IN_SIZE(2048),
        .FIFO_OUT_SIZE(2048),
        .TIME_OUT_VAL(8*1024*1024)

    ) wb_master_core (
        .okClk(okClk),
        .okRst(okRst),
        .wb_clk(sys_clk),
        .wb_rst(sys_clk_rst),
        .ep_write(ep_write),
        .wr_strobe(wr_strobe),
        .data_i(pipein_fifo_data),
        .receive_ready(receive_ready),
        .rd_strobe(rd_strobe),
        .ep_read(ep_read),
        .send_ready(send_ready),
        .data_o(pipeout_fifo_data),
        .wb_master(wb.master_port)
    );

    // --------------------------------------------------- //
    // -------------- SFP+ PORT 1 INTERFACE -------------- //
    // --------------------------------------------------- //

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
        .wb_clk_i(sys_clk),
        .wb_rst_i(sys_clk_rst),
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

    // ---------------------------- localparams --------------------------------
    localparam GT_WORD_WIDTH = 2; // 2 ==> 10G, 4 ==> 40G
    localparam GT_DATA_WIDTH = 32*GT_WORD_WIDTH;
    localparam GT_KEEP_WIDTH = ((GT_DATA_WIDTH+7)/8);

    // DC_WORD_WIDTH should be fixed at 4; otherwise crc checker
    // should be newly generated from the python code.
    localparam DC_WORD_WIDTH = 4;
    localparam DC_DATA_WIDTH = 32*DC_WORD_WIDTH;
    localparam DC_KEEP_WIDTH = ((DC_DATA_WIDTH+7)/8);

    localparam TC_DATA_WIDTH = 32*TC_WORD_WIDTH;
    localparam TC_KEEP_WIDTH = ((TC_DATA_WIDTH+7)/8);

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

    wire                     eth_axis_tx_clk;
    wire                     eth_axis_tx_rst;
    wire                     eth_axis_tx_tready;
    wire                     eth_axis_tx_tvalid;
    wire [GT_DATA_WIDTH-1:0] eth_axis_tx_tdata;
    wire                     eth_axis_tx_tlast;
    wire [GT_KEEP_WIDTH-1:0] eth_axis_tx_tkeep;

    wire                     eth_axis_rx_clk;
    wire                     eth_axis_rx_rst;
    wire                     eth_axis_rx_tready;
    wire                     eth_axis_rx_tvalid;
    wire [GT_DATA_WIDTH-1:0] eth_axis_rx_tdata;
    wire                     eth_axis_rx_tlast;
    wire [GT_KEEP_WIDTH-1:0] eth_axis_rx_tkeep;

    assign eth_axis_tx_tvalid = 0;

    // Transceiver + PHY
    sfpp1_eth_10g_axis sfpp1_eth_10g_axis_inst (
        .wb_clk(sys_clk),
        .wb_rst(sys_clk_rst),
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

        .axis_tx_clk(eth_axis_tx_clk),
        .axis_tx_rst(eth_axis_tx_rst),
        .axis_tx_tready(eth_axis_tx_tready),
        .axis_tx_tvalid(eth_axis_tx_tvalid),
        .axis_tx_tdata(eth_axis_tx_tdata),
        .axis_tx_tlast(eth_axis_tx_tlast),
        .axis_tx_tkeep(eth_axis_tx_tkeep),

        .axis_rx_clk(eth_axis_rx_clk),
        .axis_rx_rst(eth_axis_rx_rst),
        .axis_rx_tready(eth_axis_rx_tready),
        .axis_rx_tvalid(eth_axis_rx_tvalid),
        .axis_rx_tdata(eth_axis_rx_tdata),
        .axis_rx_tlast(eth_axis_rx_tlast),
        .axis_rx_tkeep(eth_axis_rx_tkeep));

   wire                     sync_rx_data_tready;
   wire                     sync_rx_data_tvalid;
   wire [DC_DATA_WIDTH-1:0] sync_rx_data_tdata;
   wire                     sync_rx_data_tlast;
   wire [DC_KEEP_WIDTH-1:0] sync_rx_data_tkeep;

    // this block is used for synchronization and width adaptation
   axis_async_fifo_adapter #(
        .DEPTH(512),
        .S_DATA_WIDTH(GT_DATA_WIDTH),
        .M_DATA_WIDTH(DC_DATA_WIDTH),
        .ID_ENABLE(0),
        .DEST_ENABLE(0),
        .USER_ENABLE(0),
        .USER_WIDTH(32),
        .RAM_PIPELINE(1),
        .FRAME_FIFO(0),
        .DROP_OVERSIZE_FRAME(0),
        .DROP_BAD_FRAME(0),
        .DROP_WHEN_FULL(0))
    axi_adapter_and_cdc_buffer (
        .s_clk(eth_axis_rx_clk),
        .s_rst(eth_axis_rx_rst),
        .s_axis_tready(eth_axis_rx_tready),
        .s_axis_tvalid(eth_axis_rx_tvalid),
        .s_axis_tdata(eth_axis_rx_tdata),
        .s_axis_tlast(eth_axis_rx_tlast),
        .s_axis_tkeep(eth_axis_rx_tkeep),

        .m_clk(sys_clk),
        .m_rst(sys_clk_rst),
        .m_axis_tready(sync_rx_data_tready),
        .m_axis_tvalid(sync_rx_data_tvalid),
        .m_axis_tdata(sync_rx_data_tdata),
        .m_axis_tlast(sync_rx_data_tlast),
        .m_axis_tkeep(sync_rx_data_tkeep)
);

   wire                     data_stream_tready;
   wire                     data_stream_tvalid;
   wire [DC_DATA_WIDTH-1:0] data_stream_tdata;
   wire                     data_stream_tlast;
   wire [DC_KEEP_WIDTH-1:0] data_stream_tkeep;

   // CRC checksum verification
   eth_axis_fcs_checker_128b
     (
      .clk(sys_clk),
      .rst(sys_clk_rst),

      .s_axis_tready(sync_rx_data_tready),
      .s_axis_tvalid(sync_rx_data_tvalid),
      .s_axis_tdata(sync_rx_data_tdata),
      .s_axis_tlast(sync_rx_data_tlast),
      .s_axis_tkeep(sync_rx_data_tkeep),

      .m_axis_tready(data_stream_tready),
      .m_axis_tvalid(data_stream_tvalid),
      .m_axis_tdata(data_stream_tdata),
      .m_axis_tlast(data_stream_tlast),
      .m_axis_tkeep(data_stream_tkeep)
      );

    // --------------------------------------------------- //
    // ----------- FPGA-link protocol decoding ----------- //
    // --------------------------------------------------- //

   wire                      tag_stream_tready;
   wire                      tag_stream_tvalid;
   wire [TC_DATA_WIDTH-1:0]  tag_stream_tdata;
   wire                      tag_stream_tlast;
   wire [TC_KEEP_WIDTH-1:0]  tag_stream_tkeep;
   wire [31:0]               tag_stream_tuser; // Contains wrap count

   // Decoding of the FPGA-link protocol
   si_data_channel #(.DATA_WIDTH_IN(DC_DATA_WIDTH), .DATA_WIDTH_OUT(TC_DATA_WIDTH), .STATISTICS(1)) data_channel
     (
      .clk(sys_clk),
      .rst(sys_clk_rst),

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

      .wb_adr_i(wb.slave_adr_i[7:0]),
      .wb_dat_i(wb.slave_dat_i),
      .wb_dat_o(wb.slave_dat_o[3]),
      .wb_we_i(wb.slave_we_i[3]),
      .wb_stb_i(wb.slave_stb_i[3]),
      .wb_cyc_i(wb.slave_cyc_i[3]),
      .wb_ack_o(wb.slave_ack_o[3])
      );

   wire [4:0]                 user_sample_inp_channel     [TC_WORD_WIDTH-1 : 0];
   wire                       user_sample_inp_rising_edge [TC_WORD_WIDTH-1 : 0];
   wire [63:0]                user_sample_inp_tagtime     [TC_WORD_WIDTH-1 : 0];
   wire [TC_WORD_WIDTH-1 : 0] user_sample_inp_tkeep;
   wire                       user_sample_inp_tready;
   wire                       user_sample_inp_tvalid;

   // Generate 64 bit timestamps
   si_tag_converter #(.DATA_WIDTH_IN(TC_DATA_WIDTH)) converter
     (
      .clk(sys_clk),
      .rst(sys_clk_rst),
      .s_axis_tvalid(tag_stream_tvalid),
      .s_axis_tready(tag_stream_tready),
      .s_axis_tdata(tag_stream_tdata),
      .s_axis_tlast(tag_stream_tlast),
      .s_axis_tkeep(tag_stream_tkeep),
      .s_axis_tuser(tag_stream_tuser),

      .m_axis_tvalid(user_sample_inp_tvalid),
      .m_axis_tready(user_sample_inp_tready),
      .m_axis_tkeep(user_sample_inp_tkeep),
      .m_axis_tagtime(user_sample_inp_tagtime),
      .m_axis_channel(user_sample_inp_channel),
      .m_axis_rising_edge(user_sample_inp_rising_edge)
      );

    // --------------------------------------------------- //
    // ------ User design, place your modules here! ------ //
    // --------------------------------------------------- //

   user_sample #(.WORD_WIDTH(TC_WORD_WIDTH)) user_design
     (
      .clk(sys_clk),
      .rst(sys_clk_rst),

      .s_axis_tvalid(user_sample_inp_tvalid),
      .s_axis_tready(user_sample_inp_tready),
      .s_axis_tkeep(user_sample_inp_tkeep),
      .s_axis_channel(user_sample_inp_channel),
      .s_axis_tagtime(user_sample_inp_tagtime),
      .s_axis_rising_edge(user_sample_inp_rising_edge),

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
