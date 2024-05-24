/**
 * Testbench for the combinations module
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

module tb_combinations_boson_sampling #(
    parameter integer WORD_WIDTH = 4,   // Amount of events processed in parallel by the histogram
    parameter integer DETECTORS  = 12,  // Amount of simulated single photon detectors
    parameter integer PHOTONS    = 6    // Amount of entangled photons generated at once
) ();

    // Random number generator seed used in this testbench
    integer seed = $random();

    /////////////////////////
    // 80 MHz pulsed laser //
    /////////////////////////
    reg laser = 0;
    always begin
        laser <= 1;
        #2.5ns;  // 2.5ns HIGH
        laser <= 0;
        #($dist_normal(seed, 1000000, 100) * 10fs);  // 10 ns +- 1ps RMS: LOW
    end

    ////////////////////////////////
    // Experiment: Boson sampling //
    ////////////////////////////////
    reg [DETECTORS-1 : 0] detector_in = 0;  // events are encoded as state toggle
    always @(posedge laser) begin
        if ($dist_uniform(seed, 0, 99) < 75) begin  // 75% chance to get any photon
            for (integer i = 0; i < PHOTONS; i++) begin
                if ($dist_uniform(seed, 0, 99) < 75) begin  // overall 75% quantum efficiency per photon
                    // Each photon is uniformly distributed over all detectors
                    automatic integer detector = $dist_uniform(seed, 0, DETECTORS - 1);
                    // Non-blocking statement. Two photons on the same detector yield one click
                    detector_in[detector] <= !detector_in[detector];
                end
            end
        end
    end

    /////////////////////////////////////
    // CH 1..: Single photon detectors //
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
                #4ns;  // 4ns pulse length
                detector[i] <= 0;
                // 6ns deadtime +- 100ps RMS jitter
                #($dist_normal(seed, 2000, 100) * 1ps);
                if ($dist_uniform(seed, 0, 99) < 5) begin  // 5% afterpulsing
                    detector[i] <= 1;
                end else begin
                    detector_active <= 1;
                end
            end
            always begin
                // 1 MHz background counts per detector
                #($dist_exponential(seed, 1000000) * 1ps);
                detector_in[i] <= !detector_in[i];
            end
        end
    endgenerate

    ////////////////////////////////////////
    // Time Tagger X and reference design //
    ////////////////////////////////////////

    axis_tag_interface #(.WORD_WIDTH(WORD_WIDTH)) axis_tags ();

    tb_timeTagGenerator #(
        .NUM_OF_INPUT_CHANNELS(DETECTORS)
    ) tb_timeTagGenerator_inst (
        .chx(detector),
        .m_time(axis_tags)
    );

    ///////////////////////////////
    // Measurement: Combinations //
    ///////////////////////////////

    /*
        TODO: Wishbone
        channels:   all rising
        window:     50 ps
    */

    // Wishbone driver and combination tester
    wb_interface wb ();
    combination_interface comb_tb ();
    tb_combination_driver #(
        .WISHBONE_INTERFACE_EN(1),
        .CHANNELS(DETECTORS)
    ) tb_combination_driver_inst (
        .clk(axis_tags.clk),
        .rst(axis_tags.rst),
        .wb(wb),
        .m_comb_tb(comb_tb)
    );

    // The combination measurement
    combination #(
        .WISHBONE_INTERFACE_EN(1),
        .NUM_OF_CHANNELS(DETECTORS),
        .ACC_WIDTH(32),
        .FIFO_DEPTH(8192)
    ) combination_inst (
        // input information of channel
        .s_time(axis_tags),
        // Wishbone interface for control & status
        .wb(wb),
        // combination interface for control & status
        .s_comb_i(comb_tb)
    );

endmodule
