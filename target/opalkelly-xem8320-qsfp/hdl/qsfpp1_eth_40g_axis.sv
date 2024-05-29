/**
 * QSFP+ 40Gbit/s Ethernet instantiation and AXI4-Stream integration.
 *
 * This file is part of Time Tagger software defined digital data acquisition.
 *
 * Copyright (C) 2022-2023 Swabian Instruments, All Rights Reserved
 * Authors:
 *     2022 Leon Schuermann <leon@swabianinstruments.com>
 *     2023 David Sawatzke  <david@swabianinstruments.com>
 *     2023 Ehsan Jokar     <ehsan@swabianinstruments.com>
 *
 * Unauthorized copying of this file is strictly prohibited.
 */

// verilog_format: off
`resetall
`timescale 1ns / 1ps
`default_nettype none
// verilog_format: on

module qsfpp1_eth_40g_axis (
    // Freerunning clock input
    // Should be very roughly at 100Mhz
    input wire freerun_clk,
    input wire freerun_rst,

    // Transceiver reference clock
    input wire mgtrefclk_p,
    input wire mgtrefclk_n,


    // Incoming PLL lock indication
    input wire pll_lock,

    // QSPF+ interface
    input  wire [3:0] qsfpp_rx_p,
    input  wire [3:0] qsfpp_rx_n,
    output wire [3:0] qsfpp_tx_p,
    output wire [3:0] qsfpp_tx_n,

    // AXI4-Stream input (without preamble & FCS, IFG maintained internally)
    output wire axis_tx_clk,
    output wire axis_tx_rst,

    axis_interface.slave axis_tx,

    // AXI4-Stream output (without preamble & FCS)
    output wire axis_rx_clk,
    output wire axis_rx_rst,

    axis_interface.master axis_rx,

    // Wishbone interface for control & status
    wb_interface.slave wb
);

    // ---------- GTWIZARD GTH INSTANTIATION ----------

    // PHY status & control signals
    //
    // CONTROL:
    // - phy_control[0]: Freerun Clk Reset
    // - phy_control[1]: TX Datapath Reset
    // - phy_control[2]: RX Datapath Reset
    // - phy_control[3]: GT TX Datapath Reset : not used
    // - phy_control[4]: GT RX Datapath Reset : not used
    // - phy_control[5]: ctl_tx_test_pattern
    // - phy_control[6]: ctl_rx_test_pattern

    reg [31:0] phy_control;

    logic [10:0] phy_status;

    // PHY loopback control (wired up to PHY loopback control directly)
    reg [11:0] phy_loopback_control;

    wire [$bits(phy_control)-1:0] phy_control_freerun_clk;

    reg [31 : 0] general_rst_cnt = 50000000;

    wire link_up;

    // This signal is used to reset the rx path each 500ms when the rx link is disable.
    reg general_rst;

    always_ff @(posedge freerun_clk) begin
        if (link_up | freerun_rst | general_rst_cnt == 0 | phy_control_freerun_clk[2]) general_rst_cnt <= 50000000;
        else general_rst_cnt <= general_rst_cnt - 1;

        if ((general_rst_cnt > 50000000 - 5000) && (general_rst_cnt < 50000000 - 1)) begin
            general_rst <= 1;
        end else begin
            general_rst <= 0;
        end
    end

    wire freerun_lock_rst;
    sync_reset #(
        .N(4)
    ) qsfpp_freerun_clk_lock_enable_sync (
        .clk(freerun_clk),
        .rst(freerun_rst | !pll_lock | phy_control_freerun_clk[0]),
        .out(freerun_lock_rst)
    );

    // XLGMII interface
    wire xlgmii_tx_clk, xlgmii_tx_rst;
    wire xlgmii_rx_clk, xlgmii_rx_rst;

    logic user_tx_reset, user_rx_reset;

    xpm_cdc_sync_rst #(
        .DEST_SYNC_FF(4),
        .INIT        (1),

        .INIT_SYNC_FF  (0),
        .SIM_ASSERT_CHK(0)
    ) xpm_cdc_sync_tx_rst_inst (
        .dest_rst(xlgmii_tx_rst),
        .dest_clk(xlgmii_tx_clk),
        .src_rst (user_tx_reset)
    );

    xpm_cdc_sync_rst #(
        .DEST_SYNC_FF(4),
        .INIT        (1),

        .INIT_SYNC_FF  (0),
        .SIM_ASSERT_CHK(0)
    ) xpm_cdc_sync_rx_rst_inst (
        .dest_rst(xlgmii_rx_rst),
        .dest_clk(xlgmii_rx_clk),
        .src_rst (user_rx_reset)
    );

    wire  tx_reset;
    logic rx_reset;
    assign axis_tx_clk = xlgmii_tx_clk;
    assign axis_tx_rst = tx_reset | xlgmii_tx_rst;
    assign axis_rx_clk = xlgmii_rx_clk;
    assign axis_rx_rst = rx_reset | xlgmii_rx_rst;

    wire [127:0] xlgmii_tx_data_int;
    wire [ 15:0] xlgmii_tx_ctrl_int;
    wire [127:0] xlgmii_rx_data;
    wire [ 15:0] xlgmii_rx_ctrl;

    wire [127:0] xlgmii_tx_clk_rx_data;
    wire [ 15:0] xlgmii_tx_clk_rx_ctrl;

    xpm_cdc_array_single #(
        .DEST_SYNC_FF(4),
        .INIT_SYNC_FF(0),
        .SIM_ASSERT_CHK(0),
        // Do not register inputs (required for asynchronous signals)
        .SRC_INPUT_REG(0),
        .WIDTH($bits(xlgmii_rx_data))
    ) xlgmii_rx_data_cdc (
        .dest_out(xlgmii_tx_clk_rx_data),
        .dest_clk(xlgmii_tx_clk),
        .src_clk(xlgmii_tx_clk),  // Inputs are not registered
        .src_in(xlgmii_rx_data)
    );
    xpm_cdc_array_single #(
        .DEST_SYNC_FF(4),
        .INIT_SYNC_FF(0),
        .SIM_ASSERT_CHK(0),
        // Do not register inputs (required for asynchronous signals)
        .SRC_INPUT_REG(0),
        .WIDTH($bits(xlgmii_rx_data))
    ) xlgmii_rx_ctrl_cdc (
        .dest_out(xlgmii_tx_clk_rx_ctrl),
        .dest_clk(xlgmii_tx_clk),
        .src_clk(xlgmii_tx_clk),  // Inputs are not registered
        .src_in(xlgmii_rx_ctrl)
    );

    // RX core clock can be looped back from the generated XLGMII RX clock,
    // according to example design:
    wire qsfpp_eth_40g_phy_rx_core_clk;
    assign qsfpp_eth_40g_phy_rx_core_clk = xlgmii_rx_clk;

    wire [$bits(phy_control)-1:0] phy_control_tx_clk;
    wire [$bits(phy_control)-1:0] phy_control_rx_clk;

    xpm_cdc_array_single #(
        .DEST_SYNC_FF(4),
        .INIT_SYNC_FF(0),
        .SIM_ASSERT_CHK(0),
        // Do not register inputs (required for asynchronous signals)
        .SRC_INPUT_REG(0),
        .WIDTH($bits(phy_control))
    ) phy_control_tx_cdc (
        .dest_out(phy_control_tx_clk),
        .dest_clk(xlgmii_tx_clk),
        .src_clk(),  // Inputs are not registered
        .src_in(phy_control)
    );

    xpm_cdc_array_single #(
        .DEST_SYNC_FF(4),
        .INIT_SYNC_FF(0),
        .SIM_ASSERT_CHK(0),
        // Do not register inputs (required for asynchronous signals)
        .SRC_INPUT_REG(0),
        .WIDTH($bits(phy_control))
    ) phy_control_rx_cdc (
        .dest_out(phy_control_rx_clk),
        .dest_clk(xlgmii_rx_clk),
        .src_clk(),  // Inputs are not registered
        .src_in(phy_control)
    );

    xpm_cdc_array_single #(
        .DEST_SYNC_FF(4),
        .INIT_SYNC_FF(0),
        .SIM_ASSERT_CHK(0),
        // Do not register inputs (required for asynchronous signals)
        .SRC_INPUT_REG(0),
        .WIDTH($bits(phy_control))
    ) phy_control_free_running_cdc (
        .dest_out(phy_control_freerun_clk),
        .dest_clk(freerun_clk),
        .src_clk(),  // Inputs are not registered
        .src_in(phy_control)
    );

    xpm_cdc_array_single #(
        .DEST_SYNC_FF(4),
        .INIT_SYNC_FF(0),
        .SIM_ASSERT_CHK(0),
        // Do not register inputs (required for asynchronous signals)
        .SRC_INPUT_REG(0),
        .WIDTH(1)
    ) tx_reset_cdc (
        .dest_out(tx_reset),
        .dest_clk(xlgmii_tx_clk),
        .src_clk(),  // Inputs are not registered
        .src_in(freerun_rst | reset_tx_datapath | phy_control_freerun_clk[1])
    );

    xpm_cdc_array_single #(
        .DEST_SYNC_FF(4),
        .INIT_SYNC_FF(0),
        .SIM_ASSERT_CHK(0),
        // Do not register inputs (required for asynchronous signals)
        .SRC_INPUT_REG(0),
        .WIDTH(1)
    ) rx_reset_cdc (
        .dest_out(rx_reset),
        .dest_clk(xlgmii_rx_clk),
        .src_clk(),  // Inputs are not registered
        .src_in(freerun_rst | phy_control_freerun_clk[2] | general_rst)
    );

    wire rx_core_clk;
    assign rx_core_clk = xlgmii_rx_clk;


    wire rx_aligned;
    wire rx_status;
    reg  reset_tx_datapath;

    qsfpp1_eth_40g_phy qsfpp1_eth_40g_phy_inst (
        // Freerunning clock and synchronous reset (gated by PLL lock)
        .dclk(freerun_clk),
        .sys_reset(freerun_lock_rst),
        // refclk
        .gt_refclk_p(mgtrefclk_p),
        .gt_refclk_n(mgtrefclk_n),
        .rx_core_clk_0(rx_core_clk),

        .gtwiz_reset_tx_datapath_0(0),
        .gtwiz_reset_rx_datapath_0(0),

        // GT instance reference clock selection. Comment from example design:
        // "This value should not be changed as per gtwizard".
        .txoutclksel_in_0({4{3'b101}}),
        .rxoutclksel_in_0({4{3'b101}}),

        // Misc transceiver status
        .gtpowergood_out_0(phy_status[3:0]),

        // QSFP+ interface
        .gt_rxp_in_0 (qsfpp_rx_p[0]),
        .gt_rxn_in_0 (qsfpp_rx_n[0]),
        .gt_txp_out_0(qsfpp_tx_p[0]),
        .gt_txn_out_0(qsfpp_tx_n[0]),
        .gt_rxp_in_1 (qsfpp_rx_p[1]),
        .gt_rxn_in_1 (qsfpp_rx_n[1]),
        .gt_txp_out_1(qsfpp_tx_p[1]),
        .gt_txn_out_1(qsfpp_tx_n[1]),
        .gt_rxp_in_2 (qsfpp_rx_p[2]),
        .gt_rxn_in_2 (qsfpp_rx_n[2]),
        .gt_txp_out_2(qsfpp_tx_p[2]),
        .gt_txn_out_2(qsfpp_tx_n[2]),
        .gt_rxp_in_3 (qsfpp_rx_p[3]),
        .gt_rxn_in_3 (qsfpp_rx_n[3]),
        .gt_txp_out_3(qsfpp_tx_p[3]),
        .gt_txn_out_3(qsfpp_tx_n[3]),

        // XLGMII bus clock and data
        .tx_mii_clk_0(xlgmii_tx_clk),
        .tx_mii_d_0(xlgmii_tx_data_int),
        .tx_mii_c_0(xlgmii_tx_ctrl_int),
        .user_tx_reset_0(user_tx_reset),
        .rx_clk_out_0(xlgmii_rx_clk),
        .rx_mii_d_0(xlgmii_rx_data),
        .rx_mii_c_0(xlgmii_rx_ctrl),
        .user_rx_reset_0(user_rx_reset),

        .rxrecclkout_0(),
        .gt_loopback_in_0(phy_loopback_control),

        .rx_reset_0(rx_reset),

        // RX_0 Control Signals
        .ctl_rx_test_pattern_0(phy_control_rx_clk[6]),

        // RX_0 Stats Signals
        .stat_rx_misaligned_0(phy_status[4]),
        .stat_rx_bip_err_0_0(phy_status[5]),
        .stat_rx_bip_err_1_0(phy_status[6]),
        .stat_rx_bip_err_2_0(phy_status[7]),
        .stat_rx_bip_err_3_0(phy_status[8]),
        .stat_rx_aligned_0(rx_aligned),
        .stat_rx_hi_ber_0(phy_status[9]),
        .stat_rx_status_0(rx_status),
        .stat_rx_local_fault_0(phy_status[10]),

        // TX_0 Signals
        .tx_reset_0(tx_reset),

        // TX_0 Control Signals
        .ctl_tx_test_pattern_0(phy_control_tx_clk[5])
    );

    xpm_cdc_array_single #(
        .WIDTH(1)
    ) rx_aligned_cdc (
        .dest_out(link_up),
        .dest_clk(freerun_clk),
        .src_clk (xlgmii_rx_clk),
        .src_in  (rx_aligned & rx_status)
    );

    // RESET TX CORE FOR 1S AFTER FREERUN_RST
    reg [27:0] reset_counter;
    always_ff @(posedge freerun_clk) begin
        if (freerun_rst) begin
            reset_counter <= 100000000;
            reset_tx_datapath <= 1;
        end else begin
            if (reset_counter > 0) begin
                reset_counter <= reset_counter - 1;
            end else begin
                reset_tx_datapath <= 0;
            end
        end
    end

    // ---------- XGMII TO AXI4-STREAM BRIDGE INSTANTIATION ----------

    xlgmii_axis_bridge bridge (

        .xlgmii_rx_data(xlgmii_rx_data),
        .xlgmii_rx_ctrl(xlgmii_rx_ctrl),
        .xlgmii_tx_data(xlgmii_tx_data_int),
        .xlgmii_tx_ctrl(xlgmii_tx_ctrl_int),

        .axis_tx(axis_tx),
        .axis_rx(axis_rx)
    );

    // ---------- WISHBONE STATUS & CONTROL LOGIC ----------

    // The status signals generally come from various clock sources, not
    // necessarily synchronized to the wb.clk. Thus perform an unregistered clock
    // domain crossing of the signals.
    wire [$bits(phy_status)-1:0] phy_status_wbclk;
    xpm_cdc_array_single #(
        .DEST_SYNC_FF(4),
        .INIT_SYNC_FF(0),
        .SIM_ASSERT_CHK(0),
        // Do not register inputs (required for asynchronous signals)
        .SRC_INPUT_REG(0),
        .WIDTH($bits(phy_status))
    ) phy_status_cdc (
        .dest_out(phy_status_wbclk),
        .dest_clk(wb.clk),
        .src_clk(),  // Inputs are not registered
        .src_in(phy_status)
    );


    always @(posedge wb.clk) begin
        wb.ack <= 0;
        if (wb.rst) begin
            wb.dat_o             <= 0;
            phy_control          <= 0;  // Don't reset anything!
            phy_loopback_control <= 0;
        end else if (wb.cyc && wb.stb) begin
            wb.ack <= 1;
            if (wb.we) begin
                // Write
                casez (wb.adr)
                    8'b000010??: phy_control <= wb.dat_i;
                    8'b000011??: phy_loopback_control <= wb.dat_i;
                endcase
            end else begin
                // Read
                casez (wb.adr)
                    // Indicate the SFP+ bus slave is present in the design
                    8'b000000??: wb.dat_o <= 1;
                    8'b000001??: wb.dat_o <= phy_status_wbclk;
                    8'b000010??: wb.dat_o <= phy_control;
                    8'b000011??: wb.dat_o <= phy_loopback_control;
                    default: wb.dat_o <= 32'h00000000;
                endcase
            end
        end else begin
            wb.dat_o <= 0;
        end
    end

endmodule
