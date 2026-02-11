# QSFP(+) Module I2C Interface Script
#
# This file is part of the Time Tagger software defined digital data
# acquisition FPGA-link reference design.
#
# Copyright (C) 2022-2026 Swabian Instruments, All Rights Reserved
#
# Authors:
# - 2022 Leon Schuermann <leon@swabianinstruments.com>
# - 2026 David Sawatzke  <david@swabianinstruments.com>
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

from common.i2c import I2CRW, MockI2CBus, MockI2CSlave, I2CInterface
from common.ok_wishbone import Wishbone
from common.xem_i2c import WishboneI2C


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


class QSFPMock(MockI2CSlave):
    def __init__(self, dump, log=None):
        MockI2CSlave.__init__(self)

        # Log I2C bus transactions and warnings
        self.log = log if log is not None else logging.getLogger(__name__)

        # Simple mock: just play back a recorded QSFP dump
        self.regs = dump

        # Internal state to emulate I2C transactions on the bus
        self.i2c_state = "idle"
        self.i2c_addr = 0x00
        self.reg_addr = 0x00
        self.current_page = 0x00

    def has_addr(self, addr):
        # QSFP uses 0xA0 (0x50 7-bit) for everything
        return (addr << 1) == 0xA0

    def start_cond(self, addr, rw):
        self.i2c_addr = addr

        if self.i2c_state == "idle" and rw == I2CRW.WRITE:
            self.log.debug("QSFP: Received start condition, idle -> awaiting_reg_addr")
            self.i2c_state = "awaiting_reg_addr"
        elif self.i2c_state == "received_reg_addr" and rw == I2CRW.READ:
            self.log.debug("QSFP: Received start condition, received_reg-addr -> read_register")
            self.i2c_state = "read_register"
        else:
            raise NotImplementedError(f"QSFP: Received start condition in {self.i2c_state}")

    def consume(self, data):
        if self.i2c_state == "awaiting_reg_addr":
            self.log.debug("QSFP: Consuming register address, awaiting_reg_addr -> received_reg_addr")
            self.reg_addr = data
            self.i2c_state = "received_reg_addr"
        elif self.i2c_state == "received_reg_addr":
            # Handle Page Select Write (Byte 127)
            if self.reg_addr == 127:
                self.log.debug(
                    f"QSFP: Page select write. Page {self.current_page} -> {data}"
                )
                self.current_page = data
            self.reg_addr += 1  # Auto-increment simulation
        else:
            self.log.warn(f"QSFP: Unexpected consume() in {self.i2c_state}")

    def stop_cond(self):
        if self.i2c_state == "awaiting_stop_cond":
            self.log.debug("QSFP: Received stop condition, awaiting_stop_cond -> idle")
            self.i2c_state = "idle"
        elif self.i2c_state == "received_reg_addr":
            self.log.debug("QSFP: Received stop condition after register address, remain in received_reg_addr")
        else:
            raise NotImplementedError(f"QSFP: Received stop condition in {self.i2c_state}")

    def ack(self):
        if self.i2c_state == "read_register_awaiting_ack":
            self.log.debug(f"QSFP: Acked register read, read_register_awaiting_ack -> awaiting_stop_cond")
            self.i2c_state = "awaiting_stop_cond"
        else:
            self.log.warn(f"QSFP: Unexpected ack(), {self.i2c_state}")

    def produce(self):
        if self.i2c_state == "read_register":
            self.i2c_state = "read_register_awaiting_ack"

            # Logic for Lower vs Upper Memory
            if self.reg_addr < 128:
                # Lower Page (always available, we store it in key 0)
                val = self.regs[0][self.reg_addr]
            else:
                # Upper Page (depends on page select)
                page = self.current_page
                if page not in self.regs:
                    val = 0x00  # Default/Empty
                else:
                    val = self.regs[page][self.reg_addr]

            self.reg_addr += 1  # Auto increment
            return val
        else:
            raise NotImplementedError(f"QSFP: Unexpected produce() in {self.i2c_state}")


