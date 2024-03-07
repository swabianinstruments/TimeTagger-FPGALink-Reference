/**
 * XEM8320 SFP+ Slot 1 Transceiver + 10Gbit/s Ethernet PHY +
 * XGMII-to-AXI4-Stream instantiation.
 *
 * This file is part of the Time Tagger software defined digital data
 * acquisition FPGA-link reference design.
 *
 * Copyright (C) 2022 Swabian Instruments, All Rights Reserved
 *
 * Authors:
 * - 2022 Leon Schuermann <leon@swabianinstruments.com>
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

module sfpp1_eth_10g_axis (
    // Freerunning clock input
    input wire freerun_clk,
    input wire freerun_rst,

    // Transceiver reference clock
    input wire mgtrefclk,

    // External PLL lock indication
    input wire pll_lock,

    // SPF+ interface
    input  wire sfpp_rx_p,
    input  wire sfpp_rx_n,
    output wire sfpp_tx_p,
    output wire sfpp_tx_n,

    // AXI4-Stream output (without preamble & FCS)
    output wire        axis_rx_clk,
    output wire        axis_rx_rst,
    input  wire        axis_rx_tready,
    output wire        axis_rx_tvalid,
    output wire [63:0] axis_rx_tdata,
    output wire        axis_rx_tlast,
    output wire [ 7:0] axis_rx_tkeep,

    // AXI4-Stream input (without preamble & FCS, IFG maintained internally)
    output wire        axis_tx_clk,
    output wire        axis_tx_rst,
    output wire        axis_tx_tready,
    input  wire        axis_tx_tvalid,
    input  wire [63:0] axis_tx_tdata,
    input  wire        axis_tx_tlast,
    input  wire [ 7:0] axis_tx_tkeep,

    // Wishbone interface for control & status
    wb_interface.slave wb
);
    // ---------- GTWIZARD GTH INSTANTIATION ----------

    // Transceiver status & control signals
    //
    // CONTROL:
    // - 00h: Transceiver Reset
    //        (1 holds all parts of the transceiver & QPLL in reset)
    // - 01h: Reset TX PLL & Datapath
    // - 02h: Reset RX PLL & Datapath
    // - 03h: Reset RX Datapath
    // - 04h: Reset TX Userclk
    // - 05h: Reset RX Userclk
    reg  [ 5:0] transceiver_control;

    // STATUS:
    // - 00h: Transceiver Power Good
    // - 01h: Transceiver in Reset
    //        (asserted when PLL is not locked or transceiver enable = 0)
    // - 02h: Transceiver TX PMA Reset Done
    // - 03h: Transceiver TX PRGDIV Reset Done
    // - 04h: Transceiver TX Reset Done
    // - 05h: Transceiver RX PMA Reset Done
    // - 06h: Transceiver RX PRGDIV Reset Done
    // - 07h: Transceiver RX Reset Done
    // - 08h: Transceiver Userclk TX Active
    // - 09h: Transceiver Userclk RX Active
    // - 0Ah: External PLL Lock Indication
    // - 0Bh: Transceiver QPLL Lock Indication
    // - 0Ch: Transceiver RX CDR Stable Indication
    wire [12:0] transceiver_status;


    // Synthesize a freerun clk rst, also respecting the lock status of the
    // external PLL and the Transceiver Enable switch.
    wire        transceiver_hold_reset;
    wire        freerun_lock_rst;
    sync_reset #(
        .N(4)
    ) sfpp_gt_freerun_clk_lock_enable_sync (
        .clk(freerun_clk),
        .rst(freerun_rst | !pll_lock | transceiver_hold_reset),
        .out(freerun_lock_rst)
    );

    // Misc transceiver control signals
    wire        gt_tx_reset_pll_datapath;
    wire        gt_rx_reset_pll_datapath;
    wire        gt_rx_reset_datapath;
    wire        gt_userclk_tx_reset;
    wire        gt_userclk_rx_reset;


    // Misc transceiver status signals
    wire        gt_powergood;
    wire        gt_qpll0_lock;
    wire        gt_tx_pma_reset_done;
    wire        gt_tx_prgdiv_reset_done;
    wire        gt_tx_reset_done;
    wire        gt_rx_pma_reset_done;
    wire        gt_rx_prgdiv_reset_done;
    wire        gt_rx_reset_done;
    wire        gt_userclk_tx_active;
    wire        gt_userclk_rx_active;
    wire        gt_rx_cdr_stable;

    // Transceiver TX interface
    wire        gt_tx_usrclk2;
    wire [63:0] gt_tx_data;
    wire [ 5:0] gt_tx_header;

    // Transceiver RX interface
    wire        gt_rx_usrclk2;
    wire        gt_rx_gearboxslip;
    wire [ 1:0] gt_rx_datavalid;
    wire [63:0] gt_rx_data;
    wire [ 1:0] gt_rx_headervalid;
    wire [ 5:0] gt_rx_header;

    sfpp1_eth_10g_gth sfpp1_eth_10g_gth_inst (
        // ----- Free-running clock & reset for reset logic -----
        .gtwiz_reset_clk_freerun_in(freerun_clk),
        .gtwiz_reset_all_in(freerun_lock_rst),

        // ----- Miscellaneous status signals -----
        .gtpowergood_out(gt_powergood),

        // ----- QPLL in core -----
        .gtrefclk00_in(mgtrefclk),
        .qpll0lock_out(gt_qpll0_lock),
        .qpll0outclk_out(),
        .qpll0outrefclk_out(),

        // ----- Transceiver differential lanes -----
        .gtyrxp_in(sfpp_rx_p),
        .gtyrxn_in(sfpp_rx_n),

        .gtytxp_out(sfpp_tx_p),
        .gtytxn_out(sfpp_tx_n),

        // ----- User parallel interface -----

        // Transmit reset
        .gtwiz_reset_tx_datapath_in(1'b0),
        .gtwiz_reset_tx_pll_and_datapath_in(gt_tx_reset_pll_datapath),
        .gtwiz_reset_tx_done_out(gt_tx_reset_done),
        .txpmaresetdone_out(gt_tx_pma_reset_done),
        .txprgdivresetdone_out(gt_tx_prgdiv_reset_done),
        .gtwiz_userclk_tx_reset_in(gt_userclk_tx_reset),

        // Transmit clocking
        .gtwiz_userclk_tx_srcclk_out (),
        .gtwiz_userclk_tx_usrclk_out (),
        .gtwiz_userclk_tx_usrclk2_out(gt_tx_usrclk2),
        .gtwiz_userclk_tx_active_out (gt_userclk_tx_active),

        // Transmit data
        .gtwiz_userdata_tx_in(gt_tx_data),
        .txheader_in(gt_tx_header),
        .txsequence_in(7'b0),

        // Receive reset
        .gtwiz_reset_rx_pll_and_datapath_in(gt_rx_reset_pll_datapath),
        .gtwiz_reset_rx_datapath_in(gt_rx_reset_datapath),
        .gtwiz_reset_rx_cdr_stable_out(gt_rx_cdr_stable),
        .gtwiz_reset_rx_done_out(gt_rx_reset_done),
        .rxpmaresetdone_out(gt_rx_pma_reset_done),
        .rxprgdivresetdone_out(gt_rx_prgdiv_reset_done),
        .gtwiz_userclk_rx_reset_in(gt_userclk_rx_reset),

        // Receive clocking
        .gtwiz_userclk_rx_srcclk_out (),
        .gtwiz_userclk_rx_usrclk_out (),
        .gtwiz_userclk_rx_usrclk2_out(gt_rx_usrclk2),
        .gtwiz_userclk_rx_active_out (gt_userclk_rx_active),


        .rxgearboxslip_in(gt_rx_gearboxslip),
        .rxdatavalid_out(gt_rx_datavalid),
        .gtwiz_userdata_rx_out(gt_rx_data),
        .rxheadervalid_out(gt_rx_headervalid),
        .rxheader_out(gt_rx_header),
        .rxstartofseq_out()
    );

    // Control signal assignments

    xpm_cdc_single #(
        .DEST_SYNC_FF(4),
        .INIT_SYNC_FF(0)
    ) sys_clk_rst_cdc (
        .dest_out(transceiver_hold_reset),
        .dest_clk(freerun_clk),  // okClk
        .src_clk(wb.clk),  // sys_clk
        .src_in(transceiver_control[0])
    );

    assign gt_tx_reset_pll_datapath = transceiver_control[1];
    assign gt_rx_reset_pll_datapath = transceiver_control[2];
    assign gt_rx_reset_datapath = transceiver_control[3];
    assign gt_userclk_tx_reset = transceiver_control[4];
    assign gt_userclk_rx_reset = transceiver_control[5];

    // Status signal assignments
    assign transceiver_status[0] = gt_powergood;
    assign transceiver_status[1] = freerun_lock_rst;
    assign transceiver_status[2] = gt_tx_pma_reset_done;
    assign transceiver_status[3] = gt_tx_prgdiv_reset_done;
    assign transceiver_status[4] = gt_tx_reset_done;
    assign transceiver_status[5] = gt_rx_pma_reset_done;
    assign transceiver_status[6] = gt_rx_prgdiv_reset_done;
    assign transceiver_status[7] = gt_rx_reset_done;
    assign transceiver_status[8] = gt_userclk_tx_active;
    assign transceiver_status[9] = gt_userclk_rx_active;
    assign transceiver_status[10] = pll_lock;
    assign transceiver_status[11] = gt_qpll0_lock;
    assign transceiver_status[12] = gt_rx_cdr_stable;

    // ---------- PHY (Transceiver to XGMII) instantiation ----------

    // PHY status signals:
    // - 00h: RX Block Lock
    // - 01h: RX High BER
    wire [15:0] phy_status;

    // PHY control signals:
    // - 00h: XGMII loopback mode
    reg  [ 0:0] phy_control;
    reg  [ 0:0] phy_control_tx_clk;

    // XGMII interface
    wire xgmii_tx_clk, xgmii_tx_rst;
    wire xgmii_rx_clk, xgmii_rx_rst;
    wire [63:0] xgmii_tx_data, xgmii_tx_data_int;
    wire [7:0] xgmii_tx_ctrl, xgmii_tx_ctrl_int;
    wire [63:0] xgmii_rx_data;
    wire [ 7:0] xgmii_rx_ctrl;

    // Clock & reset
    assign xgmii_tx_clk = gt_tx_usrclk2;
    assign xgmii_rx_clk = gt_rx_usrclk2;

    sync_reset #(.N(4))
        sfpp_xgmii_tx_sync_reset (
            .clk(xgmii_tx_clk),
            .rst(!gt_tx_reset_done),
            .out(xgmii_tx_rst)
        ),
        sfpp_xgmii_rx_sync_reset (
            .clk(xgmii_rx_clk),
            .rst(!gt_rx_reset_done),
            .out(xgmii_rx_rst)
        );

    // verilog-ethernet PHY instantiation

    wire rx_block_lock;
    wire rx_high_ber;

    eth_phy_10g #(
        .BIT_REVERSE(1)
    ) sfpp_eth_10g_phy_inst (
        .tx_clk(xgmii_tx_clk),
        .tx_rst(xgmii_tx_rst),
        .rx_clk(xgmii_rx_clk),
        .rx_rst(xgmii_rx_rst),

        .xgmii_txd(xgmii_tx_data_int),
        .xgmii_txc(xgmii_tx_ctrl_int),
        .xgmii_rxd(xgmii_rx_data),
        .xgmii_rxc(xgmii_rx_ctrl),

        .serdes_tx_data(gt_tx_data),
        .serdes_tx_hdr(gt_tx_header[1:0]),
        .serdes_rx_data(gt_rx_data),
        .serdes_rx_hdr(gt_rx_header[1:0]),
        .serdes_rx_bitslip(gt_rx_gearboxslip),

        .tx_bad_block(),
        .rx_error_count(),
        .rx_bad_block(),
        .rx_sequence_error(),
        .rx_block_lock(rx_block_lock),
        .rx_high_ber(rx_high_ber)
    );

    // To avoid unconnected pin critical warning:
    assign gt_tx_header[5:2] = 4'b0000;

    assign phy_status[0] = rx_block_lock;
    assign phy_status[1] = rx_high_ber;

    // Implement XGMII loopback feature
    assign xgmii_tx_data_int = (phy_control_tx_clk[0]) ? xgmii_rx_data : xgmii_tx_data;
    assign xgmii_tx_ctrl_int = (phy_control_tx_clk[0]) ? xgmii_rx_ctrl : xgmii_tx_ctrl;

    // ---------- XGMII TO AXI4-STREAM BRIDGE INSTANTIATION ----------

    assign axis_rx_clk = xgmii_rx_clk;
    assign axis_rx_rst = xgmii_rx_rst;

    assign axis_tx_clk = xgmii_tx_clk;
    assign axis_tx_rst = xgmii_tx_rst;

    xgmii_axis_bridge #(
        .DATA_WIDTH(64)
    ) sfpp_eth_10g_xgmii_axis_bridge (
        // Clocking & reset
        .rx_clk(xgmii_rx_clk),
        .rx_rst(xgmii_rx_rst),

        .tx_clk(xgmii_tx_clk),
        .tx_rst(xgmii_tx_rst),

        // XGMII interface
        .xgmii_rx_data(xgmii_rx_data),
        .xgmii_rx_ctrl(xgmii_rx_ctrl),

        .xgmii_tx_data(xgmii_tx_data),
        .xgmii_tx_ctrl(xgmii_tx_ctrl),

        // AXI4-Stream interface
        .axis_rx_tready(axis_rx_tready),
        .axis_rx_tvalid(axis_rx_tvalid),
        .axis_rx_tdata (axis_rx_tdata),
        .axis_rx_tlast (axis_rx_tlast),
        .axis_rx_tkeep (axis_rx_tkeep),

        .axis_tx_tready(axis_tx_tready),
        .axis_tx_tvalid(axis_tx_tvalid),
        .axis_tx_tdata (axis_tx_tdata),
        .axis_tx_tlast (axis_tx_tlast),
        .axis_tx_tkeep (axis_tx_tkeep),

        // Error / status signals
        .rx_error_ready(),
        .rx_error_preamble(),
        .rx_error_xgmii(),
        .tx_error_tlast_tkeep()
    );

    // ---------- WISHBONE STATUS & CONTROL LOGIC ----------

    // The status signals generally come from various clock sources, not
    // necessarily synchronized to the wb.clk. Thus perform an unregistered clock
    // domain crossing of the signals.
    wire [$bits(transceiver_status)-1:0] transceiver_status_wbclk;
    wire [        $bits(phy_status)-1:0] phy_status_wbclk;

    xpm_cdc_array_single #(
        .DEST_SYNC_FF(4),
        .INIT_SYNC_FF(0),
        .SIM_ASSERT_CHK(0),
        // Do not register inputs (required for asynchronous signals)
        .SRC_INPUT_REG(0),
        .WIDTH($bits({phy_status, transceiver_status}))
    ) sfpp_eth_10g_status_cdc (
        .dest_out({phy_status_wbclk, transceiver_status_wbclk}),
        .dest_clk(wb.clk),
        .src_clk(),  // Inputs are not registered
        .src_in({phy_status, transceiver_status})
    );

    xpm_cdc_array_single #(
        .DEST_SYNC_FF(4),
        .INIT_SYNC_FF(0),
        .SIM_ASSERT_CHK(0),
        // Do not register inputs (required for asynchronous signals)
        .SRC_INPUT_REG(0),
        .WIDTH($bits({phy_control}))
    ) sfpp_eth_10g_control_tx_clk_cdc (
        .dest_out({phy_control_tx_clk}),
        .dest_clk(xgmii_tx_clk),
        .src_clk(),  // Inputs are not registered
        .src_in({phy_control})
    );


    always @(posedge wb.clk) begin
        wb.ack <= 0;
        if (wb.rst) begin
            wb.dat_o <= 0;
            transceiver_control <= 0;
        end else if (wb.cyc && wb.stb) begin
            wb.ack <= 1;
            if (wb.we) begin
                // Write
                casez (wb.adr[7:0])
                    8'b000010??: transceiver_control <= wb.dat_o;
                    8'b000100??: phy_control <= wb.dat_o;
                endcase
            end else begin
                // Read
                casez (wb.adr[7:0])
                    // Indicate the SFP+ bus slave is present in the design
                    8'b000000??: wb.dat_o <= 1;
                    8'b000001??: wb.dat_o <= transceiver_status_wbclk;
                    8'b000010??: wb.dat_o <= transceiver_control;
                    8'b000011??: wb.dat_o <= phy_status_wbclk;
                    8'b000100??: wb.dat_o <= phy_control;
                    default: wb.dat_o <= 32'h00000000;
                endcase
            end
        end else begin
            wb.dat_o <= 0;
        end
    end

endmodule
