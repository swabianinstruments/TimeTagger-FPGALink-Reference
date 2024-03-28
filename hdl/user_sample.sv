/**
 * User Sample Design for high bandwidth applications
 *
 * This file is part of the Time Tagger software defined digital data
 * acquisition FPGA-link reference design.
 *
 * Copyright (C) 2023 Swabian Instruments, All Rights Reserved
 *
 * Authors:
 * - 2023 David Sawatzke <david@swabianinstruments.com>
 * - 2023 Markus Wick <markus@swabianinstruments.com>
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

// This module receives the tag stream and sets the first 2 leds based on the first 2 channels
// The data will arrive sorted from the timetagger, so the time & subtimes can be ignored for this purpose
//
// LED function:
// 0-1: State of the first 2 channels
// 2-3: Upper bits of the tag counter
// 4:   On if there was data in the last 200 ms
// 5:   Interval exceeded counter
//
// It also provides a way to detect invalid tags by determining the time
// between two subsequent tags on a certain channel and checking if the time is
// inside a user-provided interval.
//
// Register map:
//
// | Address | Name                | Purpose                                                                               |
// |---------+---------------------+---------------------------------------------------------------------------------------|
// |       0 | Presence Indicator  | Reads one, for detecting presence of this module                                      |
// |       8 | user_control        | If a non-zero is written, the status is held in reset                                 |
// |      12 | channel_select      | Determines which channel to monitor                                                   |
// |      16 | lower_bound         | The lower bound of the expected interval (64 bit)                                     |
// |      24 | upper_bound         | The upper bound of the expected interval (64 bit)                                     |
// |      32 | failed_time         | The failing time. The upper bit is set if the value is valid (64 bit)                 |
//
// Note: You can replicate much of this functionality with the Vivado ILA and adding multiple ANDed triggers with comparators
module user_sample (
    axis_tag_interface.slave s_axis,

    wb_interface.slave wb,

    output reg [5:0] led
);

    localparam WORD_WIDTH = s_axis.WORD_WIDTH;

    // This module is always ready to accept new data
    assign s_axis.tready = 1;

    reg [                    31:0] cnt;
    reg [                    15:0] tag_counter;
    reg [$clog2(WORD_WIDTH+1)-1:0] tag_counter_inc;
    always @(posedge s_axis.clk) begin
        if (s_axis.rst) begin
            led[4:0] <= 0;
            cnt <= 0;
            tag_counter <= 0;
            tag_counter_inc = 0;
        end else begin
            tag_counter_inc = 0;
            for (int i = 0; i < WORD_WIDTH; i += 1) begin
                if (s_axis.tready && s_axis.tvalid && s_axis.tkeep[i]) begin
                    unique case (s_axis.channel[i])
                        5'h01: begin
                            led[0] <= !s_axis.channel[i][5];
                        end
                        5'h02: begin
                            led[1] <= !s_axis.channel[i][5];
                        end
                        default: ;
                    endcase
                    cnt <= 31250000 * 2;  // ~200ms
                    tag_counter_inc = tag_counter_inc + 1;
                end
            end
            tag_counter <= tag_counter + tag_counter_inc;
            // keep the activity LED on for around 200ms
            if (cnt > 0) begin
                cnt <= cnt - 1;
                led[4] <= 1;
            end else begin
                led[4] <= 0;
            end
            led[3:2] = tag_counter[15:14];
        end
    end

    reg [31:0] user_control;
    reg [ 5:0] channel_select;
    reg [63:0] lower_bound;
    reg [63:0] upper_bound;
    reg [63:0] failed;

    reg [63:0] tagtimes                    [WORD_WIDTH-1:0];
    reg        tagtimes_valid              [WORD_WIDTH-1:0];
    reg [63:0] tagtimes_p                  [WORD_WIDTH-1:0];
    reg        tagtimes_valid_p            [WORD_WIDTH-1:0];
    reg [63:0] prev_tagtime_blocking;
    reg        prev_tagtime_valid_blocking;
    reg [63:0] prev_tagtimes               [WORD_WIDTH-1:0];
    reg        prev_tagtimes_valid         [WORD_WIDTH-1:0];
    reg [63:0] tagtime_diff                [WORD_WIDTH-1:0];
    reg        tagtime_diff_valid          [WORD_WIDTH-1:0];
    reg [63:0] tagtime_diff_p              [WORD_WIDTH-1:0];
    reg        tagtime_diff_p_error        [WORD_WIDTH-1:0];
    always @(posedge s_axis.clk) begin
        if (s_axis.rst || (user_control != 0)) begin
            led[5] <= 1'b0;
            failed <= 64'h0;
            prev_tagtime_blocking = 'x;
            prev_tagtime_valid_blocking = 0;
            for (int i = 0; i < WORD_WIDTH; i += 1) begin
                tagtimes[i] <= 'x;
                tagtimes_p[i] <= 'x;
                tagtimes_valid[i] <= 0;
                tagtimes_valid_p[i] <= 0;
                prev_tagtimes[i] <= 'x;
                prev_tagtimes_valid[i] <= 0;
                tagtime_diff[i] <= 'x;
                tagtime_diff_valid[i] <= 0;
                tagtime_diff_p[i] <= 'x;
                tagtime_diff_p_error[i] <= 0;
            end
        end else begin
            for (int i = 0; i < WORD_WIDTH; i += 1) begin
                /*
               // reference implementation without pipeline stages
               if (s_axis.tready && s_axis.tvalid && s_axis.tkeep[i] && channel_select == s_axis.channel[i]) begin
                    if (prev_tagtime_valid_blocking) begin
                         tagtime_diff[i] = s_axis.tagtime[i] - prev_tagtime_blocking;
                         if (tagtime_diff[i] < lower_bound || tagtime_diff[i] > upper_bound) begin
                              failed <= tagtime_diff[i];
                              failed[63] <= 1;
                              led[5] <= 1'b1;
                         end
                    end
                    prev_tagtime_blocking = s_axis.tagtime[i];
                    prev_tagtime_valid_blocking = 1;
               end
               */

                // First pipeline stage (full parallel): Select if this lane is active
                tagtimes[i] <= 'x;
                tagtimes_valid[i] <= 0;
                if (s_axis.tready && s_axis.tvalid && s_axis.tkeep[i] && channel_select == s_axis.channel[i]) begin
                    tagtimes[i] <= s_axis.tagtime[i];
                    tagtimes_valid[i] <= 1;
                end

                // Second pipeline stage (blocking statements): Mux the previous active event
                tagtimes_p[i] <= tagtimes[i];
                tagtimes_valid_p[i] <= tagtimes_valid[i];
                prev_tagtimes[i] <= prev_tagtime_blocking;
                prev_tagtimes_valid[i] <= prev_tagtime_valid_blocking;
                if (tagtimes_valid[i]) begin
                    // Assign the blocking registers, so they will be available for both the next lane and the next clock cycle
                    // Note: The order here matters. These registers must be set *after* they are used a few lines ago.
                    prev_tagtime_blocking = tagtimes[i];
                    prev_tagtime_valid_blocking = tagtimes_valid[i];
                end

                // Third pipeline stage (full parallel): Calculate the time differences
                tagtime_diff[i] <= tagtimes_p[i] - prev_tagtimes[i];
                tagtime_diff_valid[i] <= tagtimes_valid_p[i] && prev_tagtimes_valid[i];

                // Fourth pipeline stage (full parallel): Calculate if this time difference is an error
                tagtime_diff_p[i] <= tagtime_diff[i];
                tagtime_diff_p_error[i] <= tagtime_diff_valid[i] && (tagtime_diff[i] < lower_bound || tagtime_diff[i] > upper_bound);

                // Fiveth pipeline stage (last active lane): Mux the failing time difference
                if (tagtime_diff_p_error[i]) begin
                    failed <= tagtime_diff_p[i];
                    failed[63] <= 1;
                    led[5] <= 1'b1;
                end
            end
        end
    end

    always @(posedge wb.clk) begin
        wb.ack <= 0;
        if (wb.rst) begin
            wb.dat_o <= 0;
            user_control <= 0;
            channel_select <= 1;
            lower_bound <= 64'h0000000000660000;
            upper_bound <= 64'h0000000000680000;
        end else if (wb.cyc && wb.stb) begin
            wb.ack <= 1;
            if (wb.we) begin
                // Write
                unique casez (wb.adr[7:0])
                    8'b000010??: user_control <= wb.dat_i;
                    8'b000011??: channel_select <= wb.dat_i;
                    8'b00010???: lower_bound[(wb.adr&4)*8+:32] <= wb.dat_i;
                    8'b00011???: upper_bound[(wb.adr&4)*8+:32] <= wb.dat_i;
                    default: ;
                endcase
            end else begin
                // Read
                unique casez (wb.adr[7:0])
                    // Indicate the bus slave is present in the design
                    8'b000000??: wb.dat_o <= 1;
                    8'b000010??: wb.dat_o <= user_control;
                    8'b000011??: wb.dat_o <= channel_select;
                    8'b00010???: wb.dat_o <= lower_bound[(wb.adr&4)*8+:32];
                    8'b00011???: wb.dat_o <= upper_bound[(wb.adr&4)*8+:32];
                    8'b00100???: wb.dat_o <= failed[(wb.adr&4)*8+:32];
                    default: wb.dat_o <= 32'h00000000;
                endcase
            end
        end else begin
            wb.dat_o <= 0;
        end
    end
endmodule
