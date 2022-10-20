# I2C Interface Abstraction in Python
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

from abc import ABC, abstractmethod
from enum import IntEnum

class I2CRW(IntEnum):
    WRITE = 0
    READ = 1

class I2CInterface(ABC):
    @abstractmethod
    def start(self, addr, rw):
        # Prevent users from accidentally passing in an 8-bit address (already
        # indicating read/write bit)
        assert 0 <= addr <= 127

        # Enforce usage of the I2CRW enum
        assert type(rw) == I2CRW

    @abstractmethod
    def write(self, data):
        assert 0 <= data <= 255

    @abstractmethod
    def read_ack_stop(self):
        pass

    @abstractmethod
    def stop(self):
        pass

class MockI2CSlave(ABC):
    def __init__(self):
        pass

    @abstractmethod
    def has_addr(self, addr):
        pass

    @abstractmethod
    def consume(self, data):
        pass

    @abstractmethod
    def produce(self):
        pass

    def start_cond(self, addr, rw):
        pass

    def stop_cond(self):
        pass

    def ack(self):
        pass


class MockI2CBus(I2CInterface):
    def __init__(self):
        self.slaves = set()

        self.curtxn_valid = False
        self.curtxn_addr = 0x00
        self.curtxn_slaves = []
        self.curtxn_rw = I2CRW.WRITE

    def attach_slave(self, slave):
        assert isinstance(slave, MockI2CSlave)
        self.slaves.add(slave)

    def detach_slave(self, slave):
        self.curtxn_slaves.remove(slave)
        self.slaves.remove(slave)

    def start(self, addr, rw):
        # Perform some basic sanity checks
        I2CInterface.start(self, addr, rw)

        self.curtxn_addr = addr
        self.curtxn_rw = rw
        self.curtxn_valid = True

        responding_slaves = filter(
            lambda s: s.has_addr(addr),
            self.slaves
        )
        self.curtxn_slaves = list(responding_slaves)

        for s in self.curtxn_slaves:
            # Announce a start condition to the respective slave
            s.start_cond(self.curtxn_addr, rw)

    def stop(self):
        # Peform some basic sanity checks
        I2CInterface.stop(self)

        if self.curtxn_valid:
            for s in self.curtxn_slaves:
                # Announce a stop condition on the respective slave
                s.stop_cond()

        self.curtxn_valid = False

    def write(self, data):
        # Peform some basic sanity checks
        I2CInterface.write(self, data)

        # We need some valid transaction to issue a write
        if not self.curtxn_valid:
            raise RuntimeError("I2C write attempted without valid transaction")

        # But the slave may no longer be attached
        for s in self.curtxn_slaves:
            s.consume(data)

    def read_ack_stop(self):
        # Peform some basic sanity checks
        I2CInterface.read_ack_stop(self)

        # We need some valid transaction to read
        if not self.curtxn_valid:
            raise RuntimeError("I2C read attempted without valid transaction")

        # But the slave may no longer be attached
        val = 0xFF
        for s in self.curtxn_slaves:
            val &= s.produce()
            s.ack()
            s.stop_cond()

        self.curtxn_valid = False
        return val
