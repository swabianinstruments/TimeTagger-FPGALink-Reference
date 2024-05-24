/**
 * This file is part of the Time Tagger software defined digital data
 * acquisition FPGA-link reference design.
 *
 * Copyright (C) 2022-2024 Swabian Instruments, All Rights Reserved
 *
 * Authors:
 * - 2023 Loghman Rahimzadeh <loghman@swabianinstruments.com>
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
Two types of results can be expected from combinations, Stream of combinations and histogram of combinations. 
If stream of combinations is required, readout speed should exceed the combinations
throughput, otherwise an overflow will happen in the FIFO. In histogram mode, for any combination,
a 32 bits counter is stored in BRAM with depth of BRAM in 2**channels, where channels is the number of 
virtual channels(NUM_OF_CHANNELS in channel_selector). Due to memory restrictions in FPGA,up to 16 channels
are supported with 32 bits for combination's counter, while user has capability to customize number of virtual channels
 and width of combination counter.
 
Also, there are two ways to configure this module and receive data from it:

1. Using the Wishbone interface.
2. Utilizing a downstream FPGA module.

During bitstream generation, only one of these options is synthesized.
Here are the differences between these two choices:

If you intend to process the combinations data using a PC, you should transfer
the data via the Wishbone interface and configure this module by sending the
appropriate commands through this interface. To do this, you need to set the parameter
WISHBONE_INTERFACE_EN to 1. When you opt for the Wishbone interface, you will
receive the combinations. 


If you plan to process the combinations data within the FPGA, you need to set 
WISHBONE_INTERFACE_EN to 1 and supply the module with the necessary configuration data and appropriate 
read/reset commands. In this mode, all the required signals can be accessed via combination_interface.

In both ways, procedure for interaction with Combinations is similar as following:

1. If you doubt that some data is remainded in the combinations module due to unfinished previous measurements, use comb_reset to make sure that nothing remainded in combinations module.
Please keep it in mind that restart might take time.
2. Setting the configurations including channel_selectors and others.
3. Start processing the time tags by setting capture_enable to 1. Please keep this signal set if you need to read the time tags continuously. 
4. After some time for the measurements,set start_reading to 1 and reset it again. A reading will be initiated with the rising edge on this signal, 
*/

