/**
 * XLGMII to AXI4-Stream Bridge (128-bit XLGMII transmit side).
 *
 * This file is part of Time Tagger software defined digital data acquisition.
 *
 * Copyright (C) 2022 Swabian Instruments, All Rights Reserved
 * Authors:
 *     2022 Leon Schuermann <leon@swabianinstruments.com>
 *     2023 David Sawatzke  <david@swabianinstruments.com>
 *
 * This module is based on [1], originally written by Leon Schuermann as part of
 * his master's thesis and licensed under the BSD-2-Clause license.
 *
 * [1]: https://github.com/enjoy-digital/liteeth/blob/6f0c1b6a91f058da202c745202df688bf95a6135/liteeth/phy/xgmii.py
 *
 * Unauthorized copying of this file is strictly prohibited.
 */


// verilog_format: off
 `resetall
 `timescale 1ns / 1ps
 `default_nettype none
// verilog_format: on

module xlgmii_axis_bridge_tx_128b (
    axis_interface.slave axis,

    // Provide default (reset) values for xgmii_data and xgmii_ctrl,
    // as the cocotbext-eth testbench XgmiiSink expects signals to be
    // driven immediately.
    output reg [127:0] xgmii_data = {16{XGMII_IDLE}},
    output reg [ 15:0] xgmii_ctrl = 16'hFFFF,

    output reg error_tlast_tkeep
);

    initial begin
        if (axis.DATA_WIDTH != 128) begin
            $error("Error: axis.DATA_WIDTH needs to be 128 bits");
            $finish;
        end
    end

    // --------- XGMII & Ethernet constants ----------
    localparam [7:0] XGMII_IDLE = 8'h07, XGMII_START = 8'hFB, XGMII_END = 8'hFD;
    localparam [63:0] ETH_PREAMBLE = 64'hD555555555555555;


    // ---------- Interframe gap state ----------

    // State to keep track of the current inter-frame gap we are required to
    // maintain. We must take care to always have an inter-frame gap of at least
    // 96 bits (12 bytes), with an exception for the deficit idle gap
    // mechanism. Because XLGMII transactions can only start on the first or
    // ninth byte in a 128-bit bus word, it's sufficient to represent this as
    //
    // - 0: more than 8 bytes of IFG left
    // - 1: some IFG left
    // - 2: No IFG left
    reg [1:0] ifg_state;

    // Control signals for the interframe gap state.
    reg ifg_reset, ifg_add_double, ifg_add_single;

    always @(posedge axis.clk) begin
        if (axis.rst) begin
            // On reset it's fine to assume a full IFG was maintained.
            ifg_state <= 2;
        end else if (ifg_reset) begin
            ifg_state <= 0;
        end else if (ifg_add_double) begin
            ifg_state <= 2;
        end else if (ifg_add_single) begin
            if (ifg_state < 2) begin
                ifg_state <= ifg_state + 1;
            end
        end
    end

    // ---------- Shifted transmit state ----------

    reg        prev_tvalid;
    reg [63:0] prev_valid_tdata;
    reg [ 7:0] prev_valid_tkeep;
    reg        prev_valid_tlast;

    always @(posedge axis.clk) begin
        if (axis.rst) begin
            prev_tvalid <= 0;
            prev_valid_tdata <= 0;
            prev_valid_tkeep <= 0;
            prev_valid_tlast <= 0;
        end else if (axis.tvalid) begin
            prev_tvalid <= 1;
            prev_valid_tdata <= axis.tdata[127:64];
            prev_valid_tkeep <= axis.tkeep[15:8];
            prev_valid_tlast <= axis.tlast;
        end else begin
            prev_tvalid <= 0;
        end
    end

    // Whether the current transmission is shifted, meaning that the packet's
    // transmission started on the ninth octet within the 128-bit bus word. As a
    // consequence of the shifted transmission, given that we receive 128 valid
    // bits from the sink, we need to store and delay the upper half of the
    // current clock cycle's data to the next.
    //
    // This register is to be set when transitioning out of the IDLE state.
    reg transmit_shifted, transmit_shifted_next;

    // Adjusted sink tdata & tkeep. If our transmission is shifted, this will
    // contain the upper-half of the previous and lower-half of the current
    // clock cycle. Otherwise, simply equal to tdata and tkeep.
    reg adjusted_tvalid, adjusted_tlast;
    reg [127:0] adjusted_tdata;
    reg [15:0] adjusted_tkeep;
    reg fsm_mask_ready;

    always @(*) begin
        // Defaults:
        error_tlast_tkeep = 0;

        // We enforce a non-zero tkeep be asserted along tlast.
        if (axis.tlast && (axis.tkeep == 0)) begin
            error_tlast_tkeep = 1;
        end

        if (transmit_shifted) begin
            // Because we are injecting data from the previous cycle, we need to
            // respect it's valid. It's fine that adjusted_tvalid therefore is
            // deasserted for the very first bus word, given this is handled in
            // the IDLE fsm state still. This assumes a non-hostile sink where
            // valid is constantly asserted during a single transmission.

            adjusted_tvalid = prev_tvalid;
            adjusted_tdata  = {axis.tdata[63:0], prev_valid_tdata};

            // Don't expose the upper tkeep (which might be asserted) when the
            // lower isn't fully asserted (end of transaction) or when last was
            // asserted.
            if ((prev_valid_tkeep != 8'hFF) || prev_valid_tlast) begin
                adjusted_tkeep = {8'h00, prev_valid_tkeep};
            end else begin
                adjusted_tkeep = {axis.tkeep[7:0], prev_valid_tkeep};
            end

            // The adjusted sink should only be last when we have a
            // prev_valid_tkeep != 0xFF (meaning that at least some bytes aren't valid there)
            // or the current axis.tkeep should be ignored now (because a last came previously and hasn't been fully transmitted)
            // or the axis.tkeep[7:0] isn't 0xFF (not all bytes of the upper half are valid)
            // or axis.tkeep[8] is 0 (the first byte exposed in the next cycle is not valid).
            if ((prev_valid_tkeep != 8'hFF)
                || fsm_mask_ready
                || (axis.tkeep[7:0] != 8'hFF)
                || (axis.tkeep[8] == 0)) begin
                adjusted_tlast = 1;
            end else begin
                adjusted_tlast = 0;
            end
        end else begin
            adjusted_tvalid = axis.tvalid;
            adjusted_tdata  = axis.tdata;
            adjusted_tkeep  = axis.tkeep;
            adjusted_tlast  = axis.tlast;
        end
    end

    // ---------- XGMII Transmission FSM ----------

    localparam FSM_IDLE = 1'b0, FSM_TRANSMIT = 1'b1;
    reg fsm_state_reg, fsm_state_next;

    reg fsm_end_transmission, fsm_end_transmission_next;
    reg fsm_mask_ready_next;

    // Initial values for simulation
    reg [127:0] xgmii_data_next = {16{XGMII_IDLE}};
    reg [15:0] xgmii_ctrl_next = 16'hFFFF;


    always @(posedge axis.clk) begin
        if (axis.rst) begin
            fsm_state_reg <= FSM_IDLE;
            fsm_end_transmission <= 0;
            fsm_mask_ready <= 0;

            transmit_shifted <= 0;

            xgmii_data <= {16{XGMII_IDLE}};
            xgmii_ctrl <= 16'hFFFF;
        end else begin
            fsm_state_reg <= fsm_state_next;
            fsm_end_transmission <= fsm_end_transmission_next;
            fsm_mask_ready <= fsm_mask_ready_next;

            transmit_shifted <= transmit_shifted_next;

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
        fsm_mask_ready_next = 0;
        // Transmit shifted indicator (used to provide the adjusted data & ctrl
        // signals)
        transmit_shifted_next = transmit_shifted;
        // Combinational AXI4-Stream sink ready feedback
        axis.tready = 0;
        // XGMII output is produced in every branch below, use X to aid in
        // simulation. Should never propagate to output:
        xgmii_ctrl_next = {16{1'bx}};
        xgmii_data_next = {128{1'bx}};

        case (fsm_state_reg)
            FSM_IDLE: begin
                if (axis.tvalid && (ifg_state == 2)) begin
                    // Branch A: we've transmitted at least the full 12 bytes of
                    // IFG. This means that we can unconditionally start
                    // transmission on the first half.

                    // Reset the IFG counter.
                    ifg_reset = 1;

                    // Transmit the preamble and the first half.
                    xgmii_ctrl_next = 16'h0001;
                    xgmii_data_next = {axis.tdata[63:0], ETH_PREAMBLE[63:8], XGMII_START};

                    // Latch data
                    axis.tready = 1;

                    // Indicate that we are in the shifted transmit state.
                    transmit_shifted_next = 1;

                    // Go to FSM_TRANSMIT state.
                    fsm_state_next = FSM_TRANSMIT;
                end else if (axis.tvalid && (ifg_state == 1)) begin
                    // Branch B.2: we can't transmit on the first half as
                    // there haven't been sufficient IDLEs yet, but on the
                    // ninth.

                    // Perform a unshifted transmit.
                    xgmii_ctrl_next = 16'h01FF;
                    xgmii_data_next = {ETH_PREAMBLE[63:8], XGMII_START, {8{XGMII_IDLE}}};

                    // Indicate that we are in the unshifted transmit state.
                    transmit_shifted_next = 0;

                    // Reset the IFG counter.
                    ifg_reset = 1;

                    // Go to FSM_TRANSMIT state.
                    fsm_state_next = FSM_TRANSMIT;
                end else begin
                    // Branch D: either we don't have any data to transmit or
                    // insufficient IFG. Thus transmit IDLE.
                    xgmii_ctrl_next = 16'hFFFF;
                    xgmii_data_next = {16{XGMII_IDLE}};

                    // Track IFG insertion
                    ifg_add_double  = 1;
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
                    xgmii_ctrl_next = 16'hFFFF;
                    xgmii_data_next = {{15{XGMII_IDLE}}, XGMII_END};

                    // Also, we're transmitting 16 bytes worth of IDLE characters
                    // (the END does count towards IDLE).
                    ifg_add_double = 1;

                    // We've ended the transmission, if requested
                    fsm_end_transmission_next = 0;

                    // Return to IDLE
                    fsm_state_next = FSM_IDLE;
                end else begin
                    // Accept the provided data. adjusted_tvalid is checked in
                    // the branch above.
                    axis.tready = !fsm_mask_ready;

                    // Set the XGMII bus word based on the adjusted tkeep
                    for (i = 0; i < 16; i = i + 1) begin
                        if (adjusted_tkeep[i]) begin
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
                            if (i < 5) begin
                                ifg_add_double = 1;
                            end else if (i < 13) begin
                                ifg_add_single = 1;
                            end
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
                    if (adjusted_tlast && adjusted_tkeep[15]) begin
                        // Remain in this state and transmit the END control
                        // character before returning to IDLE and accepting new
                        // data.
                        fsm_end_transmission_next = 1;
                    end else if (adjusted_tlast) begin
                        // Already transmitted the END control character, return
                        // to IDLE state.
                        fsm_end_transmission_next = 0;
                        fsm_state_next = FSM_IDLE;
                    end else if (axis.tlast) begin
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

`resetall
