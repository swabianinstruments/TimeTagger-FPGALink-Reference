# Counter script
#
# This file is part of the Time Tagger software defined digital data
# acquisition FPGA-link reference design.
#
# Copyright (C) 2024 Swabian Instruments, All Rights Reserved
#
# Authors:
# - 2024 Ehsan Jokar <ehsan@swabianinstruments.com>
#
# This file is provided under the terms and conditions of the BSD 3-Clause
# license, accessible under https://opensource.org/licenses/BSD-3-Clause.
#
# SPDX-License-Identifier: BSD-3-Clause

from .ok_wishbone import Wishbone
import numpy as np


class Counter:
    MODULE_REG = 0
    FIFO_DEPTH_REG = 4
    NUM_OF_CHANNELS_REG = 8
    CHANNEL_LUT_DEPTH_REG = 12
    SET_CHANNELS_REG = 16
    WINDOW_SIZE_LSB_REG = 24
    WINDOW_SIZE_MSB_REG = 28
    CONFIG_REG = 32
    READ_DATA_REG = 36
    RESET_FPGA_MODULE_REG = 40
    NUM_DESIRED_CHANNEL_REG = 44

    def __init__(self, wb: Wishbone, capture_size=10000, base_address=0x80006500):
        self.wb = wb
        self.base_address = base_address

        module_name = self.wb.read(self.base_address + self.MODULE_REG).to_bytes(4, 'big')
        assert module_name == b'cntr', ("Connected to a module other than Counter. "
                                        "Ensure that you have connected the correct Wishbone interface to your Counter module inside the FPGA project.")

        self.capture_size = capture_size
        self.fifo_depth = self._get_fifo_depth()
        self.number_of_channels = self._get_number_of_channels()
        self.lut_channels_depth = self._get_lut_channels_depth()
        self.read_length = (self.fifo_depth if self.fifo_depth <= self.wb.MAX_BURST_SIZE
                            else (self.fifo_depth // self.wb.MAX_BURST_SIZE) * self.wb.MAX_BURST_SIZE)

        self.number_of_desired_channels = 1

        # Reset FPGA Counter module
        self.reset_FPGA_module()

    def _get_fifo_depth(self):
        return self.wb.read(self.base_address + self.FIFO_DEPTH_REG)

    def _get_lut_channels_depth(self):
        return self.wb.read(self.base_address + self.CHANNEL_LUT_DEPTH_REG)

    def _get_number_of_channels(self):
        return self.wb.read(self.base_address + self.NUM_OF_CHANNELS_REG)

    def reset_FPGA_module(self):
        self.wb.write(self.base_address + self.RESET_FPGA_MODULE_REG, 1)

        self.data_array = np.full((self.number_of_desired_channels, self.capture_size), np.nan)
        self.remaining_counters_array = []

    def start_measurement(self):
        self.wb.write(self.base_address + self.CONFIG_REG, 1)

    def _assign_channel_indices(self, input_dict):

        result_list = [self.number_of_channels] * self.lut_channels_depth

        # Check if the keys are in the range from 0 to the number of keys minus one
        if not all(0 <= key < len(input_dict) for key in input_dict):
            raise ValueError("Keys must be in the range from 0 to the number of desired channels minus one.")

        for channel_key, values in input_dict.items():
            assert 0 <= channel_key < self.number_of_channels, f"Channel key {channel_key} must be in the range [0, {self.number_of_channels})."

            def process_value(val):

                assert result_list[val &
                                   0b111111] == self.number_of_channels, f"Repeated value {val} found in the dictionary. Please ensure no repeated channel values."

                result_list[val & 0b111111] = channel_key

            if isinstance(values, int):
                process_value(values)
            elif isinstance(values, list):
                for val in values:
                    process_value(val)
            else:
                raise ValueError("Unsupported type for values in the dictionary. Must be either an integer or a list.")

        return result_list, len(input_dict)

    # example: {0: 1, 1: [2,3], 2:[-4,4]}
    def set_lut_channels(self, channels=None):
        if channels is None:
            ch = [
                (i -
                 1) if 0 < i <= self.number_of_channels else self.number_of_channels for i in range(
                    self.lut_channels_depth)]
            self.number_of_desired_channels = self.number_of_channels
        else:
            ch, self.number_of_desired_channels = self._assign_channel_indices(channels)

        # Reset FPGA Counter module
        self.reset_FPGA_module()

        self.wb.write(self.base_address + self.NUM_DESIRED_CHANNEL_REG, self.number_of_desired_channels)
        self.wb.burst_write(self.base_address + self.SET_CHANNELS_REG, ch, 0)

    def get_lut_channels(self):
        def list_to_dict(input_list):
            result_dict = {}
            for index, value in enumerate(input_list):
                if value < self.number_of_channels:
                    if value in result_dict:
                        result_dict[value].append(index)
                    else:
                        result_dict[value] = [index]
            return dict(sorted(result_dict.items()))

        read_list = self.wb.burst_read(self.base_address + self.SET_CHANNELS_REG, self.lut_channels_depth, 0)
        return list_to_dict(read_list)

    def set_window_size(self, window_size: int = 3000000000):  # 1ms by default
        lsb_mask = 0xFFFFFFFF
        lsb = window_size & lsb_mask
        msb = (window_size >> 32) & lsb_mask

        self.wb.write(self.base_address + self.WINDOW_SIZE_LSB_REG, lsb)
        self.wb.write(self.base_address + self.WINDOW_SIZE_MSB_REG, msb)

    def get_window_size(self):
        lsb = self.wb.read(self.base_address + self.WINDOW_SIZE_LSB_REG)
        msb = self.wb.read(self.base_address + self.WINDOW_SIZE_MSB_REG)
        return (lsb + (msb << 32))

    def read_data(self):
        burst_read_data = np.zeros(self.read_length, dtype=np.uint32)
        # Read in chunks until all data is retrieved
        for updated_bins in range(0, self.read_length, self.wb.MAX_BURST_SIZE):
            # Determine the current chunk size
            chunk_size = min(self.wb.MAX_BURST_SIZE, self.read_length - updated_bins)
            # Perform burst read for the current chunk
            rd_data = np.array(self.wb.burst_read(self.base_address + self.READ_DATA_REG, chunk_size, 0))
            burst_read_data[updated_bins:updated_bins + chunk_size] = rd_data

        concat_data = self.remaining_counters_array

        # Filter zero elements (dummy data)
        burst_read_data = burst_read_data[burst_read_data != 0]

        for val in burst_read_data:
            if not (val & 0x80000000):
                missed_data = int(val)
                concat_data = np.concatenate((concat_data, np.full(missed_data, np.nan)))
            else:
                concat_data = np.append(concat_data, (val & 0x7FFFFFFF))

        # Calculate lengths
        added_arrays_len = len(concat_data) // self.number_of_desired_channels
        added_data_len = added_arrays_len * self.number_of_desired_channels

        # Update arrays
        added_data = concat_data[0:added_data_len]
        self.remaining_counters_array = concat_data[added_data_len:]

        # Handle the scenario where the number of missed samples for each channel
        # exceeds the specified self.capture_size.
        if added_arrays_len > self.capture_size:
            # Flush data_array and also make the added data fit into it
            added_arrays_len = self.capture_size
            added_data = added_data[-self.capture_size * self.number_of_desired_channels:]

        self.data_array = np.concatenate((self.data_array[:, added_arrays_len:], np.reshape(
            added_data, (added_arrays_len, self.number_of_desired_channels)).T), axis=1)


if __name__ == '__main__':

    import ok

    xem = ok.FrontPanel()
    xem.OpenBySerial()

    wb = Wishbone(xem)
    counter = Counter(wb, 20000)

    channels = {
        1: list(range(1, 4)),
        0: [6, 7],
        2: -5,
        3: [-8, 8]
    }

    counter.set_lut_channels(channels)
    print(counter.get_lut_channels())
