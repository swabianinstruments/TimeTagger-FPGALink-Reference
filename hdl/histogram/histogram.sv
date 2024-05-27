/*
 * Histogram
 *
 * This file is part of the Time Tagger software defined digital data
 * acquisition FPGA-link reference design.
 *
 * Copyright (C) 2023 Swabian Instruments, All Rights Reserved
 *
 * Authors:
 * - 2023-2024 Ehsan Jokar <ehsan@swabianinstruments.com>
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

/*
There are two ways to configure this module and receive data from it:

1. Using the Wishbone interface.
2. Utilizing a downstream FPGA module.

During bitstream generation, only one of these options is synthesized.
Here are the differences between these two choices:

If you intend to process the histogram data using a PC, you should transfer
the data via the Wishbone interface and configure this module by sending the
appropriate commands through this interface. To do this, you need to set the parameter
WISHBONE_INTERFACE_EN to 1. When you opt for the Wishbone interface, you will
receive the histogram information for the time interval between the last two read
commands if you are conducting a long measurement. Consequently, it becomes the backend
responsibility to add this partial information to the previous one to calculate
the complete histogram. Additionally, no statistics are provided in this case.

If you plan to process the histogram data within the FPGA, you should supply the
module with the necessary configuration data and appropriate read/reset commands.
When your downstream module requests the histogram data, the updated value for each
bin is sent to it, eliminating the need for storage inside your module to update
the histogram information. Furthermore, the information is transmitted continuously from
the first bin to the last one with a few clock cycles latency. Therefore, the downstream module
should be ready to receive all the histogram data without any gaps of `valid_out_o` by
the upstream module.

Additionally, a few clock cycles after receiving the information of all the bins, the downstream
module will be supplied with the following statistics:

1. Weighted means: ∑n*x(n) / ∑x(n)
2. The index of the bin with the largest value
3. Variance (the square of the weighted standard deviation): ∑(x(n)*(n-offset)*(n-offset)) / ∑x(n)
*/

