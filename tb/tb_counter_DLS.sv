/**
 * Testbench for the counter module
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

module tb_counter_DLS #(
    parameter integer  WORD_WIDTH = 4,     // Amount of events processed in parallel by the counter
    parameter integer  DETECTORS  = 4,     // Amount of simulated single photon detectors
    parameter integer  SCATTERERS = 50,    // Amount of simulated scatterer particles
    parameter realtime T_PERIOD   = 10ns,  // Time interval how often the intensity gets updated
    parameter realtime T_TAU      = 10us   // Time constant of the simulated DLS experiment
) ();

    // Random number generator seed used in this testbench
    integer seed = $random();

    //////////////////////////////////////////
    // Experiment: Dynamic light scattering //
    //////////////////////////////////////////
    real phases[SCATTERERS];
    reg [DETECTORS-1 : 0] detector_in = 0;  // events are encoded as state toggle
    initial begin
        for (integer i = 0; i < SCATTERERS; i++) begin
            // uniform initial values in range -pi .. pi
            phases[i] = (6.283185307179586 / 4294967296.0) * $random();
        end
    end

    always begin
        automatic real sum_real = 0.0;
        automatic real sum_imag = 0.0;
        automatic real intensity;
        automatic realtime remaining;
        for (integer i = 0; i < SCATTERERS; i++) begin
            sum_real  = sum_real + $cos(phases[i]);
            sum_imag  = sum_imag + $sin(phases[i]);
            phases[i] = phases[i] + $sqrt(2.0 * T_PERIOD / T_TAU) * $dist_normal(seed, 0, 1000000) / 1000000.0;
        end
        intensity = (sum_real * sum_real + sum_imag * sum_imag) / SCATTERERS;

        remaining = T_PERIOD;
        forever begin
            // Total average event rate: 40 MHz
            automatic realtime dt = $dist_exponential(seed, 1000000) / (1000000.0 * intensity) * 25ns;
            if (dt < remaining) begin
                // Each photon is uniformly distributed over all detectors
                automatic integer detector = $dist_uniform(seed, 0, DETECTORS - 1);
                #dt;
                detector_in[detector] = !detector_in[detector];
                remaining = remaining - dt;
            end else begin
                #remaining;
                break;
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

    //////////////////////////
    // Measurement: Counter //
    //////////////////////////

    // TODO: Wishbone
    wb_interface wb ();

    // configuring each lane of the Counter to match one detector
    reg [5 : 0] channel_lut_i[64] = '{default: '1};  // all-ones is an invalid counter lane
    initial begin
        for (integer i = 0; i < DETECTORS; i = i + 1) begin
            // mapping the i-th rising channel to the i-th counter lane
            channel_lut_i[i+1] <= i;
        end
    end

    // outputs of the counter measurement
    wire [31 : 0] count_data_o[DETECTORS];
    wire count_valid_o;

    counter #(
        .WISHBONE_INTERFACE_EN(0),
        .NUM_OF_CHANNELS(DETECTORS)
    ) counter_inst (
        .s_axis(axis_tags),
        .wb(wb),
        .window_size_i(64'd1000000),  // 1 us binwidth
        .start_counting_i(!axis_tags.rst),  // start immediately after reset
        .reset_module_i(axis_tags.rst),  // forward reset from the axi bus
        .channel_lut_i(channel_lut_i),
        .count_data_o(count_data_o),
        .count_valid_o(count_valid_o)
    );

endmodule
