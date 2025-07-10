#!/usr/bin/env python3

# XEM8320 Time Tagger FPGALink Reference Design Configuration Tool.
#
# This file is part of the Time Tagger software defined digital data
# acquisition FPGA-link reference design.
#
# Copyright (C) 2022 Swabian Instruments, All Rights Reserved
#
# Authors:
# - 2022 David Sawatzke <markus@swabianinstruments.com>
# - 2022 Leon Schuermann <leon@swabianinstruments.com>
#
# This file is provided under the terms and conditions of the BSD 3-Clause
# license, accessible under https://opensource.org/licenses/BSD-3-Clause.
#
# SPDX-License-Identifier: BSD-3-Clause

import argparse
import ok


def main():
    parser = argparse.ArgumentParser(
        description=("Configure the XEM3820 device settings for the FPGALink "
                     + "reference design."))

    parser.add_argument("--xem-serial", type=str)
    parser.add_argument("command", choices=["configure"])

    args = parser.parse_args()

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

    assert xem.GetBoardModel() == xem.brdXEM8320AU25P, \
        "Selected OpalKelly board is not supported by this script."

    # Print some information about the device
    print(f"Connected to device {xem.GetDeviceID()} with serial "
          + f"{xem.GetSerialNumber()}!")
    devInfo = ok.okTDeviceInfo()
    if xem.NoError != xem.GetDeviceInfo(devInfo):
        print("Unable to retrieve device information.")
        exit(-1)
    print("         Product: " + devInfo.productName)
    print(
        "Firmware version: %d.%d" % (devInfo.deviceMajorVersion, devInfo.deviceMinorVersion)
    )
    print("   Serial Number: %s" % devInfo.serialNumber)
    print("       Device ID: %s" % devInfo.deviceID)
    if (devInfo.deviceMajorVersion == 1) and (devInfo.deviceMinorVersion < 56):
        print("Firmware outdated!")
        print("Please update to firmware version >= 1.56 to ensure correct reset behaviour!")
        exit(-1)

    if args.command == "configure":
        settings = ok.okCDeviceSettings()

        if xem.NoError != xem.GetDeviceSettings(settings):
            print("Unable to retrieve device information.")
            exit(-1)
        print("Setting XEM8320_SMARTVIO_MODE to 0x01")
        settings.SetInt("XEM8320_SMARTVIO_MODE", 0x01)
        # For LEDs
        print("Setting XEM8320_VIO1_VOLTAGE to 120")
        settings.SetInt("XEM8320_VIO1_VOLTAGE", 120)
        # For SFP comms
        print("Setting XEM8320_VIO2_VOLTAGE to 330")
        settings.SetInt("XEM8320_VIO2_VOLTAGE", 330)
        settings.Save()
        print("Saved settings.")


if __name__ == "__main__":
    main()
