/**
 * User Sample Design for high bandwidth applications
 *
 * This file is part of the Time Tagger software defined digital data
 * acquisition FPGA-link reference design.
 *
 * Copyright (C) 2023 Swabian Instruments, All Rights Reserved
 *
 * Authors:
 * - 2023-2024 Ehsan Jokar <ehsan@swabianinstruments.com>
 * - 2023-2024 Markus Wick <markus@swabianinstruments.com>
 *
 * This file is provided under the terms and conditions of the BSD 3-Clause
 * license, accessible under https://opensource.org/licenses/BSD-3-Clause.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */
`resetall
`timescale 1ns / 1ps
`default_nettype none

module wb_master #
(
    parameter WORD_SIZE         = 32,
    parameter FIFO_IN_SIZE      = 2048,
    parameter FIFO_OUT_SIZE     = 2048,
    parameter TIME_OUT_VAL      = 100,
    parameter TIMER_SIZE        = $clog2(TIME_OUT_VAL)
)
(
    input  wire                         okClk,
    input  wire                         okRst,

    input  wire                         wb_clk,
    input  wire                         wb_rst,

    // interfaces to OKBTPipeIn
    input  wire                         ep_write,       // valid signal associated with the input data comes from okBTPipeIn
    input  wire                         wr_strobe,      // assetred by okBTPipeIn before starting a write transaction (added for possible usage)
    input  wire [WORD_SIZE - 1 : 0]     data_i,         // data comes from okBTPipeIn
    output reg                          receive_ready,  // asserted by wb_master to show that it's ready to receive data from okBTPipeIn

    // interfaces to OKBTPipeOut
    input  wire                         rd_strobe,      // assetred by okBTPipeOut before starting a write transaction (added for possible usage)
    input  wire                         ep_read,        // asserted by okBTPipeOut before reading the data. The data has to be available exactly in the next clock cycle
    output reg                          send_ready,     // asserted by wb_master to show that there exists data to be read by okBTPipeOut
    output reg [WORD_SIZE - 1 : 0]      data_o,         // data read by okBTPipeOut. The data is available exactly one clock cycle after the assertion of the ep_ready by okBTPipeOut

    // wishbone interfaces
    wb_interface.master_port            wb_master
);

///////////////////////////////////////////////////////input command structure /////////////////////////////////////////////////////////
// command[1  : 0]  : cmd: ==> // 0: read; 1:  write ; 2: read modify write;
// command[14 : 2]  : number of read/write data samples
// command[22 : 15] : command ID
// command[23]      : block position: if it's zero, the block is the first porstion of a larger block data, otherwise, it would not be the first portion. The idea is that
//                    a large block of information can be sent into FPGA during several block transcations. If wb device does not respond, the rest of the data should be discard.
//                    It means that the current block and other blocks related to the existing large block of information should be discard.
//                    This signal is therefore used when the timeout occurs. In this case, other portion of the larger block should be flushed and not be sent to the wishbone block.
// command[31 : 24] : address increment: this is used in the burst mode to determine the incremental size of the address

/////////////////////////////////////// sequence of the input data into the input FIFO /////////////////////////////////////////////////

//  single write        : command --> address --> dummy data (or mask) --> data
//  single read         : command --> address --> dummy data --> dummy data
//  burst write         : command --> address --> one dummy data --> data1 --> data2 --> data3 --> ... dataN --> dummy data  (to be compatible with single burst write)
//  burst read          : command --> address --> dummy data --> dummy data
//  read modify write   : command --> address --> mask --> data

/////////////////////////////////////// sequence of the output data into the output FIFO ////////////////////////////////////////////////
// result structure:
// result [0]           : time_out detection: 0: no time out; 1: time_out occurred

//  single write        : sent command --> zero padding --> address --> result
//  single read         : sent command --> data         --> address --> result
//  burst write         : sent command --> zero padding --> address --> result
//  burst read          : sent command --> data1  --> data2 --> data3 --> ... dataN --> zero padding (if needed) --> address --> result
//  read modify write   : sent command --> previous data --> address --> result

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

logic fifo1_empty, fifo1_full, fifo1_prog_empty, fifo1_prog_full, fifo1_valid;
logic fifo1_rd_en;
logic [WORD_SIZE - 1 : 0] fifo1_dout;

// input FIFO: used to store data comes from okBTPipeIn
xpm_fifo_async #(
   .CDC_SYNC_STAGES     (2                  ),
   .FIFO_MEMORY_TYPE    ("auto"             ),
   .FIFO_WRITE_DEPTH    (FIFO_IN_SIZE       ),
   .PROG_EMPTY_THRESH   (10),
   .PROG_FULL_THRESH    (FIFO_IN_SIZE - 300 ),
   .READ_DATA_WIDTH     (WORD_SIZE          ),
   .READ_MODE           ("fwft"             ),
   .USE_ADV_FEATURES    ("0707"             ),
   .WRITE_DATA_WIDTH    (WORD_SIZE          )
)
xpm_fifo_async_input (
    .rst            (okRst              ),
    .wr_clk         (okClk              ),
    .rd_clk         (wb_clk             ),
    .empty          (fifo1_empty        ),
    .full           (fifo1_full         ),
    .prog_empty     (fifo1_prog_empty   ),
    .prog_full      (fifo1_prog_full    ),
    .dout           (fifo1_dout         ),
    .wr_en          (ep_write           ),
    .din            (data_i             ),
    .rd_en          (fifo1_rd_en        )
);
// XPM FWFT valid does not match the other valid behavior.
// So let's define it on our own.
assign fifo1_valid = !fifo1_empty && fifo1_rd_en;

logic fifo2_empty, fifo2_full, fifo2_prog_empty, fifo2_prog_full;
logic fifo2_data_valid, fifo2_wt_en;
logic [WORD_SIZE - 1 : 0] fifo2_din;

// output FIFO: used to store data send to okBTPipeOut
xpm_fifo_async #(
   .CDC_SYNC_STAGES     (2                  ),
   .FIFO_MEMORY_TYPE    ("auto"             ),
   .FIFO_WRITE_DEPTH    (FIFO_IN_SIZE       ),
   .PROG_EMPTY_THRESH   (4 - 1              ), // Asserted "at or below" this value
   .PROG_FULL_THRESH    (FIFO_IN_SIZE - 10  ),
   .READ_DATA_WIDTH     (WORD_SIZE          ),
   .USE_ADV_FEATURES    ("1707"             ),
   .WRITE_DATA_WIDTH    (WORD_SIZE          )
)
xpm_fifo_async_output (
    .rst            (wb_rst             ),
    .wr_clk         (wb_clk             ),
    .rd_clk         (okClk              ),
    .empty          (fifo2_empty        ),
    .full           (fifo2_full         ),
    .prog_empty     (fifo2_prog_empty   ),
    .prog_full      (fifo2_prog_full    ),
    .data_valid     (fifo2_data_valid   ),
    .dout           (data_o             ),
    .wr_en          (fifo2_wt_en        ),
    .din            (fifo2_din          ),
    .rd_en          (ep_read            )
);

//wb_master and okBTPipeIn/okBTPipeOut Handshake
always_comb @(*) begin
    receive_ready   <= !fifo1_prog_full;
    send_ready      <= !fifo2_prog_empty;
end

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

enum logic [3 : 0] {COMMAND_EXTRACTION, ADDRESS_EXCTRACTION, EXTRACT_MASK, EXTRACT_DATA, SEND_WB_COMMAND, WRITING_BACK_COMMAND, WRITTING_DATA, WRITING_ADDRESS, WRITING_RESULT} input_state;

logic [WORD_SIZE - 1  : 0]  command;
logic [WORD_SIZE - 1  : 0]  mask;
logic [WORD_SIZE - 1  : 0]  pure_data;
logic [WORD_SIZE - 1  : 0]  wb_inp_address;
logic [WORD_SIZE - 1  : 0]  last_address;
logic [WORD_SIZE - 1  : 0]  result;  // the lsb bit determines whether a timeout has occurred or not.

// Parse command struct and provide easier to use helpers
logic [1  : 0]  command_type;   // 0: read; 1:  write ; 2: read modify write;
logic [12 : 0]  block_size;
logic [7  : 0]  command_ID;
logic [7  : 0]  addr_incr;      // address increment
logic           block_position; // 0: first portion, 1: otherwise
logic           single_read;
logic           single_write;
logic           read_modify_write;
logic           burst_read;
logic           burst_write;
always @(*) begin
    command_type        <= command[1  :  0];
    block_size          <= command[14 :  2];
    command_ID          <= command[22 : 15];
    block_position      <= command[23];
    addr_incr           <= command[31 : 24];

    single_read         <= command_type == 0 && block_size == 1;
    burst_read          <= command_type == 0 && block_size != 1;
    single_write        <= command_type == 1 && block_size == 1;
    burst_write         <= command_type == 1 && block_size != 1;
    read_modify_write   <= command_type == 2;
end

logic [TIMER_SIZE - 1 : 0]  timeout_cnt;
logic                       timeout_flag;        // 1: timeout has occurred.

logic [15 : 0]              cnt_data_read;       // This counter is used to count the total samples of command, address, all the data, and the dummy data read from FIFO1
logic [15 : 0]              cnt_pure_data_read;  // This counter is used to count the real data samples read from FIFO1

logic [15 : 0]              cnt_data_write;      // This counter is used to count the total samples of command, address, all the data, and the dummy data written into FIFO2
logic [15 : 0]              cnt_pure_data_write; // This counter is used to count the real data samples written into FIFO2

logic [WORD_SIZE - 1  : 0]  wb_data_in;
logic                       command_sent;        // 1 means command hs been sent one, and for the burst read mode, the state changes from SEND_WB_COMMAND to WRITTING_DATA, otherwise the state changes from SEND_WB_COMMAND to WRITING_BACK_COMMAND.

logic                       modified_data_write; // when it's asserted, the state changes into SEND_WB_COMMAND, and the data is written into the target module through the wb interface.
logic [WORD_SIZE - 1  : 0]  non_modified_data;   // data read from wb before beign modified
logic [WORD_SIZE - 1  : 0]  modified_data;       // modified data

// connecting the wb_master clock and reset ports to the input clk and rst ports
assign wb_master.clk      = wb_clk;
assign wb_master.rst      = wb_rst;

always_ff @(posedge wb_clk) begin
    if (wb_rst) begin
        input_state         <= COMMAND_EXTRACTION;
        fifo1_rd_en         <= 0;
        timeout_flag        <= 0;
        cnt_data_read       <= 0;
        cnt_pure_data_read  <= 0;
        cnt_data_write      <= 0;
        cnt_pure_data_write <= 0;
        result              <= 0;
    end

    // By default: Release the wishbone bus.
    // So every blocking state must manually keep stb&cyc asserted.
    wb_master.wb_stb_o  <= 0;
    wb_master.wb_cyc_o  <= 0;
    wb_master.wb_we_o   <= 'X;
    wb_master.wb_adr_o  <= 'X;
    wb_master.wb_dat_o  <= 'X;

    // By default: No action on the fifos
    fifo2_wt_en         <= 0;
    fifo2_din           <= 'X;
    fifo1_rd_en         <= 0;

    // Reset timeout and assembly return word
    timeout_cnt         <= 0;
    result[0]           <= timeout_flag;

    unique case (input_state)
        //-----------------------------------------------------------------------
        COMMAND_EXTRACTION : begin
            fifo1_rd_en     <= 1;
            if (fifo1_valid) begin
                input_state         <= ADDRESS_EXCTRACTION;

                command             <= fifo1_dout;

                cnt_data_read       <= 1;
                cnt_pure_data_read  <= 0;
                command_sent        <= 0;
                modified_data_write <= 0;
            end
        end

        //-----------------------------------------------------------------------
        ADDRESS_EXCTRACTION : begin
            fifo1_rd_en     <= 1;
            // if we receive a completely new block of information, block_position is zero, meaning that the current block of data is the first portion
            // of a larger block of data. Therefore, the previous timeout_flag is reset. Otherwise, timeout_flag keeps it's previous value.
            if (!block_position)
                timeout_flag    <= 0;

            if (fifo1_valid) begin
                wb_inp_address      <= fifo1_dout;
                input_state         <= EXTRACT_MASK;

                cnt_data_read       <= 2;
                cnt_pure_data_read  <= 0;
            end
        end
        //-----------------------------------------------------------------------
        EXTRACT_MASK : begin
            fifo1_rd_en     <= 1; // EXTRACT_DATA always wants to read at least one word, so it is safe to set it here
            if (fifo1_valid) begin
                mask            <= fifo1_dout;
                input_state     <= EXTRACT_DATA;

                cnt_data_read       <= 3;
                cnt_pure_data_read  <= 0;
            end
        end
        //-----------------------------------------------------------------------
        EXTRACT_DATA : begin
            if ((cnt_pure_data_read >= block_size) && (cnt_data_read[1:0] == 0) && (burst_write)) begin
                input_state     <= WRITING_BACK_COMMAND;
            end else begin
                fifo1_rd_en     <= 1;
            end

            if (fifo1_valid) begin
                pure_data           <= fifo1_dout;

                cnt_data_read       <= cnt_data_read + 1;
                cnt_pure_data_read  <= cnt_pure_data_read + 1;

                // Always disable the reading of the fifo. Se we only get a new word every second clock cycle.
                // We don't care about the throughput, but this makes the tracking of cnt_data_read easier.
                fifo1_rd_en     <= 0;

                // if timeout has not occurred, by receiving a new data from FIFO1, the state changes into SEND_WB_COMMAND to start a new wb transaction.
                // Otherwise, no wb transaction is initiated, and the state remains EXTRACT_DATA until flushing the block. If timeout_flag is still asserted,
                // the FIFO1 output data is discard even though a new command is initiated. If fact, we discard the data until the block_position signal be zero,
                // indicating that a completely new block of information is received.
                if (!timeout_flag && (cnt_pure_data_read < block_size)) begin
                    input_state     <= SEND_WB_COMMAND;
                end
            end
        end
        //-----------------------------------------------------------------------
        SEND_WB_COMMAND : begin
            wb_master.wb_stb_o  <= 1'b1;
            wb_master.wb_cyc_o  <= 1'b1;
            wb_master.wb_we_o   <= command_type[0]; // 0: read; 1: write
            wb_master.wb_adr_o  <= wb_inp_address;
            wb_master.wb_dat_o  <= pure_data;
            if (modified_data_write) begin
                wb_master.wb_we_o   <= 1; // 0: read; 1: write
                wb_master.wb_dat_o  <= modified_data;
            end

            if (wb_master.wb_ack_i || timeout_flag) begin
                wb_master.wb_stb_o  <= 1'b0;
                wb_master.wb_cyc_o  <= 1'b0;
                wb_master.wb_adr_o  <= 'X;
                wb_master.wb_dat_o  <= 'X;
                wb_master.wb_we_o   <= 'X;
                wb_inp_address      <= wb_inp_address + addr_incr;
                last_address        <= wb_inp_address;
                wb_data_in          <= wb_master.wb_dat_i;

                if (burst_write)
                    input_state     <= EXTRACT_DATA;
                else if (command_sent)
                    input_state     <= WRITTING_DATA; // used in the burst_read mode to write the second and other data into FIFO2
                else
                    input_state     <= WRITING_BACK_COMMAND;
            end

            timeout_cnt         <= timeout_cnt + 1;
            if (timeout_cnt == TIME_OUT_VAL - 1)
                timeout_flag    <= 1;

        end
        //-----------------------------------------------------------------------
        WRITING_BACK_COMMAND: begin
            if (!fifo2_prog_full) begin
                fifo2_wt_en         <= 1;
                fifo2_din           <= command;
                input_state         <= WRITTING_DATA;
                if(read_modify_write) begin
                    input_state         <= SEND_WB_COMMAND;
                    non_modified_data   <= wb_data_in;
                    modified_data       <= (wb_data_in & ~mask) | (pure_data & mask);
                    modified_data_write <= 1;
                end

                cnt_data_write      <= 1;
                cnt_pure_data_write <= 0;
            end
            command_sent        <= 1;
        end
        //-----------------------------------------------------------------------
        WRITTING_DATA: begin
            if (!fifo2_prog_full) begin
                fifo2_wt_en         <= 1;
                if (single_write || burst_write)
                    fifo2_din       <= 32'hdeadbeef;
                else if (read_modify_write)
                    fifo2_din       <= non_modified_data;
                else
                    fifo2_din       <= wb_data_in;

                cnt_data_write      <= cnt_data_write + 1;
                cnt_pure_data_write <= cnt_pure_data_write + 1;

                if (burst_read) begin
                    if (!timeout_flag && cnt_pure_data_write < block_size-1)
                        input_state     <= SEND_WB_COMMAND;
                    else if (cnt_pure_data_write >= block_size-1 && cnt_data_write[1:0]==1)
                        input_state     <= WRITING_ADDRESS;
                end else if (!burst_read)
                    input_state     <= WRITING_ADDRESS;
            end

        end
        //-----------------------------------------------------------------------
        WRITING_ADDRESS: begin
            if (!fifo2_prog_full) begin
                fifo2_wt_en     <= 1;
                fifo2_din       <= last_address;
                input_state     <= WRITING_RESULT;
            end
        end
        //-----------------------------------------------------------------------
        WRITING_RESULT: begin
            if (!fifo2_prog_full) begin
                fifo2_wt_en     <= 1;
                fifo2_din       <= result;
                input_state     <= COMMAND_EXTRACTION;
            end
        end
        //-----------------------------------------------------------------------
        default: begin
            input_state     <= COMMAND_EXTRACTION;
        end
    endcase

end

endmodule
