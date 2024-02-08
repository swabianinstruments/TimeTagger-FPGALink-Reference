#!/usr/bin/env python3

# Header Parser Tests
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

import logging
import random
from pathlib import Path
import pytest
import binascii

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

import misc

@cocotb.test()
async def header_parser_testbench(dut, packets=[]):
    rng = random.Random(42)

    # Generate accurate header
    def gen_packet(data, sequence, wrap_count):
        header = (
            b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"  # MAC
            + b"\x80\x9B"  # ETHTYPE
            + b"SITT"  # MAGIC
            + b"\x00"  # Version
            + b"\x00\x00\x00\x00"  # Reserved
            + b"\x00"  # Type
        )
        header += sequence.to_bytes(4, byteorder="little")
        header += wrap_count.to_bytes(4, byteorder="little")
        return header + data

    # send sucessive packets
    packets = [gen_packet(b"\x00" * 20, i, 0) for i in range(100)]

    # Start the clock
    cocotb.start_soon(Clock(dut.clk, 2, units="ns").start())

    # Set some non high-impedance values on the AXI source bus
    dut.s_axis_tvalid.value = 0
    dut.s_axis_tdata.value = 0
    dut.s_axis_tkeep.value = 0
    dut.s_axis_tlast.value = 0

    # And deassert ready on the AXI master bus
    dut.m_axis_tready.value = 0

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

    def random_pause_generator():
        while True:
            yield rng.randrange(2) == 1

    axis_source.set_pause_generator(random_pause_generator())
    axis_sink.set_pause_generator(random_pause_generator())
    for p in packets:
        await axis_source.send(p)
        await axis_source.wait()
    # assert dut.lost_packet == 0
    for p in packets:
        await axis_source.send(p)
        await axis_source.wait()
    # assert dut.lost_packet == 1

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

    for p in packets:
        await axis_source.send(p)
        await axis_source.wait()
    # assert dut.lost_packet == 0

    for _ in range(1024):
        await RisingEdge(dut.clk)


def test_header_parser():
    tests_dir = Path(__file__).parent
    top_dir = tests_dir.parent
    hdl_dir = top_dir / "hdl"

    misc.cocotb_test(
        dut="si_header_parser",
        test_module=Path(__file__).stem,
        verilog_sources=[
            hdl_dir / "header_parser.sv",
        ],
    )
