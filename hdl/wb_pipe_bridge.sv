/**
 * Wishbone OpallKelly Block-Throttled Pipe Bridge.
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

module wb_pipe_bridge #(
    parameter BLOCK_CNT = 4,
    parameter BTPIPEIN_ADDR,
    parameter BTPIPEOUT_ADDR
) (
    input wire               okClk,
    input wire               okRst,
    input wire [112:0]       okHE,
    output wire [64:0]       okEH,

    wb_interface.master_port wb_master
);

    // The Wishbone bridge communicates via 2 block-throttled pipes. The okEH
    // signal exposed by this module thus is an OR of their respective return
    // signals.
    wire [64:0]        okEH_BtPipeIn;
    wire [64:0]        okEH_BtPipeOut;
    okWireOR #(
        .N(2))
    okWireOR_wb_pipe_bridge_inst (
        .okEH(okEH),
        .okEHx({
            okEH_BtPipeIn,
            okEH_BtPipeOut
        }));

    // Wishbone bridge request input state.
    reg [(BLOCK_CNT*128)-1:0] wbbridge_pipe_in_buf;
    reg [(BLOCK_CNT*4)-1:0]   wbbridge_pipe_in_buf_msk;
    wire [31:0]               wbbridge_pipe_in_data;
    wire                      wbbridge_pipe_in_data_valid;

    // Wishbone bridge request input interface.
    reg                       wbbridge_in_ready;
    wire [63:0]               wbbridge_in_data;
    wire                      wbbridge_in_valid;
    assign wbbridge_in_data = wbbridge_pipe_in_buf[63:0];
    assign wbbridge_in_valid = &wbbridge_pipe_in_buf_msk[1:0];

    okBTPipeIn okBTPipeIn_inst (
        .okHE(okHE),
        .okEH(okEH_BtPipeIn),
        .ep_addr(BTPIPEIN_ADDR),
        .ep_dataout(wbbridge_pipe_in_data),
        .ep_write(wbbridge_pipe_in_data_valid),
        .ep_blockstrobe(),
        .ep_ready(!wbbridge_pipe_in_buf_msk[0]));

    always @(posedge okClk) begin
        if (okRst) begin
            wbbridge_pipe_in_buf <= {(BLOCK_CNT*128){1'bx}};
            wbbridge_pipe_in_buf_msk <= {(BLOCK_CNT*4){1'b0}};
        end else if (wbbridge_pipe_in_buf_msk[0]) begin
            // Outstanding requests have been loaded in the FIFO, wait for ready
            // to process them:
            if (wbbridge_in_ready) begin
                wbbridge_pipe_in_buf <= {
                    {64{1'bx}},
                    wbbridge_pipe_in_buf[(BLOCK_CNT*128)-1:64]
                };
                wbbridge_pipe_in_buf_msk <= {
                    2'b0,
                    wbbridge_pipe_in_buf_msk[(BLOCK_CNT*4)-1:2]
                };
            end
        end else begin
            // Load new Wishbone requests from the Pipe.
            if (wbbridge_pipe_in_data_valid) begin
                wbbridge_pipe_in_buf <= {
                    wbbridge_pipe_in_data,
                    wbbridge_pipe_in_buf[(BLOCK_CNT*128)-1:32]
                };
                wbbridge_pipe_in_buf_msk <= {
                    1'b1,
                    wbbridge_pipe_in_buf_msk[(BLOCK_CNT*4)-1:1]
                };
            end
        end
    end

    // Wishbone bridge response output pipe state.
    reg [(BLOCK_CNT*128)-1:0] wbbridge_pipe_out_buf;
    reg [(BLOCK_CNT*4)-1:0]   wbbridge_pipe_out_buf_msk;
    wire                      wbbridge_pipe_out_read;
    reg [31:0]                wbbridge_pipe_out_data;

    // Wishbone bridge response output interface.
    wire                      wbbridge_out_ready;
    reg [63:0]                wbbridge_out_data;
    reg                       wbbridge_out_valid;
    assign wbbridge_out_ready = !wbbridge_pipe_out_buf_msk[0];

    okBTPipeOut okBTPipeOut_inst (
        .okHE(okHE),
        .okEH(okEH_BtPipeOut),
        .ep_addr(BTPIPEOUT_ADDR),
        .ep_datain(wbbridge_pipe_out_data),
        .ep_read(wbbridge_pipe_out_read),
        .ep_blockstrobe(),
        .ep_ready(wbbridge_pipe_out_buf_msk[0]));

    always @(posedge okClk) begin
        if (okRst) begin
            wbbridge_pipe_out_buf <= {(BLOCK_CNT*128){1'bx}};
            wbbridge_pipe_out_buf_msk <= {(BLOCK_CNT*4){1'b0}};
        end else if (wbbridge_pipe_out_buf_msk[0]) begin
            // We need to shift out response data into the Pipe.
            if (wbbridge_pipe_out_read) begin
                wbbridge_pipe_out_buf <= {
                    {32{1'bx}},
                    wbbridge_pipe_out_buf[(BLOCK_CNT*128)-1:32]
                };
                wbbridge_pipe_out_buf_msk <= {
                    1'b0,
                    wbbridge_pipe_out_buf_msk[(BLOCK_CNT*4)-1:1]
                };
                wbbridge_pipe_out_data <= wbbridge_pipe_out_buf[31:0];
            end
        end else begin
            // Accept response data from the state machine below.
            if (wbbridge_out_valid) begin
                wbbridge_pipe_out_buf <= {
                    wbbridge_out_data,
                    wbbridge_pipe_out_buf[(BLOCK_CNT*128)-1:64]
                };
                wbbridge_pipe_out_buf_msk <= {
                    2'b11,
                    wbbridge_pipe_out_buf_msk[(BLOCK_CNT*4)-1:2]
                };
            end
        end
    end

    // Wishbone bridge master state machine.
    reg        wb_master_cyc_or;
    reg        wb_master_stb_or;
    // 31 bit, the upper address bit is statically driven to 1, given its used
    // to encode read/write through Wishbone bridge. Lower half of address space
    // is reserved for chip-local peripherals such as ROM/RAM for a softcore.
    reg [30:0] wb_master_adr_or;
    reg [31:0] wb_master_dat_or;
    reg        wb_master_we_or;

    assign wb_master.clk = okClk;
    assign wb_master.rst = okRst;
    assign wb_master.wb_cyc_o = wb_master_cyc_or;
    assign wb_master.wb_stb_o = wb_master_stb_or;
    assign wb_master.wb_adr_o = {1'b1, wb_master_adr_or};
    assign wb_master.wb_dat_o = wb_master_dat_or;
    assign wb_master.wb_we_o = wb_master_we_or;

    always @(posedge okClk) begin
        if (okRst) begin
            wb_master_cyc_or <= 1'b0;
            wb_master_stb_or <= 1'b0;
            wb_master_adr_or <= {31{1'bx}};
            wb_master_dat_or <= {32{1'bx}};
            wb_master_we_or <= 1'bx;
        end else begin
            // Default drivers: don't accept new incoming Wishbone
            // requests, ...
            wbbridge_in_ready <= 1'b0;
            // ... and assert stb for a single cycle only:
            wb_master_stb_or <= 1'b0;

            // Wait for potential feedback to be accepted by the output buffer:
            if (!wbbridge_out_valid || wbbridge_out_ready) begin
                // Either we aren't inserting feedback in this cycle or it was
                // accepted, in any case it's safe to deassert valid now:
                wbbridge_out_valid <= 1'b0;

                // Use the wb_cyc signal as an indication whether we are
                // currently in the midst of a bus transaction.
                if (wb_master_cyc_or) begin
                    // Only act when we have an ACK.
                    if (wb_master.wb_ack_i) begin
                        // Got an ACK in this very cycle, insert feedback into
                        // the output FIFO.
                        wbbridge_out_valid <= 1'b1;
                        wbbridge_out_data <= {
                            wb_master_we_or,
                            wb_master_adr_or,
                            wb_master.wb_dat_i
                        };

                        // Also, deassert stb and cyc.
                        wb_master_cyc_or <= 1'b0;
                        wb_master_stb_or <= 1'b0;
                    end
                end
                else if (wbbridge_in_valid) begin
                    // This word contains the data, accept it:
                    wbbridge_in_ready <= 1'b1;

                    // Set the appropriate bus values:
                    wb_master_cyc_or <= 1'b1;
                    wb_master_stb_or <= 1'b1;
                    wb_master_adr_or <= wbbridge_in_data[62:32];
                    wb_master_we_or <= wbbridge_in_data[63];
                    wb_master_dat_or <= wbbridge_in_data[31:0];
                end
            end
        end
    end

endmodule

`resetall
