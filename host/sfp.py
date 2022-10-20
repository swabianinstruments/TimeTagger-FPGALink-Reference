# SFP(+) Module I2C Interface Script
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

import time
from enum import IntEnum
import pickle
import logging
import argparse
import textwrap

import ok

from .i2c import I2CRW, MockI2CBus, MockI2CSlave, I2CInterface
from .xem_wishbone import XEMWishbone
from .xem_i2c import WishboneI2C

class SFPType(IntEnum):
    # Invalid value, not part of the specification
    INVALID = -1
    # Designated "unknown" field by the specification
    UNKNOWN = 0x00
    GBIC = 0x01
    SOLDERED = 0x02
    SFPSFPP = 0x03
    XBI300Pin = 0x04
    XENPAK = 0x05
    XFP = 0x06
    XFF = 0x07
    XFPE = 0x08
    XPAK = 0x09
    X2 = 0x0A
    DWDMSFPSFPP = 0x0B
    QSFP = 0x0C
    QSFPP = 0x0D
    CXP = 0x0E
    SMMHD4X = 0x0F
    SMMHD8X = 0x10
    QSFP28 = 0x11
    CXP2 = 0x12
    CDFP12 = 0x13
    SMMHD4XFANOUT = 0x14
    SMMHD8XFANOUT = 0x15
    CDFP3 = 0x16
    MICROQSFP = 0x17
    QSFPDD = 0x18
    OSFP8X = 0x19
    SFPDD2X = 0x1A
    DSFP = 0x1B
    MINILINKX4 = 0x1C
    MINILINKX8 = 0x1D
    QSFPPCMIS = 0x1E

class SFPConnector(IntEnum):
    # Invalid value, not part of the specification
    INVALID = -1
    # Designated "unknown" field by the specification
    UNKNOWN = 0x00
    SC = 0x01
    FIBERCHANNEL1C = 0x02
    FIBERCHANNEL2C = 0x03
    BNCTNC = 0x04
    FIBERCHANNELCOAX = 0x05
    FIBERJACK = 0x06
    LC = 0x07
    MTRJ = 0x08
    MU = 0x09
    SG = 0x0A
    OPTICALPIGTAIL = 0x0B
    MPO1X12 = 0x0C
    MPO2X16 = 0x0D
    HSSDCII = 0x20
    COPPERPIGTAIL = 0x21
    RJ45 = 0x22
    NOTSEPERABLE = 0x23
    MXC2X16 = 0x24
    CS = 0x25
    SN = 0x26
    MPO2X12 = 0x27
    MPO1X16 = 0x28

class SFPMock(MockI2CSlave):
    def __init__(self, dump, log=None):
        MockI2CSlave.__init__(self)

        # Log I2C bus transactions and warnings
        self.log = log if log is not None else logging.getLogger(__name__)

        # Simple mock: just play back a recorded SFP dump
        self.regs = dump

        # Internal state to emulate I2C transactions on the bus
        self.i2c_state = "idle"
        self.i2c_addr = 0x00
        self.reg_addr = 0x00

    def has_addr(self, addr):
        return (addr << 1) in [0xA0, 0xA2]

    def start_cond(self, addr, rw):
        self.i2c_addr = addr

        if self.i2c_state == "idle" and rw == I2CRW.WRITE:
            self.log.debug("SFP: Received start condition, idle -> awaiting_reg_addr")
            self.i2c_state = "awaiting_reg_addr"
        elif self.i2c_state == "received_reg_addr" and rw == I2CRW.READ:
            self.log.debug("SFP: Received start condition, received_reg-addr -> read_register")
            self.i2c_state = "read_register"
        else:
            raise NotImplementedError(f"SFP: Received start condition in {self.i2c_state}")

    def consume(self, data):
        if self.i2c_state == "awaiting_reg_addr":
            self.log.debug("SFP: Consuming register address, awaiting_reg_addr -> received_reg_addr")
            self.reg_addr = data
            self.i2c_state = "received_reg_addr"
        else:
            self.log.warn(f"SFP: Unexpected consume() in {self.i2c_state}")

    def stop_cond(self):
        if self.i2c_state == "awaiting_stop_cond":
            self.log.debug("SFP: Received stop condition, awaiting_stop_cond -> idle")
            self.i2c_state = "idle"
        elif self.i2c_state == "received_reg_addr":
            self.log.debug("SFP: Received stop condition after register address, remain in received_reg_addr")
        else:
            raise NotImplementedError(f"SFP: Received stop condition in {self.i2c_state}")

    def ack(self):
        if self.i2c_state == "read_register_awaiting_ack":
            self.log.debug(f"SFP: Acked register read, read_register_awaiting_ack -> awaiting_stop_cond")
            self.i2c_state = "awaiting_stop_cond"
        else:
            self.log.warn(f"SFP: Unexpected ack(), {self.i2c_state}")

    def produce(self):
        if self.i2c_state == "read_register":
            self.i2c_state = "read_register_awaiting_ack"
            return self.regs[self.i2c_addr << 1][self.reg_addr]
        else:
            raise NotImplementedError(f"SFP: Unexpected produce() in {self.i2c_state}")

