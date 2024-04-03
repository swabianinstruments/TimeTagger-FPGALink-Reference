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
 * - 2022-2024 David Sawatzke <david@swabianinstruments.com>
 * - 2023-2024 Ehsan Jokar <ehsan@swabianinstruments.com>
 * - 2023-2024 Markus Wick <markus@swabianinstruments.com>
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

`include "../../../hdl/ref_design_pkg.sv"
import pkg_base_address::*;

module xem8320_reference #(
    /* TC_WORD_WIDTH controls how many events are processed simultaneously by
    the tag converter and the modules that use its output, such as Histogram,
    coincidence, and countrate. */
    parameter TC_WORD_WIDTH = 1

) (
    // OpalKelly USB Host Interface
    input  wire [ 4:0] okUH,
    output wire [ 2:0] okHU,
    inout  wire [31:0] okUHU,
    inout  wire        okAA,
    input  wire        reset,

    // SFP+ Transceiver Common Reference Clock
    input wire sfpp_mgtrefclk_p,
    input wire sfpp_mgtrefclk_n,

    // SFP+ Port 1 I2C Management Interface
    inout  wire sfpp1_i2c_sda,
    inout  wire sfpp1_i2c_scl,
    output wire sfpp1_rs0,
    output wire sfpp1_rs1,
    input  wire sfpp1_mod_abs,
    input  wire sfpp1_rc_los,
    output wire sfpp1_tx_disable,
    input  wire sfpp1_tx_fault,

    // SFP+ Port 1 Lanes
    output wire sfpp1_tx_p,
    output wire sfpp1_tx_n,
    input  wire sfpp1_rx_p,
    input  wire sfpp1_rx_n,

    // sys_clk
    input wire sys_clkp,
    input wire sys_clkn,

    output wire [5:0] led
);

    // --------------------------------------------------- //
    // ---------------- LOCAL PARAMETERS-- --------------- //
    // --------------------------------------------------- //
    localparam GT_WORD_WIDTH = 2;  // 2 ==> 10G, 4 ==> 40G
    localparam GT_DATA_WIDTH = 32 * GT_WORD_WIDTH;

    // DC_WORD_WIDTH should be fixed at 4; otherwise crc checker
    // should be newly generated from the python code.
    localparam DC_WORD_WIDTH = 4;
    localparam DC_DATA_WIDTH = 32 * DC_WORD_WIDTH;

    localparam TC_DATA_WIDTH = 32 * TC_WORD_WIDTH;

    // --------------------------------------------------- //
    // --------------- OPALKELLY INTERFACE --------------- //
    // --------------------------------------------------- //

    // Target interface bus
    wire         okClk;
    wire [112:0] okHE;
    wire [ 64:0] okEH;

    // Instantiate the okHost and connect endpoints
    okHost okHI (
        .okUH (okUH),
        .okHU (okHU),
        .okUHU(okUHU),
        .okAA (okAA),
        .okClk(okClk),
        .okHE (okHE),
        .okEH (okEH)
    );

    // OpalKelly WireOr to connect the various outputs
    wire [64:0] okEH_PipeIn;
    wire [64:0] okEH_PipeOut;

    okWireOR #(
        .N(2)
    ) okWireOR_inst (
        .okEH (okEH),
        .okEHx({okEH_PipeIn, okEH_PipeOut})
    );

    // Central synchronous okClk reset
    wire okRst;
    xpm_cdc_sync_rst #(
        .DEST_SYNC_FF(2),
        .INIT(1)
    ) xpm_cdc_sync_rst_inst (
        .dest_rst(okRst),
        .dest_clk(okClk),
        .src_rst (reset)
    );

    // --------------------------------------------------- //
    // --------------- Generating sys_clk- --------------- //
    // --------------------------------------------------- //

    wire sys_clk, sys_clk_locked;
    clk_core clk_core_inst (
        sys_clk,
        sys_clk_locked,
        sys_clkp,
        sys_clkn
    );

    wire sys_clk_rst;
    xpm_cdc_single #(
        .DEST_SYNC_FF(4),
        .INIT_SYNC_FF(0)
    ) sys_clk_rst_cdc (
        .dest_out(sys_clk_rst),
        .dest_clk(sys_clk),
        .src_clk (),
        .src_in  (okRst || !sys_clk_locked)
    );
    // --------------------------------------------------- //
    // ---------- WISHBONE CROSSBAR & OK BRIDGE -----------//
    // --------------------------------------------------- //

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

    // to_wb_ic is the interface between wb_master and wb_interconnect
    wb_interface to_wb_ic ();

    localparam WB_MASTER_FIFO_DEPTH = 2048;
    wb_master #(
        .FIFO_IN_SIZE (WB_MASTER_FIFO_DEPTH),
        .FIFO_OUT_SIZE(WB_MASTER_FIFO_DEPTH),
        .TIME_OUT_VAL (8 * 1024 * 1024)

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
        .wb_master(to_wb_ic)
    );

    wb_interface wb_array[WB_SIZE] ();

    wb_interconnect #(
        .INSTANCES(WB_SIZE),
        .BASE_ADDRESS(base_address),
        .MEMORY_SPACE(memory_space)
    ) wb_interconnect_inst (
        .s_wb(to_wb_ic),
        .m_wb(wb_array)
    );

    // --------------------------------------------------- //
    // --------- TOP MODULE WISHBONE INTERFACE------------ //
    // --------------------------------------------------- //

    // Wishbone Always ACK Machine, required for OpalKelly Pipe-based Wishbone Bridge
    always @(posedge sys_clk) begin
        if (sys_clk_rst) begin
            wb_array[top_module].ack   <= 1'b0;
            wb_array[top_module].dat_o <= 32'b0;
        end else if (wb_array[top_module].cyc && wb_array[top_module].stb) begin
            wb_array[top_module].ack <= 1'b1;
            if (wb_array[top_module].we) begin

            end else begin
                case (wb_array[top_module].adr[7:0])
                    8'b00000000: wb_array[top_module].dat_o <= 1;
                    8'b00000001:
                    wb_array[top_module].dat_o   <= WB_MASTER_FIFO_DEPTH; // return the size of the FIFOs used in wb_master
                    default: wb_array[top_module].dat_o <= 32'b0;
                endcase
            end
        end else begin
            wb_array[top_module].ack <= 1'b0;
        end
    end

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
        .O (sfpp1_i2c_scl_in),
        .IO(sfpp1_i2c_scl),
        .I (sfpp1_i2c_scl_out),
        .T (sfpp1_i2c_scl_out_en)
    );

    IOBUF sfpp1_i2c_sda_iobuf (
        .O (sfpp1_i2c_sda_in),
        .IO(sfpp1_i2c_sda),
        .I (sfpp1_i2c_sda_out),
        .T (sfpp1_i2c_sda_out_en)
    );

    i2c_master_top i2c_sfpp (
        .wb_clk_i(sys_clk),
        .wb_rst_i(sys_clk_rst),
        .arst_i(1),
        .wb_adr_i(wb_array[i2c_master].adr),
        .wb_dat_i(wb_array[i2c_master].dat_i),
        .wb_dat_o(wb_array[i2c_master].dat_o),
        .wb_we_i(wb_array[i2c_master].we),
        .wb_stb_i(wb_array[i2c_master].stb),
        .wb_cyc_i(wb_array[i2c_master].cyc),
        .wb_ack_o(wb_array[i2c_master].ack),
        .wb_inta_o(),
        .scl_pad_i(sfpp1_i2c_scl_in),
        .scl_pad_o(sfpp1_i2c_scl_out),
        .scl_padoen_o(sfpp1_i2c_scl_out_en),
        .sda_pad_i(sfpp1_i2c_sda_in),
        .sda_pad_o(sfpp1_i2c_sda_out),
        .sda_padoen_o(sfpp1_i2c_sda_out_en)
    );



    // ---------- SFP+ PORT 1 (incl. TRANSCEIVER + PHY + AXI4-STREAM) ----------
    assign sfpp1_tx_disable = 0;
    assign sfpp1_rs0 = 1;
    assign sfpp1_rs1 = 1;

    wire sfpp_mgtrefclk;

    IBUFDS_GTE4 #(
        .REFCLK_EN_TX_PATH(1'b0),
        .REFCLK_HROW_CK_SEL(2'b00),  // UG576 p28
        .REFCLK_ICNTL_RX(2'b00)
    ) qsfp_mgtrefclk_inbuf (
        .O(sfpp_mgtrefclk),
        .ODIV2(),
        .CEB(0),
        .I(sfpp_mgtrefclk_p),
        .IB(sfpp_mgtrefclk_n)
    );

    wire eth_axis_tx_clk, eth_axis_tx_rst;
    wire eth_axis_rx_clk, eth_axis_rx_rst;

    axis_interface #(
        .DATA_WIDTH(GT_DATA_WIDTH)
    ) eth_axis_tx (
        .clk(eth_axis_tx_clk),
        .rst(eth_axis_tx_rst)
    );
    axis_interface #(
        .DATA_WIDTH(GT_DATA_WIDTH)
    ) eth_axis_rx (
        .clk(eth_axis_rx_clk),
        .rst(eth_axis_rx_rst)
    );

    assign eth_axis_tx.tvalid = 0;
    assign eth_axis_tx.tdata  = 0;
    assign eth_axis_tx.tkeep  = 0;
    assign eth_axis_tx.tlast  = 0;

    // Transceiver + PHY
    sfpp1_eth_10g_axis sfpp1_eth_10g_axis_inst (
        .wb(wb_array[ethernet]),

        .freerun_clk(okClk),
        .freerun_rst(okRst),

        .mgtrefclk(sfpp_mgtrefclk),
        .pll_lock(1'b1),  // no PLL

        .sfpp_rx_p(sfpp1_rx_p),
        .sfpp_rx_n(sfpp1_rx_n),
        .sfpp_tx_p(sfpp1_tx_p),
        .sfpp_tx_n(sfpp1_tx_n),

        .axis_tx_clk(eth_axis_tx_clk),
        .axis_tx_rst(eth_axis_tx_rst),
        .axis_rx_clk(eth_axis_rx_clk),
        .axis_rx_rst(eth_axis_rx_rst),

        .axis_tx(eth_axis_tx),
        .axis_rx(eth_axis_rx)

    );

    // --------------------------------------------------- //
    // -------- SYNCHRONIZATION AND WIDTH ADAPTION ------- //
    // --------------------------------------------------- //
    axis_interface #(
        .DATA_WIDTH(DC_DATA_WIDTH)
    ) sync_rx_data (
        .clk(sys_clk),
        .rst(sys_clk_rst)
    );

    // this block is used for synchronization and width adaptation.
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
        .DROP_WHEN_FULL(0)
    ) axi_adapter_and_cdc_buffer (
        .s_clk(eth_axis_rx.clk),
        .s_rst(eth_axis_rx.rst),
        .s_axis_tready(eth_axis_rx.tready),
        .s_axis_tvalid(eth_axis_rx.tvalid),
        .s_axis_tdata(eth_axis_rx.tdata),
        .s_axis_tlast(eth_axis_rx.tlast),
        .s_axis_tkeep(eth_axis_rx.tkeep),

        .m_clk(sync_rx_data.clk),
        .m_rst(sync_rx_data.rst),
        .m_axis_tready(sync_rx_data.tready),
        .m_axis_tvalid(sync_rx_data.tvalid),
        .m_axis_tdata(sync_rx_data.tdata),
        .m_axis_tlast(sync_rx_data.tlast),
        .m_axis_tkeep(sync_rx_data.tkeep)
    );

    // --------------------------------------------------- //
    // ------------ CRC CHECKSUM VERIFICATION ------------ //
    // --------------------------------------------------- //

    axis_interface #(
        .DATA_WIDTH(DC_DATA_WIDTH)
    ) data_stream (
        .clk(sys_clk),
        .rst(sys_clk_rst)
    );

    // CRC checksum verification
    eth_axis_fcs_checker_128b fcs_checker (
        .s_axis(sync_rx_data),
        .m_axis(data_stream)
    );

    // --------------------------------------------------- //
    // ----------- FPGA-link protocol decoding ----------- //
    // --------------------------------------------------- //

    axis_interface #(
        .DATA_WIDTH(TC_DATA_WIDTH)
    ) tag_stream (
        .clk(sys_clk),
        .rst(sys_clk_rst)
    );

    /* The si_data_channel module is responsible for extracting raw data and associated
   time information from Ethernet data, which includes various headers.
   */
    si_data_channel #(
        .STATISTICS(1)
    ) data_channel (
        .s_axis(data_stream),
        .m_axis(tag_stream),

        .wb_statistics(wb_array[statistics])
    );

    // --------------------------------------------------- //
    // ----------- GENERATING 64 BIT TIMESTAMPS ---------- //
    // --------------------------------------------------- //

    /* The si_tag_converter is tasked with decoding the 32-bit input data into real timestamps.
   These timestamps are represented as 64 bits, and the resolution is 1/3 picoseconds.
   */
    axis_tag_interface #(.WORD_WIDTH(TC_WORD_WIDTH)) measurement_inp ();
    si_tag_converter converter (
        .s_axis(tag_stream),
        .m_axis(measurement_inp)
    );

    // --------------------------------------------------- //
    // --- User design, add your modules to measurement -- //
    // --------------------------------------------------- //

    /*The measurement module encompasses various components such as user_sample,
      histogram, and coincidence. If you wish to incorporate your own measurement
      module, it is highly recommended to include it within the measurement module.
      To achieve this, ensure that you handle all necessary Wishbone interfaces for
      your modules.
    */
    measurement measurement_core (
        .s_axis(measurement_inp),

        .wb_user_sample(wb_array[user_sample]),  // wb interface for user_sample module
        .wb_histogram(wb_array[histogram]),  // wb interface for histogram module
        .wb_counter(wb_array[counter]),  // wb interface for counter module

        //------------------------------------------//
        //---- add wb interface for your modules ----//

        /*please define its base addresses and memory_spaces
        in the pkg_base_address defined in the ref_design_pkg.sv */

        // wb_your_module_1(wb_array[your_inst_name_1]),
        // wb_your_module_2(wb_array[your_inst_name_2]),

        .led(led)
    );

endmodule
