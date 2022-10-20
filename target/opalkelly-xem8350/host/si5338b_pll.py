# XEM8350 Si5338B PLL Configuration Utility
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
import argparse

from common.i2c import I2CRW, MockI2CBus, MockI2CSlave, I2CInterface
from common.xem_wishbone import XEMWishbone
from common.xem_i2c import WishboneI2C

def try_dec_utf8(utf8_bytes):
    try:
        return utf8_bytes.decode("utf-8")
    except UnicodeDecodeError:
        return utf8_bytes

class I2CSi5338BPLL():
    def __init__(self, i2c_bus):
        assert isinstance(i2c_bus, I2CInterface)
        self.i2c = i2c_bus
        self.i2c.queue_wb_writes()
        self.current_page = None

    def write_pll_i2c(self, pll_reg_addr, data):
        self.i2c.start(0xE0 >> 1, I2CRW.WRITE)
        self.i2c.write(pll_reg_addr & 0xFF)
        self.i2c.write(data & 0xFF)
        self.i2c.stop()
        self.i2c.flush_writes()

    def read_pll_i2c(self, pll_reg_addr):
        self.i2c.start(0xE0 >> 1, I2CRW.WRITE)
        self.i2c.write(pll_reg_addr & 0xFF)
        self.i2c.stop()
        self.i2c.flush_writes()
        self.i2c.start(0xE0 >> 1, I2CRW.READ)
        return self.i2c.read_ack_stop()

    def write_pll_reg(self, pll_page_reg_addr, data):
        if self.current_page != (pll_page_reg_addr >> 8) & 0x01:
            self.write_pll_i2c(0xFF, (pll_page_reg_addr >> 8) & 0x01)
            self.current_page = (pll_page_reg_addr >> 8) & 0x01
        self.write_pll_i2c(pll_page_reg_addr & 0xFF, data)

    def read_pll_reg(self, pll_page_reg_addr):
        if self.current_page != (pll_page_reg_addr >> 8) & 0x01:
            self.write_pll_i2c(0xFF, (pll_page_reg_addr >> 8) & 0x01)
            self.current_page = (pll_page_reg_addr >> 8) & 0x01
        return self.read_pll_i2c(pll_page_reg_addr & 0xFF)

    def clear_pll_reg_bit(self, pll_page_reg_addr, bitmask):
        r = self.read_pll_reg(pll_page_reg_addr)
        r &= ~bitmask
        self.write_pll_reg(pll_page_reg_addr, r)

    def set_pll_reg_bit(self, pll_page_reg_addr, bitmask):
        r = self.read_pll_reg(pll_page_reg_addr)
        r |= bitmask
        self.write_pll_reg(pll_page_reg_addr, r)

    def flash_csv(self, conf_csv, skip_first=False, pll_lock_timeout=10, log=False):
        # Configuration preamble
        self.set_pll_reg_bit(230, 1 << 4) # Disable Outputs, OEB_ALL = 1
        self.set_pll_reg_bit(241, 1 << 7) # Pause LOL, DIS_LOL = 1

        # Write the configuration
        register_contents = {}

        filtered = filter(
            lambda l: not l.startswith("#") and l.strip() != "",
            conf_csv.splitlines()
        )

        if skip_first:
            next(filtered)

        for line in filtered:
            split = line.strip().split(',')
            assert len(split) == 2
            addr = int(split[0], 10)
            val = int(split[1][:-1], 16)
            self.write_pll_reg(addr, val)

        # Configuration postamble
        self.clear_pll_reg_bit(49, 1 << 7) # FCAL_OVRD_EN = 0
        self.set_pll_reg_bit(246, 1 << 1) # SOFT_RESET = 1
        time.sleep(0.025)
        self.write_pll_reg(241, 0x65)

        if log:
            print("Waiting for PLL to acquire lock.")
        pll_lock_time = 0
        r = None
        while (r := self.read_pll_reg(218) & 0b10001) != 0x00:
            if pll_lock_time >= pll_lock_timeout:
                raise RuntimeError("PLL did not acquire lock in time!")

            # print(f"Register 218: 0x{r:02x}")
            time.sleep(0.5)
            pll_lock_time += 0.5

        if log:
            print("PLL locked, finishing configuration and enabling outputs!")
        self.write_pll_reg(47, self.read_pll_reg(237) & 0b11)
        self.write_pll_reg(46, self.read_pll_reg(236))
        self.write_pll_reg(45, self.read_pll_reg(235))
        self.set_pll_reg_bit(47, 0b00010100)
        self.set_pll_reg_bit(49, 1 << 7)
        self.clear_pll_reg_bit(230, 1 << 4)
        if log:
            print("Done!")

def main():
    parser = argparse.ArgumentParser(
        description="Interact with the OpalKelly XEM8350 Si5338B PLL")

    parser.add_argument("--device", choices=["xem_i2c"], required=True)
    parser.add_argument("--input-csv", type=str)
    parser.add_argument("--xem-serial", type=str)
    parser.add_argument("--xem-bitstream", type=str)
    parser.add_argument("command", choices=["flash"])

    args = parser.parse_args()

    # Instantiate the I2C bus and SFP device:
    if args.device == "xem_i2c":
        import ok

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

        assert xem.GetBoardModel() == xem.brdXEM8350KU060, \
            "Selected OpalKelly board is not supported by this script."

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
        i2c_bus = WishboneI2C(wb, 0x100)
    else:
        raise NotImplementedError()

    # Instantiate the PLL wrapper
    pll = I2CSi5338BPLL(i2c_bus)

    partial_part_number = pll.read_pll_reg(0x0002) & 0x3F
    print(f"Last 2 digits of PLL part number: {partial_part_number}")
    assert partial_part_number == 38
    print(f"Device revision ID: 0x{pll.read_pll_reg(0x0000) & 0x07:02x}")

    if args.command == "flash":
        if args.input_csv is None:
            parser.error(f"command {args.command} requires --input-csv")

        with open(args.input_csv, "r") as f:
            print(f"Flashing {args.input_csv} to PLL, please wait.")
            pll.flash_csv(f.read())
            print("Done. PLL has acquired lock with new configuration.")


if __name__ == "__main__":
    main()