class I2CSFP():
    class SFPBank(IntEnum):
        INFO = 0xA0
        DIAG = 0xA2

    INFORMATION_MEMORY_MAP = {
        "vendor": (20, 16),
        "oui": (37, 3),
        "rev": (56, 4),
        "pn": (40, 16),
        "sn": (68, 16),
        "dc": (84, 6),
        "type": (0, 1),
        "connector": (2, 1),
        "bitrate": (12, 1),
        "wavelength": (60, 2),
        "sm_len": (14, 1),
        "om1_len": (17, 1),
        "om2_len": (16, 1),
        "om3_len": (19, 1),
        "om4_len": (18, 1),
    }

    DIAGNOSTIC_FIELDS = {
        "temp": {
            "bounds_addr": 0,
            "val_addr": 96,
            "div": 256,
            "signed": True,
            "unit": "degC",
        },

        "vcc": {
            "bounds_addr": 8,
            "val_addr": 98,
            "div": 10000,
            "signed": False,
            "unit": "V",
        },

        "tx_bias": {
            "bounds_addr": 16,
            "val_addr": 100,
            "div": 500,
            "signed": False,
            "unit": "mA",
        },

        "tx_power": {
            "bounds_addr": 24,
            "val_addr": 102,
            "div": 10000,
            "signed": False,
            "unit": "mW",
        },

        "rx_power": {
            "bounds_addr": 32,
            "val_addr": 104,
            "div": 10000,
            "signed": False,
            "unit": "mW",
        },

        "laser_temp": {
            "bounds_addr": 40,
            "val_addr": 106,
            "div": 256,
            "signed": True,
            "unit": "degC",
        },

        "tec": {
            "bounds_addr": 48,
            "val_addr": 108,
            "div": 10,
            "signed": True,
            "unit": "mA",
        },
    }

    def __init__(self, i2c_bus):
        assert isinstance(i2c_bus, I2CInterface)
        self.i2c = i2c_bus

        # Cached SFP device memory contents
        self.cache = {}

    def __read_sfp_addr(self, bank, sfp_reg_addr):
        self.i2c.start(int(bank) >> 1, I2CRW.WRITE)
        self.i2c.write(sfp_reg_addr)
        self.i2c.start(int(bank) >> 1, I2CRW.READ)
        return self.i2c.read_ack_stop()

    def __get_info_reg(self, reg):
        assert reg in self.INFORMATION_MEMORY_MAP
        reg_bounds = self.INFORMATION_MEMORY_MAP[reg]

        # Check in the cache first
        if f"info_{reg}" in self.cache:
            return self.cache[f"info_{reg}"]

        # Not in the cache, read the register
        contents = [
            self.__read_sfp_addr(self.SFPBank.INFO, addr)
            for addr in range(reg_bounds[0], reg_bounds[0] + reg_bounds[1])
        ]

        # Place it in the cache
        self.cache[f"info_{reg}"] = contents

        return contents

    def __get_diagnostic(self, diag):
        assert diag in self.DIAGNOSTIC_FIELDS
        df = self.DIAGNOSTIC_FIELDS[diag]

        # Ensure bounds are loaded in the cache first
        if not f"diagbounds_{diag}" in self.cache:
            read_bounds_data = [
                self.__read_sfp_addr(
                    self.SFPBank.DIAG, df["bounds_addr"] + i)
                for i in range(8)
            ]
            self.cache[f"diagbounds_{diag}"] = {
                # Positive error
                "pos_error": bytes(read_bounds_data[0:2]),
                # Negative error
                "neg_error": bytes(read_bounds_data[2:4]),
                # Positive warning
                "pos_warning": bytes(read_bounds_data[4:6]),
                # Negative warning
                "neg_warning": bytes(read_bounds_data[6:8]),
            }

        # Retrieve bounds from the cache
        bounds = self.cache[f"diagbounds_{diag}"]

        # Load raw value, never cached
        val = bytes([
            self.__read_sfp_addr(self.SFPBank.DIAG, df["val_addr"] + 0),
            self.__read_sfp_addr(self.SFPBank.DIAG, df["val_addr"] + 1),
        ])

        def convert(b):
            v = int.from_bytes(b, byteorder="big", signed=df["signed"])
            return v / df["div"]

        return {
            "val": convert(val),
            "bounds": {
                k: convert(v)
                for k, v in bounds.items()
            },
            **df,
        }

    def invalidate_device_cache(self):
        self.cache = {}

    def get_vendor(self):
        try:
            return bytes(self.__get_info_reg("vendor")).decode('utf-8')
        except UnicodeDecodeError:
            return None

    def get_oui(self):
        return int.from_bytes(
            bytes(self.__get_info_reg("oui")), byteorder="big")

    def get_rev(self):
        try:
            return bytes(self.__get_info_reg("rev")).decode("utf-8")
        except UnicodeDecodeError:
            return None

    def get_pn(self):
        try:
            return bytes(self.__get_info_reg("pn")).decode("utf-8")
        except UnicodeDecodeError:
            return None

    def get_sn(self):
        try:
            return bytes(self.__get_info_reg("sn")).decode("utf-8")
        except UnicodeDecodeError:
            return None

    def get_dc(self):
        try:
            return bytes(self.__get_info_reg("dc")).decode("utf-8")
        except UnicodeDecodeError:
            return None

    def get_type(self):
        raw_type = self.__get_info_reg("type")[0]

        for t in SFPType:
            if int(t) == raw_type:
                return t

        return SFPType.INVALID

    def get_connector(self):
        raw_connector = self.__get_info_reg("connector")[0]

        for c in SFPConnector:
            if int(c) == raw_connector:
                return c

        return SFPConnector.INVALID

    def get_bitrate(self):
        return self.__get_info_reg("bitrate")[0] * 100

    def get_wavelength(self):
        return int.from_bytes(
            bytes(self.__get_info_reg("wavelength")),
            byteorder="big"
        )

    def get_max_fiber_lengths(self):
        return {
            "sm": self.__get_info_reg("sm_len")[0] * 1000,
            "om1": self.__get_info_reg("om1_len")[0] * 10,
            "om2": self.__get_info_reg("om2_len")[0] * 10,
            "om3": self.__get_info_reg("om3_len")[0] * 10,
            "om4": self.__get_info_reg("om4_len")[0] * 10,
        }

    def dump(self):
        return {
            b: [self.__read_sfp_addr(b, a) for a in range(256)]
            for b in self.SFPBank
        }

    def print_info(self):
        fl = self.get_max_fiber_lengths()
        print(textwrap.dedent(f"""
            Vendor:\t\t{self.get_vendor()}
            OUI:\t\t0x{self.get_oui():06x}
            Rev:\t\t{self.get_rev()}
            PN:\t\t{self.get_pn()}
            SN:\t\t{self.get_sn()}
            DC:\t\t{self.get_dc()}
            Type:\t\t{self.get_type().name} (0x{self.get_type():02x})
            Connector:\t{self.get_connector().name} (0x{self.get_connector():02x})
            Bitrate:\t{self.get_bitrate()} MBd
            Wavelength:\t{self.get_wavelength()} nm
            \t\t{'SM':>10s}{'OM1':>7s}{'OM1':>7s}{'OM3':>7s}{'OM4':>7s}
            Max length:\t{fl['sm']:8d} m {fl['om1']:4d} m {fl['om2']:4d} m {fl['om3']:4d} m {fl['om4']:4d} m
        """))

    def get_temp(self):
        return self.__get_diagnostic("temp")

    def get_vcc(self):
        return self.__get_diagnostic("vcc")

    def get_tx_bias(self):
        return self.__get_diagnostic("tx_bias")

    def get_tx_power(self):
        return self.__get_diagnostic("tx_power")

    def get_rx_power(self):
        return self.__get_diagnostic("rx_power")

    def get_laser_temp(self):
        return self.__get_diagnostic("laser_temp")

    def get_tec(self):
        return self.__get_diagnostic("tec")

    def print_diagnostics(self):
        print("Diagnostics:")
        print(f"  {'':21} {'VAL':>8s} "
              + f"{'+ER':>8s} {'+WR':>8s} {'-WR':>8s} {'-ER':>8s}")
        for d in self.DIAGNOSTIC_FIELDS.keys():
            v = self.__get_diagnostic(d)
            print(f"  {d:12} {'(' + v['unit'] + ')':>6} "
                  + f": {v['val']:8.3f} "
                  + f"{v['bounds']['pos_error']:8.3f} "
                  + f"{v['bounds']['pos_warning']:8.3f} "
                  + f"{v['bounds']['neg_warning']:8.3f} "
                  + f"{v['bounds']['neg_error']:8.3f}")

