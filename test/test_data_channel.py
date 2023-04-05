#!/usr/bin/env python3

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
async def data_channel_testbench(dut, packets=[]):
    rng = random.Random(42)

    # Generate accurate header
    def gen_packet(tags, sequence, wrap_count):
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
        data = header
        for tag in tags:
            data += tag.to_bytes(4, byteorder="little")
        return data

    def gen_tag(counter, subtime, channel):
        event_type = 0b01
        tag = (counter & 0xFFF) | ((subtime & 0xFFF) << 12) | ((channel & 0x3F) << 24) | (event_type << 30)
        return tag

    packet_contents = [
        {
            "wrap_count": rng.getrandbits(32),
            "tags": [gen_tag(rng.getrandbits(12), rng.getrandbits(12), rng.getrandbits(6)) for i in range((rng.randrange(20) + 1) * 4)], # Ensure only 128 bit words are sent
        } for i in range(20)
    ]
    # send sucessive packets
    packets = [gen_packet(contents["tags"], sequence, contents["wrap_count"]) for (sequence, contents) in enumerate(packet_contents)]

    async def custom_clock():
        # pre-construct triggers for performance
        delay = Timer(2, units="ns")
        await delay
        while True:
            dut.eth_clk.value = 1
            dut.usr_clk.value = 1
            await delay
            dut.eth_clk.value = 0
            dut.usr_clk.value = 0
            await delay
    # Start the clock
    cocotb.start_soon(custom_clock())

    # Set some non high-impedance values on the AXI source bus
    dut.s_axis_tvalid.value = 0
    dut.s_axis_tdata.value = 0
    dut.s_axis_tkeep.value = 0
    dut.s_axis_tlast.value = 0

    # And deassert ready on the AXI master bus
    dut.m_axis_tready.value = 0

    # Reset the simulation, propagating these idle signals
    dut.eth_rst.setimmediatevalue(0)
    dut.usr_rst.setimmediatevalue(0)
    await RisingEdge(dut.eth_clk)
    await RisingEdge(dut.eth_clk)
    dut.eth_rst.value = 1
    dut.usr_rst.value = 1
    await RisingEdge(dut.eth_clk)
    await RisingEdge(dut.eth_clk)
    dut.eth_rst.value = 0
    dut.usr_rst.value = 0
    await RisingEdge(dut.eth_clk)
    await RisingEdge(dut.eth_clk)

    # Instantiate a collector for the resulting AXI bus
    axis_sink = AxiStreamSink(AxiStreamBus.from_prefix(dut, "m_axis"), dut.usr_clk, dut.usr_rst)
    axis_sink.log.setLevel(logging.INFO)

    # Instantiate an AxiStreamSource for the TX AXI bus
    axis_source = AxiStreamSource(
        AxiStreamBus.from_prefix(dut, "s_axis"), dut.eth_clk, dut.eth_rst
    )
    axis_source.log.setLevel(logging.INFO)

    def random_pause_generator():
        while True:
            yield rng.randrange(2) == 1

    axis_source.set_pause_generator(random_pause_generator())
    axis_sink.set_pause_generator(random_pause_generator())

    sent_packets = [(await axis_source.send(p)) for p in packets]

    recv_packets = []

    for _ in range(len(packets)):
        # We must wait for a packet to be ready before we receive it
        while axis_sink.empty():
            await RisingEdge(dut.usr_clk)

        
        p = await axis_sink.recv()
        recv_packets += [p]

    for pc, rp in zip(packet_contents, recv_packets):
        assert len(pc["tags"]) * 4 == len(rp.tdata)

        tag_bytes =  []
        for tag in pc["tags"]:
            tag_bytes += tag.to_bytes(4, byteorder="little")

        for (tb, rb) in zip(tag_bytes, rp.tdata):
            assert tb == rb
        assert pc["wrap_count"] == rp.tuser
    

def test_data_channel():
    tests_dir = Path(__file__).parent
    top_dir = tests_dir.parent
    hdl_dir = top_dir / "hdl"
    axis_rtl_dir = top_dir / "3rdparty" / "verilog-ethernet" / "lib" / "axis" / "rtl"

    misc.cocotb_test(
        dut="si_data_channel",
        test_module=Path(__file__).stem,
        verilog_sources=[
            hdl_dir / "header_parser.sv",
            hdl_dir / "data_channel.sv",
            hdl_dir / "header_detacher.sv",
            axis_rtl_dir / "axis_async_fifo.v",
            axis_rtl_dir / "axis_adapter.v",
        ],
    )