module combination_wrapper #(
    parameter WISHBONE_INTERFACE_EN = 0,
    parameter HISTOGRAM_EN          = 1,
    parameter NUM_OF_CHANNELS       = 16,
    parameter ACC_WIDTH             = 32,
    parameter FIFO_DEPTH            = 8192
) (
    // input information of channel
    axis_tag_interface.slave s_time,

    // Wishbone interface for control & status
    wb_interface.slave wb,
    // combination interface for configuration and readout
    combination_interface.slave s_comb_i
);
    // Forward parameters from the AXI-Stream interface
    localparam integer LANE = s_time.WORD_WIDTH;
    localparam integer TIME_TAG_WIDTH = s_time.TIME_WIDTH;
    wire clk = s_time.clk;
    wire rst = s_time.rst;

    //This interface will be drived by either wishbone or from another module in the FPGA depending on WISHBONE_INTERFACE_EN's value
    combination_interface #(
        .TIME_WIDTH(s_time.TIME_WIDTH),
        .CHANNELS_IN_WIDTH(s_time.CHANNEL_WIDTH),
        .CHANNELS(NUM_OF_CHANNELS),
        .ACC_WIDTH(ACC_WIDTH)
    ) m_comb ();

    localparam integer CHANNEL_WIDTH = $clog2(NUM_OF_CHANNELS);
    logic                        m_axis_sel_tvalid;
    logic [            LANE-1:0] m_axis_sel_tkeep;
    logic [TIME_TAG_WIDTH-1 : 0] Channel_TimeTag             [LANE-1:0];
    logic [ CHANNEL_WIDTH-1 : 0] Channel_Index               [LANE-1:0];
    logic                        reset_done_channel_selector;
    channel_selector #(
        .WIDTH(TIME_TAG_WIDTH),
        .LANE(LANE),
        .CHANNEL_INP_WIDTH(s_time.CHANNEL_WIDTH),
        .CHANNEL_OUTP_WIDTH(CHANNEL_WIDTH)
    ) channel_selector_inst (
        .clk(clk),
        .rst(rst | m_comb.reset_comb),

        .s_axis_tvalid (s_time.tvalid),
        .s_axis_tready (s_time.tready),
        .s_axis_tkeep  (s_time.tkeep),
        .s_axis_tagtime(s_time.tagtime),
        .s_axis_channel(s_time.channel),

        .m_axis_tvalid(m_axis_sel_tvalid),
        .m_axis_tready(1'b1),
        .m_axis_tkeep(m_axis_sel_tkeep),
        .m_axis_tagtime(Channel_TimeTag),
        .m_axis_channel(Channel_Index),
        .reset_comb_done(reset_done_channel_selector),
        .lut_ack(m_comb.lut_ack),
        .lut_WrRd(m_comb.lut_WrRd),
        .lut_addr(m_comb.lut_addr),
        .lut_dat_i(m_comb.lut_dat_i),
        .lut_dat_o(m_comb.lut_dat_o)
    );

    // Pack all valid events to the first lanes, required by combination_extraction
    logic [TIME_TAG_WIDTH-1 : 0] Channel_TimeTag_align  [LANE-1:0];
    logic [ CHANNEL_WIDTH-1 : 0] Channel_Index_align    [LANE-1:0];
    logic [            LANE-1:0] Channel_In_Valid_align;

    always @(posedge clk) begin
        automatic int j = 0;
        Channel_TimeTag_align  <= '{default: 'X};
        Channel_Index_align    <= '{default: 'X};
        Channel_In_Valid_align <= 0;
        for (int i = 0; i < LANE; i = i + 1) begin
            if (m_axis_sel_tvalid && m_axis_sel_tkeep[i] && m_comb.capture_enable) begin
                Channel_TimeTag_align[j]  <= Channel_TimeTag[i];
                Channel_Index_align[j]    <= Channel_Index[i];
                Channel_In_Valid_align[j] <= 1;
                j = j + 1;
            end
        end
    end

    // Assemble the combinations if the window size matches.
    // This process consumes the timestamps and yields the bitset of the real combinations.
    logic [NUM_OF_CHANNELS-1:0] comb_extraction_dout    [LANE-1:0];
    logic [           LANE-1:0] comb_extraction_dout_vd;
    logic [               31:0] debug_reg_sys           [     2:0];
    combination_extraction #(
        .LANE          (LANE),
        .TIME_TAG_WIDTH(TIME_TAG_WIDTH),
        .COMB_WIDTH    (NUM_OF_CHANNELS)
    ) combination_extraction_inst (
        .clk               (clk),
        .rst               (rst | m_comb.reset_comb),
        .window            (m_comb.window),
        //input information of channel
        .Channel_TimeTag   (Channel_TimeTag_align),
        .Channel_Index     (Channel_Index_align),
        .Channel_In_Valid  (Channel_In_Valid_align),
        .debug_comb_ext    (debug_reg_sys),
        .out_channel_bitset(comb_extraction_dout),
        .out_valid         (comb_extraction_dout_vd)
    );

    // Filter: Only select combinations if the sum of bits is in a given range
    logic [NUM_OF_CHANNELS-1:0] filter_dout    [LANE-1:0];
    logic [           LANE-1:0] filter_dout_vd;
    filter_combination #(
        .LANE (LANE),
        .WIDTH(NUM_OF_CHANNELS)
    ) filter_combination_inst (
        .rst        (rst | m_comb.reset_comb),
        .clk        (clk),
        .filter_min (m_comb.filter_min),
        .filter_max (m_comb.filter_max),
        .data_in_vd (comb_extraction_dout_vd),
        .data_in    (comb_extraction_dout),
        .data_out_vd(filter_dout_vd),
        .data_out   (filter_dout)
    );

    // Make full lanes, so dout_vd is either all zero or all one, needed for lane_reduction to be efficient
    logic [NUM_OF_CHANNELS-1:0] packing_dout    [LANE-1:0];
    logic [           LANE-1:0] packing_dout_vd;
    logic                       packing_flush;
    lane_packing #(
        .LANE (LANE),
        .WIDTH(NUM_OF_CHANNELS)
    ) lane_packing_inst (
        .rst        (rst | m_comb.reset_comb),
        .clk        (clk),
        .flush      (packing_flush),
        .data_in_vd (filter_dout_vd),
        .data_in    (filter_dout),
        .data_out_vd(packing_dout_vd),
        .data_out   (packing_dout)
    );

    // Adapter to switch to single lane execution
    // Both the combination_extraction and the filter reduces the rate of combinations, so single lane processing is fine for the histogram
    logic [NUM_OF_CHANNELS-1:0] one_lane_dout;
    logic                       one_lane_dout_vd;
    logic                       one_lane_empty;
    logic overflow_log, overflow_sent;
    lane_reduction #(
        .LANE(LANE),
        .WIDTH(NUM_OF_CHANNELS),
        .FIFO_DEPTH(FIFO_DEPTH)
    ) lane_reduction_inst (
        .rst(rst | m_comb.reset_comb),
        .clk(clk),
        .data_in_vd(packing_dout_vd),
        .data_in(packing_dout),
        .read_en((m_comb.select_comb_fifo == 2'b01) ? m_comb.ready_i : 1),
        .data_out_vd(one_lane_dout_vd),
        .data_out(one_lane_dout),
        .o_overflow(m_comb.overflow),
        .fifo_empty(one_lane_empty)
    );
    // Flush lane_packing if the fifo is empty to achieve real-time processing
    assign packing_flush = one_lane_empty;

    logic reset_done_histogram;
    generate
        if (HISTOGRAM_EN) begin
            // Group series of matching combinations and provide the count of grouped combinations
            // This is required for the histogramming in the next stage
            localparam LEN_OF_BUFFER = 7;
            localparam LEN_OF_CNT = $clog2(LEN_OF_BUFFER + 2);
            logic [NUM_OF_CHANNELS-1:0] pre_cal_dout;
            logic [     LEN_OF_CNT-1:0] pre_cal_data_count;
            logic                       pre_cal_data_vd;
            accumulator_pre_calculator #(
                .WIDTH        (NUM_OF_CHANNELS),
                .LEN_OF_BUFFER(LEN_OF_BUFFER)     //pipeline
            ) accumulator_pre_calculator_inst (
                .clk         (clk),
                .rst         (rst | m_comb.reset_comb),
                //input information of channel
                .data_in_vd  (one_lane_dout_vd & (m_comb.select_comb_fifo == 2'b10)),
                .data_in     (one_lane_dout),
                .data_out_cnt(pre_cal_data_count),
                .data_out    (pre_cal_dout),
                .data_out_vd (pre_cal_data_vd)
            );

            // Calculate the histogram of all combinations
            combination_accumulator #(
                .COMB_WIDTH(NUM_OF_CHANNELS),
                .ACC_WIDTH (ACC_WIDTH),
                .WIDTH_CNT (LEN_OF_CNT)
            ) combination_accumulator_inst (
                .rst(rst),
                .clk(clk),
                .data_in_vd(pre_cal_data_vd),
                .data_in(pre_cal_dout),  //combination
                .data_cnt_in(pre_cal_data_count),//pre-calculated to eliminate similar combination during accumulation(pipeline)
                .reset_comb(m_comb.reset_comb),
                .ready_i(m_comb.ready_i),
                .start_reading(m_comb.start_reading),
                .ready_o(m_comb.ready_o),
                .reset_comb_done(reset_done_histogram),
                .comb_out_vd(m_comb.comb_out_vd),
                .comb_value(m_comb.comb_value),
                .comb_count(m_comb.comb_count)
            );
        end
        // Based on mode, pick the reset_done either from the channel_selector or from the histogram
        assign m_comb.reset_comb_done = HISTOGRAM_EN ? reset_done_histogram : reset_done_channel_selector;

        if (WISHBONE_INTERFACE_EN) begin
            //------------------------------------------------------------------//
            // Wb interface

            //  FIFO to read data from memory and feed to WB
            logic [ACC_WIDTH-1 : 0] fifo_dout;
            logic                   fifo_rd_en;
            logic                   fifo_empty;
            logic                   fifo_prog_full;

            always @(posedge wb.clk) begin
                wb.ack <= 0;
                wb.dat_o <= 'X;
                fifo_rd_en <= 0;
                m_comb.reset_comb <= 0;
                m_comb.start_reading <= 0;
                m_comb.lut_WrRd <= 2'h0;  // no action in the channel selector
                if (m_comb.overflow) begin  // Overflow is stored to be reported to user in the readout
                    overflow_log <= 1;
                end
                if (rst || wb.rst) begin
                    m_comb.capture_enable   <= 0;
                    m_comb.reset_comb       <= 0;
                    m_comb.window           <= 0;
                    m_comb.filter_max       <= 0;
                    m_comb.filter_min       <= 0;
                    m_comb.select_comb_fifo <= 0;
                    overflow_log            <= 0;
                    overflow_sent           <= 0;
                    m_comb.lut_dat_i        <= 'X;
                    m_comb.lut_addr         <= 'X;
                end else if (wb.stb && wb.cyc && !wb.ack) begin
                    wb.ack <= 1;
                    if (wb.we) begin
                        /////////////////////// Write registers
                        case (wb.adr[7:0])
                            8'h01: begin
                                m_comb.window[TIME_TAG_WIDTH/2-1:0] <= wb.dat_i;
                            end
                            8'h02: begin
                                m_comb.window[TIME_TAG_WIDTH-1:TIME_TAG_WIDTH/2] <= wb.dat_i;
                            end
                            8'h03: begin
                                m_comb.filter_max <= wb.dat_i[$clog2(NUM_OF_CHANNELS+1)-1+16:16];
                                m_comb.filter_min <= wb.dat_i[$clog2(NUM_OF_CHANNELS+1)-1:0];
                            end
                            8'h04: begin
                                m_comb.select_comb_fifo <= wb.dat_i[1:0];
                            end
                            8'h05: begin
                                m_comb.capture_enable <= wb.dat_i[0];
                                if (wb.dat_i[0]) begin
                                    overflow_log <= 0;
                                end
                            end
                            8'h06: begin
                                m_comb.start_reading <= wb.dat_i[0];
                                overflow_sent        <= 0;
                            end
                            8'h07: begin
                                m_comb.capture_enable   <= 0;  // Resetting combinations will reset important registers
                                m_comb.window           <= 0;
                                m_comb.filter_max       <= 0;
                                m_comb.filter_min       <= 0;
                                m_comb.select_comb_fifo <= 0;
                                m_comb.reset_comb       <= wb.dat_i[0];
                                overflow_log            <= 0;
                                if (wb.dat_i[0]) begin
                                    // deassert the wb.ack until resetting the whole BRAMs
                                    wb.ack <= 0;
                                    if (m_comb.reset_comb_done) begin
                                        wb.ack            <= 1;
                                        m_comb.reset_comb <= 0;
                                    end
                                end
                            end
                            8'h08: begin
                                m_comb.lut_dat_i <= wb.dat_i[0+:CHANNEL_WIDTH];
                                m_comb.lut_dat_i[CHANNEL_WIDTH] <= wb.dat_i[15];
                                m_comb.lut_addr <= wb.dat_i[16+:s_time.CHANNEL_WIDTH];
                                m_comb.lut_WrRd <= wb.dat_i[31 : 30];
                            end
                        endcase
                    end else begin
                        // Read registers and data
                        case (wb.adr[7:0])
                            8'h00:   wb.dat_o <= 32'h636F6D62;  // "comb"
                            8'h01:   wb.dat_o <= m_comb.window[TIME_TAG_WIDTH/2-1:0];
                            8'h02:   wb.dat_o <= m_comb.window[TIME_TAG_WIDTH-1:TIME_TAG_WIDTH/2];
                            8'h03:   wb.dat_o <= {16'h0000 | m_comb.filter_max, 16'h0000 | m_comb.filter_min};
                            8'h04:   wb.dat_o <= m_comb.select_comb_fifo;
                            8'h05:   wb.dat_o <= m_comb.capture_enable;
                            8'h06:   wb.dat_o <= m_comb.start_reading;
                            8'h07:   wb.dat_o <= m_comb.reset_comb;
                            8'h08: begin
                                m_comb.lut_WrRd    <= 2'b01;
                                // deassert the wb.ack until reading one cell of channel selector's is done
                                wb.ack <= 0;
                                if (m_comb.lut_ack) begin
                                    wb.dat_o <= {
                                        2'h0 | m_comb.lut_WrRd,
                                        14'h0000 | m_comb.lut_addr,
                                        m_comb.lut_dat_o[CHANNEL_WIDTH],
                                        15'h0000 | m_comb.lut_dat_o[0+:CHANNEL_WIDTH]
                                    };
                                    wb.ack <= 1;
                                    m_comb.lut_WrRd <= 2'b00;
                                end
                            end
                            8'h09:   wb.dat_o <= FIFO_DEPTH;
                            8'h0A:   wb.dat_o <= NUM_OF_CHANNELS;
                            8'h0B:   wb.dat_o <= s_time.CHANNEL_WIDTH;
                            8'h0C:   wb.dat_o <= ACC_WIDTH;
                            8'h0D:   wb.dat_o <= HISTOGRAM_EN;
                            8'h0F: begin
                                if (m_comb.select_comb_fifo == 2'b01 && fifo_empty) begin
                                    // Streaming mode without data: Yield zeros
                                    wb.dat_o <= 0;
                                end else if(m_comb.select_comb_fifo==2'b10 && overflow_log && ~overflow_sent && !fifo_empty) begin
                                    // Overflow in histogramming mode: Replace one word with the overflow marker
                                    overflow_log <= 0;
                                    overflow_sent <= 1; // This is to being sure that we send overflow word only once to wishbone
                                    wb.dat_o <= '1;
                                    fifo_rd_en <= 1;
                                end else if (!fifo_empty) begin
                                    // Histogramming or streaming mode with data in the FIFO: Just send the next word
                                    wb.dat_o   <= fifo_dout;
                                    fifo_rd_en <= 1;
                                end else begin
                                    // Histogramming mode, but no data in the FIFO. Let's block the WB bus
                                    wb.ack <= 0;
                                end
                            end
                            8'h10:   wb.dat_o <= debug_reg_sys[0];
                            8'h11:   wb.dat_o <= debug_reg_sys[1];
                            8'h12:   wb.dat_o <= debug_reg_sys[2];
                            default: wb.dat_o <= '0;
                        endcase
                    end
                end
            end
            //------------------------------------------------------------------//
            logic                 wr_en_fifo;
            logic [ACC_WIDTH-1:0] din_comb_fifo;

            assign wr_en_fifo    = (m_comb.select_comb_fifo==2'b10) ? m_comb.comb_out_vd : (m_comb.select_comb_fifo==2'b01) ? one_lane_dout_vd : 0;
            assign din_comb_fifo = (m_comb.select_comb_fifo==2'b10) ? m_comb.comb_count  : (m_comb.select_comb_fifo==2'b01) ? {m_comb.overflow , one_lane_dout}    : 'X;

            xpm_fifo_sync #(
                .FIFO_WRITE_DEPTH(128),
                .WRITE_DATA_WIDTH(ACC_WIDTH),
                .READ_DATA_WIDTH(ACC_WIDTH),
                .PROG_FULL_THRESH(100),
                .READ_MODE("fwft"),
                .FULL_RESET_VALUE(1),
                .USE_ADV_FEATURES("0707")
            ) output_buffer_fifo (
                .rst      (rst),
                .wr_clk   (clk),
                .wr_en    (wr_en_fifo),
                .din      (din_comb_fifo),
                .prog_full(fifo_prog_full),
                .dout     (fifo_dout),
                .empty    (fifo_empty),
                .rd_en    (fifo_rd_en)
            );

            assign m_comb.ready_i = !fifo_prog_full;
        end

        //--------------------------------FGPA based readout ----------------------------------//

        if (!WISHBONE_INTERFACE_EN) begin

            assign m_comb.window = s_comb_i.window;
            assign m_comb.filter_max = s_comb_i.filter_max;
            assign m_comb.filter_min = s_comb_i.filter_min;

            assign m_comb.ready_i = s_comb_i.ready_i;

            assign m_comb.capture_enable = s_comb_i.capture_enable;
            assign m_comb.start_reading = s_comb_i.start_reading;
            assign m_comb.select_comb_fifo = s_comb_i.select_comb_fifo;
            assign m_comb.reset_comb = s_comb_i.reset_comb;

            assign m_comb.lut_WrRd = s_comb_i.lut_WrRd;
            assign m_comb.lut_addr = s_comb_i.lut_addr;
            assign m_comb.lut_dat_i = s_comb_i.lut_dat_i;
        end
    endgenerate

    // Assigning the output signals of s_comb_i
    assign s_comb_i.ready_o = m_comb.ready_o;
    assign s_comb_i.overflow = m_comb.overflow;
    assign s_comb_i.lut_dat_o = m_comb.lut_dat_o;
    assign s_comb_i.lut_ack = m_comb.lut_ack;
    assign s_comb_i.reset_comb_done = m_comb.reset_comb_done;
    assign s_comb_i.comb_out_vd = (m_comb.select_comb_fifo == 2'b10) ? m_comb.comb_out_vd :( m_comb.select_comb_fifo == 2'b01 ) ? one_lane_dout_vd : 0;
    assign s_comb_i.comb_value = (m_comb.select_comb_fifo == 2'b10) ? m_comb.comb_value : (m_comb.select_comb_fifo == 2'b01   ) ? {m_comb.overflow, one_lane_dout} : 'X;
    assign s_comb_i.comb_count = m_comb.comb_count;


endmodule
