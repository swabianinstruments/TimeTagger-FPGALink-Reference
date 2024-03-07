/**
 * XGMII to AXI4-Stream Bridge (64-bit transmit side).
 *
 * This file is part of the Time Tagger software defined digital data
 * acquisition FPGA-link reference design.
 *
 * Copyright (C) 2021-2022 Leon Schuermann <leon@is.currently.online>
 * Copyright (C) 2022 Swabian Instruments, All Rights Reserved
 *
 * Authors:
 * - 2021-2022 Leon Schuermann <leon@is.currently.online>
 * - 2022 Leon Schuermann <leon@swabianinstruments.com>
 *
 * This module is based on [1], licensed under the BSD-2-Clause
 * license. It has been relicensed for the purposes of inclusion into
 * this repository under the BSD 3-Clause license.
 *
 * This file is provided under the terms and conditions of the BSD 3-Clause
 * license, accessible under https://opensource.org/licenses/BSD-3-Clause.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * [1]: https://github.com/enjoy-digital/liteeth/blob/6f0c1b6a91f058da202c745202df688bf95a6135/liteeth/phy/xgmii.py
 */

// verilog_format: off
 `resetall
 `timescale 1ns / 1ps
 `default_nettype none
// verilog_format: on

module xgmii_axis_bridge_tx_64b #(
    parameter ENABLE_DIC = 1
) (
    input wire clk,
    input wire rst,

    // Provide default (reset) values for xgmii_data and xgmii_ctrl,
    // as the cocotbext-eth testbench XgmiiSink expects signals to be
    // driven immediately.
    output reg [63:0] xgmii_data,
    output reg [ 7:0] xgmii_ctrl = 8'hFF,

    output reg         axis_tready,
    input  wire        axis_tvalid,
    input  wire [63:0] axis_tdata,
    input  wire        axis_tlast,
    input  wire [ 7:0] axis_tkeep,

    output reg error_tlast_tkeep
);

    // --------- XGMII & Ethernet constants ----------
    localparam [7:0] XGMII_IDLE = 8'h07, XGMII_START = 8'hFB, XGMII_END = 8'hFD;
    localparam [63:0] ETH_PREAMBLE = 64'hD555555555555555;

    initial xgmii_data = {8{XGMII_IDLE}};

    // ---------- Masked tkeep to encode last --------
    reg [7:0] axis_tkeep_masked;

    always @(*) begin
        if (axis_tlast) begin
            axis_tkeep_masked = axis_tkeep;
        end else begin
            axis_tkeep_masked = 8'hFF;
        end
    end

    // ---------- Interframe gap state ----------

    // State to keep track of the current inter-frame gap we are required to
    // maintain. We must take care to always have an inter-frame gap of at least
    // 96 bits (12 bytes), with an exception for the deficit idle gap
    // mechanism. Because XGMII transactions can only start on the first or
    // fifth byte in a 64-bit bus word, it's sufficient to represent this as
    //
    // - 0: less than 4 bytes of IFG transmitted
    // - 1: less than 8 bytes of IFG transmitted
    // - 2: less than 12 bytes of IFG transmitted
    // - 3: 12 or more bytes of IFG transmitted
    reg [1:0] ifg_state;

    // Control signals for the interframe gap state. Useful to add a 32-bit or
    // 64-bit IDLE bus word to the current interframe gap without worrying about
    // wrapping or to reset it (on the start of a new transmission).
    reg ifg_reset, ifg_add_double, ifg_add_single;

    always @(posedge clk) begin
        if (rst) begin
            // On reset it's fine to assume a full IFG was maintained.
            ifg_state <= 3;
        end else if (ifg_reset) begin
            ifg_state <= 0;
        end else if (ifg_add_single) begin
            if (ifg_state < 3) begin
                ifg_state <= ifg_state + 1;
            end
        end else if (ifg_add_double) begin
            if (ifg_state < 2) begin
                ifg_state <= ifg_state + 2;
            end else begin
                ifg_state <= 3;
            end
        end
    end

    // ---------- Deficit idle count mechanism state ----------

    // Because XGMII only allows start of frame characters to be placed on lane
    // 0 (first and fifth octet in a 64-bit bus word), when a packet's length %
    // 4 != 0, we can't transmit exactly 12 XGMII idle characters inter-frame
    // gap (the XGMII end of frame character counts towards the inter-frame gap,
    // while start of frame does not). Given we are required to transmit a
    // minimum of 12 bytes IFG, it's allowed to send packet length % 4 bytes
    // additional IFG bytes. However this would waste precious bandwidth
    // transmitting these characters.
    //
    // Thus, 10Gbit/s Ethernet and above allow using the deficit idle count
    // mechanism. It allows to delete some idle characters, as long as an
    // average count of >= 12 bytes IFG is maintained. This is to be implemented
    // as a two bit counter as specified in IEEE802.3-2018, section four,
    // 46.3.1.4 Start control character alignment.
    //
    // This module implements the deficit idle count algorithm as described by
    // Eric Lynskey of the UNH InterOperability Lab[1]:
    //
    // | current |             |             |             |             |
    // | count   |           0 |           1 |           2 |           3 |
    // |---------+-----+-------+-----+-------+-----+-------+-----+-------|
    // |         |     | new   |     | new   |     | new   |     | new   |
    // | pkt % 4 | IFG | count | IFG | count | IFG | count | IFG | count |
    // |---------+-----+-------+-----+-------+-----+-------+-----+-------|
    // |       0 |  12 |     0 |  12 |     1 |  12 |     2 |  12 |     3 |
    // |       1 |  11 |     1 |  11 |     2 |  11 |     3 |  15 |     0 |
    // |       2 |  10 |     2 |  10 |     3 |  14 |     0 |  14 |     1 |
    // |       3 |   9 |     3 |  13 |     0 |  13 |     1 |  13 |     2 |
    //
    // [1]: https://www.iol.unh.edu/sites/default/files/knowledgebase/10gec/10GbE_DIC.pdf


    // Additional state to keep track of exactly how many bytes % 4 we've
    // transmitted in the last packet. We need this information to judge whether
    // we've had a sufficiently large IFG given the current DIC count. Value the
    // range of [0; 3].
    //
    // If the DIC mechanism is disabled, the last_packet_rem is replaced with a
    // constant signal which should allow for significant logic optimizations.
    wire [1:0] last_packet_rem;
    reg [1:0] last_packet_rem_reg, last_packet_rem_next;

    generate
        if (ENABLE_DIC) begin
            assign last_packet_rem = last_packet_rem_reg;
        end else begin
            assign last_packet_rem = 0;
        end
    endgenerate

    // Bounded counter of deleted XGMII idle characters. Must be within [0;
    // 3]. If we disable the deficit idle count mechanism, dic_deleted is
    // replaced with a constant signal which should allow for significant logic
    // optimizations.
    wire [1:0] dic_deleted;
    reg [1:0] dic_deleted_reg, dic_deleted_next;

    generate
        if (ENABLE_DIC) begin
            assign dic_deleted = dic_deleted_reg;
        end else begin
            assign dic_deleted = 0;
        end
    endgenerate

    // ---------- Shifted transmit state ----------

    reg        prev_tvalid;
    reg [31:0] prev_valid_tdata;
    reg [ 3:0] prev_valid_tkeep;
    reg        prev_valid_tlast;

    always @(posedge clk) begin
        if (rst) begin
            prev_tvalid <= 0;
            prev_valid_tdata <= 0;
            prev_valid_tkeep <= 0;
            prev_valid_tlast <= axis_tlast;
        end else if (axis_tvalid) begin
            prev_tvalid <= 1;
            prev_valid_tdata <= axis_tdata[63:32];
            prev_valid_tkeep <= axis_tkeep_masked[7:4];
            prev_valid_tlast <= axis_tlast;
        end else begin
            prev_tvalid <= 0;
        end
    end

    // Whether the current transmission is shifted, meaning that the packet's
    // transmission started on the fifth octet within the 64-bit bus word. As a
    // consequence of the shifted transmission, given that we receive 64 valid
    // bits from the sink, we need to store and delay the upper half of the
    // current clock cycle's data to the next.
    //
    // This register is to be set when transitioning out of the IDLE state.
    reg transmit_shifted, transmit_shifted_next;

    // Adjusted sink tdata & tkeep. If our transmission is shifted, this will
    // contain the upper-half of the previous and lower-half of the current
    // clock cycle. Otherwise, simply equal to tdata and the masked tkeep.
    reg adjusted_tvalid, adjusted_tlast;
    reg [63:0] adjusted_tdata;
    reg [ 7:0] adjusted_tkeep;

    always @(*) begin
        // Defaults:
        error_tlast_tkeep = 0;

        // We enforce a non-zero tkeep be asserted along tlast.
        if (axis_tlast && (axis_tkeep == 0)) begin
            error_tlast_tkeep = 1;
        end

        if (transmit_shifted) begin
            // Because we are injecting data from the previous cycle, we need to
            // respect it's valid. It's fine that adjusted_tvalid therefore is
            // deasserted for the very first bus word, given this is handled in
            // the IDLE fsm state still. This assumes a non-hostile sink where
            // valid is constantly asserted during a single transmission.

            adjusted_tvalid = prev_tvalid;
            adjusted_tdata  = {axis_tdata[31:0], prev_valid_tdata};

            // Don't expose the upper tkeep (which might be asserted) when the
            // lower isn't fully asserted (end of transaction) or when last was
            // asserted.
            if ((prev_valid_tkeep != 4'hF) || prev_valid_tlast) begin
                adjusted_tkeep = {4'h0, prev_valid_tkeep};
            end else begin
                adjusted_tkeep = {axis_tkeep_masked[3:0], prev_valid_tkeep};
            end

            // The adjusted sink should only be last when we have a
            // prev_valid_tkeep != 0xF (meaning that at least some bytes aren't
            // valid there) or the axis_tkeep_masked[3:0] isn't 0xF (not all
            // bytes of the upper half are valid) or axis_tkeep_masked[4] is 0
            // (the first byte exposed in the next cycle is not valid).
            if ((prev_valid_tkeep != 4'hF) || (axis_tkeep_masked[3:0] != 4'hF) || (axis_tkeep_masked[4] == 0)) begin
                adjusted_tlast = 1;
            end else begin
                adjusted_tlast = 0;
            end
        end else begin
            adjusted_tvalid = axis_tvalid;
            adjusted_tdata  = axis_tdata;
            adjusted_tkeep  = axis_tkeep_masked;
            adjusted_tlast  = axis_tlast;
        end
    end

    // ---------- XGMII Transmission FSM ----------

    localparam FSM_IDLE = 1'b0, FSM_TRANSMIT = 1'b1;
    reg fsm_state_reg, fsm_state_next;

    reg fsm_end_transmission, fsm_end_transmission_next;
    reg fsm_shifted_preamble, fsm_shifted_preamble_next;
    reg fsm_mask_ready, fsm_mask_ready_next;

    // Initial values for simulation
    reg [63:0] xgmii_data_next = {8{XGMII_IDLE}};
    reg [ 7:0] xgmii_ctrl_next = 8'hFF;


    always @(posedge clk) begin
        if (rst) begin
            fsm_state_reg <= FSM_IDLE;
            fsm_end_transmission <= 0;
            fsm_shifted_preamble <= 0;
            fsm_mask_ready <= 0;

            transmit_shifted <= 0;
            dic_deleted_reg <= 3;  // Start with no deleted idle characters
            last_packet_rem_reg <= 0;  // Assume aligned packet length (full)

            xgmii_data <= {8{XGMII_IDLE}};
            xgmii_ctrl <= 8'hFF;
        end else begin
            fsm_state_reg <= fsm_state_next;
            fsm_end_transmission <= fsm_end_transmission_next;
            fsm_shifted_preamble <= fsm_shifted_preamble_next;
            fsm_mask_ready <= fsm_mask_ready_next;

            transmit_shifted <= transmit_shifted_next;
            dic_deleted_reg <= dic_deleted_next;
            last_packet_rem_reg <= last_packet_rem_next;

            xgmii_data <= xgmii_data_next;
            xgmii_ctrl <= xgmii_ctrl_next;
        end
    end

    // Loop index variable
    integer i;

    always @(*) begin
        // Combinational default values (corresponding to synchronous
        // assignments above)
        //
        // IFG state control signals
        ifg_reset = 0;
        ifg_add_single = 0;
        ifg_add_double = 0;
        // Internal FSM state
        fsm_state_next = fsm_state_reg;
        fsm_end_transmission_next = 0;
        fsm_shifted_preamble_next = 0;
        fsm_mask_ready_next = 0;
        // Transmit shifted indicator (used to provide the adjusted data & ctrl
        // signals)
        transmit_shifted_next = transmit_shifted;
        // Deficit idle count state
        dic_deleted_next = dic_deleted;
        // Remainder of last packet, mod 4 (relevant for DIC)
        last_packet_rem_next = last_packet_rem;
        // Combinational AXI4-Stream sink ready feedback
        axis_tready = 0;
        // XGMII output is produced in every branch below, use X to aid in
        // simulation. Should never propagate to output:
        xgmii_ctrl_next = {8{1'bx}};
        xgmii_data_next = {64{1'bx}};

        case (fsm_state_reg)
            FSM_IDLE: begin
                if (axis_tvalid && (ifg_state == 3)) begin
                    // Branch A: we've transmitted at least the full 12 bytes of
                    // IFG. This means that we can unconditionally start
                    // transmission on the first octet.

                    // Reset the IFG counter.
                    ifg_reset = 1;

                    // Transmit the preamble.
                    xgmii_ctrl_next = 8'h01;
                    xgmii_data_next = {ETH_PREAMBLE[63:8], XGMII_START};

                    // Indicate that we are in the unshifted transmit state.
                    transmit_shifted_next = 0;

                    // We may have inserted some extra IFG and thus can reduce the
                    // deficit.
                    if ($signed(dic_deleted - last_packet_rem) < 0) begin
                        dic_deleted_next = 0;
                    end else begin
                        dic_deleted_next = dic_deleted - last_packet_rem;
                    end

                    // Go to FSM_TRANSMIT state.
                    fsm_state_next = FSM_TRANSMIT;
                end else if (axis_tvalid && (ifg_state == 2)) begin
                    // Branch B: we've transmitted at least 8 bytes of IFG. This
                    // means that we can either -- depending on the DIC -- start
                    // transmission on the first or fifth octet. Manipulate the
                    // DIC count accordingly.
                    if ((last_packet_rem != 0) && (dic_deleted + last_packet_rem <= 3)) begin
                        // Branch B.1: we can leave out some IDLEs thanks to DIC,
                        // and can thus transmit on the first octet.
                        dic_deleted_next = dic_deleted + last_packet_rem;

                        // Perform an unshifted transmit.
                        xgmii_ctrl_next = 8'h01;
                        xgmii_data_next = {ETH_PREAMBLE[63:8], XGMII_START};

                        // Indicate that we are in the unshifted transmit state.
                        transmit_shifted_next = 0;

                    end else begin
                        // Branch B.2: we can't transmit on the first octet as
                        // there haven't been sufficient IDLEs yet, but on the
                        // fifth.

                        // We may have inserted some extra IFG and thus can reduce
                        // the deficit.
                        if ($signed(dic_deleted - last_packet_rem) < 0) begin
                            dic_deleted_next = 0;
                        end else begin
                            dic_deleted_next = dic_deleted - last_packet_rem;
                        end

                        // Perform a shifted transmit.
                        xgmii_ctrl_next = 8'h1F;
                        xgmii_data_next = {ETH_PREAMBLE[31:8], XGMII_START, {4{XGMII_IDLE}}};

                        // Indicate that we are in the shifted transmit state.
                        transmit_shifted_next = 1;
                        fsm_shifted_preamble_next = 1;
                    end

                    // Reset the IFG counter.
                    ifg_reset = 1;

                    // Go to FSM_TRANSMIT state.
                    fsm_state_next = FSM_TRANSMIT;
                end else if (axis_tvalid
                           && (ifg_state == 1)
                           && (last_packet_rem != 0)
                           && (dic_deleted + last_packet_rem <= 3)) begin
                    // Branch C: we've transmitted at least 4 bytes of IFG, but
                    // can already start a new transmission thanks to DIC. We're
                    // deleting at least one IFG character, hence update the DIC
                    // count.
                    dic_deleted_next = dic_deleted + last_packet_rem;

                    // Perform a shifted transmit.
                    xgmii_ctrl_next = 8'h1F;
                    xgmii_data_next = {ETH_PREAMBLE[31:8], XGMII_START, {4{XGMII_IDLE}}};

                    // Indicate that we are in the shifted transmit state.
                    transmit_shifted_next = 1;
                    fsm_shifted_preamble_next = 1;


                    // Reset the IFG counter.
                    ifg_reset = 1;

                    // Go to FSM_TRANSMIT state.
                    fsm_state_next = FSM_TRANSMIT;
                end else begin
                    // Branch D: either we don't have any data to transmit or
                    // insufficient IFG (even with DIC). Thus transmit IDLE.
                    xgmii_ctrl_next = 8'hFF;
                    xgmii_data_next = {8{XGMII_IDLE}};

                    // Track IFG insertion
                    ifg_add_double  = 1;

                    // If we have already inserted over 8 bytes of IFG we will
                    // eliminate any idle deficit in this cycle.
                    if (ifg_state >= 2) begin
                        dic_deleted_next = 0;
                    end
                end
            end

            FSM_TRANSMIT: begin
                // Check whether the supplied data is still valid or the transmission
                // should end immediately.
                if (fsm_end_transmission || !adjusted_tvalid) begin
                    // Data isn't valid or we're forced to end the
                    // transmission. This may happen if we've finished
                    // transmitting all packet data but didn't have space left for
                    // the XGMII_END control character. Thus end the transmission
                    // now.
                    xgmii_ctrl_next = 8'hFF;
                    xgmii_data_next = {{7{XGMII_IDLE}}, XGMII_END};

                    // Also, we're transmitting 64 bits worth of IDLE characters
                    // (the END does count towards IDLE).
                    ifg_add_double = 1;

                    // We've ended the transmission, if requested
                    fsm_end_transmission_next = 0;

                    // Return to IDLE
                    fsm_state_next = FSM_IDLE;
                end else begin
                    // Accept the provided data. adjusted_tvalid is checked in
                    // the branch above.
                    axis_tready = !fsm_mask_ready;

                    // Set the XGMII bus word based on the adjusted tkeep
                    for (i = 0; i < 8; i = i + 1) begin
                        if (fsm_shifted_preamble && i < 4) begin
                            xgmii_ctrl_next[i] = 0;
                            xgmii_data_next[(i*8)+:8] = ETH_PREAMBLE[32+(i*8)+:8];
                        end else if (adjusted_tkeep[i]) begin
                            // The byte at offset i holds valid data!
                            xgmii_ctrl_next[i] = 0;
                            xgmii_data_next[(i*8)+:8] = adjusted_tdata[(i*8)+:8];
                        end else if (i == 0 || adjusted_tkeep[i-1]) begin
                            // This is the first byte not holding valid data, end
                            // the transmission. For i == 0, this branch really
                            // shouldn't be taken, given we dont accept a tlast &&
                            // (tkeep == 0) and report such conditions as
                            // error_tlast_tkeep. Still, handle this case properly
                            // and record the IFG inserted.
                            xgmii_ctrl_next[i] = 1;
                            xgmii_data_next[(i*8)+:8] = XGMII_END;

                            // From this character onward the IFG starts.
                            if (i == 0) begin
                                ifg_add_double = 1;
                            end else if (i < 5) begin
                                ifg_add_single = 1;
                            end

                            // Also, keep track of the remainder (mod 4) of IDLE
                            // bytes being sent (the END character counts).
                            /* verilator lint_off WIDTH */
                            last_packet_rem_next = i % 4;  // MODIVS generates 32 bits
                            /* verilator lint_on WIDTH */
                        end else begin
                            xgmii_ctrl_next[i] = 1;
                            xgmii_data_next[(i*8)+:8] = XGMII_IDLE;
                        end
                    end

                    // If this was the last data word, we must determine whether
                    // we have transmitted the XGMII end of frame control
                    // character. The only way this cannot happen is if every byte
                    // in the data word was valid. If this is the case, we must
                    // send an additional XGMII end of frame control character in
                    // the next cycle.
                    if (adjusted_tlast && adjusted_tkeep[7]) begin
                        // Remain in this state and transmit the END control
                        // character before returning to IDLE and accepting new
                        // data.
                        fsm_end_transmission_next = 1;
                    end else if (adjusted_tlast) begin
                        // Already transmitted the END control character, return
                        // to IDLE state.
                        fsm_end_transmission_next = 0;
                        fsm_state_next = FSM_IDLE;
                    end else if (axis_tlast) begin
                        // This wasn't the last adjusted (shifted) word, but the
                        // last non-shifted AXI transaction. This means that the
                        // lower half of the next (shifted) word will contain the
                        // end of packet. Thus mask the next ready.
                        fsm_mask_ready_next = 1;
                    end
                end
            end
        endcase
    end

endmodule
