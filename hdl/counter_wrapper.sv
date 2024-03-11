/*
 * countrate_wrapper
 *
 * This file is part of the Time Tagger software defined digital data
 * acquisition FPGA-link reference design.
 *
 * Copyright (C) 2024 Swabian Instruments, All Rights Reserved
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

module counter_wrapper #(
    parameter WISHBONE_INTERFACE_EN = 1,
    parameter TAG_WIDTH = 64,
    parameter NUM_OF_TAGS = 4,
    parameter TOT_TAGS_WIDTH = NUM_OF_TAGS * TAG_WIDTH,
    parameter CHANNEL_WIDTH = 6,
    parameter TOT_CHANNELS_WIDTH = NUM_OF_TAGS * CHANNEL_WIDTH,
    parameter WINDOW_WIDTH = TAG_WIDTH,
    parameter NUM_OF_CHANNELS = 16,
    parameter COUNTER_WIDTH = 32,
    parameter INPUT_FIFO_DEPTH = 1024,
    parameter OUTPUT_FIFO_DEPTH = 8 * 1024,
    parameter CHANNEL_LUT_DEPTH = 2 ** CHANNEL_WIDTH
) (
    /* All inputs and outputs are synchronized into the clk. if some controlling
    signals are generated in different clock domains, cdc should be used
    for synchronization outside of this module.
    */
    input wire clk,
    input wire rst,

    input wire [NUM_OF_TAGS - 1 : 0] valid_tag,
    input wire [TOT_TAGS_WIDTH - 1 : 0] tagtime,
    input wire [TOT_CHANNELS_WIDTH - 1 : 0] channel,

    //    Wishbone interface for control & status      		//
    wb_interface.slave wb,

    //       	 downstream module interface                //
    input wire [WINDOW_WIDTH - 1 : 0] window_size_i,
    input wire start_counting_i,
    input wire reset_module_i,
    input wire [CHANNEL_WIDTH - 1 : 0] channel_lut_i[CHANNEL_LUT_DEPTH],
    //Each lane represents the count of detected tags in its respective channel.
    output wire [COUNTER_WIDTH - 1 : 0] count_data_o[NUM_OF_CHANNELS],
    output wire count_valid_o

);

    //--------------------Channels LUT ---------------------------------//
    logic [CHANNEL_WIDTH - 1 : 0] channel_lut[CHANNEL_LUT_DEPTH] = '{default: '0};

    // register input signals
    logic [NUM_OF_TAGS - 1 : 0] valid_tag_inp;
    logic [TOT_TAGS_WIDTH - 1 : 0] tagtime_inp;
    logic [TOT_CHANNELS_WIDTH - 1 : 0] channel_inp;

    // channel mapping
    always_ff @(posedge clk) begin
        valid_tag_inp <= valid_tag;
        tagtime_inp   <= tagtime;

        for (int i = 0; i < NUM_OF_TAGS; i++) begin
            channel_inp[i*CHANNEL_WIDTH+:CHANNEL_WIDTH] <= channel_lut[channel[i*CHANNEL_WIDTH+:CHANNEL_WIDTH]];
            if (channel_lut[channel[i*CHANNEL_WIDTH+:CHANNEL_WIDTH]] >= NUM_OF_CHANNELS) valid_tag_inp[i] <= 0;
        end
    end

    //-------------------- Countrate Module ---------------------------//
    logic [WINDOW_WIDTH - 1 : 0] window_size;
    logic start_counting;
    logic [COUNTER_WIDTH - 1 : 0] count_data[NUM_OF_CHANNELS];
    logic count_valid;
    logic reset_module;
    countrate #(
        .TAG_WIDTH(TAG_WIDTH),
        .NUM_OF_TAGS(NUM_OF_TAGS),
        .CHANNEL_WIDTH(CHANNEL_WIDTH),
        .WINDOW_WIDTH(WINDOW_WIDTH),
        .NUM_OF_CHANNELS(NUM_OF_CHANNELS),
        .COUNTER_WIDTH(COUNTER_WIDTH),
        .INPUT_FIFO_DEPTH(INPUT_FIFO_DEPTH)
    ) countrate_inst (
        .clk(clk),
        .rst(rst | reset_module),
        .valid_tag(valid_tag_inp),
        .tagtime(tagtime_inp),
        .channel(channel_inp),
        .window_size(window_size),
        .start_counting(start_counting),
        .count_data(count_data),
        .count_valid(count_valid)
    );

    //------------------------------------------------------------------//
    generate
        if (WISHBONE_INTERFACE_EN) begin
            initial begin
                /* Ensure that COUNTER_WIDTH is not larger than 32. Otherwise, you need to
               read each counter over two or more wb transactions.*/
                if (COUNTER_WIDTH > 32) begin
                    $error("Error: COUNTER_WIDTH is larger than 32. Re-desing reading the counters.");
                    $finish;
                end
            end

            //---------------------------------------------------------//
            /* Serialize the 'count_data' and store the data corresponding to the desired
            channels in the FIFO.*/
            logic [COUNTER_WIDTH - 1 : 0] serialized_count_data;
            logic fifo_wt_en;
            logic [CHANNEL_WIDTH - 1 : 0] fifo_cnt;
            logic [CHANNEL_WIDTH - 1 : 0] num_desired_channels;

            always @(posedge clk) begin
                fifo_cnt   <= 0;
                fifo_wt_en <= 0;
                if (!(rst | reset_module) && (count_valid | fifo_wt_en)) begin
                    if (fifo_cnt <= num_desired_channels - 1) begin
                        fifo_wt_en <= 1;
                    end
                    fifo_cnt <= fifo_cnt + 1;
                end

                /* We set the MSB of the data generated by the 'countrate' module to
               inform the backend that this number represents a counter value.*/
                serialized_count_data <= {1'b1, count_data[fifo_cnt][COUNTER_WIDTH-2 : 0]};
            end

            // Output FIFO
            xpm_fifo_sync #(
                .FIFO_MEMORY_TYPE("auto"),
                .FIFO_WRITE_DEPTH(OUTPUT_FIFO_DEPTH),
                .WRITE_DATA_WIDTH(COUNTER_WIDTH),
                .READ_DATA_WIDTH(COUNTER_WIDTH),
                .PROG_FULL_THRESH(OUTPUT_FIFO_DEPTH - NUM_OF_CHANNELS - 10),
                .READ_MODE("fwft"),
                .USE_ADV_FEATURES("0707")
            ) output_buffer (
                .rst(rst | reset_module),  // Discard FIFO data when the reset_module signal is asserted
                .wr_clk(clk),
                .wr_en(fifo_wt_en),
                .din(serialized_count_data),
                .prog_full(fifo_prog_full),
                .dout(fifo_dout),
                .empty(fifo_empty),
                .rd_en(fifo_rd_en)
            );

            //---------------------------------------------------------//

            logic window_size_valid;
            logic [WINDOW_WIDTH - 1 : 0] r0window_size;
            logic [31 : 0] fifo_dout;
            logic fifo_rd_en, fifo_empty;
            logic fifo_prog_full;

            logic discard_enable;
            logic [31 : 0] discard_cnt;
            // This counter counts from 0 to NUM_OF_CHANNELS-1
            logic [CHANNEL_WIDTH - 1 : 0] channel_cnt;
            // This flag indicate that some somples have been discarded.
            logic discard_flag;

            // This counter counts over channel_lut and used for set or resetting it
            logic [CHANNEL_WIDTH - 1 : 0] lut_cnt_reset = 0;
            logic [CHANNEL_WIDTH - 1 : 0] lut_cnt_update = 0;
            logic [CHANNEL_WIDTH - 1 : 0] lut_cnt_readout = 0;
            logic update_lut;

            always @(posedge clk) begin
                wb.ack <= 0;
                wb.dat_o <= 'X;
                start_counting <= 0;
                reset_module <= 0;
                window_size_valid <= 0;
                fifo_rd_en <= 0;
                channel_cnt <= 'X;
                update_lut <= 0;

                if (window_size_valid) begin
                    window_size <= r0window_size;
                end

                lut_cnt_reset <= 0;
                if (reset_module) begin
                    lut_cnt_reset <= lut_cnt_reset + 1;
                    // reset each element to a value out of the range [0 , NUM_OF_CHANNELS - 1]
                    channel_lut[lut_cnt_reset] <= NUM_OF_CHANNELS;
                    lut_cnt_update <= 0;
                    lut_cnt_readout <= 0;
                end

                if (rst || wb.rst) begin
                    r0window_size <= 64'h00000000B2D05E00;  // 1ms
                    num_desired_channels <= NUM_OF_CHANNELS;
                end else begin
                    //-------------------------------------------------------------//
                    /*Here, we verify whether any data is omitted due to the slow reading of data over the
                    Wishbone interface. */

                    /* If FIFO is almost full, new data arrives, and there is no request through the Wishbone
                    interface to read data, then read NUM_OF_CHANNELS samples from the FIFO and discard them.*/
                    if (fifo_prog_full && fifo_wt_en && !discard_enable) begin
                        discard_enable <= 1;
                        channel_cnt <= 0;
                    end

                    if (discard_enable) begin
                        channel_cnt <= channel_cnt + 1;
                        if (channel_cnt == NUM_OF_CHANNELS - 1) begin
                            discard_enable <= 0;
                        end
                        // read `NUM_OF_CHANNELS` samples from FIFO
                        fifo_rd_en   <= 1;
                        discard_cnt  <= discard_cnt + 1;
                        discard_flag <= 1;
                    end
                    //-------------------------------------------------------------//
                    if (wb.stb && wb.cyc && !wb.ack) begin
                        wb.ack <= 1;
                        if (wb.we) begin
                            // Write
                            casez (wb.adr[7:0])
                                8'b000100??: begin  // initializing channel_lut
                                    channel_lut[lut_cnt_update] <= wb.dat_i[CHANNEL_WIDTH-1 : 0];
                                    lut_cnt_update <= lut_cnt_update + 1;
                                end
                                8'b000110??: begin
                                    r0window_size[31:0] <= wb.dat_i;
                                end
                                8'b000111??: begin
                                    r0window_size[63:32] <= wb.dat_i;
                                    window_size_valid <= 1;
                                end
                                8'b001000??: begin
                                    start_counting <= wb.dat_i[0];
                                end
                                8'b001010??: begin
                                    reset_module <= wb.dat_i[0];

                                    // wait until resetting all channel_lut elements
                                    wb.ack <= 0;
                                    if (lut_cnt_reset == CHANNEL_LUT_DEPTH - 1) wb.ack <= 1;
                                end
                                8'b001011??: begin
                                    num_desired_channels <= wb.dat_i[CHANNEL_WIDTH-1 : 0];
                                end

                            endcase
                        end else begin
                            // Read
                            casez (wb.adr[7:0])

                                8'b000000??: wb.dat_o <= 32'h636E7472;  // ASCII: cntr
                                8'b000001??: wb.dat_o <= OUTPUT_FIFO_DEPTH;
                                8'b000010??: wb.dat_o <= NUM_OF_CHANNELS;
                                8'b000011??: wb.dat_o <= CHANNEL_LUT_DEPTH;
                                8'b000100??: begin
                                    wb.dat_o <= channel_lut[lut_cnt_readout];
                                    lut_cnt_readout <= lut_cnt_readout + 1;

                                end
                                8'b000110??: wb.dat_o <= window_size[31:0];
                                8'b000111??: wb.dat_o <= window_size[63:32];
                                8'b001000??: wb.dat_o <= start_counting;
                                // reading counters
                                8'b001001??: begin
                                    /* Read the count of discarded samples if discard_flag is asserted, and then
                              clear the discard_flag. Additionally, refrain from discarding data thereafter.*/
                                    discard_enable <= 0;
                                    if (discard_flag) begin
                                        // Do not assert wb.ack while discard_enable is one.
                                        wb.ack <= !discard_enable;
                                        if (!discard_enable) begin
                                            discard_flag <= 0;
                                            discard_cnt  <= 0;
                                        end
                                        wb.dat_o   <= discard_cnt;
                                        fifo_rd_en <= 0;
                                    end else begin
                                        // Send zero as dummy data when there is no data in the FIFO.
                                        wb.dat_o <= 0;
                                        if (!fifo_empty) begin
                                            // Enable fifo_rd_en for one clock cycle if it's not empty.
                                            fifo_rd_en <= 1;
                                            wb.dat_o   <= fifo_dout;
                                        end
                                    end

                                end
                                8'b001010??: begin
                                    wb.dat_o <= reset_module;
                                end
                                8'b001011??: begin
                                    wb.dat_o <= num_desired_channels;
                                end
                                default: wb.dat_o <= 'X;
                            endcase
                        end
                    end
                end

                if (rst || reset_module || wb.rst) begin
                    discard_enable <= 0;
                    discard_flag <= 0;
                    discard_cnt <= 0;
                end
            end
        end
    endgenerate
    //------------------------------------------------------------------//
    generate
        if (!WISHBONE_INTERFACE_EN) begin
            assign window_size = window_size_i;
            assign start_counting = start_counting_i;
            assign reset_module = reset_module_i;
            assign count_valid_o = count_valid;
            assign count_data_o = count_data;

            always_ff @(posedge clk) begin
                channel_lut <= channel_lut_i;
            end
        end
    endgenerate

endmodule
