/**
 * Statistics gathering module
 *
 * This file is part of the Time Tagger software defined digital data
 * acquisition FPGA-link reference design.
 *
 * Copyright (C) 2022-2024 Swabian Instruments, All Rights Reserved
 *
 * Authors:
 * - 2022-2024 David Sawatzke <david@swabianinstruments.com>
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

// This module provides various statistics over wishbone over the received data. For this purpose, two axi streams inside the data_channel are sniffed.
//
// Register map
//
// | Address | Name                     | Purpose                                                                                       |
// |---------+--------------------------+-----------------------------------------------------------------------------------------------|
// |       0 | Presence Indicator       | Reads b'stat', for detecting presence of this module.                                         |
// |       4 | statistics_control       | None                                                                                          |
// |       8 | statistics_reset         | Resets various parts. 0: Reset received_* statistics 1: Reset packet_loss. 2: Reset overflow. |
// |      12 | packet_rate              | (Valid) Packets received over the last second. Updates every second.                          |
// |      16 | word_rate                | Data Words (128 bit) in Packets received over the last second. Updates every second.          |
// |      24 | received_packets (64bit) | Number of (valid) packets received in total.                                                  |
// |      32 | received_words (64bit)   | Number of words in valid packets received in total.                                           |
// |      40 | size_of_last_packet      | Number of Words in the last valid packet.                                                     |
// |      44 | packet_loss              | If `1` indicates a lost packet.                                                               |
// |      48 | invalid_packets          | Invalid Packets received in total. Also counts (for example) ARP and similar.                 |
// |      52 | tag_rate                 | Tags received over the last second. Updates every second.                                     |
// |      56 | received_tags (64bit)    | Number of tags received in total.                                                             |
// |      64 | overflowed               | If `1` indicates that an overflow has occurred inside the TTX and has not been ended.         |
// |         |                          | If `2` indicates that an overflow has occurred and ended inside the TTX.                      |
// |      72 | missed tags (64bit)      | Counting the number of tags marked as "Missed events" within the TTX due to the overflow.     |

// Note: All statistics exclude the header with a size of 128 bit.
// Note: All 64bit values must be fetched in the order (LSB, MSB).
module si_statistics_wb #(
    parameter DATA_WIDTH = 128,
    parameter KEEP_WIDTH = (DATA_WIDTH + 7) / 8,
    parameter CLK_FREQ   = 333333333
) (
    input wire clk,
    input wire rst,

    // AXI-Stream before the header parser
    input wire pre_axis_tvalid,
    input wire pre_axis_tready,
    input wire pre_axis_tlast,

    // Signals from the header parser
    input wire lost_packet,
    input wire invalid_packet,

    // AXI-Stream after the header detacher
    input wire                  post_axis_tvalid,
    input wire [DATA_WIDTH-1:0] post_axis_tdata,
    input wire [KEEP_WIDTH-1:0] post_axis_tkeep,
    input wire                  post_axis_tready,
    input wire                  post_axis_tlast,

    // Wishbone interface for control & status
    wb_interface.slave wb
);

    // Timer to determine the length of a second
    reg   [  31:0] second_timer;

    reg   [  31:0] invalid_packet_counter;
    reg   [  31:0] size_of_last_packet_counter;
    reg   [  31:0] size_of_last_packet;
    reg   [  31:0] tag_rate_counter;
    reg   [  31:0] tag_rate_latched;
    reg   [  31:0] word_rate_counter;
    reg   [  31:0] word_rate_latched;
    reg   [  31:0] packet_rate_counter;
    reg   [  31:0] packet_rate_latched;
    reg   [  63:0] received_words;
    reg   [  63:0] received_packets;
    reg   [  63:0] received_tags;
    reg            overflow_begin;
    reg            overflow_end;

    reg            reset_total_counters;

    reg   [  31:0] statistics_reset;

    logic [23 : 0] missed_events               [KEEP_WIDTH/4];
    logic [24 + $clog2(KEEP_WIDTH / 4) - 1 : 0] partial_sum, partial_sum_comb;
    logic [63 : 0] total_missed_events;

    always_ff @(posedge clk) begin
        overflow_begin <= 0;
        overflow_end <= 0;
        missed_events <= '{default: '0};
        partial_sum <= 0;
        partial_sum_comb = 0;
        if (rst) begin
            second_timer <= CLK_FREQ - 1;
            second_timer <= 0;
            invalid_packet_counter <= 0;
            received_tags <= 0;
            received_words <= 0;
            received_packets <= 0;
            tag_rate_counter <= 0;
            word_rate_counter <= 0;
            packet_rate_counter <= 0;
            tag_rate_latched <= 0;
            word_rate_latched <= 0;
            packet_rate_latched <= 0;
            size_of_last_packet_counter <= 0;
            total_missed_events <= 0;
        end else begin
            if (pre_axis_tvalid && pre_axis_tready && pre_axis_tlast && invalid_packet) begin
                invalid_packet_counter <= invalid_packet_counter + 1;
            end

            if (post_axis_tvalid && post_axis_tready) begin
                for (integer i = 0; i < (KEEP_WIDTH / 4); i += 1) begin
                    automatic logic [1:0] event_type = post_axis_tdata[32*i+30+:2];
                    automatic logic [5:0] event_ch_id = post_axis_tdata[32*i+24+:6];

                    if (post_axis_tkeep[3+4*i] && (event_type == 2'b10)) begin
                        if (event_ch_id == 6'h3F) begin
                            // OverflowBegin
                            overflow_begin <= 1;
                        end
                        if (event_ch_id < 40) begin
                            // Missed events LSB
                            missed_events[i] <= post_axis_tdata[32*i+12+:12];
                        end
                    end

                    if (post_axis_tkeep[3+4*i] && (event_type == 2'b11)) begin
                        if (event_ch_id == 6'h3F) begin
                            // OverflowEnd
                            overflow_end <= 1;
                        end
                        if (event_ch_id < 40) begin
                            // Missed events MSB
                            missed_events[i] <= post_axis_tdata[32*i+12+:12] << 12;
                        end
                    end
                end

                received_tags <= received_tags + $unsigned(($countones(post_axis_tkeep) >> 2));
                tag_rate_counter <= tag_rate_counter + $unsigned(($countones(post_axis_tkeep) >> 2));
                received_words <= received_words + 1;
                word_rate_counter <= word_rate_counter + 1;
                size_of_last_packet_counter <= size_of_last_packet_counter + 1;

                if (post_axis_tlast) begin
                    received_packets <= received_packets + 1;
                    packet_rate_counter <= packet_rate_counter + 1;
                    size_of_last_packet <= size_of_last_packet_counter;
                    size_of_last_packet_counter <= 1;  // The last word doesn't get counted otherwise
                end
            end

            // Sum up the missed events within two cycles after receiving the data
            for (integer i = 0; i < (KEEP_WIDTH / 4); i += 1) begin
                partial_sum_comb = partial_sum_comb + missed_events[i];
            end
            partial_sum <= partial_sum_comb;
            total_missed_events <= total_missed_events + partial_sum;

            if (reset_total_counters) begin
                received_tags <= 0;
                received_words <= 0;
                received_packets <= 0;
            end

            if (second_timer == 0) begin
                second_timer <= CLK_FREQ - 1;

                // Latch & reset the rate counters
                tag_rate_latched <= tag_rate_counter;
                tag_rate_counter <= 0;

                word_rate_latched <= word_rate_counter;
                word_rate_counter <= 0;

                packet_rate_latched <= packet_rate_counter;
                packet_rate_counter <= 0;
            end else begin
                second_timer <= second_timer - 1;
            end
        end

        if (statistics_reset[2]) begin
            missed_events <= '{default: '0};
            partial_sum <= 0;
            total_missed_events <= 0;
        end
    end

    reg        packet_loss;
    reg        overflow_begin_reg;
    reg        overflow_end_reg;

    reg [31:0] statistics_control;

    assign reset_total_counters = statistics_reset[0];

    // Registers for latching the MSB while fetching the LSB
    // This allow us to fetch a real 64bit value over WB by fetching LSB first and MSB later
    reg [31:0] received_packets_MSB;
    reg [31:0] received_words_MSB;
    reg [31:0] received_tags_MSB;
    reg [31:0] total_missed_events_MSB;

    always_ff @(posedge clk) begin
        wb.ack <= 0;
        wb.dat_o <= 'X;
        statistics_reset <= 0;
        if (rst) begin
            statistics_control      <= 0;
            packet_loss             <= 0;
            overflow_begin_reg      <= 0;
            overflow_end_reg        <= 0;

            received_packets_MSB    <= 0;
            received_words_MSB      <= 0;
            received_tags_MSB       <= 0;
            total_missed_events_MSB <= 0;
        end else if (wb.cyc && wb.stb) begin
            wb.ack <= 1;
            if (wb.we) begin
                // Write
                casez (wb.adr[7:0])
                    8'b000001??: statistics_control <= wb.dat_i;
                    8'b000010??: statistics_reset <= wb.dat_i;
                endcase
            end else begin
                // Read
                casez (wb.adr[7:0])
                    // Indicate the Debug bus slave is present in the design
                    8'b000000??: wb.dat_o <= 32'h73746174;  // ASCII: 'stat'
                    8'b000001??: wb.dat_o <= statistics_control;
                    8'b000010??: wb.dat_o <= statistics_reset;  // Always 0
                    8'b000011??: wb.dat_o <= packet_rate_latched;
                    8'b000100??: wb.dat_o <= word_rate_latched;
                    8'b000110??: begin
                        wb.dat_o <= received_packets[31 : 0];
                        received_packets_MSB <= received_packets[63 : 32];
                    end
                    8'b000111??: wb.dat_o <= received_packets_MSB;
                    8'b001000??: begin
                        wb.dat_o <= received_words[31 : 0];
                        received_words_MSB <= received_words[63 : 32];
                    end
                    8'b001001??: wb.dat_o <= received_words_MSB;
                    8'b001010??: wb.dat_o <= size_of_last_packet;
                    8'b001011??: wb.dat_o <= packet_loss;
                    8'b001100??: wb.dat_o <= invalid_packet_counter;
                    8'b001101??: wb.dat_o <= tag_rate_latched;
                    8'b001110??: begin
                        wb.dat_o <= received_tags[31 : 0];
                        received_tags_MSB <= received_tags[63 : 32];
                    end
                    8'b001111??: wb.dat_o <= received_tags_MSB;
                    8'b010000??: wb.dat_o <= {overflow_end_reg, overflow_begin_reg};
                    8'b010010??: begin
                        wb.dat_o <= total_missed_events[31 : 0];
                        total_missed_events_MSB <= total_missed_events[63 : 32];
                    end
                    8'b010011??: wb.dat_o <= total_missed_events_MSB;
                    default: wb.dat_o <= 32'h00000000;
                endcase
            end
        end

        if (lost_packet) begin
            packet_loss <= 1;
        end else if (statistics_reset[1]) begin
            packet_loss <= 0;
        end
        if (overflow_begin) begin
            overflow_begin_reg <= 1;
        end else if (overflow_end | statistics_reset[2]) begin
            overflow_begin_reg <= 0;
        end

        if (overflow_end) begin
            overflow_end_reg <= 1;
        end else if (statistics_reset[2]) begin
            overflow_end_reg <= 0;
        end
    end
endmodule