class I2CQSFP:
    # QSFP uses Address 0xA0 (0x50 7-bit) for everything.
    # Page Select is at Byte 127.
    QSFP_ADDR = 0x50

    # Defined in SFF-8636
    # Note: Vendor info is in Upper Page 00h (Bytes 128+)
    # Lower Page (0-127) contains monitors and status.
    INFORMATION_MEMORY_MAP = {
        # (Page, Start Address, Length)
        "vendor": (0x00, 148, 16),
        "oui": (0x00, 165, 3),
        "pn": (0x00, 168, 16),
        "rev": (0x00, 184, 2),
        "sn": (0x00, 196, 16),
        "dc": (0x00, 212, 8),
        # Lower Page fields (Page "None" implies Lower Page < 128)
        "type": (None, 0, 1),  # Identifier
        "connector": (0x00, 130, 1),  # Upper Page 00
        "bitrate": (0x00, 140, 1),  # Upper Page 00 (approx)
        # Fiber length is complex in QSFP, simplified here using Page 00
        "sm_len": (0x00, 142, 1),
        "om3_len": (0x00, 143, 1),
        "om2_len": (0x00, 144, 1),
        "om1_len": (0x00, 145, 1),
        "om4_len": (0x00, 146, 1),  # Cable Assembly Length
    }

    # Monitors are in Lower Page (always accessible).
    # Thresholds (Bounds) are in Page 03h.
    DIAGNOSTIC_FIELDS = {
        "temp": {
            "page": None,
            "addr": 22,  # Lower Page
            "bounds_page": 0x03,
            "bounds_addr": 128,
            "div": 256,
            "signed": True,
            "unit": "degC",
            "count": 1,
        },
        "vcc": {
            "page": None,
            "addr": 26,  # Lower Page
            "bounds_page": 0x03,
            "bounds_addr": 144,
            "div": 10000,
            "signed": False,
            "unit": "V",
            "count": 1,
        },
        "rx_power": {
            "page": None,
            "addr": 34,  # Lower Page (Ch1 MSB)
            "bounds_page": 0x03,
            "bounds_addr": 176,
            "div": 10000,
            "signed": False,
            "unit": "mW",
            "count": 4,
            "stride": 2,
        },
        "tx_bias": {
            "page": None,
            "addr": 42,  # Lower Page (Ch1 MSB)
            "bounds_page": 0x03,
            "bounds_addr": 184,
            "div": 500,
            "signed": False,
            "unit": "mA",
            "count": 4,
            "stride": 2,
        },
        "tx_power": {
            "page": None,
            "addr": 50,  # Lower Page (Ch1 MSB)
            "bounds_page": 0x03,
            "bounds_addr": 192,
            "div": 10000,
            "signed": False,
            "unit": "mW",
            "count": 4,
            "stride": 2,
        },
    }

    def __init__(self, i2c_bus):
        assert isinstance(i2c_bus, I2CInterface)
        self.i2c = i2c_bus
        self.cache = {}
        self._current_page = -1

    def __set_page(self, page):
        # QSFP Page Select is Byte 127 on Address 0xA0
        if page is None:
            return  # Lower page accesses don't strictly require page set, but good practice
        # if self._current_page == page:
        #     return

        self.i2c.start(self.QSFP_ADDR, I2CRW.WRITE)
        self.i2c.write(127)  # Page Select Byte
        self.i2c.write(page)
        self.i2c.stop()
        self._current_page = page

    def __read_qsfp_bytes(self, page, start_addr, length):
        # Page selection only necessary for Upper Page
        if start_addr >= 128:
            self.__set_page(page)

        self.i2c.start(self.QSFP_ADDR, I2CRW.WRITE)
        self.i2c.write(start_addr)
        self.i2c.start(self.QSFP_ADDR, I2CRW.READ)
        data = []
        for _ in range(length - 1):
            data.append(self.i2c.read_ack())
        data.append(self.i2c.read_ack_stop())  # Last byte ACK+STOP
        return data

    def __get_info_reg(self, reg):
        assert reg in self.INFORMATION_MEMORY_MAP
        page, addr, length = self.INFORMATION_MEMORY_MAP[reg]

        # Check in the cache first
        if f"info_{reg}" in self.cache:
            return self.cache[f"info_{reg}"]

        # Not in the cache, read the register
        contents = self.__read_qsfp_bytes(page if page is not None else 0, addr, length)

        self.cache[f"info_{reg}"] = contents

        return contents

    def __get_diagnostic(self, diag):
        assert diag in self.DIAGNOSTIC_FIELDS
        df = self.DIAGNOSTIC_FIELDS[diag]

        # Ensure bounds are loaded in the cache first
        if f"diagbounds_{diag}" not in self.cache:
            read_bounds_data = self.__read_qsfp_bytes(
                df["bounds_page"], df["bounds_addr"], 8
            )
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

        # Load raw values, never cached
        values = []

        # Read all channels in one burst if possible, but for simplicity/robustness we read per value here
        # (Optimized burst read could be done, but keeping it simple)
        for i in range(df["count"]):
            addr_offset = df["addr"] + (i * df.get("stride", 0))
            raw_val = self.__read_qsfp_bytes(df["page"], addr_offset, 2)
            values.append(raw_val)

        def convert(b):
            v = int.from_bytes(b, byteorder="big", signed=df["signed"])
            return v / df["div"]

        # Convert bounds (single set for all channels)
        conv_bounds = {k: convert(v) for k, v in bounds.items()}

        # Convert values (list)
        conv_values = [convert(v) for v in values]

        return {"vals": conv_values, "bounds": conv_bounds, **df}

    def invalidate_device_cache(self):
        self.cache = {}
        self._current_page = -1

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

    def get_max_fiber_lengths(self):
        # QSFP lengths in Page 00
        return {
            "sm": self.__get_info_reg("sm_len")[0] * 1000,  # km -> m
            "om3": self.__get_info_reg("om3_len")[0] * 2,  # 2m units
            "om2": self.__get_info_reg("om2_len")[0] * 1,  # 1m units
            "om1": self.__get_info_reg("om1_len")[0] * 1,  # 1m units
            "om4": self.__get_info_reg("om4_len")[0] * 1,  # Copper/Active Cable
        }

    def dump(self):
        # QSFP Dump: Lower Page + Upper Page 00 + Upper Page 03 (Diagnostic Thresholds)
        # We structure this as a Dict of Pages for the Mock class
        pages = {}

        # Page 0 (Lower + Upper 00)
        # Note: In standard, Lower (0-127) is shared. Upper (128-255) is paged.
        # We will dump Page 00 fully (0-255)
        pages[0x00] = self.__read_qsfp_bytes(0x00, 0, 256)

        # Page 03 (Thresholds)
        # We only need upper bytes 128-255
        # To make it simple for the mock, we can dump full 256 bytes but ignore lower
        pages[0x03] = [0] * 128 + self.__read_qsfp_bytes(0x03, 128, 128)

        return pages

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
            \t\t{'SM':>10s}{'OM1':>7s}{'OM2':>7s}{'OM3':>7s}{'Len':>7s}
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

    def print_diagnostics(self):
        print("Diagnostics:")
        print(
            f"  {'':21} {'VAL':>8s} "
            + f"{'+ER':>8s} {'+WR':>8s} {'-WR':>8s} {'-ER':>8s}"
        )
        for d in self.DIAGNOSTIC_FIELDS.keys():
            data = self.__get_diagnostic(d)
            bounds = data["bounds"]
            vals = data["vals"]  # List of values

            # Print bounds only on the first line (or generic line)
            # If multiple channels, we print one line per channel

            for i, val in enumerate(vals):
                label = f"{d}[{i}]" if len(vals) > 1 else d

                print(
                    f"  {label:12} {'(' + data['unit'] + ')':>6} "
                    + f": {val:8.3f} "
                    + f"{bounds['pos_error']:8.3f} "
                    + f"{bounds['pos_warning']:8.3f} "
                    + f"{bounds['neg_warning']:8.3f} "
                    + f"{bounds['neg_error']:8.3f}"
                )


