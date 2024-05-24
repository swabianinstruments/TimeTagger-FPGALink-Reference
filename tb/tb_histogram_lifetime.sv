/**
 * Testbench for the histogram module
 *
 * This file is part of the Time Tagger software defined digital data
 * acquisition FPGA-link reference design.
 *
 * Copyright (C) 2024 Swabian Instruments, All Rights Reserved
 *
 * This file is provided under the terms and conditions of the BSD 3-Clause
 * license, accessible under https://opensource.org/licenses/BSD-3-Clause.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

// verilog_format: off
 `resetall
 `timescale 1ns / 10fs
 `default_nettype none
// verilog_format: on

module tb_histogram_lifetime #(
    parameter integer WORD_WIDTH = 4,    // Amount of events processed in parallel by the histogram
    parameter integer DETECTORS = 4,     // Amount of simulated single photon detectors
    parameter integer FLUORESCENCES = 50 // Amount of simulated single photon generators, should be sufficiently large
) ();

    // Random number generator seed used in this testbench
    integer seed = $random();

    ///////////////////////////////
    // CH 1: 80 MHz pulsed laser //
    ///////////////////////////////
    reg laser_optical = 0;
    reg laser_electrical = 0;
    always begin
        laser_optical <= 1;
        #2.5ns;  // 2.5ns HIGH
        laser_optical <= 0;
        #($dist_normal(seed, 1000000, 100) * 10fs);  // 10 ns +- 1ps RMS: LOW
    end
    always @(laser_optical) begin
        #($dist_normal(seed, 10000, 1000) * 10fs);  // 100 ps delay +- 10ps electrical jitter
        laser_electrical <= laser_optical;
    end

    ///////////////////////////////////////
    // Experiment: Fluorescence lifetime //
    ///////////////////////////////////////
    reg [DETECTORS-1 : 0] detector_in = 0;  // events are encoded as state toggle
    generate
        for (genvar i = 0; i < FLUORESCENCES; i++) begin
            reg fluorescence = 0;
            always @(posedge laser_optical) begin
                // Note: This always block cannot be triggered twice in parallel, so decay time must be much smaller than the laser period to be accurate.
                //       However with more simulated fluorescence, the efficiency each goes down and so the result gets better.
                if ($dist_uniform(seed, 0, 100 * FLUORESCENCES - 1) < 50) begin  // overall 50% quantum efficiency
                    #($dist_exponential(seed, 3500) * 1ps);  // 3.5ns decay time
                    fluorescence <= !fluorescence;
                end
            end
            always begin
                // 10 MHz background counts
                #($dist_exponential(seed, 100000 * FLUORESCENCES) * 1ps);
                fluorescence <= !fluorescence;
            end
            always @(fluorescence) begin
                automatic integer detector = $dist_uniform(seed, 0, DETECTORS - 1);
                detector_in[detector] <= !detector_in[detector];
            end
        end
    endgenerate

    /////////////////////////////////////
    // CH 2..: Single photon detectors //
    /////////////////////////////////////
    reg [DETECTORS-1 : 0] detector = 0;
    generate
        for (genvar i = 0; i < DETECTORS; i++) begin
            reg detector_active = 1;
            always @(detector_in[i]) begin
                #($dist_normal(seed, 100000, 1000) * 10fs);  // 1 ns delay +- 10ps RMS jitter
                if (detector_active) begin
                    detector_active <= 0;
                    detector[i] <= 1;
                end
            end
            always @(posedge detector[i]) begin
                #8ns;  // 8ns pulse length
                detector[i] <= 0;
                // 14ns deadtime +- 100ps RMS jitter
                #($dist_normal(seed, 6000, 100) * 1ps);
                if ($dist_uniform(seed, 0, 99) < 5) begin  // 5% afterpulsing
                    detector[i] <= 1;
                end else begin
                    detector_active <= 1;
                end
            end
        end
    endgenerate

    ////////////////////////////////////////
    // Time Tagger X and reference design //
    ////////////////////////////////////////

    axis_tag_interface #(.WORD_WIDTH(WORD_WIDTH)) axis_tags ();

    tb_timeTagGenerator #(
        .NUM_OF_INPUT_CHANNELS(DETECTORS + 1)
    ) tb_timeTagGenerator_inst (
        .chx({detector, laser_electrical}),
        .m_time(axis_tags)
    );

    ////////////////////////////
    // Measurement: Histogram //
    ////////////////////////////

    // TODO: Wishbone
    wb_interface wb ();

    reg hist_read_start_i = 0;
    always begin
        // Read out the histogram every 20us
        #19990ns hist_read_start_i <= 1;
        #10ns hist_read_start_i <= 0;
    end
    reg config_en_i = 0;
    initial #100ns config_en_i <= 1;  // start histogramming after 100ns

    // Data output
    wire [2*32 -1 : 0] data_out_o;
    wire valid_out_o;

    // Statistics
    wire statistics_valid;
    wire [12 - 1 : 0] index_max;
    wire [12 - 1 : 0] offset;
    wire [32 - 1 : 0] variance;

    histogram #(
        .WISHBONE_INTERFACE_EN(0)
    ) histogram_inst (
        .s_axis(axis_tags),
        .wb(wb),

        // Config input
        .hist_read_start_i(hist_read_start_i),
        .hist_reset_i(axis_tags.rst),
        .config_en_i(config_en_i),
        .click_channel_i(6'd2),  // first detector channel
        .start_channel_i(6'd1),  // laser channel
        .shift_val_i(6'd6),  // 64ps binwidth

        // Histogram output
        .data_out_o (data_out_o),
        .valid_out_o(valid_out_o),

        // Statistics output
        .statistics_valid(statistics_valid),
        .index_max(index_max),
        .offset(offset),
        .variance(variance)
    );

endmodule
