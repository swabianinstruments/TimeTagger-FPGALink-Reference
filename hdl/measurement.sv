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
 * - 2024 Loghman Rahimzadeh <loghman@swabianinstruments.com>
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
    wb_interface.slave wb_combination,

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
        m_axis_user_sample (), m_axis_histogram (), m_axis_counter (), m_axis_combination ();

    axis_tag_broadcast #(
        .FANOUT(4)
    ) axis_tag_broadcast_inst (
        .s_axis(s_axis),
        .m_axis({m_axis_user_sample, m_axis_histogram, m_axis_counter, m_axis_combination})
    );

    // --------------------------------------------------- //
    // ------------------- User_sample ------------------- //
    // --------------------------------------------------- //

    user_sample user_design (
        .s_axis(m_axis_user_sample),
        .wb(wb_user_sample),
        .led(led)
    );

    // --------------------------------------------------- //
    // -------------------- Histogram -------------------- //
    // --------------------------------------------------- //

    histogram_wrapper #(
        .WISHBONE_INTERFACE_EN(1),
        .CHANNEL_WIDTH(m_axis_histogram.CHANNEL_WIDTH),
        .SHIFT_WIDTH($clog2(m_axis_histogram.TIME_WIDTH))
    ) histogram_wrapper_inst (
        .s_axis(m_axis_histogram),

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
        .WINDOW_WIDTH(m_axis_counter.TIME_WIDTH),
        .CHANNEL_WIDTH(m_axis_counter.CHANNEL_WIDTH)
    ) counter_wrapper_inst (
        .s_axis(m_axis_counter),

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
    // ------------------ Combinations ------------------- //
    // --------------------------------------------------- //
    localparam NUM_OF_CHANNELS = 16;
    localparam ACC_WIDTH = 32;
    localparam COMB_FIFO_DEPTH = 8192;

    combination_interface #(
        .TIME_WIDTH(m_axis_combination.TIME_WIDTH),
        .CHANNELS_IN_WIDTH(m_axis_combination.CHANNEL_WIDTH),
        .CHANNELS(NUM_OF_CHANNELS),
        .ACC_WIDTH(ACC_WIDTH)
    ) m_comb_i ();


    assign m_comb_i.ready_i = 0;
    assign m_comb_i.window = 0;
    assign m_comb_i.filter_max = 0;
    assign m_comb_i.filter_min = 0;
    assign m_comb_i.capture_enable = 0;
    assign m_comb_i.start_reading = 0;
    assign m_comb_i.select_comb_fifo = 0;
    assign m_comb_i.reset_comb = 0;
    assign m_comb_i.lut_WrRd = 0;
    assign m_comb_i.lut_addr = 0;
    assign m_comb_i.lut_dat_i = 0;

    combination_wrapper #(
        .WISHBONE_INTERFACE_EN(1),
        .HISTOGRAM_EN(1),
        .NUM_OF_CHANNELS(NUM_OF_CHANNELS),
        .ACC_WIDTH(ACC_WIDTH),
        .FIFO_DEPTH(COMB_FIFO_DEPTH)
    ) combination_wrapper_inst (
        // input information of channel
        .s_time(m_axis_combination),

        // Wishbone interface for control & status //
        .wb(wb_combination),

        // configuration and readout form combination when no wishbone is instantiated in bitfile generation(standalone)
        .s_comb_i(m_comb_i.slave)
    );

    // --------------------------------------------------- //
    // -------------- ADD YOUR MODULES HERE -------------- //
    // --------------------------------------------------- //


endmodule
