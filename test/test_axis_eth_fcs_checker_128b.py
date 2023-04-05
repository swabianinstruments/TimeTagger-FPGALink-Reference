# AXI4-Stream Ethernet FCS checker for 128-bit Words cocotb-Tests
#
# This file is part of the Time Tagger software defined digital data
# acquisition FPGA-link reference design.
#
# Copyright (C) 2022 Swabian Instruments, All Rights Reserved
#
# Authors:
# - 2022 David Sawatzke <david@swabianinstruments.com>
#
# This file is provided under the terms and conditions of the BSD 3-Clause
# license, accessible under https://opensource.org/licenses/BSD-3-Clause.
#
# SPDX-License-Identifier: BSD-3-Clause

import shutil
import os
import csv
import logging
import random
import zlib
import pytest
import tempfile
from pathlib import Path
from asyncio import Event

import cocotb_test.simulator
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import Timer, RisingEdge
from cocotbext.axi import (
    AxiStreamBus,
    AxiStreamSource,
    AxiStreamSink,
    AxiStreamMonitor,
    AxiStreamFrame,
)
from cocotbext.eth import XgmiiSource, XgmiiFrame, XgmiiSink

import misc

# Hack to support randbytes method for Python < 3.9
if not hasattr(random.Random, "randbytes"):

    def randbytes_polyfill(self, n):
        """Generate n random bytes."""
        return self.getrandbits(n * 8).to_bytes(n, "little")

    random.Random.randbytes = randbytes_polyfill


@cocotb.test()
async def axis_fcs_checker_testbench(dut, packets=[]):
    rng = random.Random(42)

    # Generate some packets to transmit
    packets = []
    valid_packets = []

    for _ in range(10):
        # The packets need to have a length % 128 = 0
        packet = rng.randbytes(16 + 16 * rng.randrange(9))
        zlib_fcs = zlib.crc32(packet)

        if rng.randrange(2) == 1:
            # Corrupt crc
            zlib_fcs = (0xDEAD << 16) | (zlib_fcs ^ 1)
        else:
            # Valid packet
            valid_packets += [packet]

        packet += zlib_fcs.to_bytes(4, byteorder="little")
        packets += [packet]

    # Set some non high-impedance values on the AXI source bus
    dut.s_axis_tvalid.value = 0
    dut.s_axis_tdata.value = 0
    dut.s_axis_tkeep.value = 0
    dut.s_axis_tlast.value = 0

    # And deassert ready on the AXI master bus
    dut.m_axis_tready.value = 0

    # Start the clock
    cocotb.start_soon(Clock(dut.clk, 2, units="ns").start())

    # Reset the simulation, propagating these idle signals
    dut.rst.setimmediatevalue(0)
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    dut.rst.value = 1
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    dut.rst.value = 0
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)

    # Instantiate a collector for the resulting AXI bus
    axis_sink = AxiStreamSink(AxiStreamBus.from_prefix(dut, "m_axis"), dut.clk, dut.rst)
    axis_sink.log.setLevel(logging.INFO)

    # Instantiate an AxiStreamSource for the TX AXI bus
    axis_source = AxiStreamSource(
        AxiStreamBus.from_prefix(dut, "s_axis"), dut.clk, dut.rst
    )
    axis_source.log.setLevel(logging.INFO)

    # Randomly assert and deassert valid / ready on the source / sink
    # respectively
    def random_pause_generator():
        while True:
            yield rng.randrange(2) == 1

    axis_source.set_pause_generator(random_pause_generator())

    # Insert the packets
    sent_packets = [(await axis_source.send(p)) for p in packets]

    # Read back all packets
    recv_packets = []
    for _ in range(len(valid_packets)):
        # We must wait for a packet to be ready before we receive it
        while axis_sink.empty():
            await RisingEdge(dut.clk)

        p = await axis_sink.recv()
        recv_packets += [p]

    for vp, rp in zip(valid_packets, recv_packets):
        assert len(vp) == len(rp)
        for vb, rb in zip(vp, rp):
            assert vb == rb


def test_axis_fcs_checker_128b():
    tests_dir = Path(__file__).parent
    top_dir = tests_dir.parent
    hdl_dir = top_dir / "hdl"
    gen_srcs_dir = top_dir / "gen_srcs"
    axis_rtl_dir = top_dir / "3rdparty" / "verilog-ethernet" / "lib" / "axis" / "rtl"

    misc.cocotb_test(
        dut="eth_axis_fcs_checker_128b",
        test_module=Path(__file__).stem,
        verilog_sources=[
            hdl_dir / "eth_axis_fcs_checker_128b.sv",
            gen_srcs_dir / "eth_crc_128b_comb.v",
            axis_rtl_dir / "axis_fifo.v",
        ],
    )
