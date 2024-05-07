/**
 * Test bench for user_sample
 *
 * Creates (kind of) plausible tags to verify parts of user_sample in simulation
 *
 * This file is part of the Time Tagger software defined digital data
 * acquisition FPGA-link reference design.
 *
 * Copyright (C) 2023 Swabian Instruments, All Rights Reserved
 *
 * Authors:
 * - 2023 David Sawatzke <david@swabianinstruments.com>
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

module tb_user_sample #(
    parameter integer WORD_WIDTH = 2,  // Amount of events processed in one clock period
    parameter integer CHANNELS   = 4   // Channels for which events will be generated
) ();

    ///////////////////////////////////
    // 100 MSamples of random events //
    ///////////////////////////////////

    /*
        Random events with in total 100 MHz rate.
        They are distributed randomly over all channels, but with a fixed period of 10ns.
    */
    reg [CHANNELS-1 : 0] channels = 0;
    integer c;
    always begin
        #10ns;
        c = $urandom() % CHANNELS;
        channels[c] <= !channels[c];
    end

    ////////////////////////////////////////
    // Time Tagger X and reference design //
    ////////////////////////////////////////

    // System Verilog interface for the stream of time tags (with AXI-S handshake).
    // `WORD_WIDTH` time tags are processed per clock cycle in parallel.
    axis_tag_interface #(.WORD_WIDTH(WORD_WIDTH)) axis_tags ();

    /*
        Helper module for simple simulating measurements: It replaces the TimeTaggerX and most of the shared code of this repository.
        It converts events encoded as simulation_time into events encoded as timetag_time.
        So use e.g. the Verilod wait statement `#123ps` to generate the input and it yields
        the integer 123 on the data stream.
        Use the output directly with your desired measurements.
    */
    tb_timeTagGenerator #(
        .NUM_OF_INPUT_CHANNELS(CHANNELS)
    ) tb_timeTagGenerator_inst (
        .chx(channels),
        .m_time(axis_tags)
    );

    //////////////////////////////
    // Measurement: User Sample //
    //////////////////////////////

    // System Verilog interface for the Wishbone bus.
    wb_interface wb ();

    // Example evaluation of the time tag stream.
    user_sample user_design (
        .s_axis(axis_tags),
        .wb(wb),
        .led()
    );

endmodule