module histogram #(
    parameter WISHBONE_INTERFACE_EN = 1,
    parameter HIST_MEM_DEPTH = 4096,
    parameter CHANNEL_WIDTH = 6,
    parameter SHIFT_WIDTH = 6,
    parameter HIST_WORD_SIZE = 32,
    parameter HIST_MEM_ADDR_WIDTH = $clog2(HIST_MEM_DEPTH),
    parameter ENABLE_INPUT_REGISTERS = 1,
    parameter VARIANCE_WIDTH = 32
) (
    axis_tag_interface.slave s_axis,

    //    Wishbone interface for control & status      		//
    wb_interface.slave wb,

    //       	 downstream module interface                //
    input wire hist_read_start_i,
    input wire hist_reset_i,
    input wire config_en_i,
    input wire [CHANNEL_WIDTH - 1 : 0] click_channel_i,
    input wire [CHANNEL_WIDTH - 1 : 0] start_channel_i,
    input wire [SHIFT_WIDTH - 1 : 0] shift_val_i,
    output reg [2*HIST_WORD_SIZE -1 : 0] data_out_o,
    output reg valid_out_o,

    // Statistics
    /* all the following statistics are valid when statistics_valid
	   is asserted. The downstream module should capture these values
	   for later usage. After reading the bins value, it will take a few
	   hundreds clock cycles to assert statistics_valid.*/
    output reg statistics_valid,
    output reg [HIST_MEM_ADDR_WIDTH - 1 : 0] index_max,
    output reg [HIST_MEM_ADDR_WIDTH - 1 : 0] offset,  // 0 ~ HIST_MEM_DEPTH-1
    output reg [VARIANCE_WIDTH - 1 : 0] variance  // square of weighted standard deviation

);

    assign s_axis.tready = 1;

    localparam integer WORD_WIDTH = s_axis.WORD_WIDTH;
    localparam integer TIME_WIDTH = s_axis.TIME_WIDTH;
    localparam integer TOT_TAGS_WIDTH = WORD_WIDTH * TIME_WIDTH;
    localparam integer TOT_CHANNELS_WIDTH = WORD_WIDTH * CHANNEL_WIDTH;

    logic [TOT_TAGS_WIDTH-1:0] tagtime;
    logic [TOT_CHANNELS_WIDTH-1:0] channel;

    always_comb begin
        for (int i = 0; i < WORD_WIDTH; i++) begin
            tagtime[i*TIME_WIDTH+:TIME_WIDTH] <= s_axis.tagtime[i];
            channel[i*CHANNEL_WIDTH+:CHANNEL_WIDTH] <= s_axis.channel[i];
        end
    end

    //------------------------------------------------------------------//
    // histogram module

    logic hist_read_start;
    logic hist_reset;
    logic config_en;
    logic [CHANNEL_WIDTH - 1 : 0] click_channel;
    logic [CHANNEL_WIDTH - 1 : 0] start_channel;
    logic [SHIFT_WIDTH - 1 : 0] shift_val;
    logic [HIST_WORD_SIZE -1 : 0] hist_data_out;
    logic hist_valid_out;
    logic hist_read_en;
    logic reset_hist_module;
    logic last_sample;

    histogram_impl #(
        .TAG_WIDTH(TIME_WIDTH),
        .SHIFT_WIDTH(SHIFT_WIDTH),
        .NUM_OF_TAGS(WORD_WIDTH),
        .TOT_TAGS_WIDTH(TOT_TAGS_WIDTH),
        .CHANNEL_WIDTH(CHANNEL_WIDTH),
        .TOT_CHANNELS_WIDTH(TOT_CHANNELS_WIDTH),
        .HIST_MEM_DEPTH(HIST_MEM_DEPTH),
        .HIST_WORD_SIZE(HIST_WORD_SIZE),
        .HIST_MEM_ADDR_WIDTH(HIST_MEM_ADDR_WIDTH),
        .ENABLE_INPUT_REGISTERS(ENABLE_INPUT_REGISTERS)
    ) histogram_impl_inst (
        .clk(s_axis.clk),
        .rst(reset_hist_module),
        .tagtime(tagtime),
        .channel(channel),
        .valid_tag(s_axis.tvalid ? s_axis.tkeep : '0),
        .hist_read_start(hist_read_start),
        .hist_reset(hist_reset),
        .config_en(config_en),
        .click_channel(click_channel),
        .start_channel(start_channel),
        .shift_val(shift_val),
        .data_out(hist_data_out),
        .valid_out(hist_valid_out),
        .last_sample_out(last_sample),
        .read_en(hist_read_en)
    );
    //------------------------------------------------------------------//

    generate
        if (WISHBONE_INTERFACE_EN) begin
            //------------------------------------------------------------------//
            // Output FIFO signals
            logic [31 : 0] fifo_dout;
            logic fifo_data_valid;
            logic fifo_rd_en, fifo_empty;
            logic fifo_prog_full;
            logic [31 : 0] config_data;
            logic hist_is_running = 0;

            assign start_channel = config_data[0+:CHANNEL_WIDTH];
            assign click_channel = config_data[CHANNEL_WIDTH+:CHANNEL_WIDTH];
            assign shift_val     = config_data[2*CHANNEL_WIDTH+:SHIFT_WIDTH];

            always @(posedge wb.clk) begin
                wb.ack <= 0;
                wb.dat_o <= 'X;
                config_en <= 0;
                hist_read_start <= 0;
                hist_reset <= 0;
                fifo_rd_en <= 0;
                reset_hist_module <= 0;
                if (config_en) begin
                    hist_is_running <= 1;
                end else if (hist_reset) begin
                    hist_is_running <= 0;
                end

                if (wb.rst) begin
                    wb.dat_o <= 0;
                    config_data <= 'X;
                end else if (wb.cyc && !wb.ack) begin
                    wb.ack <= 1;
                    if (wb.we) begin
                        // Write
                        casez (wb.adr[7:0])
                            // 8'b000011??: begin

                            // end
                            8'b000011??: begin
                                config_data <= wb.dat_i;
                                config_en   <= 1;
                            end
                            8'b000100??: begin
                                hist_read_start <= wb.dat_i[0];
                                // reset the BRAMs for next measurement
                                hist_reset <= wb.dat_i[1];
                                // reset the module
                                reset_hist_module <= wb.dat_i[2];

                                if (wb.dat_i[2]) begin
                                    // deassert the wb.ack until resetting the whole BRAMs
                                    wb.ack <= 0;
                                    if (last_sample) begin
                                        wb.ack <= 1;
                                    end
                                end
                            end
                        endcase
                    end else begin
                        // Read
                        casez (wb.adr[7:0])

                            8'b000000??: wb.dat_o <= 32'h68697374;  // ASCII: hist
                            8'b000001??: wb.dat_o <= HIST_MEM_DEPTH;
                            8'b000010??: wb.dat_o <= hist_is_running;
                            8'b000011??: wb.dat_o <= config_data;
                            8'b000100??: wb.dat_o <= 0;
                            // If the output FIFO is not empty, the data will be available immediately,
                            // otherwise, we should delay asserting wb.ack until arriving a new data
                            8'b000101??: begin
                                wb.dat_o <= fifo_dout;
                                wb.ack <= fifo_data_valid;
                                fifo_rd_en <= 1;
                                // to make sure that we only read one data from FIFO
                                if (fifo_data_valid) fifo_rd_en <= 0;
                            end
                            default: wb.dat_o <= 'X;
                        endcase
                    end
                end else begin
                    wb.dat_o <= 0;
                end
            end

            //------------------------------------------------------------------//
            // Output FIFO

            xpm_fifo_sync #(
                .FIFO_MEMORY_TYPE("auto"),     // string; "auto", "block", or "distributed";
                .FIFO_WRITE_DEPTH(64),
                .WRITE_DATA_WIDTH(HIST_WORD_SIZE),
                .READ_DATA_WIDTH(32),
                .PROG_FULL_THRESH(50),
                .READ_MODE("fwft"),
                .FULL_RESET_VALUE(1),
                .USE_ADV_FEATURES("0707")
            ) output_buffer (
                .rst(s_axis.rst | reset_hist_module),
                .wr_clk(s_axis.clk),
                .wr_en(hist_valid_out),
                .din(hist_data_out),
                .prog_full(fifo_prog_full),
                .dout(fifo_dout),
                .empty(fifo_empty),
                .rd_en(fifo_rd_en)
            );

            assign fifo_data_valid = !fifo_empty && fifo_rd_en;
            // read the BRAMs if reset_hist_module is 1
            assign hist_read_en = !fifo_prog_full | reset_hist_module;

            /* These outputs are not used when WISHBONE_INTERFACE_EN is one, but initialized to
               zero to fix warnings */
            always_comb begin
                data_out_o <= 0;
                valid_out_o <= 0;
                statistics_valid <= 0;
                index_max <= 0;
                offset <= 0;
                variance <= 0;
            end

        end
    endgenerate

    //------------------------------------------------------------------//
    generate
        if (!WISHBONE_INTERFACE_EN) begin
            //----------------------------------------------------------//
            // assigning the histogram ports
            assign hist_read_start = hist_read_start_i;
            assign hist_reset = hist_reset_i;
            assign config_en = config_en_i;
            assign click_channel = click_channel_i;
            assign start_channel = start_channel_i;
            assign shift_val = shift_val_i;
            assign hist_read_en = 1;
            assign reset_hist_module = 0;

            //----------------------------------------------------------//
            // Simple Dual Port Memory to store the final bins value
            localparam BRAM_DATA_WIDTH = 2 * HIST_WORD_SIZE;
            reg [BRAM_DATA_WIDTH - 1 : 0] BRAM[HIST_MEM_DEPTH - 1 : 0] = '{default: '0};

            reg [BRAM_DATA_WIDTH - 1 : 0] ram_data;
            logic [HIST_MEM_ADDR_WIDTH - 1 : 0] addra;
            logic [HIST_MEM_ADDR_WIDTH - 1 : 0] addrb;
            logic [BRAM_DATA_WIDTH - 1 : 0] dina;
            logic wea;
            logic enb;
            logic [BRAM_DATA_WIDTH - 1 : 0] doutb;

            always @(posedge s_axis.clk) begin
                if (wea) BRAM[addra] <= dina;
                if (enb) ram_data <= BRAM[addrb];

                doutb <= ram_data;
            end

            //----------------------------------------------------------//
            // updating the BRAM
            logic [31 : 0] valid_delay = 0;
            logic [HIST_WORD_SIZE -1 : 0] r1hist_data_out, r2hist_data_out, r3hist_data_out;
            logic BRAM_rst;
            always @(posedge s_axis.clk) begin
                // Delay the input data to align it with the BRAM output
                r1hist_data_out <= hist_data_out;
                r2hist_data_out <= r1hist_data_out;
                r3hist_data_out <= r2hist_data_out;

                enb <= hist_valid_out;
                // Histogram module sends the data without any intrupt
                // since hist_read_en is awlays one
                addrb <= 0;
                if (enb) addrb <= addrb + 1;

                // if hist_reset is asserted, zero will be written into the
                // blockRAM, otherwise r3hist_data_out will be added to the
                // blockRAM output and written into the same address. To this
                // end, the hist_reset will be latched when asserted.
                BRAM_rst <= 0;

                if (!valid_delay[2] && valid_delay[3])  // equals to  if (addra == HIST_MEM_DEPTH - 1)
                    BRAM_rst <= 0;
                else if ((hist_reset && hist_read_start) || BRAM_rst) BRAM_rst <= 1;


                // different delays of hist_valid_out is required
                valid_delay[0] <= hist_valid_out;
                valid_delay[31 : 1] <= valid_delay[30 : 0];

                dina <= 'X;
                if (valid_delay[2]) begin
                    dina <= BRAM_rst ? 0 : r3hist_data_out + doutb;
                end
                wea   <= valid_delay[2];
                addra <= 0;
                if (wea) addra <= addra + 1;

                // assigning proper data into the output ports
                data_out_o  <= r3hist_data_out + doutb;
                valid_out_o <= valid_delay[2];
            end

            //----------------------------------------------------------//
            // Computing the statistics
            /*
			offset = ∑n*x(n) / ∑x(n);
			variance = ∑(x(n)*(n-offset)*(n-offset)) / ∑x(n)
					 = (∑n*n*x(n) -2*offset*∑n*x(n) + offset*offset*∑x(n)) / ∑x(n)

			To determine the offset and variance, it is essential to precalculate
			the following terms: the summation of x(n) (∑x(n)), the summation of
			n times x(n) (∑n*x(n)), and the summation of n squared times x(n) (∑n*n*x(n)).
			Subsequently, the offset is computed first, and its value is then utilized
			to calculate the variance.

			It is important to note that these terms are computed while updating the blockRAM.
			Additionally, the computation of ∑n*n*x(n) obviates the need for re-reading the
			blockRAM when calculating the variance.
			*/
            localparam INDEX_WIDTH = HIST_MEM_ADDR_WIDTH + 1;
            // ∑x(n)
            localparam SUM_WIDTH = BRAM_DATA_WIDTH + INDEX_WIDTH;
            // ∑n*x(n)
            localparam WEIGHTED_SUM_WIDTH = BRAM_DATA_WIDTH + 2 * INDEX_WIDTH;
            // ∑n*n*x(n)
            localparam SQUARED_WEIGHTED_SUM_WIDTH = BRAM_DATA_WIDTH + 3 * INDEX_WIDTH;

            localparam SQUARED_MULT_WIDTH = 2 * INDEX_WIDTH;
            localparam WIDE_MULT1_WIDTH = BRAM_DATA_WIDTH + INDEX_WIDTH;
            localparam WIDE_MULT2_WIDTH = BRAM_DATA_WIDTH + 2 * INDEX_WIDTH;
            localparam WIDE_MULT3_WIDTH = BRAM_DATA_WIDTH + 3 * INDEX_WIDTH;  // offset*offset*∑x(n)
            localparam WIDE_MULT4_WIDTH = BRAM_DATA_WIDTH + 3 * INDEX_WIDTH;  // offset*∑n*x(n)
            localparam MULT1_LATENCY = 6;
            localparam MULT2_LATENCY = 6;
            localparam MULT3_LATENCY = 6;
            localparam MULT4_LATENCY = 6;
            localparam MULT_LATENCY_MAX = MULT4_LATENCY >= MULT3_LATENCY ? MULT4_LATENCY : MULT3_LATENCY;
            localparam OFFSET_VALID_BUFF_WIDTH = MULT_LATENCY_MAX + 4;

            logic [INDEX_WIDTH - 1 : 0] index, r1index, r2index;
            logic [SQUARED_MULT_WIDTH - 1 : 0] squared_index;
            logic [BRAM_DATA_WIDTH - 1 : 0] data_value, data_value_max;
            logic [WIDE_MULT1_WIDTH - 1 : 0] wide_mult1;  // n*x(n)
            logic [WIDE_MULT2_WIDTH - 1 : 0] wide_mult2;  // n*n*x(n)
            logic [WIDE_MULT3_WIDTH - 1 : 0] wide_mult3;  // offset*offset*∑x(n)
            logic [WIDE_MULT4_WIDTH - 1 : 0] wide_mult4;  // offset*∑n*x(n)
            logic [SUM_WIDTH - 1 : 0] data_sum, data_sum_reg;  // ∑x(n)
            logic [WEIGHTED_SUM_WIDTH - 1 : 0] weighted_sum, weighted_sum_reg;  // ∑n*x(n)
            logic [SQUARED_WEIGHTED_SUM_WIDTH - 1 : 0] squared_weighted_sum, squared_weighted_sum_reg;  // ∑n*n*x(n)

            logic start_offset_div;
            logic [INDEX_WIDTH - 1 : 0] offset_reg;
            logic [2*INDEX_WIDTH - 1 : 0] squared_offset;
            logic [INDEX_WIDTH + 2*HIST_MEM_ADDR_WIDTH : 0] shifted_offset_sum;

            logic [SQUARED_WEIGHTED_SUM_WIDTH : 0] partial_sum;
            logic [SQUARED_WEIGHTED_SUM_WIDTH : 0] subtraction;

            // calculating offset: ∑n*x(n) / ∑x(n)
            logic [WEIGHTED_SUM_WIDTH - 1 : 0] offset_quotient;
            logic [SUM_WIDTH - 1 : 0] offset_remainder;
            logic offset_validout;
            logic [OFFSET_VALID_BUFF_WIDTH - 1 : 0] offset_validout_buff;

            // calculating variance
            logic [SQUARED_WEIGHTED_SUM_WIDTH : 0] variance_quotient;
            logic [SUM_WIDTH - 1 : 0] variance_remainder;
            logic variance_validout;

            always @(posedge s_axis.clk) begin
                // The index begins at 1 and extends up to HIST_MEM_ADDR_WIDTH.
                // This ensures that the impact of the initial bin with an address
                // of zero is preserved and not disregarded.
                index <= 'X;
                if (enb) begin
                    index <= addrb + 1;
                end
                r1index <= index;

                // r2index, squared_index, and data_value are aligned
                r2index <= r1index;
                squared_index <= r1index * r1index;
                data_value <= r3hist_data_out + doutb;  // the same as data_out_o

                // calculating index_max
                if (valid_delay[3]) begin
                    if (data_value >= data_value_max) begin
                        data_value_max <= data_value;
                        // latching the max index for later usage
                        index_max <= r2index - 1;  // begins from zero to HIST_MEM_ADDR_WIDTH-1
                    end
                end else begin
                    data_value_max <= 0;
                end

                // calculating  ∑x(n)
                data_sum <= 0;
                if (valid_delay[3]) begin
                    data_sum <= data_sum + data_value;
                end
                // latching the value of data_sum
                if (!valid_delay[3] && valid_delay[4]) begin
                    data_sum_reg <= data_sum;
                end

                // calculating  ∑n*x(n)
                weighted_sum <= 0;
                if (valid_delay[3+MULT1_LATENCY]) begin
                    weighted_sum <= weighted_sum + wide_mult1;
                end

                // latching the value of weighted_sum
                if (!valid_delay[3+MULT1_LATENCY] && valid_delay[4+MULT1_LATENCY]) begin
                    weighted_sum_reg <= weighted_sum;
                end
                start_offset_div <= !valid_delay[3+MULT1_LATENCY] && valid_delay[4+MULT1_LATENCY];

                // calculating  ∑n*n*x(n)
                squared_weighted_sum <= 0;
                if (valid_delay[3+MULT2_LATENCY]) begin
                    squared_weighted_sum <= squared_weighted_sum + wide_mult2;
                end
                // latching the value of squared_weighted_sum
                if (!valid_delay[3+MULT2_LATENCY] && valid_delay[4+MULT2_LATENCY]) begin
                    squared_weighted_sum_reg <= squared_weighted_sum;
                end

                // latch the offset value
                if (offset_validout) begin
                    offset_reg <= offset_quotient[0+:HIST_MEM_ADDR_WIDTH];
                    /* Rounding the offset to the nearest integer value: If the remainder is equal
					   to or greater than half of data_sum_reg, the offset should be increased by one.
					   This adjustment is necessary because the actual offset value is closer to the
					   next integer value than the computed one. */
                    if (offset_remainder >= (data_sum_reg >> 1))
                        offset_reg <= offset_quotient[0+:HIST_MEM_ADDR_WIDTH] + 1;
                end
                /* To derive the offset value, it is essential to decrement the offset_reg value by one.
				   This adjustment is crucial due to the disparity in the ranges—offset_reg spans from 1
				   to HIST_MEM_DEPTH, whereas the offset ranges from zero to HIST_MEM_DEPTH-1. */
                offset <= offset_reg - 1;

                // computing offset*offset
                squared_offset <= offset_reg * offset_reg;

                // computing ∑n*n*x(n) + squared_offset*∑x(n)
                partial_sum <= squared_weighted_sum_reg + wide_mult3;

                // computing ∑n*n*x(n) + offset*offset*∑x(n) - 2*offset*∑n*x(n)
                // The result is non-negative. Proceed with unsigned subtraction.
                subtraction <= partial_sum - {wide_mult4, 1'b0};

                offset_validout_buff <= {offset_validout_buff[OFFSET_VALID_BUFF_WIDTH-2 : 0], offset_validout};

                // latching the variance
                if (variance_validout) begin
                    variance <= variance_quotient[0+:VARIANCE_WIDTH];
                    // Rounding the variance to the nearest integer value
                    if (variance_remainder >= (data_sum_reg >> 1)) variance <= variance_quotient[0+:VARIANCE_WIDTH] + 1;
                end
                statistics_valid <= variance_validout;

            end

            // calculating n*x(n)
            wide_mult #(
                .INPUT1_WIDTH(INDEX_WIDTH),
                .INPUT2_WIDTH(BRAM_DATA_WIDTH),
                .LATENCY(MULT1_LATENCY)
            ) wide_mult_inst1 (
                .clk(s_axis.clk),
                .din1(r2index),  // n
                .din2(data_value),  // x(n)
                .dout(wide_mult1)  // n*x(n)
            );
            // calculating n*n*x(n)
            wide_mult #(
                .INPUT1_WIDTH(SQUARED_MULT_WIDTH),
                .INPUT2_WIDTH(BRAM_DATA_WIDTH),
                .LATENCY(MULT2_LATENCY)
            ) wide_mult_inst2 (
                .clk (s_axis.clk),
                .din1 (squared_index), // n*n
                .din2 (data_value),    // x(n)
                .dout (wide_mult2)     // n*n*x(n)
            );
            // calculating offset: ∑n*x(n) / ∑x(n)
            wide_divider #(
                .DIVIDEND_WIDTH(WEIGHTED_SUM_WIDTH),
                .DIVISOR_WIDTH (SUM_WIDTH)
            ) calculating_offset (
                .clk      (s_axis.clk),
                .start    (start_offset_div),
                .dividend (weighted_sum_reg),  // ∑n*x(n)
                .divisor  (data_sum_reg),      // ∑x(n)
                .quotient (offset_quotient),
                .remainder(offset_remainder),
                .validout (offset_validout)
            );

            // calculating squared_offset*data_sum_reg
            wide_mult #(
                .INPUT1_WIDTH(SQUARED_MULT_WIDTH),
                .INPUT2_WIDTH(SUM_WIDTH),
                .LATENCY(MULT3_LATENCY)
            ) wide_mult_inst3 (
                .clk (s_axis.clk),
                .din1(squared_offset),  // offset*offset
                .din2(data_sum_reg),    // ∑x(n)
                .dout(wide_mult3)       // offset*offset*∑x(n)
            );

            // calculating offset*weighted_sum_reg
            wide_mult #(
                .INPUT1_WIDTH(INDEX_WIDTH),
                .INPUT2_WIDTH(WEIGHTED_SUM_WIDTH),
                .LATENCY(MULT4_LATENCY)
            ) wide_mult_inst4 (
                .clk (s_axis.clk),
                .din1(offset_reg),        // offset
                .din2(weighted_sum_reg),  // ∑n*x(n)
                .dout(wide_mult4)         // offset*∑n*x(n)
            );
            // calculating variance
            wide_divider #(
                .DIVIDEND_WIDTH(SQUARED_WEIGHTED_SUM_WIDTH + 1),
                .DIVISOR_WIDTH (SUM_WIDTH)
            ) calculating_variance (
                .clk(s_axis.clk),
                .start(offset_validout_buff[OFFSET_VALID_BUFF_WIDTH-1]),
                .dividend(subtraction),  // (∑n*n*x(n) + N*offset*offset) - (offset*N*N + offset*N)
                .divisor(data_sum_reg),  // ∑x(n)
                .quotient(variance_quotient),
                .remainder(variance_remainder),
                .validout(variance_validout)
            );
        end

    endgenerate
endmodule
