/**
 * measurement module: Add all your modules here!
 *
 * This file is part of the Time Tagger software defined digital data
 * acquisition FPGA-link reference design.
 *
 * Copyright (C) 2022-2024 Swabian Instruments, All Rights Reserved
 *
 * Authors:
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

module measurement (
    axis_tag_interface.slave s_axis,

    wb_interface.slave wb_user_sample,
    wb_interface.slave wb_histogram,
    wb_interface.slave wb_counter,

    //------------------------------------------//
    //-- connect wb interface to your modules --//

    // wb_interface.slave      wb_your_module_1,
    // wb_interface.slave      wb_your_module_2,

    output reg [5:0] led
);

    // Distribute the AXI bus to all measurements
    axis_tag_interface #(
        .WORD_WIDTH(s_axis.WORD_WIDTH),
        .TIME_WIDTH(s_axis.TIME_WIDTH),
        .CHANNEL_WIDTH(s_axis.CHANNEL_WIDTH)
    )
        m_axis_user_sample (), m_axis_histogram (), m_axis_counter ();
    axis_broadcast #(
        .FANOUT(3)
    ) axis_broadcast_inst (
        .s_axis(s_axis),
        .m_axis({m_axis_user_sample, m_axis_histogram, m_axis_counter})
    );

    /* The measurement module supplies tag times and their corresponding channels in
   an unpacked format. In case your modules receive data in a packed format, we also
   provide you with the packed tag times and channels.*/
    localparam integer WORD_WIDTH = s_axis.WORD_WIDTH;
    localparam integer TIME_WIDTH = s_axis.TIME_WIDTH;
    localparam integer CHANNEL_WIDTH = s_axis.CHANNEL_WIDTH;
    logic [TIME_WIDTH*WORD_WIDTH-1:0] s_axis_tagtime_packed;
    logic [CHANNEL_WIDTH*WORD_WIDTH-1:0] s_axis_channel_packed;

    always_comb begin
        for (int i = 0; i < WORD_WIDTH; i++) begin
            s_axis_tagtime_packed[i*TIME_WIDTH+:TIME_WIDTH] <= s_axis.tagtime[i];
            s_axis_channel_packed[i*CHANNEL_WIDTH+:CHANNEL_WIDTH] <= s_axis.channel[i];
        end
    end


    // --------------------------------------------------- //
    // ------------------- User_sample ------------------- //
    // --------------------------------------------------- //

    user_sample #(
        .WORD_WIDTH(m_axis_user_sample.WORD_WIDTH)
    ) user_design (
        .clk(m_axis_user_sample.clk),
        .rst(m_axis_user_sample.rst),

        .s_axis_tvalid (m_axis_user_sample.tvalid),
        .s_axis_tready (m_axis_user_sample.tready),
        .s_axis_tkeep  (m_axis_user_sample.tkeep),
        .s_axis_channel(m_axis_user_sample.channel),
        .s_axis_tagtime(m_axis_user_sample.tagtime),

        .wb(wb_user_sample),

        .led(led)
    );

    // --------------------------------------------------- //
    // -------------------- Histogram -------------------- //
    // --------------------------------------------------- //

    histogram_wrapper #(
        .WISHBONE_INTERFACE_EN(1),
        .NUM_OF_TAGS(m_axis_histogram.WORD_WIDTH)
    ) histogram_wrapper_inst (
        .clk(m_axis_histogram.clk),
        .rst(m_axis_histogram.rst),
        .tagtime(s_axis_tagtime_packed),
        .channel(s_axis_channel_packed),
        .valid_tag(m_axis_histogram.tvalid ? m_axis_histogram.tkeep : '0),
        .tready(m_axis_histogram.tready),

        .wb(wb_histogram),

        /*If you intend to process histogram data within the FPGA, set "WISHBONE_INTERFACE_EN"
       to zero. Utilize the signals below to interface with this module. Refer to the
       "histogram_wrapper" and "histogram" modules for guidance on transmitting
       configuration data and receiving output data.*/
        .hist_read_start_i(),
        .hist_reset_i(),
        .config_en_i(),
        .click_channel_i(),
        .start_channel_i(),
        .shift_val_i(),
        .data_out_o(),
        .valid_out_o(),
        .statistics_valid(),
        .index_max(),
        .offset(),
        .variance()
    );

    // --------------------------------------------------- //
    // --------------------- Counter --------------------- //
    // --------------------------------------------------- //
    /* This module is designed to measure the number of tags received in each
     channel continuously. */
    counter_wrapper #(
        .WISHBONE_INTERFACE_EN(1),
        .NUM_OF_TAGS(m_axis_counter.WORD_WIDTH)
    ) counter_wrapper_inst (
        .clk(m_axis_counter.clk),
        .rst(m_axis_counter.rst),
        .tagtime(s_axis_tagtime_packed),
        .lowest_time_bound(m_axis_counter.lowest_time_bound),
        .channel(s_axis_channel_packed),
        .valid_tag(m_axis_counter.tvalid ? m_axis_counter.tkeep : '0),
        .tready(m_axis_counter.tready),
        .wb(wb_counter),
        /*If you intend to process counter data within the FPGA , set "WISHBONE_INTERFACE_EN"
     to zero. Utilize the signals below to interface with this module.*/
        .window_size_i(),
        .start_counting_i(),
        .reset_module_i(),
        .channel_lut_i(),
        .count_data_o(),
        .count_valid_o()
    );
    // --------------------------------------------------- //
    // -------------- ADD YOUR MODULES HERE -------------- //
    // --------------------------------------------------- //


endmodule
