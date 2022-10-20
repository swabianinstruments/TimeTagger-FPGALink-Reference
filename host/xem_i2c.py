# OpalKelly Module Wishbone-I2C Core Interface Driver
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

from .xem_wishbone import WishboneTransaction, WishboneRW
from .i2c import I2CInterface, I2CRW

class WBI2CReg(IntEnum):
    PRER_LOW = 0
    PRER_HIGH = 1
    CTR = 2
    RXR = 3
    SR = 4
    TXR = 5
    CR = 6

class WishboneI2C(I2CInterface):
    def __init__(self, wb, i2c_base):
        self.wb = wb
        self.i2c_base = i2c_base
        self.queue_wb_writes_enabled = False
        self.queued_wb_writes = []

        # Setup appropriate I2C clocking
        self.__write_prer(0x00CA)
        self.__write_wb(WBI2CReg.CTR, 0x80)

    def __write_wb(self, addr, val):
        if self.queue_wb_writes_enabled:
            self.queued_wb_writes += [(self.i2c_base + addr, val)]
        else:
            self.wb.write(self.i2c_base + addr, val)

    def __read_wb(self, addr):
        if len(self.queued_wb_writes) > 0:
            txns = [
                WishboneTransaction(
                    waddr, WishboneRW.Write, write_val=val)
                for waddr, val in self.queued_wb_writes
            ]
            read_txn = WishboneTransaction(
                self.i2c_base + addr, WishboneRW.Read)
            txns += [read_txn]
            assert self.wb.bulk_chunk_size() >= len(txns)
            self.wb.bulk_process(txns)
            assert read_txn.is_fulfilled()
            self.queued_wb_writes = []
            return read_txn.read_val
        else:
            return self.wb.read(self.i2c_base + addr)

    def flush_writes(self):
        if len(self.queued_wb_writes) > 0:
            txns = [
                WishboneTransaction(
                    waddr, WishboneRW.Write, write_val=val)
                for waddr, val in self.queued_wb_writes
            ]
            assert self.wb.bulk_chunk_size() >= len(txns)
            self.wb.bulk_process(txns)
            assert txns[-1].is_fulfilled()
            self.queued_wb_writes = []

    def queue_wb_writes(self, queue_writes=True):
        if not queue_writes:
            self.flush_writes()
        self.queue_wb_writes_enabled = queue_writes

    def __read_prer(self):
        return (
            self.__read_wb(WBI2CReg.PRER_HIGH) << 8
            | self.__read_wb(WBI2CReg.PRER_LOW)
        )

    def __write_prer(self, val):
        self.__write_wb(WBI2CReg.PRER_LOW, val & 0xFF)
        self.__write_wb(WBI2CReg.PRER_HIGH, (val >> 8) & 0xFF)

    def start(self, addr, rw):
        # Prevent users from accidentally passing in an 8-bit address (already
        # indicating read/write bit)
        assert 0 <= addr <= 127

        # Enforce usage of the I2CRW enum
        assert type(rw) == I2CRW

        # Write the slave address to the RXR register
        self.__write_wb(WBI2CReg.RXR, (addr << 1) | int(rw))
        # Issue the start condition
        self.__write_wb(WBI2CReg.SR, 0x90)

    def write(self, val):
        # Send data to the device
        self.__write_wb(WBI2CReg.RXR, val)
        # Place the data on the bus
        self.__write_wb(WBI2CReg.SR, 0x10)

    # TODO: does this have to be a composite function?
    def read_ack_stop(self):
        self.__write_wb(WBI2CReg.SR, 0x68)
        return self.__read_wb(WBI2CReg.RXR)

    def stop(self):
        self.__write_wb(WBI2CReg.SR, 0x40)

    def print_i2cwb_registers(self):
        print("PRER: 0x{:04x}".format(self.__read_prer()))
        print("CTR:  0x{:02x}".format(self.__read_wb(WBI2CReg.CTR)))
        print("RXR:  0x{:02x}".format(self.__read_wb(WBI2CReg.RXR)))
        print("SR:   0x{:02x}".format(self.__read_wb(WBI2CReg.SR)))
        print("TXR:  0x{:02x}".format(self.__read_wb(WBI2CReg.TXR)))
        print("CR:   0x{:02x}".format(self.__read_wb(WBI2CReg.CR)))
