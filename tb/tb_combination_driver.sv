/**
 * This file is part of the Time Tagger software defined digital data
 * acquisition FPGA-link reference design.
 *
 * Copyright (C) 2022-2024 Swabian Instruments, All Rights Reserved
 *
 * Authors:
 * - 2024 Loghman Rahimzadeh <loghman@swabianinstruments.com>
 *
 * This file is provided under the terms and conditions of the BSD 3-Clause
 * license, accessible under https://opensource.org/licenses/BSD-3-Clause.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

// verilog_format: off
 `resetall
 `timescale 1ns / 1ns
 `default_nettype none
// verilog_format: on

/////////////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////// test bench ///////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////////////////////////////////////
module tb_combination_driver #(
    parameter WISHBONE_INTERFACE_EN = 1,
    parameter CHANNELS_IN_WIDTH = $clog2(18 + 1) + 1,
    parameter CHANNELS = 16,
    parameter CHANNEL_WIDTH = 4
) (
    input wire clk,
    input wire rst,
    //wishbone signals
    wb_interface wb,  // master testbench
    combination_interface.master m_comb_tb  // master testbench
);
    // Parameters for the combination measurement
    logic [63:0] window = 64'h0000000000000032;
    logic [$clog2(CHANNELS+1)-1:0] filter_min = 0;  //higher_bound=16 & lower_bound=0
    logic [$clog2(CHANNELS+1)-1:0] filter_max = CHANNELS;  //higher_bound=16 & lower_bound=0
    logic [31:0] filter = {16'h0000 | filter_max, 16'h0000 | filter_min};  //higher_bound=16 & lower_bound=0
    logic [1 : 0] select_comb_fifo = 2'b10;
    logic capture_enable = 1;
    logic start_reading = 0;
    logic reset_comb = 0;
    reg [15:0] idx_out[64];  //channel out from channel selector
    logic [13:0] addr = 0;

    logic [32:0] comb_results[2**16] = '{default: '0};

    logic [1:0] lut_WrRd;
    assign wb.clk = clk;
    assign wb.rst = rst;
    logic [31:0] data_o;
    logic [31:0] error_cnt = 0;  //should remain in zero
    initial begin
        @(rst == 0);
        #101;
        @(posedge clk);
        #100;
        idx_out = '{default: '0};
        for (int i = 1; i < CHANNELS + 1; i++) begin
            idx_out[i] = (1 << 15) + (i - 1);  // valid & channel
        end

        if (WISHBONE_INTERFACE_EN) begin
            // applying setting
            wb.write(8'h01, window[31:0]);
            wb.write(8'h02, window[63:32]);
            wb.write(8'h03, filter);
            wb.write(8'h04, select_comb_fifo);
            // Configging the LUT in channel selector
            lut_WrRd = 2'b10;
            for (int i = 0; i < 64; i++) begin
                automatic logic [13:0] idx_in = i;
                wb.write(8'h08, {lut_WrRd, idx_in, idx_out[i]});
            end
            lut_WrRd = 2'b01;  // to read back channel selector's LUT
            for (int i = 0; i < 2 ** 6; i++) begin
                wb.write(8'h08, {2'b00, addr, 16'hXXXX});
                wb.read(8'h08, data_o);
                if (data_o[15:0] != idx_out[i]) error_cnt = error_cnt + 1;
                addr = addr + 1;
            end
            wb.read(8'h00, data_o);
            if (data_o != 32'h636F6D62) error_cnt = error_cnt + 1;

            wb.read(8'h01, data_o);
            if (data_o != window[31:0]) error_cnt = error_cnt + 1;

            wb.read(8'h02, data_o);
            if (data_o != window[63:32]) error_cnt = error_cnt + 1;

            wb.read(8'h03, data_o);
            if (data_o != filter) error_cnt = error_cnt + 1;

            wb.read(8'h04, data_o);
            if (data_o[1:0] != select_comb_fifo) error_cnt = error_cnt + 1;
            start_reading = 0;
            wb.write(8'h06, start_reading);

            //activating capture
            wb.write(8'h05, capture_enable);
            wb.read(8'h05, data_o);  //check
            if (data_o[0] != capture_enable) error_cnt = error_cnt + 1;

            #5ms  // wait to accumulate some combinations

            //reading the results
            start_reading = 1;
            wb.write(8'h06, start_reading);

            wb.read(8'h06, data_o);
            if (data_o[0] != start_reading) error_cnt = error_cnt + 1;

            for (int i = 0; i < 2 ** 16; i++) begin
                wb.read(8'h0F, data_o);
                comb_results[i] <= data_o;
            end
            start_reading = 0;
            wb.write(8'h06, start_reading);
            ////////////////////////////////////////////////////////////////////////////////////////
            ////// Reading combinations directly from fifo without histogram ////////////////////////////////
            //////////////////////////////////////////////////////////////////////////////////////// 
            //activating capture
            capture_enable = 0;
            wb.write(8'h05, capture_enable);
            //resetting combination module
            reset_comb = 1;
            wb.write(8'h07, reset_comb);

            wb.write(8'h01, window[31:0]);
            wb.write(8'h02, window[63:32]);
            wb.write(8'h03, filter);
            wb.write(8'h04, select_comb_fifo);
            select_comb_fifo = 2'b01;
            wb.write(8'h04, select_comb_fifo);
            lut_WrRd = 2'b10;
            for (int i = 0; i < 64; i++) begin
                automatic logic [13:0] idx_in = i;
                wb.write(8'h08, {lut_WrRd, idx_in, idx_out[i]});
            end
            capture_enable = 1;
            wb.write(8'h05, capture_enable);
            #5ms  // wait to accumulate some combinations
            start_reading = 1;
            wb.write(8'h06, start_reading);

            comb_results = '{default: '0};
            for (int i = 0; i < 2 ** 16; i++) begin
                wb.read(8'h0F, data_o);
                comb_results[i] <= data_o;
            end
            start_reading = 0;
            wb.write(8'h06, start_reading);
        end else begin
            wait (m_comb_tb.ready_o);
            comb_results = '{default: '0};
            m_comb_tb.start_reading = 0;
            m_comb_tb.window = window;
            m_comb_tb.filter_min = filter_min;
            m_comb_tb.filter_max = filter_max;
            for (int i = 0; i < 64; i++) begin
                m_comb_tb.lut_WrRd = 2'b10;
                m_comb_tb.lut_addr = i;
                m_comb_tb.lut_dat_i = idx_out[i][$clog2(CHANNELS)-1:0];
                m_comb_tb.lut_dat_i[CHANNELS] = idx_out[i][15];
                wait (m_comb_tb.lut_ack);
                @(negedge m_comb_tb.lut_ack);
            end
            m_comb_tb.lut_WrRd = 2'b00;
            m_comb_tb.select_comb_fifo = 2'b10;
            m_comb_tb.capture_enable = 1;
            #5ms m_comb_tb.ready_i = 1;
            m_comb_tb.start_reading = 1;
            @(posedge clk);

            for (integer j = 0; j < 2 ** 16; j++) begin
                wait (m_comb_tb.comb_out_vd);
                comb_results[j] = m_comb_tb.comb_count;
                @(negedge clk);
            end
            @(posedge clk);
            m_comb_tb.start_reading = 0;
            m_comb_tb.ready_i = 0;
            ////////////////////////////////////////////////////////////////////////////////////////
            ////// Reading combinations directly from fifo without histogram ////////////////////////////////
            //////////////////////////////////////////////////////////////////////////////////////// 
            m_comb_tb.reset_comb = 1;
            wait (m_comb_tb.reset_comb_done);
            m_comb_tb.reset_comb = 0;
            @(posedge clk);
            m_comb_tb.capture_enable = 0;

            @(posedge clk);
            //// Now we are reading from fifo
            m_comb_tb.select_comb_fifo = 2'b01;
            m_comb_tb.capture_enable   = 1;
            #5ms comb_results = '{default: '0};
            m_comb_tb.ready_i = 1;
            m_comb_tb.start_reading = 1;
            for (int i = 0; i < 2 ** 10; i++) begin
                wait (m_comb_tb.comb_out_vd);
                comb_results[i] = m_comb_tb.comb_count;
                @(posedge clk);
            end
            m_comb_tb.ready_i = 0;
            m_comb_tb.start_reading = 0;
            @(posedge clk);
        end
    end

endmodule
