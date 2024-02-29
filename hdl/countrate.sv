/*
 * countrate
 *
 * This file is part of the Time Tagger software defined digital data
 * acquisition FPGA-link reference design.
 *
 * Copyright (C) 2023 Swabian Instruments, All Rights Reserved
 *
 * Authors:
 * - 2023-2024 Ehsan Jokar <ehsan@swabianinstruments.com>
 */

 `resetall
 `timescale 1ns / 1ps
 `default_nettype none


module countrate #(
    parameter TAG_WIDTH =  64,
    parameter NUM_OF_TAGS = 4,
    parameter TOT_TAGS_WIDTH = NUM_OF_TAGS * TAG_WIDTH,
    parameter CHANNEL_WIDTH = 6,
    parameter TOT_CHANNELS_WIDTH = NUM_OF_TAGS * CHANNEL_WIDTH,
    parameter WINDOW_WIDTH = TAG_WIDTH,
    parameter NUM_OF_CHANNELS = 16,
    parameter COUNTER_WIDTH = 32,
    parameter INPUT_FIFO_DEPTH = 1024

)
(
    /* All inputs and outputs are synchronized into the clk. if some controlling
    signals are generated in different clock domains, cdc should be used
    for synchronization outside of this module.
    */
    input wire clk,
    input wire rst,

    input wire [NUM_OF_TAGS - 1 : 0] valid_tag,
    input wire [TOT_TAGS_WIDTH - 1 : 0] tagtime,
    /*There is a possibility to receive a keep alive tag in order to update the
    window information and update the PC or the downstream module with the existence
    of empty wondows. This will happen if we don't receive any real tag for a long period.
    To deal with this, the keep alive would be an effective solution. This tag can come with
    a channel number outside of [0 : NUM_OF_CHANNELS) range. */
    input wire [TOT_CHANNELS_WIDTH - 1 : 0] channel,

    /*The window_size resolution is 1/3 ps, aligning with the tagtime input. It is possible to
    modify the window_size dynamically during runtime. However, any changes made will take
    effect after two consecutive instances of the specified window_size.*/
    input wire [WINDOW_WIDTH - 1 : 0] window_size,

    /* When start_counting is asserted, the channel counting is started
    and the counter values will be output by the end of each window. The
    start point of the first window would be the time of the tag coming
    after assetion of start_counting.
    */
    input wire start_counting,
    /* when reset_counting is asserted, all the process is reset, and the
    core waits for asserting start_counting.
    */
    input wire reset_counting,

    //Each lane represents the count of detected tags in its respective channel.
    output wire [COUNTER_WIDTH - 1 : 0] count_data [NUM_OF_CHANNELS],

    /* The countrate_wrapper module is tasked with receiving data when
    count_valid is asserted. Within the countrate_wrapper module, it is
    essential to employ dedicated async FIFOs to store the outputs if the
    data is read by PC. If data is read by downstream module inside FPGA,
    it's responsible to rerceive the data whenever the count_valid signal is
    asserted. If needed, downstream module can use FIFO per each lane to read
    them whenever it wants.
    */
    output wire count_valid
    );

    //------------------------------------------------------------------//
    // Input FIFOs

    // register input signals
    logic [NUM_OF_TAGS - 1 : 0] r1valid_tag;
    logic [TOT_TAGS_WIDTH - 1 : 0] r1tagtime;
    logic [TOT_CHANNELS_WIDTH - 1 : 0] r1channel;
    logic [TAG_WIDTH - 1 : 0] r1window_size;

    /*This signal indicate whether there is at least one valid tag or not.
    If so, the inputs tagtime, channel, and valid_tag will be written into
    the corresponding FIFO.*/
    logic valid_tag_or;

    always_ff @(posedge clk) begin
        r1valid_tag <= valid_tag;
        r1tagtime <= tagtime;
        r1channel <= channel;
        r1window_size <= window_size;
        valid_tag_or <= |valid_tag;
    end

    logic fifo_empty;
    logic inp_fifo_rd_en = 1;

    logic fifo_data_valid;
    assign fifo_data_valid = !fifo_empty && inp_fifo_rd_en;

    logic [NUM_OF_TAGS - 1 : 0] valid_tag_o;
    logic [TOT_TAGS_WIDTH - 1 : 0] tagtime_o;
    logic [TOT_CHANNELS_WIDTH - 1 : 0] channel_o;

   xpm_fifo_sync #(
       .FIFO_MEMORY_TYPE("auto"),
       .FIFO_READ_LATENCY(2),
       .FIFO_WRITE_DEPTH(INPUT_FIFO_DEPTH),
       .READ_DATA_WIDTH(NUM_OF_TAGS + TOT_TAGS_WIDTH + TOT_CHANNELS_WIDTH),
       .READ_MODE("fwft"),
       .USE_ADV_FEATURES("1707"),
       .WRITE_DATA_WIDTH(NUM_OF_TAGS + TOT_TAGS_WIDTH + TOT_CHANNELS_WIDTH)
    )
    valid_fifo_inst (
       .dout({valid_tag_o, tagtime_o, channel_o}),
       .empty(fifo_empty),
       .din({r1valid_tag, r1tagtime, r1channel}),
       .rd_en(inp_fifo_rd_en),
       .rst(rst),
       .wr_clk(clk),
       .wr_en(valid_tag_or)
    );

    //------------------------------------------------------------------//
    // unpacking the FIFO's outputs
    typedef struct{
        logic valid[NUM_OF_TAGS];
        logic [TAG_WIDTH - 1 : 0] time_tag[NUM_OF_TAGS];
        logic [CHANNEL_WIDTH - 1 : 0] channel[NUM_OF_TAGS];
    } data_type;

    data_type data;
    always_comb begin
        for (int i = 0; i < NUM_OF_TAGS; i++) begin
            if (fifo_data_valid) begin
                data.valid[i] <= valid_tag_o[i];
                data.time_tag[i] <= tagtime_o[i*TAG_WIDTH +: TAG_WIDTH];
                data.channel[i] <= channel_o[i*CHANNEL_WIDTH +:CHANNEL_WIDTH];
            end

        end
    end

    //------------------------------------------------------------------//
    // Updating the window information
    logic start_counting_hold = 0;
    logic [TAG_WIDTH - 1 : 0] window_start;
    logic [TAG_WIDTH - 1 : 0] window_end;
    logic [TAG_WIDTH - 1 : 0] next_window_end;
    logic start_measurement = 0;
    logic update_window;
    localparam DELAY_BUFF_SIZE = 3;
    logic [DELAY_BUFF_SIZE -1 : 0] update_window_delays = 0;

    /* Window is updated when update_window is asserted. If all the valid tags in the current
    clock cycle belong to the current window, update_window would be zero. If valid tags belong
    to both the current window and the next one, update_window will be asserted immediately and
    remains high for one clock cycle. Therefore, window will be updated, and the tags at the next
    clock cycle would be compared with the updated window. If a tag belongs to a window that is
    neither the current window nor the next one (at least two windows away), no data will be read
    from the FIFOs, and the updating process continues until the window becomes the next window
    for the last valid tag.
    */

    always_ff @(posedge clk) begin
        // resetting start_measurement for the next measurement
        if (rst || reset_counting) begin
            start_measurement <= 0;
        end

        /* When start_counting is asserted, start_counting_hold will be set to one and remain
        high until receiving a valid tag to initialize the window information.*/
        if (rst || reset_counting || (start_counting_hold && fifo_data_valid)) begin
            start_counting_hold <= 0;
        end else if (start_counting) begin
            start_counting_hold <= 1;
        end

        // initializing the first window
        if (!start_measurement) begin
            for (int i = NUM_OF_TAGS - 1; i >= 0; i--) begin
                if(data.valid[i] && fifo_data_valid && start_counting_hold) begin
                    window_start <= data.time_tag[i];
                    window_end <= data.time_tag[i] + r1window_size;
                    next_window_end <= data.time_tag[i] + (r1window_size << 1);
                    start_measurement <= 1;
                    break;
                end
            end
        end
        else if (update_window) begin
            /* This type of updating the window information allows to dynamically change the window size
            during runtime. */
            window_start <= window_end;
            window_end <= next_window_end;
            next_window_end <= next_window_end + r1window_size;
        end

        update_window_delays[DELAY_BUFF_SIZE - 1 : 0] <= {update_window_delays[DELAY_BUFF_SIZE - 2 : 0], update_window};
    end
    //------------------------------------------------------------------//
    // calculating the difference between data.time_tag and the end of the current and next windows

    /* Here, we employ differentiators instead of comparators to determine whether a tag belongs to
    the current window, the next one, or neither. The key concept here is that using differentiators
    enables us to conduct comparisons even when one of the operands overflows. This capability allows
    us to process tags to infinity.*/
    logic [TAG_WIDTH - 1 : 0] difference[2][NUM_OF_TAGS];
    always_comb begin
        for (int i = 0; i < NUM_OF_TAGS; i++) begin
            difference[0][i] <= data.time_tag[i] - window_end;
            difference[1][i] <= data.time_tag[i] - next_window_end;
        end
    end
    //------------------------------------------------------------------//
    // updating detected_channel information

    /* This block is tasked with determining whether the last valid tag belongs to the neither the current
    not the next window. If so, inp_fifo_rd_en is deasserted immediately, and no data is read from the FIFOs.
    'extended_valid' is also asserted to indicate that the received tags remain valid and will be utilized
    for multiple clock cycles. After updating the window until it becomes the next window for the last
    valid tag, 'inp_fifo_rd_en' is once again asserted to read new data from the FIFOs, and 'extended_valid'
    is subsequently deasserted.
    It is important to highlight that if all the tags in a clock cycle belong to both the current and the next
    window, the subsequent data will be read from the FIFO. This eliminates any idle cycle in this scenario,
    albeit at the expense of counting the number of tags associated with both the current and the next window.
    */
    logic r0inp_fifo_rd_en = 1;
    logic extended_valid = 0;
    always_comb begin
        r0inp_fifo_rd_en = inp_fifo_rd_en;
        for (int i = 0; i < NUM_OF_TAGS; i++) begin
            if(data.valid[i] && fifo_data_valid && start_measurement) begin
                // !difference[1][i][TAG_WIDTH-1] is the same as data.time_tag[i] >= next_window_end
                if (!difference[1][i][TAG_WIDTH-1]) begin
                    r0inp_fifo_rd_en = 0;
                end
            end
        end
        if (!inp_fifo_rd_en && update_window_delays[0] && !update_window) begin
            r0inp_fifo_rd_en = 1;
        end
        extended_valid = !r0inp_fifo_rd_en;
    end
    always_ff @(posedge clk) begin
        inp_fifo_rd_en <= r0inp_fifo_rd_en;
    end

    /*
    If any tags belong to the subsequent windows, there is a need to update the window information for the
    upcoming tags in the next clock cycle. If a tag belongs to a window that is neither the current window nor
    the next one (at least two windows away), no data will be read from the FIFOs, and the updating process
    continues until the window becomes the next window for the last valid tag.

    Consider a scenario in which a tag is associated with a window 10 cycles later. Consequently, window_update
    will be set to 1 for 10 clock cycles, facilitating the continuous update of the window information during this
    period until that particular window becomes the next window for the tag.
    */
    always_comb begin
        update_window   <= 0;
        for (int i = 0; i < NUM_OF_TAGS; i++) begin
            if (data.valid[i] && (fifo_data_valid || extended_valid) && start_measurement) begin
                // !difference[0][i][TAG_WIDTH-1] is the same as data.time_tag[i] >= window_end
                if (!difference[0][i][TAG_WIDTH-1]) begin
                    update_window   <= 1;
                end
            end
        end
    end

    /* detected_channel[0] monitors tags associated with the current window. If any tags belong
    to the subsequent window, the corresponding register in detected_channel[1] is set to one.
    If a tag belongs to neither the current nor the next window, the respective register in
    detected_channel remains zero.

    Consider a scenario where all tags are valid, with the first and last belonging to channel 2
    and the second and third to channel 7. If the last tag belongs to the next window and the first
    three to the current window (assuming NUM_OF_TAGS is 4), then detected_channel[0][2] would be 0001,
    detected_channel[0][7] would be 0110, and detected_channel[1][2] would be 1000. This indicates that
    there is one tag belonging to channel 2 and two tags to channel 7 in the current window, and one tag
    belonging to channel 2 in the next window.

    detected_channel exclusively stores information about tags present in the current clock cycle.
    Subsequently, this information is decoded into numerical values by simply adding the number of one
    bits for each channel, which are then incorporated into dedicated counters.
    */
    logic [NUM_OF_TAGS - 1 : 0] detected_channel[2][NUM_OF_CHANNELS] = '{default:'0};

    always_ff @(posedge clk) begin
        detected_channel <= '{default:'0};
        for (int i = 0; i < NUM_OF_TAGS; i++) begin
            if (data.valid[i] && (fifo_data_valid || extended_valid) && start_measurement) begin
                // difference[0][i][TAG_WIDTH-1] is the same as data.time_tag[i] < window_end
                if (difference[0][i][TAG_WIDTH-1] && fifo_data_valid) begin
                    for (int j = 0; j < NUM_OF_CHANNELS; j++) begin
                        if (j == data.channel[i]) begin
                            detected_channel[0][j][i] <= 1;
                        end
                    end
                end
                // difference[1][i][TAG_WIDTH-1] is the same as data.time_tag[i] < next_window_end
                // !difference[0][i][TAG_WIDTH-1] is the same as data.time_tag[i] >= window_end
                else if (difference[1][i][TAG_WIDTH-1] && !difference[0][i][TAG_WIDTH-1]) begin
                    for (int j = 0; j < NUM_OF_CHANNELS; j++) begin
                        if (j == data.channel[i]) begin
                            detected_channel[1][j][i] <= 1;
                        end
                    end
                end
            end
        end
    end

    //------------------------------------------------------------------//
    // Updating the counters value and the outputs

    //This block counts the number of tags for each channels in both the current and next window.
    localparam SUM_WIDTH = $clog2(NUM_OF_TAGS + 1);
    typedef logic [SUM_WIDTH - 1 : 0] part_sum_type[2][NUM_OF_CHANNELS];
    part_sum_type r0partial_sum, partial_sum;
    always_comb begin
        r0partial_sum = '{default:'0};
        for (int i = 0; i < NUM_OF_CHANNELS; i++) begin
            for (int j = 0; j < NUM_OF_TAGS; j++) begin
                r0partial_sum[0][i] = r0partial_sum[0][i] + detected_channel[0][i][j];
                r0partial_sum[1][i] = r0partial_sum[1][i] + detected_channel[1][i][j];
            end
        end
    end

    logic [COUNTER_WIDTH - 1 : 0] counters[NUM_OF_CHANNELS];
    // this registers are used to capter the value of the counter by the end of the window
    logic [COUNTER_WIDTH - 1 : 0] counters_reg[NUM_OF_CHANNELS];
    always_ff @(posedge clk) begin
        partial_sum <= r0partial_sum;
        // reset the counters for a new measurement

        counters_reg <= '{default:'X};
        if (start_measurement) begin
            for (int i = 0; i < NUM_OF_CHANNELS; i++) begin
                /*update_window_delays[1] is the delayed update_window signal aligned with partial_sum.
                If it's zero, counters will be updated for the current window. If not, counters will be
                initialized with partial_sum[1] which is the tags information belong to the next window.
                */
                counters[i] <= counters[i] + partial_sum[0][i];
                if (update_window_delays[1]) begin
                    counters[i] <= partial_sum[1][i];
                    /*When 'update_window_delays[1]' is asserted, the last 'partial_sum[0]' values are
                    added to the counters, and the resulting sums are registered at 'counters_reg'.
                    This guarantees that information from all tags has been accounted for.
                    */
                    counters_reg[i] <= counters[i] + partial_sum[0][i];
                end
            end
        end

        if (rst || reset_counting) begin
            counters <= '{default:'0};
        end
    end

    assign count_data = counters_reg;
    assign count_valid = update_window_delays[2];

endmodule
