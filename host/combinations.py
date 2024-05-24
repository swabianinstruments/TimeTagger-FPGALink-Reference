# Combinations script
#
# This file is part of the Time Tagger software defined digital data
# acquisition FPGA-link reference design.
#
# Copyright (C) 2024 Swabian Instruments, All Rights Reserved
#
# Authors:
# - 2024 Loghman Rahimzadeh <loghman@swabianinstruments.com>
#
# This file is provided under the terms and conditions of the BSD 3-Clause
# license, accessible under https://opensource.org/licenses/BSD-3-Clause.
#
# SPDX-License-Identifier: BSD-3-Clause

from enum import IntEnum
from typing import Mapping
import numpy as np
import numpy.typing as npt
from .ok_wishbone import Wishbone


class Combinations:
    class Reg(IntEnum):
        Module = 0
        WindowLSB = 1
        WindowMSB = 2
        Filter = 3
        Select = 4
        Capture = 5
        StartReading = 6
        Reset = 7
        LUTConfig = 8
        FIFODepth = 9
        NumberCombinations = 10
        NumberInpChannels = 11
        AccWidth = 12
        HistogramEnable = 13
        ReadData = 15

    type ChannelDict = Mapping[int, list[int] | int]

    def __init__(self, wb: Wishbone, base_address: int = 0x80007000):
        self.wb = wb
        self.base_address = base_address

        module_name = self.wb.read(
            self.base_address + self.Reg.Module).to_bytes(4, 'big')
        assert module_name == b'comb', ("Connected to a module other than combinations."
                                        "Ensure that you have connected the correct Wishbone interface to your combinations module in the FPGA.")

        # Fetch bitfile constants from the FPGA
        self.FIFO_depth = self.wb.read(self.base_address + self.Reg.FIFODepth)
        self.combinations_width = self.wb.read(self.base_address + self.Reg.NumberCombinations)
        self.number_of_input_channels = 2**self.wb.read(self.base_address + self.Reg.NumberInpChannels)
        self.acc_width = self.wb.read(self.base_address + self.Reg.AccWidth)
        self.histogram_en = self.wb.read(self.base_address + self.Reg.HistogramEnable)

        # Reset and load default values
        self.reset_FPGA_module()
        self.select_data_source("histogram" if self.histogram_en else "combination")

    def get_combinations_width(self) -> int:
        return self.combinations_width

    def set_config(self, window: int, filter_max: int, filter_min: int):
        # window's width is 64 bits so two 32bit writes required
        self.wb.write(self.base_address + self.Reg.WindowLSB, window & 0xffffffff)
        self.wb.write(self.base_address + self.Reg.WindowMSB, window >> 32)

        self.wb.write(self.base_address + self.Reg.Filter, (filter_max << 16) + filter_min)

    def select_data_source(self, select: str):
        assert select in {"histogram", "combination"}
        if select == "histogram":
            assert self.histogram_en, "The histogram feature is disabled in the bitfile."
            self.wb.write(self.base_address + self.Reg.Select, 2)
            self.select = 2
        elif select == "combination":
            self.wb.write(self.base_address + self.Reg.Select, 1)
            self.select = 1
        else:
            assert False

    def set_capture_enable(self, capture: bool):
        self.wb.write(self.base_address + self.Reg.Capture, 1 if capture else 0)

    def reset_FPGA_module(self):
        self.wb.write(self.base_address + self.Reg.Reset, 1)

    def _assign_channel_indices(self, input_dict: ChannelDict) -> list[int]:

        result_list = [0] * self.number_of_input_channels

        # Check if the keys are in the range from 0 to the number of keys minus one
        if not all(0 <= key < len(input_dict) for key in input_dict):
            raise ValueError(
                f"Keys must be in the range from 0 to {self.combinations_width - 1}.")

        for channel_key, values in input_dict.items():
            assert 0 <= channel_key < self.combinations_width, f"Channel key {
                channel_key} must be in the range[0, {self.combinations_width})."

            def process_value(val):
                assert result_list[val & 0b111111] == 0, f"Repeated value {
                    val} found in the dictionary. Please ensure no repeated channel values."
                result_list[val & 0b111111] = channel_key | (1 << 15)  # key value + enable bit

            if isinstance(values, int):
                process_value(values)
            elif isinstance(values, list):
                for val in values:
                    process_value(val)
            else:
                raise ValueError(
                    "Unsupported type for values in the dictionary. Must be either an integer or a list.")

        return result_list

    # example: {0: 1, 1: [2,3], 2: [-4,4]}
    def set_lut_channels(self, channels: ChannelDict | None = None):
        if channels is None:
            # By default, just pick the first physical inputs
            channels = {i: i + 1 for i in range(self.combinations_width)}

        ch = self._assign_channel_indices(channels)

        ch_ = [(2 << 30) + ((i & 0b111111) << 16) + c for i, c in enumerate(ch)]

        self.wb.burst_write(self.base_address + self.Reg.LUTConfig, ch_, addr_incr=0)

    def get_lut_channels(self) -> dict[int, list[int]]:
        ret = {}
        for i in range(-32, 32):
            self.wb.write(self.base_address + self.Reg.LUTConfig,
                          (0b01 << 30) + ((i & 0b111111) << 16))
            conf = self.wb.read(self.base_address + self.Reg.LUTConfig)
            if conf & (1 << 15):
                ret.setdefault(conf & 0x7FFF, []).append(i)
        return ret

    def read_data(self) -> npt.NDArray[np.uint32]:
        transfer_words = 0
        if self.select == 2:
            # Read the full histogram
            self.wb.write(self.base_address + self.Reg.StartReading, 1)
            transfer_words = 2**self.combinations_width
        elif self.select == 1:
            # Read one FIFO of data at once
            transfer_words = self.FIFO_depth

        data_array = np.zeros(transfer_words, dtype=np.uint32)

        for updated_combs in range(0, transfer_words, self.wb.MAX_BURST_SIZE):
            # Determine the current chunk size
            chunk_size = min(self.wb.MAX_BURST_SIZE, transfer_words - updated_combs)

            # Perform burst read for the current chunk
            data_array[updated_combs:updated_combs +
                       chunk_size] = self.wb.burst_read(
                self.base_address +
                self.Reg.ReadData,
                chunk_size,
                addr_incr=0)

        if self.select == 2:
            if 2**self.acc_width - 1 in data_array:
                raise ValueError("overflow happened in the FIFO in FPGA")
        if self.select == 1:
            if np.any((data_array[1:] & (1 << self.combinations_width)) != 0):
                raise ValueError("overflow happened in the FIFO in FPGA")

            # Filter out all invalid elements, they were added for low data rates
            data_array = data_array[data_array != 0]

        return data_array


if __name__ == '__main__':
    import ok
    import time

    xem = ok.FrontPanel()
    assert xem.OpenBySerial() == xem.NoError

    wb = Wishbone(xem)
    combinations = Combinations(wb)
    width = combinations.get_combinations_width()  # By default: 16

    # Analyze the first 16 physical inputs
    channels = {i: i + 1 for i in range(width)}

    # Configure and start the measurement in histogramming mode
    combinations.set_config(window=3000, filter_max=width, filter_min=0)
    combinations.select_data_source("histogram")
    combinations.set_lut_channels(channels)
    combinations.set_capture_enable(True)

    time.sleep(1)

    # Read back results
    data = combinations.read_data()
    print(sum(data))

    # Re-configure to streaming mode
    combinations.select_data_source("combination")

    time.sleep(1)

    # Read back results
    data = combinations.read_data()
    print(sum(data))
