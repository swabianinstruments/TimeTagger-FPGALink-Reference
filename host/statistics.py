#!/usr/bin/env python3
# Statistics Interface Script
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
import time
from enum import IntEnum
import argparse
import textwrap

import ok

from .ok_wishbone import Wishbone


class Statistics:
    DIAGNOSTIC_FIELDS = {
        "packet_rate": {
            "val_addr": 12,
            "div": 1,
            "signed": False,
            "unit": "Packets/s",
        },
        "word_rate": {
            "val_addr": 16,
            "div": 1,
            "signed": False,
            "unit": "Words (128 bit)/s",
        },
        "tag_rate": {
            "val_addr": 40,
            "div": 1,
            "signed": False,
            "unit": "Tags/s",
        },
        "received_packets": {
            "val_addr": 20,
            "div": 1,
            "signed": False,
            "unit": "Packets",
        },
        "received_words": {
            "val_addr": 24,
            "div": 1,
            "signed": False,
            "unit": "Words (128 bit)",
        },
        "received_tags": {
            "val_addr": 44,
            "div": 1,
            "signed": False,
            "unit": "Tags",
        },
        "size_of_last_packet": {
            "val_addr": 28,
            "div": 1,
            "signed": False,
            "unit": "Words (128 bit)/Packet",
        },
        "packet_loss": {
            "val_addr": 32,
            "div": 1,
            "signed": False,
            "unit": "bool",
        },
        "overflowed": {
            "val_addr": 48,
            "div": 1,
            "signed": False,
            "unit": "bool",
        },
        "invalid_packets": {
            "val_addr": 36,
            "div": 1,
            "signed": False,
            "unit": "Packets",
        },
    }

    def __init__(self, wb, offset):
        assert isinstance(wb, Wishbone)
        self.wb = wb
        self.offset = offset

    def __read_wb_addr(self, addr):
        return self.wb.read(self.offset + addr)

    def __get_diagnostic(self, diag):
        assert diag in self.DIAGNOSTIC_FIELDS
        df = self.DIAGNOSTIC_FIELDS[diag]

        val = self.__read_wb_addr(df["val_addr"])

        return {
            "val": val,
            **df,
        }

    def get_temp(self):
        return self.__get_diagnostic("temp")

    def print_diagnostics(self):
        # Construct output first and then print it for less flicker
        output = "Diagnostics:" + "\n"
        output += f"  {'':50} {'VAL':>8s} \n"
        for d in self.DIAGNOSTIC_FIELDS.keys():
            v = self.__get_diagnostic(d)
            output += f"  {d:20} {'(' + v['unit'] + ')':>27} " + f": {v['val']:8} \n"
        print(output)


def main():
    parser = argparse.ArgumentParser(
        description="Interact with the statistics interface"
    )

    parser.add_argument("--xem-serial", type=str)
    parser.add_argument("--xem-bitstream", type=str)
    parser.add_argument("--monitor", type=bool)

    args = parser.parse_args()

    # Open device, either using the supplied serial or if there
    # happens to be only one device connected:
    xem = ok.okCFrontPanel()

    # Mapping from internal XEM device IDs to human-readable board
    # names. Done at runtime to use the up-to-date OpalKelly board
    # list from the used version of the FrontPanel SDK:
    device_id_str_map = {
        int(getattr(xem, v)): v[3:] for v in dir(xem) if v.startswith("brd")
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
        assert cnt == 1, (
            "Cannot automatically determine which XEM to connect to, "
            "please specify the --xem-serial argument.\n"
            "Available devices:"
            + "\n  - ".join(
                [""] + [f"{serial}: \t {board}" for serial, _, board in devices]
            )
        )
        xem_serial = devices[0][0]

    assert (
        xem.OpenBySerial(xem_serial) == 0
    ), f'Failed to open OpalKelly board with serial "{xem_serial}".'

    # Print some information about the device
    print(
        f"Connected to device {xem.GetDeviceID()} with serial "
        + f"{xem.GetSerialNumber()}!"
    )

    if args.xem_bitstream is not None:
        print(
            "Configuring FPGA using bitstream "
            + f'"{args.xem_bitstream}", please wait...'
        )
        assert (
            xem.ConfigureFPGA(args.xem_bitstream) == 0
        ), "Failed to configure the FPGA using the supplied bitstream."
        time.sleep(1)

    assert xem.IsFrontPanelEnabled(), (
        "Bitstream is not OpalKelly FrontPanel-enabled or FPGA not "
        "configured, cannot continue!"
    )

    wb = Wishbone(xem)

    stat = Statistics(wb, 0b100000000000000001010001 << 8)

    stat.print_diagnostics()
    if args.monitor:
        while True:
            stat.print_diagnostics()
            time.sleep(0.5)
            print()


if __name__ == "__main__":
    main()
