/**
 * AXI4-Stream Ethernet Frame Check Sequence Checker for streams of
 * 128-bit data words.
 *
 * This file is part of the Time Tagger software defined digital data
 * acquisition FPGA-link reference design.
 *
 * Copyright (C) 2022 Swabian Instruments, All Rights Reserved
 *
 * Authors:
 * - 2022 David Sawatzke <david@swabianinstruments.com>
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

// Checks the crc value of ethernet packets and removes it
module eth_axis_fcs_checker_128b (

    axis_interface.slave  s_axis,
    axis_interface.master m_axis
);

    initial begin
        if (s_axis.DATA_WIDTH != 128) begin
            $error("Error: s_axis.DATA_WIDTH needs to be 128 bits");
            $finish;
        end

        if (m_axis.DATA_WIDTH != 128) begin
            $error("Error: m_axis.DATA_WIDTH needs to be 128 bits");
            $finish;
        end
    end

    assign m_axis.tkeep = {(m_axis.KEEP_WIDTH) {1'b1}};

    localparam [31:0] initial_fcs_state = 32'hFFFFFFFF;
    reg  [31:0] fcs_state;
    wire [31:0] fcs_state_next;
    wire [31:0] expected_crc;

    // The combinational CRC module seems to be too complex for Verilator to
    // parse / optimize. Thus, when running in Verilator, replace it by some
    // stupid signal assignments such that linting still works. This will
    // cause Verilator-simulations to behave incorrectly. Should be fixable by
    // resorting to the more generic and iteratively evaluated 128-bit
    // verilog-ethernet LFSR module?
`ifndef VERILATOR
    eth_crc_128b_comb eth_crc_128b_comb_inst (
        .state_in (fcs_state),
        .data_in  (s_axis.tdata),
        .state_out(fcs_state_next)
    );
`else
    // See the comment above, this is a dummy statement!
    assign fcs_state_next = fcs_state ^ {31'h0, &s_axis.tdata};
`endif

    always @(posedge s_axis.clk) begin
        if (s_axis.rst) begin
            fcs_state <= initial_fcs_state;
        end else begin
            if (s_axis.tvalid && s_axis.tready) begin
                // If the data is valid, forward the FCS state
                fcs_state <= fcs_state_next;

                if (s_axis.tlast) begin
                    // If this is the last input word, reset the fcs_state to the initial state value.
                    fcs_state <= initial_fcs_state;
                end
            end
        end
    end

    // Small buffer to invalidate packet if needed & cut off last word (only containing crc value)
    // Always keep one data word here while a packet is received
    reg [127:0] tdata;
    reg         valid;
    reg         fifo_valid;
    reg         last;
    reg         invalid;

    always @(posedge s_axis.clk) begin
        if (s_axis.rst) begin
            tdata <= 0;
            valid <= 0;
        end else if (s_axis.tready && s_axis.tvalid) begin
            if (valid) begin
                valid <= 0;
            end
            if (!s_axis.tlast) begin
                tdata <= s_axis.tdata;
                valid <= 1;
            end
        end
    end

    assign expected_crc = ~fcs_state;

    always @(*) begin
        if (!s_axis.rst && s_axis.tvalid && s_axis.tready && s_axis.tlast) begin
            last = 1;
            if ((expected_crc) == s_axis.tdata[31:0]) begin
                invalid = 0;
            end else begin
                // axis_fifo removes the whole package from the fifo
                invalid = 1;
            end
        end else begin
            invalid = 0;
            last = 0;
        end
        fifo_valid = valid && s_axis.tready && s_axis.tvalid;
    end

    // Small fifo to be able to drop packets if needed
    // We need ~10000 bytes, so a depth of at least 612. Since block rams have at a depth of n * 512, go to a depth of 1024
    //
    /* verilator lint_off PINMISSING*/
    axis_fifo #(
        .DEPTH(1024),
        .DATA_WIDTH(128),
        .KEEP_ENABLE(0),
        .FRAME_FIFO(1),
        .DROP_OVERSIZE_FRAME(1),
        .DROP_BAD_FRAME(1)
    ) fifo (
        .clk(s_axis.clk),
        .rst(s_axis.rst),

        .s_axis_tdata(tdata),
        .s_axis_tvalid(fifo_valid),
        .s_axis_tuser(invalid),
        .s_axis_tlast(last),
        .s_axis_tready(s_axis.tready), // This may lead to the module not being ready when in could be when the buffer gets full, but simplifies the logic and shouldn't happen anyway

        .m_axis_tdata (m_axis.tdata),
        .m_axis_tvalid(m_axis.tvalid),
        .m_axis_tready(m_axis.tready),
        .m_axis_tlast (m_axis.tlast)
        // TODO pass the overflow signal through?
    );
    /*v verilator lint_on PINMISSING*/

    // Unused signals as per Verilator guidelines:
    // https://verilator.org/guide/latest/warnings.html
    wire _unused_ok = &{1'b0, s_axis.tkeep, 1'b0};
endmodule
