# Wishbone interface directly by the Opal Kelly interface

# This file is part of the Time Tagger software defined digital data
# acquisition FPGA-link reference design.
#
# Copyright (C) 2022 Swabian Instruments, All Rights Reserved
#
# Authors:
# - 2023-2024 Markus Wick <markus@swabianinstruments.com>
# - 2023-2024 Ehsan Jokar <ehsan@swabianinstruments.com>
#
# This file is provided under the terms and conditions of the BSD 3-Clause
# license, accessible under https://opensource.org/licenses/BSD-3-Clause.
#
# SPDX-License-Identifier: BSD-3-Clause

import ok
import struct
import math


class Wishbone:
    xem: ok.okCFrontPanel
    seq: int = 0
    ADDR_WBBRIDGE_IN: int = 0x83
    ADDR_WBBRIDGE_OUT: int = 0xA4
    # We should support 2048 words, but with prog_full
    MAX_FIFO_SIZE = (2 * 1024 - 300) * 4
    MAX_BURST_SIZE = 8191

    def __init__(self, xem: ok.okCFrontPanel):
        self.xem = xem
        self.cmd_queue = []
        self.cmd_buffer = bytearray()
        self.cmd_queue_output_size = 0

    def flush_queue(self):
        if len(self.cmd_queue) == 0:
            return

        assert min(len(self.cmd_buffer),
                   self.cmd_queue_output_size) <= self.MAX_FIFO_SIZE

        self.xem.WriteToBlockPipeIn(self.ADDR_WBBRIDGE_IN, 16, self.cmd_buffer)

        res_sum = bytearray(self.cmd_queue_output_size)
        self.xem.ReadFromBlockPipeOut(self.ADDR_WBBRIDGE_OUT, 16, res_sum)

        res_offset = 0
        first_exception = None
        for read_size, h in self.cmd_queue:
            try:
                h(res_sum[res_offset: res_offset + read_size])
            except Exception as e:
                if not first_exception:
                    first_exception = e
            res_offset += read_size

        self.cmd_buffer.clear()
        self.cmd_queue = []
        self.cmd_queue_output_size = 0

        if first_exception:
            raise first_exception

    def queue(self, cmd, read_size, handler):
        if min(len(self.cmd_buffer) + len(cmd), self.cmd_queue_output_size + read_size) > self.MAX_FIFO_SIZE:
            self.flush_queue()

        self.cmd_buffer += cmd
        self.cmd_queue.append([read_size, handler])

        self.cmd_queue_output_size += read_size

    def read(self, addr, in_transaction=False, future=False):
        header, cmd = self._encode(
            cmd=0, block_position=in_transaction, addr=addr)

        data = None

        def handle(res):
            nonlocal data
            header2, data, addr2, time_out = struct.unpack('<IIII', res)

            assert header == header2
            assert time_out == 0, f"timeout on reading from addr {addr2}"
            assert addr == addr2

        self.queue(cmd, 16, handle)

        def fetch():
            self.flush_queue()
            return data
        return fetch if future else fetch()

    def write(self, addr, data, in_transaction=False):
        header, cmd = self._encode(
            cmd=1, block_position=in_transaction, addr=addr, data=data)

        def handle(res):
            header2, _, addr2, time_out = struct.unpack('<IIII', res)

            assert header == header2
            assert time_out == 0, f"timeout on writing to addr {addr2}"
            assert addr == addr2

        self.queue(cmd, 16, handle)
        self.flush_queue()

    def modify(self, addr, data, mask, in_transaction=False, future=False):
        header, cmd = self._encode(
            cmd=2, block_position=in_transaction, addr=addr, mask=mask, data=data)

        old_data = None

        def handle(res):
            nonlocal old_data
            header2, old_data, addr2, time_out = struct.unpack('<IIII', res)

            assert header == header2
            assert time_out == 0, f"timeout on modify addr {addr2}"
            assert addr == addr2

        self.queue(cmd, 16, handle)

        def fetch():
            self.flush_queue()
            return old_data
        return fetch if future else fetch()

    def burst_read(self, addr, size, addr_incr=1, in_transaction=False, future=False):
        if size == 0:
            return []
        if size == 1:
            return [self.read(addr, in_transaction=in_transaction)]

        header, cmd = self._encode(
            cmd=0, size=size, block_position=in_transaction, addr_incr=addr_incr, addr=addr)
        words = (size + 3) + -(size + 3) % 4

        data = None

        def handle(res):
            nonlocal data
            res = struct.unpack('<' + 'I' * words, res)
            header2 = res[0]
            data = res[1:size + 1]
            addr2 = res[-2]
            time_out = res[-1]

            assert header == header2
            assert time_out == 0, f"timeout on burst read from addr {addr2}"
            assert addr + (size - 1) * addr_incr == addr2

        self.queue(cmd, words * 4, handle)

        def fetch():
            self.flush_queue()
            return data
        return fetch if future else fetch()

    def burst_write(self, addr, data, addr_incr=1, in_transaction=False):
        size = len(data)

        if size == 0:
            return
        if size == 1:
            return self.write(addr, data[0], in_transaction=in_transaction)

        header, cmd = self._encode(
            cmd=1, size=size, block_position=in_transaction, addr_incr=addr_incr, addr=addr, data=data)

        def handle(res):
            header2, _, addr2, time_out = struct.unpack('<IIII', res)

            assert header == header2
            assert time_out == 0, f"timeout on burst writing to addr {addr2}"
            assert addr + (size - 1) * addr_incr == addr2

        self.queue(cmd, 16, handle)

    def _encode(self, cmd=0, size=1, block_position=0, addr_incr=0, addr=0, mask=0xdeadbeef, data=0):
        assert 0 <= cmd < 4, "cmd is 2 bit"
        assert 0 <= size < 8192, "size is 13 bit"
        assert 0 <= block_position < 2, "size is 1 bit"
        assert 0 <= addr_incr < 256, "size is 8 bit"
        header = (cmd << 0) | (size << 2) | ((self.seq & 0xff) <<
                                             15) | (block_position << 23) | (addr_incr << 24)
        self.seq += 1

        total_words = (size + 3) + -(size + 3) % 4
        # 3 stands for command, address, and the header dummy data used ro be compatible with single write
        footer_dummy_size = total_words - size - 3
        total_data = []
        total_data.append(header)
        total_data.append(addr)
        total_data.append(mask)

        if (cmd == 0 or size == 1):
            total_data.append(data)
            format_string = f'<{4}I'
        else:
            format_string = f'<{total_words}I'
            for i in range(size):
                total_data.append(data[i])

        if (cmd == 1 and size > 1):
            for i in range(footer_dummy_size):
                total_data.append(mask)

        return header, bytearray(struct.pack(format_string, *total_data))
