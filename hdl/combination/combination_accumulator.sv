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

/*
This module is to calculate histogram. Accumulation is supported during readout by using read_out_blocking. 
There is a line buffer to store the input data, if there is no data in the line buffer, reading out will be possible through wishbone or FPGA.
*/

// verilog_format: off
`resetall
`timescale 1ns / 1ps
`default_nettype none
// verilog_format: on

module combination_accumulator #(
    parameter COMB_WIDTH = 16,
    parameter ACC_WIDTH  = 32,
    parameter WIDTH_CNT  = 4
) (
    input wire clk,
    input wire rst,

    input wire data_in_vd,
    input wire [COMB_WIDTH-1 : 0] data_in,
    input wire [WIDTH_CNT-1  : 0] data_cnt_in, //pre-calculated to eliminate similar combination during accumulation (pipeline)
    input wire reset_comb,
    input wire ready_i,
    input wire start_reading,
    output wire ready_o,
    output reg reset_comb_done,
    output wire comb_out_vd,
    output wire [COMB_WIDTH-1 : 0] comb_value,
    output wire [ACC_WIDTH-1  : 0] comb_count
);

    localparam RAM_DEPTH = 2 ** COMB_WIDTH;
    localparam N_pipe = 8;  // buffering data to prevent conflict/overwriting during reading out the results
    ///////////////////////   Memory signal definitions //////////////////////////////
    logic [COMB_WIDTH-1:0] addra;  // Write address bus, width determined from RAM_DEPTH
    logic [COMB_WIDTH-1:0] addrb;  // Read address bus, width determined from RAM_DEPTH

    logic [COMB_WIDTH-1:0] addr_rd_next;  // To readout data from memory
    logic [COMB_WIDTH-1:0] addr_rst_next;  // To reset data in the memory

    logic wea;  // Write enable to store results of combination accumulation
    logic enb;  // Read Enable to readout previous amount of combination

    logic [ACC_WIDTH-1:0] dina;
    logic [ACC_WIDTH-1:0] doutb_reg;
    (* cascade_height=2 *) logic [ACC_WIDTH-1:0] ram_combination[RAM_DEPTH-1:0] = '{default: '0};
    logic [ACC_WIDTH-1:0] ram_data = '0;
    ///////////////////////   accumulate signal definations //////////////////////////////
    logic [WIDTH_CNT-1:0] cnt_line_buff[N_pipe-1:0];
    logic [N_pipe:0] data_in_vd_buff;
    logic [COMB_WIDTH-1:0] data_in_buff[N_pipe-1:0];

    // read out control signal 
    logic reading_out_busy_ff;

    logic start_reading_d1;  // Delays start_reading to detect a rising edge and initiate the readout phase
    logic read_out_blocking;

    logic enb_buff[1:0];
    logic [COMB_WIDTH-1:0] addrb_buff[1:0];
    logic reading_out_busy_buff[1:0];
    /////////////////////////  comb acc  ////////////////////////////////
    always_comb begin
        cnt_line_buff[0]   = data_cnt_in;
        data_in_buff[0]    = data_in;
        data_in_vd_buff[0] = data_in_vd;
    end
    always @(posedge clk) begin
        // By default: No read or write action on BRAM
        wea              <= 0;
        addra            <= 'X;
        dina             <= 'X;
        enb              <= 0;
        addrb            <= 'X;
        start_reading_d1 <= 0;
        reset_comb_done  <= 0;
        if (rst) begin
            addr_rd_next        <= 'X;
            addr_rst_next       <= 'X;
            reading_out_busy_ff <= 0;
            read_out_blocking = 0;
            cnt_line_buff[N_pipe-1:1] <= '{default: 'X};
            data_in_buff[N_pipe-1:1]  <= '{default: 'X};
            data_in_vd_buff[N_pipe:1] <= '{default: 0};
        end else begin
            cnt_line_buff[N_pipe-1:1] <= cnt_line_buff[N_pipe-2:0];
            data_in_buff[N_pipe-1:1]  <= data_in_buff[N_pipe-2:0];
            data_in_vd_buff[N_pipe:1] <= data_in_vd_buff[N_pipe-1:0];
            start_reading_d1          <= start_reading;
            //reading out from portB

            if (start_reading && ~start_reading_d1) begin  // starting the readout phase, rising edge of start_reading
                reading_out_busy_ff <= 1;
                addr_rd_next        <= '0;
            end

            read_out_blocking = |data_in_vd_buff;
            if (data_in_vd_buff[4]) begin  //// reading out from portB
                enb   <= 1;
                addrb <= data_in_buff[4];
            end else if (reading_out_busy_ff && ready_i && !read_out_blocking) begin   // reading out from the memory cell by cell based on reading request (reading_out_en)
                enb          <= 1;
                addrb        <= addr_rd_next;
                addr_rd_next <= addr_rd_next + 1;
                if (addr_rd_next == '1) begin
                    reading_out_busy_ff <= 0;
                end
            end
            addr_rst_next <= 0;
            if (reset_comb) begin
                wea                       <= 1;
                addra                     <= addr_rst_next;
                dina                      <= 0;
                addr_rst_next             <= addr_rst_next + 1;
                data_in_vd_buff[N_pipe:1] <= '{default: 0};
                if (addra == '1) begin
                    reset_comb_done <= 1;
                end
            end else if (data_in_vd_buff[7]) begin  // accumulating as histogram
                wea   <= 1;
                addra <= data_in_buff[7];
                dina  <= doutb_reg + cnt_line_buff[7];
            end else if (reading_out_busy_buff[0] && ~data_in_vd_buff[5]) begin  // reset the memory content for next round of accumulation (histogram)
                wea   <= enb;
                addra <= addrb;
                dina  <= 0;
            end
        end
    end

    /////////////////////////  Memory implementation  ////////////////////////////////
    always_ff @(posedge clk) begin
        if (rst) begin
            doutb_reg <= '0;
        end else begin
            doutb_reg <= ram_data;  // register the output to increase the frequency
        end
        if (wea) begin
            ram_combination[addra] <= dina;
        end
        if (enb) begin
            ram_data <= ram_combination[addrb];
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            enb_buff              <= '{default: '0};
            addrb_buff            <= '{default: '0};
            reading_out_busy_buff <= '{default: '0};
        end else begin
            enb_buff              <= {enb_buff[0], enb};
            addrb_buff            <= {addrb_buff[0], addrb};
            reading_out_busy_buff <= {reading_out_busy_buff[0], reading_out_busy_ff};
        end
    end

    assign ready_o     = ~(reading_out_busy_ff | reading_out_busy_buff[1]);
    assign comb_out_vd = enb_buff[1] && ~data_in_vd_buff[7];
    assign comb_count  = doutb_reg;
    assign comb_value  = addrb_buff[1];

endmodule
