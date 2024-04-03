/**
 * Ethernet data processing channel
 *
 * This file is part of the Time Tagger software defined digital data
 * acquisition FPGA-link reference design.
 *
 * Copyright (C) 2022 Swabian Instruments, All Rights Reserved
 *
 * Authors:
 * - 2022-2024 David Sawatzke <david@swabianinstruments.com>
 * - 2023-2024 Ehsan Jokar <ehsan@swabianinstruments.com>
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

module si_data_channel #(
    parameter STATISTICS = 0
) (
    wb_interface.slave wb_statistics,
    axis_interface.slave s_axis,
    axis_interface.master m_axis
);
    initial begin

        // Some sanity checks:

        // - ensure that the input data-width is 128 bits, this is the only width supported by this module
        if (s_axis.DATA_WIDTH != 128) begin
            $error("Error: s_axis.DATA_WIDTH needs to be 128 bits");
            $finish;
        end
        // - ensure that the output data-width is a multiple of 32 bits, to not split tags
        if ((m_axis.DATA_WIDTH % 32) != 0) begin
            $error("Error: m_axis.DATA_WIDTH needs to be a multiple of 32 bits");
            $finish;
        end
    end

    axis_interface #(.DATA_WIDTH(s_axis.DATA_WIDTH))
        filtered_axis (
            .clk(s_axis.clk),
            .rst(s_axis.rst)
        ),
        unpacked_axis (
            .clk(s_axis.clk),
            .rst(s_axis.rst)
        );

    wire lost_packet;
    wire invalid_packet;

    // This component filters out invalid frames (or non-recognized ones, like ARP)
    si_header_parser header_parser (
        .s_axis(s_axis),
        .m_axis(filtered_axis),

        .lost_packet(lost_packet),
        .invalid_packet(invalid_packet)
    );

    si_header_detacher header_detacher (

        .s_axis(filtered_axis),
        .m_axis(unpacked_axis)
    );

    axis_adapter #(
        .S_DATA_WIDTH(s_axis.DATA_WIDTH),
        .M_DATA_WIDTH(m_axis.DATA_WIDTH),
        .USER_WIDTH  (32)
    ) width_adpter (
        .clk(unpacked_axis.clk),
        .rst(unpacked_axis.rst),

        .s_axis_tvalid(unpacked_axis.tvalid),
        .s_axis_tready(unpacked_axis.tready),
        .s_axis_tdata (unpacked_axis.tdata),
        .s_axis_tlast (unpacked_axis.tlast),
        .s_axis_tkeep (unpacked_axis.tkeep),
        .s_axis_tuser (unpacked_axis.tuser),

        .m_axis_tvalid(m_axis.tvalid),
        .m_axis_tready(m_axis.tready),
        .m_axis_tdata (m_axis.tdata),
        .m_axis_tlast (m_axis.tlast),
        .m_axis_tkeep (m_axis.tkeep),
        .m_axis_tuser (m_axis.tuser)
    );

    generate
        if (STATISTICS == 1) begin
            si_statistics_wb #(
                .DATA_WIDTH(s_axis.DATA_WIDTH)
            ) statistics (
                .clk(s_axis.clk),
                .rst(s_axis.rst),
                .pre_axis_tvalid(s_axis.tvalid),
                .pre_axis_tready(s_axis.tready),
                .pre_axis_tlast(s_axis.tlast),
                .post_axis_tvalid(unpacked_axis.tvalid),
                .post_axis_tdata(unpacked_axis.tdata),
                .post_axis_tkeep(unpacked_axis.tkeep),
                .post_axis_tready(unpacked_axis.tready),
                .post_axis_tlast(unpacked_axis.tlast),

                .lost_packet(lost_packet),
                .invalid_packet(invalid_packet),

                .wb(wb_statistics)
            );

        end
    endgenerate

endmodule  // si_data_channel
