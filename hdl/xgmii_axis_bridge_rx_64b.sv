/**
 * XGMII to AXI4-Stream Bridge (64-bit receive side).
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

`timescale 1ns / 1ps
`default_nettype none

module xgmii_axis_bridge_rx_64b (
    input wire        clk,
    input wire        rst,

    input wire [63:0] xgmii_data,
    input wire [7:0]  xgmii_ctrl,

    input wire        axis_tready,
    output reg        axis_tvalid,
    output reg [63:0] axis_tdata,
    output reg        axis_tlast,
    output reg [7:0]  axis_tkeep,

    output reg        error_ready,
    output reg        error_preamble,
    output reg        error_xgmii
);

    // --------- XGMII & Ethernet constants ----------
    localparam [7:0]  XGMII_IDLE = 8'h07,
                      XGMII_START = 8'hFB,
                      XGMII_END = 8'hFD;
    localparam [63:0] ETH_PREAMBLE = 64'hD555555555555555;


    // ---------- XGMII delayed signals ----------
    reg [63:0]        xgmii_data_p;
    reg [7:0]         xgmii_ctrl_p;

    // 2D array representation of the data to access individual bytes
    wire [7:0][7:0]    xgmii_data_a_p;
    assign xgmii_data_a_p = xgmii_data_p;

    // We need to work on a delayed version of the XGMII signals. This is
    // because we must perform a lookahead onto the next 64-bit XGMII bus word
    // to see whether it follows with an immediate XGMII end of frame. This is
    // used to end the transmission the current cycle (never have tlast && tkeep
    // == 0).
    //
    // Technically AXI4-Stream allows tlast && tkeep == 0. Furthermore, for
    // 10Gbit/s Ethernet, the receiver is guaranteed to observe an IFG of at
    // least 5 bytes. Because of lane alignment, this means that we always have
    // a guaranteed minimum 8 bytes of IDLE between frames. This would
    // technically allow us to insert an empty last bus transaction and avoid
    // this lookahead. However, for >10Gbit/s Ethernet, this invariant no longer
    // holds. To make this code more reusable, and later stages simpler, prevent
    // empty last bus transactions, so the last bus transaction is guaranteed to
    // always carry some valid data.
    always @(posedge clk) begin
        xgmii_ctrl_p <= xgmii_ctrl;
        xgmii_data_p <= xgmii_data;
    end

    // ---------- AXI4-Stream TKEEP encoder ----------

    // For the last received 64-bit XGMII bus word, we need to determine where a
    // packet ends and encode it for the AXI4-Stream interface accordingly. We
    // can do this for every XGMII bus word, as only the last may have an XGMII
    // END control character.
    //
    // To reliably find the first XGMII_END character and produce a corresponding
    // tkeep (mask of all valid data), we scan over the XGMII bus word from left to
    // right. As soon as the first XGMII_END is found, all subsequent tkeep bits
    // must be zero. Hence this signal is defined as self-referencing and cannot be
    // flattened.
    //
    // Use the fact that we need to pipeline anyways and work on the non-delayed
    // signal and pipeline the output. This eases timing.

    /* verilator lint_off UNOPTFLAT */
    wire [7:0] tkeep_enc;
    /* verilator lint_on UNOPTFLAT */
    reg [7:0]   tkeep_enc_p;

    // Scan over the XGMII word
    genvar      i;
    generate
        for (i = 0; i < 8; i = i + 1) begin
            assign tkeep_enc[i] =
                (i > 0 ? tkeep_enc[i-1] : 1'b1)
                & ((xgmii_ctrl[i] == 1'b0)
                   | (xgmii_data[i*8+:8] != XGMII_END));
        end
    endgenerate

    // Provide a pipelined version of the signal
    always @(posedge clk) begin
        tkeep_enc_p <= tkeep_enc;
    end

    // ---------- Receive finite state machine ----------
    localparam [1:0] FSM_IDLE = 2'b00;

    // When we receive a shifted frame start, we will only see the lower half of
    // the preamble in the upper half of the XGMII data signal. Thus the next
    // cycle must not output the upper half of the preamble in the lower half of
    // its XGMII data. Hence, when transitioning from XGMII IDLE to SHIFTED,
    // this state will be active for one cycle, indicating that fsm_shifted_data
    // does contain the first part of the preamble.
    localparam [1:0] FSM_SHIFTED_PREAMBLE = 2'b01;

    // Shifted and unshifted reception states, respectively. These will be
    // entered depending on whether the XGMII_START word is present on the first
    // or firth XGMII 64-bit word lane.
    localparam [1:0] FSM_UNSHIFTED = 2'b10;
    localparam [1:0] FSM_SHIFTED = 2'b11;

    reg [1:0]        fsm_state;

    // Shifted receive means that a 64-bit data word is constitutes from the
    // upper half of the previous and lower half of the current clock
    // cycle. Thus, buffer the upper half of the previous cycle:
    /* verilator lint_off UNUSED */
    reg [3:0]        fsm_shifted_ctrl_p; // lowest bit not used
    /* verilator lint_on UNUSED */
    reg [31:0]       fsm_shifted_data_p;

    // Furthermore, shifted still requires access to the encoded tkeep of the
    // previous cycle.
    reg [3:0]        fsm_shifted_tkeep_enc_p;

    // Shifted data
    always @(posedge clk) begin
        if (rst) begin
            fsm_shifted_ctrl_p <= 4'hF;
            fsm_shifted_data_p <= {4{XGMII_IDLE}};
            fsm_shifted_tkeep_enc_p <= 0;
        end else begin
            fsm_shifted_ctrl_p <= xgmii_ctrl_p[7:4];
            fsm_shifted_data_p <= xgmii_data_a_p[7:4];
            fsm_shifted_tkeep_enc_p <= tkeep_enc_p[7:4];
        end
    end

    // The FSM may return to IDLE even before it has consumed the XGMII end of
    // frame control character, because of the lookahead. Thus the IDLE state
    // must be tolerant of it if this happens. If this signal is set, the first
    // bit/byte of xgmii_{ctrl,data}_p must indicate an XGMII_END control
    // character!
    reg             fsm_idle_tolerate_end;

    // Receive state machine
    always @(posedge clk) begin
        // Output default values
        error_ready <= 0;
        error_preamble <= 0;
        error_xgmii <= 0;

        axis_tvalid <= 0;
        axis_tdata <= {64{1'bx}};
        axis_tlast <= 1'bx;
        axis_tkeep <= {8{1'bx}};

        if (rst) begin
            fsm_state <= FSM_IDLE;
            fsm_idle_tolerate_end <= 0;
        end else begin

            // tolerate_end and shifted_preamble are only relevant for the next
            // cycle, thus deassert it by default:
            fsm_idle_tolerate_end <= 0;

            case (fsm_state)
              FSM_IDLE: begin
                  // No packet reception ongoing, check for XGMII start control
                  // characters on lanes 0 and 4! Otherwise, validate
                  if ((xgmii_ctrl_p[0] == 1)
                      && (xgmii_data_a_p[0] == XGMII_START)) begin
                      // A new frame starts at the beginning of this XGMII
                      // 64-bit bus word. The first IDLE character has been
                      // replaced with the XGMII start of frame control
                      // character, ensure the rest constitutes the Ethernet
                      // frame:
                      if ((xgmii_ctrl_p[7:1] == {7{1'b0}})
                          && (xgmii_data_a_p[7:1] == ETH_PREAMBLE[63:8])) begin
                          // Okay, the preamble looks good! Switch to the
                          // unshifted RX state. We don't need to output
                          // anything yet.
                          fsm_state <= FSM_UNSHIFTED;
                      end else begin
                          // We did receive a well-aligned start of frame
                          // control character, but the preamble is
                          // broken. Report this error condition, remain in
                          // IDLE. If indeed an Ethernet frame arrives, this
                          // will cause XGMII errors to be generated in the
                          // subsequent cycles, which we have to accept.
                          error_preamble <= 1;
                      end
                  end else if ((xgmii_ctrl_p[4] == 1)
                               && (xgmii_data_a_p[4] == XGMII_START)) begin
                      // A new frame starts at the second 32-bit word of this
                      // XGMII 64-bit bus word. The preamble will continue in
                      // the first half of the next bus word.

                      // Validate that the first half of this bus word contains
                      // only XGMII IDLE characters. 10Gbit/s Ethernet mandates
                      // an IFG at the receiver of at least 5 bytes, meaning it
                      // must be impossible for a partial packet reception to be
                      // contained in the first half of the current 64-bit bus
                      // word:
                      if (!((xgmii_ctrl_p[3:0] == {4{1'b1}})
                            && (xgmii_data_a_p[3:0] == {4{XGMII_IDLE}}))) begin
                          // There is an XGMII bus error. Still we can accept
                          // the currently starting packet, as long as its
                          // preamble is valid. Given that the packet will only
                          // produce data in the next cycle, report the error in
                          // this cycle.
                          error_xgmii <= 1;
                      end

                      // Go to the SHIFTED_PREAMBLE reception state, which will
                      // process the remaining 4 bytes of the preamble:
                      fsm_state <= FSM_SHIFTED_PREAMBLE;
                  end else begin
                      // We don't have an XGMII start-of-frame control character
                      // on lane 0 and 4, so the bus word must be entirely XGMII
                      // IDLEs. However, we must tolerate an END character on
                      // the first octet sometimes.
                      if ((xgmii_ctrl_p != {8{1'b1}})
                          || (xgmii_data_a_p[7:1] != {7{XGMII_IDLE}})) begin
                          error_xgmii <= 1;
                      end else if (fsm_idle_tolerate_end
                                   && (xgmii_data_a_p[0] != XGMII_END)) begin
                          error_xgmii <= 1;
                      end else if (xgmii_data_a_p[0] != XGMII_IDLE) begin
                          error_xgmii <= 1;
                      end
                  end
              end

              FSM_SHIFTED_PREAMBLE: begin
                  if (({xgmii_ctrl_p[3:0], fsm_shifted_ctrl_p[3:1]} == 7'b0)
                      && ({xgmii_data_a_p[3:0], fsm_shifted_data_p[31:8]}
                          == ETH_PREAMBLE[63:8])) begin
                      // Okay, the preamble looks good! Don't output anything
                      // yet, transition further into the FSM_SHIFTED state:
                      fsm_state <= FSM_SHIFTED;
                  end else begin
                      // Preamble is erroneous, go back to IDLE
                      fsm_state <= FSM_IDLE;
                  end
              end

              FSM_UNSHIFTED: begin
                  // We have consumed the preamble, it was valid, and we are now
                  // in the progress of receiving unshifted data. First, check
                  // whether we have any data at all. While a 0-byte Ethernet
                  // frame is illegal, we handle it gracefully:
                  if (tkeep_enc_p == 8'h0) begin
                      // Okay, we observed an XGMII end of frame control
                      // character at the first octet and thus have no
                      // data. Return to IDLE.
                      //
                      // This is guaranteed to not abort any in-progress AXI
                      // transfer, as we also look for this case when valid data
                      // is placed on the bus.
                      fsm_state <= FSM_IDLE;

                      // We should raise a preamble error. An empty frame
                      // doesn't have a preamble, which technically counts as a
                      // broken preamble.
                      error_preamble <= 1;
                  end else begin
                      // Okay, good we have some data. Place it on the
                      // AXI4-Stream bus:
                      axis_tvalid <= 1;
                      axis_tdata <= xgmii_data_p;

                      // Make sure that ready is asserted. We can't handle the
                      // slave not being ready, so raise an error if it is not:
                      if (axis_tready != 1'b1) begin
                          error_ready <= 1;
                      end

                      // Check whether this is the last cycle based on the
                      // encoded tkeep, as well as the lookahead. This also
                      // determines state transitions back to IDLE.
                      if (tkeep_enc_p != 8'hFF) begin
                          axis_tlast <= 1;
                          axis_tkeep <= tkeep_enc_p;
                          fsm_state <= FSM_IDLE;
                      end else if (xgmii_ctrl[0]
                                   && (xgmii_data[7:0] == XGMII_END)) begin
                          // Lookahead tells us that the next XGMII bus word
                          // starts with an END control character. Tolerate that
                          // in IDLE:
                          fsm_idle_tolerate_end <= 1;

                          axis_tlast <= 1;
                          axis_tkeep <= 8'hFF;
                          fsm_state <= FSM_IDLE;
                      end else begin
                          axis_tlast <= 0;
                          axis_tkeep <= 8'hFF;
                      end

                      // The tkeep logic also provides a mask for control
                      // characters. If a control character is found in the
                      // middle of the packet and not masked by this mask, it
                      // means that the packet must've experienced an error:
                      if ((xgmii_ctrl_p & tkeep_enc_p) != 8'h0) begin
                          error_xgmii <= 1;
                          axis_tlast <= 1;
                          fsm_state <= FSM_IDLE;
                      end

                      // For >10Gbit/s we would have to check whether a new
                      // transition starts on lane 4 (shifted) here, validate
                      // the preamble, go to FSM_SHIFTED_PREAMBLE and set
                      // fsm_shifted_data_p = xgmii_data_a_p[7:4]. For 10Gbit/s
                      // Ethernet this is not necessary.
                  end
              end

              FSM_SHIFTED: begin
                  // We have some data. Place it on the AXI4-Stream bus:
                  axis_tvalid <= 1;
                  axis_tdata <= {xgmii_data_a_p[3:0], fsm_shifted_data_p};

                  // Make sure that ready is asserted. We can't handle the slave
                  // not being ready, so raise an error if it is not:
                  if (axis_tready != 1'b1) begin
                      error_ready <= 1;
                  end

                  // We need to check whether the packet ends here. This is a
                  // little complex, because our tkeep encoding is based on the
                  // unshifted XGMII 64-bit bus words. This means that the
                  // `tkeep_enc_p` is based on the XGMII bus word one after the
                  // one `fsm_shifted_tkeep_enc_p` is based on. Hence, if
                  // `fsm_shifted_tkeep_enc_p` encodes a frame end,
                  // `tkeep_enc_p` can be 4'hF again, so simply concatenating
                  // these signals does not work. First, check whether the
                  // previous upper half of tkeep_enc_p contains some marker
                  // (unequal 4'hF). If that is the case, then the lower half of
                  // our produced data contains the end.
                  if (fsm_shifted_tkeep_enc_p != 4'hF) begin
                      axis_tlast <= 1;
                      axis_tkeep <= {4'h0, fsm_shifted_tkeep_enc_p};
                      fsm_state <= FSM_IDLE;
                  end
                  // Then, we need to check whether the end of frame is
                  // somewhere in the upper part of our current produced data.
                  else if (tkeep_enc_p[3:0] != 4'hF) begin
                      axis_tlast <= 1;
                      axis_tkeep <= {tkeep_enc_p[3:0], 4'hF};
                      fsm_state <= FSM_IDLE;
                  end
                  // Finally, we need to check whether the first octect of the
                  // upper half of the current bus word constitutes the end of
                  // frame. This would mean that XGMII_END would be the first
                  // byte of the next shifted bus word we process, and thus the
                  // next shifted bus word wouldn't hold any valid data.
                  else if (xgmii_ctrl_p[4]
                           && (xgmii_data_a_p[4] == XGMII_END)) begin
                      axis_tlast <= 1;
                      axis_tkeep <= 8'hFF;
                      fsm_state <= FSM_IDLE;

                      // fsm_idle_tolerate_end does not have to be set here,
                      // given we're working on a 1/2 cycle delayed version of
                      // the signals and IDLE won't consider the upper (for us
                      // future) half of the current XGMII bus word any more.
                  end else begin
                      // If none of the above, enitre word is valid data.
                      axis_tlast <= 0;
                      axis_tkeep <= 8'hFF;
                  end

                  // The tkeep logic also provides a mask for control
                  // characters. If a control character is found in the middle
                  // of the packet and not masked by this mask, it means that
                  // the packet must've experienced an error:
                  if ((fsm_shifted_ctrl_p & fsm_shifted_tkeep_enc_p) != 4'h0
                      || (fsm_shifted_tkeep_enc_p == 4'hF
                          && (xgmii_ctrl_p[3:0] & tkeep_enc_p[3:0]) != 4'h0)) begin
                      error_xgmii <= 1;
                      axis_tlast <= 1;
                      fsm_state <= FSM_IDLE;
                  end
              end
            endcase
        end
    end

endmodule

`resetall
