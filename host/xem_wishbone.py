# OpalKelly Module Block-Throttled Pipe Wishbone Bridge Interface
# 
# This file is part of the Time Tagger software defined digital data
# acquisition FPGA-link reference design.
#
# Copyright (C) 2022 Swabian Instruments, All Rights Reserved
#
# Authors:
# - 2022 Leon Schuermann <leon@swabianinstruments.com>
#
# This file is provided under the terms and conditions of the BSD 3-Clause
# license, accessible under https://opensource.org/licenses/BSD-3-Clause.
#
# SPDX-License-Identifier: BSD-3-Clause

from enum import IntEnum

# Taken from https://stackoverflow.com/a/312464, licensed under a
# CC-BY-SA 4.0 license:
# https://creativecommons.org/licenses/by-sa/4.0/
def chunks(lst, n):
    """Yield successive n-sized chunks from lst."""
    for i in range(0, len(lst), n):
        yield lst[i:i + n]

class WishboneRW(IntEnum):
    Read = 0
    Write = 1

class WishboneTransaction():
    def __init__(self, addr: int, read_write: WishboneRW, write_val=None):
        self.addr = addr
        self.read_write = read_write
        self.write_val = write_val
        self.read_val = None
        self.fulfilled = False
        assert self.read_write == WishboneRW.Read or self.write_val is not None

    def is_fulfilled(self):
        return self.fulfilled

    def get_read_val(self):
        return self.read_val

class XEMWishbone():
    def __init__(self, xem, block_cnt=4):
        self.xem = xem
        self.delay = 0.1
        self.block_cnt = block_cnt

    def read(self, addr):
        txn = WishboneTransaction(addr, WishboneRW.Read)
        self.bulk_process([txn])
        assert txn.is_fulfilled()
        return txn.read_val

    def write(self, addr, val):
        txn = WishboneTransaction(addr, WishboneRW.Write, write_val=val)
        self.bulk_process([txn])
        assert txn.is_fulfilled()

    def bulk_process(self, txns):
        data_in = bytearray(b"\0") * (16 * self.block_cnt)
        data_out = bytearray(b"\0") * (16 * self.block_cnt)

        for chunked_txns in chunks(txns, 2 * self.block_cnt):
            for i, t in enumerate(chunked_txns):
                data_in[(i*8)+4:(i*8)+8] = t.addr.to_bytes(4, byteorder="little")
                data_in[(i*8)+7] = data_in[(i*8)+7] & 0x7F
                if t.read_write == WishboneRW.Write:
                    data_in[(i*8)+0:(i*8)+4] = t.write_val.to_bytes(4, byteorder="little")
                    data_in[(i*8)+7] = data_in[(i*8)+7] | (1 << 7)
                elif t.read_write != WishboneRW.Read:
                    raise NotImplementedError()

            self.xem.WriteToBlockPipeIn(0x83, 64, data_in)
            self.xem.ReadFromBlockPipeOut(0xA4, 64, data_out)

            for i, t in enumerate(chunked_txns):
                if t.read_write == WishboneRW.Read:
                    t.read_val = int.from_bytes(data_out[(i*8)+0:(i*8)+3], byteorder="little")
                t.fulfilled = True

    def bulk_chunk_size(self):
        return 2 * self.block_cnt
