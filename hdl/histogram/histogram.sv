/*
 * Histogram
 *
 * This file is part of the Time Tagger software defined digital data
 * acquisition FPGA-link reference design.
 *
 * Copyright (C) 2023 Swabian Instruments, All Rights Reserved
 *
 * Authors:
 * - 2023 Ehsan Jokar <ehsan@swabianinstruments.com>
 *
 * This file is provided under the terms and conditions of the BSD 3-Clause
 * license, accessible under https://opensource.org/licenses/BSD-3-Clause.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

`resetall
`timescale 1ns / 1ps
`default_nettype none


module histogram  #(
    parameter TAG_WIDTH = 64,
    parameter SHIFT_WIDTH = $clog2(TAG_WIDTH),
    parameter NUM_OF_TAGS = 4,
    parameter TOT_TAGS_WIDTH = NUM_OF_TAGS * TAG_WIDTH,
    parameter CHANNEL_WIDTH = 6,
    parameter TOT_CHANNELS_WIDTH = NUM_OF_TAGS * CHANNEL_WIDTH,
    parameter HIST_MEM_DEPTH = 4096,
    parameter HIST_WORD_SIZE = 32,
    parameter HIST_MEM_ADDR_WIDTH = $clog2(HIST_MEM_DEPTH),
    parameter ENABLE_INPUT_REGISTERS= 1
)
(
    // All inputs and outputs are synchronized into clk.
    input wire clk,
    input wire rst,
    input wire [TOT_TAGS_WIDTH - 1 : 0] tagtime,
    input wire [TOT_CHANNELS_WIDTH - 1 : 0] channel,
    input wire [NUM_OF_TAGS - 1 : 0] valid_tag,

    /*
       If hist_read_start remains high for more than one clock
       cycle, its value would be discarded until the next rising
       edge of this input, indicating that if this signal is still
       high while all memory data has beed read, next reading is
       not initiated until the next rising edge of this signal.
    */
    input wire hist_read_start,

    /*
       hist_reset should be aligned with hist_read_start. It means,
       both should be asserted at the same clock cycle, otherwise,
       this reset request will be discarded.
    */
    input wire hist_reset,

    /* Input tagtimes will be discard until setting config inputs.
       When channel_config_en asserted, these inputs will be captured.
       Setting these configurations is not allowed when input tagtimes
       are gathered until asserting hist_reset and hist_read_start.
       During reading the histogram memory, if hist_reset is not asserted,
       it indicates that a longer measurement is intended, and there is no
       need to provide new congiguration. Otherwise, if hist_reset is asserted,
       all the config.s should be set again.
    */
    input wire config_en,
    input wire [CHANNEL_WIDTH - 1 : 0] click_channel,
    input wire [CHANNEL_WIDTH - 1 : 0] start_channel,
    input wire [SHIFT_WIDTH - 1 : 0] shift_val,

    output reg [HIST_WORD_SIZE -1 : 0] data_out,
    output reg valid_out,
    output reg last_sample_out,
    // read latency is 6 clock cycles.
    input wire read_en
    );

    //------------------------------------------------------------------//
    // setting the configurations

    // defining all the possible states
    enum logic[1 : 0]{INITIAL_CONFIG, DATA_GATHERING, MEM_READ} state = INITIAL_CONFIG;

    // register config_en to detect when it is asserted
    logic r1config_en;

    // registers for capturing the config. data
    logic [CHANNEL_WIDTH - 1 : 0] click_channel_reg, start_channel_reg;
    logic [SHIFT_WIDTH - 1 : 0]   shift_val_reg;

    // register hist_read_start to detect when it is asserted
    logic r1hist_read_start;

    // reading memory data samples has been completed
    logic read_completed = 0;

    // latching hist_reset when hist_read_start is asserted
    logic hist_reset_reg = 0;

    // latching hist_read_start
    logic hist_read_start_reg = 0;

    logic toggle = 0;

    logic new_config = 0;

    always_ff @(posedge clk) begin
        r1hist_read_start <= hist_read_start;
        r1config_en <= config_en;
        case (state)
            INITIAL_CONFIG: begin
                new_config <= 0;
                // if new config is available, start measurment
                if (config_en && !r1config_en) begin
                    state <= DATA_GATHERING;
                end
            end

            DATA_GATHERING: begin
                new_config <= 0;
                // resetting hist_reset_reg for the next measurement
                hist_reset_reg <= 0;
                // detecting the risisng edge of hist_read_start
                hist_read_start_reg <= 0;
                if (hist_read_start && !r1hist_read_start) begin
                    state <= MEM_READ;
                    hist_reset_reg <= hist_reset;
                    hist_read_start_reg <= 1;
                    toggle <= ~toggle;
                end
            end
            // data will be read in this state if hist_reset_reg is zero.
            // It means that when we want to read the histogram will do not
            // want to abort the measurment, we continue reading.
            MEM_READ: begin
                if (read_completed) begin
                    state <= DATA_GATHERING;
                    // due to resetting the hist. memory, new configuration is required.
                    if (hist_reset_reg && !new_config) begin
                        state <= INITIAL_CONFIG;
                    end
                end
            end

            default: begin
                state <= INITIAL_CONFIG;
            end
        endcase

        // New configuration can be received if either new config has not been set yet
        // or memory reset is asserted. Therefore, new configuration is required for a
        // new meauserment. When memory reset is asserted, new configuration can be set
        // during reading out the memory of after that. Hence, if a new configuration is
        // set during reading the memory, the values would be latched, and new_config is
        // asserted. Therefore, new configuration is no longer accepted, and the state will
        // switched to DATA_GATHERING after reading out the memory.
        if (state == INITIAL_CONFIG || hist_reset_reg) begin
            if (config_en && !r1config_en && !new_config) begin
                click_channel_reg <= click_channel;
                start_channel_reg <= start_channel;
                shift_val_reg <= shift_val;
                new_config <= 1;
            end
        end

        if (rst) begin
            state <= INITIAL_CONFIG;
            toggle <= 0;
        end

    end

    // Process the input data if we are doing continues measurment,
    // or only the read memory is requested, or the read and reset memory
    // is asserted but during reading the data through the wb interface,
    // a new configuration is asserted. Therefore, there is no need to wait
    // to read the whole data thanks to the ping-pong buffers used in this design
    logic inp_ready;
    assign inp_ready = ((!hist_reset_reg && state == MEM_READ)
                        || state == DATA_GATHERING
                        || (hist_reset_reg && new_config)) ? 1 : 0;

    // when hist_read_start is asserted, it takes a few clock cycles to update
    // the memory with respect to the last data. Therefore, we delay the both
    // hist_read_start_reg and hist_reset_reg signals eight clock cycles, and
    // then start reading out the memory and possibly reset it.
    localparam DELAY_SIZE = 8;
    logic [DELAY_SIZE-1 : 0] reset_buf, read_buf;
    logic reset_mem, read_mem;
    always_ff @(posedge clk) begin
        reset_buf <= {reset_buf[6 : 0], hist_reset_reg};
        read_buf <= {read_buf[6 : 0], hist_read_start_reg};
    end
    // these signals are used for resetting and reading the memory
    assign reset_mem = (state == MEM_READ) ? reset_buf[DELAY_SIZE - 1] : 0;
    assign read_mem = (state == MEM_READ) ? read_buf[DELAY_SIZE - 1] : 0;

    //------------------------------------------------------------------//
    // detecting the start and click channels' data and computing
    // the difference between start channel and click channel data

    // This signal is asserted when the first data from the start channel
    // is detected. It will remain high until the end of the current measurement.
    // When this signal is zero, all detected data from click channel will be
    // discarded as there is no starting channel data to compute the difference.
    logic detected_start_data = 0;
    logic r1detected_start_data;

    // to store the last data comes from the start channel
    logic [TAG_WIDTH - 1 : 0] last_start_data;
    logic [TAG_WIDTH - 1 : 0] r1last_start_data;

    // to compute the difference between the data samples
    // come from start and clock channels
    logic [TOT_TAGS_WIDTH - 1 : 0] r0diff_value, diff_value;
    logic [NUM_OF_TAGS - 1 : 0] r0diff_value_valid, diff_value_valid;

    // register the inputs if needed
    logic [TOT_TAGS_WIDTH - 1 : 0] r1tagtime;
    logic [TOT_CHANNELS_WIDTH - 1 : 0] r1channel;
    logic [NUM_OF_TAGS - 1 : 0] r1valid_tag;
    logic r1inp_ready;
    generate
        if (ENABLE_INPUT_REGISTERS == 1) begin
            always_ff @(posedge clk) begin
                r1tagtime <= tagtime;
                r1channel <= channel;
                r1valid_tag <= valid_tag;
                r1inp_ready <= inp_ready;
            end
        end else begin
            assign r1tagtime = tagtime;
            assign r1channel = channel;
            assign r1valid_tag = valid_tag;
            assign r1inp_ready = inp_ready;
        end
    endgenerate

    always_comb begin
        // resetting detected_start_data for next measurement
        // This signal is reset when we want to do a measurement with
        // different channels. In this case, reset_mem is asserted, and
        // this signal is deasserted. For contineous measurment, this signal
        // is not deasserted. Therefore, after reading out the hisogram memory,
        // it can be updated with the last start data.
        if (reset_mem) begin
            detected_start_data = 0;
        end

        r0diff_value_valid = 0;
        r0diff_value = 'X;
        detected_start_data = r1detected_start_data;
        last_start_data = r1last_start_data;
        for (int i = 0; i < NUM_OF_TAGS; i++) begin
            // detecting the data samples coming from the start channel
            if((r1channel[i*CHANNEL_WIDTH +:CHANNEL_WIDTH] == start_channel_reg) && r1inp_ready && r1valid_tag[i]) begin
                detected_start_data = 1;
                last_start_data = r1tagtime[i*TAG_WIDTH +: TAG_WIDTH];
            end
            // detecting the data samples coming from the click channel
            if((r1channel[i*CHANNEL_WIDTH +:CHANNEL_WIDTH] == click_channel_reg)
             && r1inp_ready && r1valid_tag[i] && detected_start_data) begin
                r0diff_value[i*TAG_WIDTH +: TAG_WIDTH] = r1tagtime[i*TAG_WIDTH +: TAG_WIDTH] - last_start_data;
                r0diff_value_valid[i] = 1;
            end
        end
    end

    // use register to avoid inferring latch
    always_ff @(posedge clk) begin
        r1detected_start_data <= detected_start_data;
        r1last_start_data <= last_start_data;

        if (rst) begin
            r1detected_start_data <= 0;
        end
    end

    // register the outputs
    always_ff @(posedge clk) begin
        diff_value <= r0diff_value;
        diff_value_valid <= r0diff_value_valid;
    end

    //------------------------------------------------------------------//
    // using barrel shifter to shift the data aimed at adjusting the bin size

    logic [TOT_TAGS_WIDTH - 1 : 0] bs_data_out;
    logic [NUM_OF_TAGS - 1 : 0] bs_valid_out;

    genvar i, j;
    generate
        for (i=0; i < NUM_OF_TAGS; i++) begin
            always_ff @(posedge clk) begin
                bs_valid_out[i] <= diff_value_valid[i];
                bs_data_out[i*TAG_WIDTH +: TAG_WIDTH] <= 'X;
                if(diff_value_valid[i]) begin
                    bs_data_out[i*TAG_WIDTH +: TAG_WIDTH] <= diff_value[i*TAG_WIDTH +: TAG_WIDTH] >> shift_val_reg;
                end
            end
        end
    endgenerate

    //------------------------------------------------------------------//
    // implemetation of Histogram module

    // supports up to four tags
    wire [NUM_OF_TAGS * HIST_WORD_SIZE - 1 : 0] hist_dout[2];
    wire [NUM_OF_TAGS - 1 : 0] hist_valid_out[2];
    wire [NUM_OF_TAGS - 1 : 0] last_sample[2];
    logic mem_active[2];

    // reading the histogram information: here, we generate the address
    // and the enable for reading data from the memories
    logic [HIST_MEM_ADDR_WIDTH : 0] cnt_addr;
    logic [HIST_MEM_ADDR_WIDTH - 1 : 0] mem_read_addr;
    logic mem_read_en;
    logic r1rst;
    always_ff @(posedge clk) begin
        mem_read_en <= 0;
        mem_read_addr <= cnt_addr[HIST_MEM_ADDR_WIDTH - 1 : 0];
        if (state == DATA_GATHERING) begin
            cnt_addr <= 0;
        end else if (read_mem) begin
            if (read_en && cnt_addr[HIST_MEM_ADDR_WIDTH]==0) begin
                mem_read_en <= 1;
                cnt_addr <= cnt_addr + 1;
            end
        end

        r1rst <= rst;
        if (rst^r1rst) begin
            cnt_addr <= 0;
        end else if (rst) begin
            // generating address for reading out the BRAMs and resetting them
            mem_read_en <= 1;
            cnt_addr <= cnt_addr + 1;
            if (cnt_addr > HIST_MEM_DEPTH-1) begin
                mem_read_en <= 0;
            end
        end
    end

    generate
        for (i = 0; i < NUM_OF_TAGS; i++) begin
            // Here we use the idea of double-buffering to process the income data and
            // store them in one of the memories while we read from another.
            // Here, we reset the memory after reading, indicating that we only store the
            // information of the time-frame we started measuring. It means that when we read
            // the memory, we only send the partial information into the software. When the
            // partial data is read at the backend, it's the backend responsibility to sum
            // up the partial data with the previous summation. This can avoid data overflow
            // in FPGA. Backend can use 64-bit data representation for storing the whole data.

            assign mem_active[0] = toggle;
            assign mem_active[1] = !toggle;
            for (j = 0; j < 2; j++) begin
                // Generating the proper address for each hist_1lane
                // module in DATA_GATHERING state
                logic [TAG_WIDTH - 1 : 0] wide_address;
                assign wide_address   = mem_active[j] ? 'X : bs_data_out[i*TAG_WIDTH +: TAG_WIDTH];
                logic [HIST_MEM_ADDR_WIDTH - 1 : 0] address_in;
                logic address_valid_in;
                always_ff @(posedge clk) begin
                    address_valid_in <= 0;
                    address_in <= 'X;
                    if ((read_mem && mem_active[j]) | rst) begin
                        // address assignment in MEM_READ state
                        address_in <= mem_read_addr;
                        address_valid_in <= mem_read_en;
                    end else if (!mem_active[j] && !hist_reset_reg) begin
                        // address assignment in DATA_GATHERING state
                        address_in <= wide_address[HIST_MEM_ADDR_WIDTH - 1 : 0];
                        if (wide_address[TAG_WIDTH - 1 : HIST_MEM_ADDR_WIDTH] != 0) begin
                            address_in <= '1;
                        end
                        address_valid_in <= bs_valid_out[i];
                    end
                end

                Hist_1lane # (
                .HIST_MEM_DEPTH(HIST_MEM_DEPTH),
                .HIST_WORD_SIZE(HIST_WORD_SIZE),
                .HIST_MEM_ADDR_WIDTH(HIST_MEM_ADDR_WIDTH)
                )
                Hist_1lane_inst (
                .clk(clk),
                .address_in(address_in),
                .valid_in(address_valid_in),
                // if rst is one, start reading out and resetting all memories.
                .hist_rst((read_mem  && mem_active[j]) | rst), // reset the memory during reading it
                .hist_read((read_mem  && mem_active[j]) | rst),
                .data_out(hist_dout[j][i*HIST_WORD_SIZE +: HIST_WORD_SIZE]),
                .valid_out(hist_valid_out[j][i]),
                .last_sample(last_sample[j][i])
                );
            end
        end
    endgenerate

    // For a four-tage addition, one level of logic would be fine;
    // however, if the number of tags increases 4, a pipeline stage
    // for addition will be needed.
    logic [HIST_WORD_SIZE - 1 : 0] sum;
    logic r1hist_valid_out;
    logic r1last_sample;
    logic [NUM_OF_TAGS * HIST_WORD_SIZE - 1 : 0] r1hist_dout;
    always_ff @(posedge clk) begin
        r1hist_dout <= toggle ? hist_dout[0] : hist_dout[1];
        r1hist_valid_out <= toggle ? hist_valid_out[0][0] : hist_valid_out[1][0];
        r1last_sample <= toggle ? last_sample[0][0] : last_sample[1][0];
        valid_out <= r1hist_valid_out;
        read_completed <= r1last_sample;
        last_sample_out <= r1last_sample;
        data_out <= 'X;
        if(r1hist_valid_out) begin
            data_out <= sum;
        end
    end
    always_comb begin
        sum = r1hist_dout[0 +: HIST_WORD_SIZE];
        for (int i = 1; i <  NUM_OF_TAGS; i++) begin
            sum = sum + r1hist_dout[i*HIST_WORD_SIZE +: HIST_WORD_SIZE];
        end
    end


//------------------------------------------------------------------//

endmodule