def main():
    parser = argparse.ArgumentParser(
        description="Interact with the QSFP(+) module I2C interface"
    )

    parser.add_argument("--device", choices=["xem_i2c", "dumpfile"], required=True)
    parser.add_argument("--xem-serial", type=str)
    parser.add_argument("--xem-bitstream", type=str)
    parser.add_argument("--dumpfile-in", type=str)
    parser.add_argument("--dumpfile-out", type=str)
    parser.add_argument("command", choices=["dump", "monitor"])

    args = parser.parse_args()

    # Instantiate the I2C bus and QSFP device:
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
        wb = Wishbone(xem)
        i2c_bus = WishboneI2C(wb, 0b100000000000000000000010 << 8)
    elif args.device == "dumpfile":
        if args.dumpfile_in is None:
            parser.error("--device dumpfile requires --dumpfile-in")

        with open(args.dumpfile_in, "rb") as f:
            qsfp_dump = pickle.load(f)

        mock_qsfp_device = QSFPMock(qsfp_dump)
        i2c_bus = MockI2CBus()
        i2c_bus.attach_slave(mock_qsfp_device)
    else:
        raise NotImplementedError()

    # Instantiate the QSFP module wrapper
    qsfp = I2CQSFP(i2c_bus)

    print("Connected to the following QSFP module:")
    qsfp.print_info()
    print()

    if args.command == "dump":
        if args.dumpfile_out is None:
            parser.error("command dump requires --dumpfile-out")

        with open(args.dumpfile_out, "wb") as f:
            pickle.dump(qsfp.dump(), f)

        print("Dumped QSFP memory contents.")
    elif args.command == "monitor":
        while True:
            qsfp.print_diagnostics()
            time.sleep(0.5)
            print()
    else:
        raise NotImplementedError()


if __name__ == "__main__":
    main()
