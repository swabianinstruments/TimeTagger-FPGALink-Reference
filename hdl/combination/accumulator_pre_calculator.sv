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
This module precalculates the accumulation of the input. If some data is repeated, it will added it up with data_out_happened.
In this case we will be sure that there is no repeated data as input of histogram and we don't need to do dataforwarding during histogram calculation
*/

// verilog_format: off
`resetall
`timescale 1ns / 1ps
`default_nettype none
// verilog_format: on

module accumulator_pre_calculator #(
    parameter WIDTH = 16,
    parameter LEN_OF_BUFFER = 7,  //pipeline
    parameter WIDTH_CNT = $clog2(LEN_OF_BUFFER + 2)
) (
    //input information of channel
    input wire               data_in_vd,
    input wire [WIDTH-1 : 0] data_in,

    input wire clk,
    input wire rst,

    output reg [WIDTH_CNT-1:0] data_out_cnt,
    output reg [    WIDTH-1:0] data_out,
    output reg                 data_out_vd
);

    logic [WIDTH - 1 : 0] data_in_buff_ff[LEN_OF_BUFFER:0];
    logic [LEN_OF_BUFFER:0] data_in_vd_buff_ff;
    logic [WIDTH_CNT-1:0] cnt_comb;

    always @(posedge clk) begin
        cnt_comb = 1;
        data_out_cnt <= 'X;
        data_out <= 'X;
        data_out_vd <= 0;
        if (rst) begin
            data_in_buff_ff <= '{default: 'X};
            data_in_vd_buff_ff <= 0;
        end else begin
            data_in_buff_ff[LEN_OF_BUFFER] <= data_in;
            data_in_vd_buff_ff[LEN_OF_BUFFER] <= data_in_vd;
            for (int i = 1; i <= LEN_OF_BUFFER; i++) begin
                data_in_buff_ff[i-1] <= data_in_buff_ff[i];
                data_in_vd_buff_ff[i-1] <= data_in_vd_buff_ff[i];
                if ((data_in_vd_buff_ff[0] == 1) && (data_in_vd_buff_ff[i] == 1) && (data_in_buff_ff[0] == data_in_buff_ff[i])) begin
                    cnt_comb = cnt_comb + 1;
                    data_in_vd_buff_ff[i-1] <= 0;
                end
            end

            if (data_in_vd_buff_ff[0]) begin
                data_out_vd  <= data_in_vd_buff_ff[0];
                data_out     <= data_in_buff_ff[0];
                data_out_cnt <= cnt_comb;
            end
        end
    end
endmodule