def main():
    parser = argparse.ArgumentParser(
        description="Interact with the SFP(+) module I2C interface")

    parser.add_argument("--device", choices=["xem_i2c", "dumpfile"], required=True)
    parser.add_argument("--xem-serial", type=str)
    parser.add_argument("--xem-bitstream", type=str)
    parser.add_argument("--dumpfile-in", type=str)
    parser.add_argument("--dumpfile-out", type=str)
    parser.add_argument("command", choices=["dump", "monitor"])

    args = parser.parse_args()

    # Instantiate the I2C bus and SFP device:
    if args.device == "xem_i2c":
        # Open device, either using the supplied serial or if there
        # happens to be only one device connected:
        xem = ok.okCFrontPanel()

        # Mapping from internal XEM device IDs to human-readable board
        # names. Done at runtime to use the up-to-date OpalKelly board
        # list from the used version of the FrontPanel SDK:
        device_id_str_map = {
            int(getattr(xem, v)): v[3:]
            for v in dir(xem) if v.startswith("brd")
        }

        xem_serial = args.xem_serial
        if xem_serial is None:
            cnt = xem.GetDeviceCount()
            devices = [
                (
                    xem.GetDeviceListSerial(i),
                    xem.GetDeviceListModel(i),
                    device_id_str_map[xem.GetDeviceListModel(i)],
                )
                for i in range(cnt)
            ]
            assert cnt == 1, \
                "Cannot automatically determine which XEM to connect to, " \
                "please specify the --xem-serial argument.\n" \
                "Available devices:" + "\n  - ".join([""] + [
                    f"{serial}: \t {board}"
                    for serial, _, board in devices
                ])
            xem_serial = devices[0][0]

        assert xem.OpenBySerial(xem_serial) == 0, \
            f"Failed to open OpalKelly board with serial \"{xem_serial}\"."

        # Print some information about the device
        print(f"Connected to device {xem.GetDeviceID()} with serial "
              + f"{xem.GetSerialNumber()}!")

        if args.xem_bitstream is not None:
            print("Configuring FPGA using bitstream "
                  + f"\"{args.xem_bitstream}\", please wait...")
            assert xem.ConfigureFPGA(args.xem_bitstream) == 0, \
                "Failed to configure the FPGA using the supplied bitstream."
            time.sleep(1)

        assert xem.IsFrontPanelEnabled(), \
            "Bitstream is not OpalKelly FrontPanel-enabled or FPGA not " \
            "configured, cannot continue!"

        # Instantiate the I2C bus wrapper based on the SFP argument
        wb = XEMWishbone(xem)
        i2c_bus = WishboneI2C(wb, 0b10 << 8)
    elif args.device == "dumpfile":
        if args.dumpfile_in is None:
            parser.error("--device dumpfile requires --dumpfile-in")

        with open(args.dumpfile_in, "rb") as f:
            sfp_dump = pickle.load(f)

        mock_sfp_device = SFPMock(sfp_dump)
        i2c_bus = MockI2CBus()
        i2c_bus.attach_slave(mock_sfp_device)
    else:
        raise NotImplementedError()

    # Instantiate the SFP module wrapper
    sfp = I2CSFP(i2c_bus)

    print("Connected to the following SFP module:")
    sfp.print_info()
    print()

    if args.command == "dump":
        if args.dumpfile_out is None:
            parser.error("command dump requires --dumpfile-out")

        with open(args.dumpfile_out, "wb") as f:
            pickle.dump(sfp.dump(), f)

        print("Dumped SFP memory contents.")
    elif args.command == "monitor":
        while True:
            sfp.print_diagnostics()
            time.sleep(0.5)
            print()
    else:
        raise NotImplementedError()

if __name__ == "__main__":
    main()
