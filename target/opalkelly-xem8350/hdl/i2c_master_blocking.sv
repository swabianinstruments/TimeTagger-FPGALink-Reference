/**
 * Blocking State Machine Wrapper Around Wishbone-I2C core.
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

module i2c_master_blocking (
    input wire        wb_clk_i,
    input wire        wb_rst_i,
    input wire [2:0]  wb_adr_i,
    input wire [7:0]  wb_dat_i,
    output wire [7:0] wb_dat_o,
    input wire        wb_we_i,
    input wire        wb_stb_i,
    input wire        wb_cyc_i,
    output reg        wb_ack_o,
    output wire       wb_inta_o,

    input wire        scl_pad_i,
    output wire       scl_pad_o,
    output wire       scl_padoen_o,
    input wire        sda_pad_i,
    output wire       sda_pad_o,
    output wire       sda_padoen_o
);

    // Instantiate the regular I2C slave, with the appropriate switched signals:
    reg [2:0]  i2c_wb_adr_o;
    reg [7:0]  i2c_wb_dat_o;
    wire [7:0] i2c_wb_dat_i;
    reg        i2c_wb_cyc_o;
    reg        i2c_wb_stb_o;
    wire       i2c_wb_ack_i;
    reg        i2c_wb_we_o;

    i2c_master_top i2c_wb (
        .wb_clk_i(wb_clk_i),
        .wb_rst_i(wb_rst_i),
        .arst_i(1),
        .wb_adr_i(i2c_wb_adr_o),
        .wb_dat_i(i2c_wb_dat_o),
        .wb_dat_o(i2c_wb_dat_i),
        .wb_we_i(i2c_wb_we_o),
        .wb_stb_i(i2c_wb_stb_o),
        .wb_cyc_i(i2c_wb_cyc_o),
        .wb_ack_o(i2c_wb_ack_i),
        .wb_inta_o(wb_inta_o),

        .scl_pad_i(scl_pad_i),
        .scl_pad_o(scl_pad_o),
        .scl_padoen_o(scl_padoen_o),
        .sda_pad_i(sda_pad_i),
        .sda_pad_o(sda_pad_o),
        .sda_padoen_o(sda_padoen_o));

    // Pass through data from the I2C core.
    reg [7:0] i2c_wb_dat_i_buf;
    assign wb_dat_o = i2c_wb_dat_i_buf;

    reg [1:0] state;

    always @(posedge wb_clk_i) begin
        wb_ack_o <= 1'b0;
        i2c_wb_stb_o <= 1'b0;

        if (wb_rst_i) begin
            state <= 1'b0;

            i2c_wb_adr_o <= {3{1'bx}};
            i2c_wb_dat_o <= {8{1'bx}};
            i2c_wb_cyc_o <= 1'b0;
            i2c_wb_stb_o <= 1'b0;
            i2c_wb_we_o <= 1'bx;
        end else if (state == 0) begin
            if (wb_stb_i && wb_cyc_i) begin
                i2c_wb_cyc_o <= 1'b1;
                i2c_wb_stb_o <= 1'b1;
                i2c_wb_adr_o <= wb_adr_i;
                i2c_wb_dat_o <= wb_dat_i;
                i2c_wb_we_o <= wb_we_i;
                state = 1;
            end
        end else if (state == 1) begin
            i2c_wb_stb_o <= 1'b0;

            if (i2c_wb_ack_i) begin
                // The slave has responsed, store the original response.
                i2c_wb_dat_i_buf <= i2c_wb_dat_i;

                // Transition to the next state, which will repeatedly query the
                // i2c_busy status flag:
                state = 2;
            end
        end else if (state == 2) begin
            i2c_wb_stb_o <= 1'b1;
            i2c_wb_adr_o <= 6; // command register read
            i2c_wb_dat_o <= 0;
            i2c_wb_we_o <= 1'b0;
            state <= 3;
        end else if (state == 3) begin
            i2c_wb_stb_o <= 1'b0;

            if (i2c_wb_ack_i) begin
                if (i2c_wb_dat_i[7:4] != 0) begin
                    state <= 2;
                end else begin
                    wb_ack_o <= 1'b1;
                    i2c_wb_cyc_o <= 1'b0;
                    state <= 0;
                end
            end
        end
    end

endmodule

`resetall
