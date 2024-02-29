# Histogram script
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

class Histogram:
    MODULE_REG = 0
    BIN_SIZE_REG = 4
    IS_RUNNING_REG = 8
    CONFIG_REG = 12
    READ_RESET_REQ_REG = 16
    READ_DATA_REG = 20

    def __init__(self, wb: Wishbone, base_address=0x80006000):
        self.wb = wb
        self.base_address = base_address

        module_name = self.wb.read(self.base_address + self.MODULE_REG).to_bytes(4, 'big')
        assert module_name == b'hist', (
        "Connected to a module other than Histogram. "
        "Ensure that you have connected the correct Wishbone interface to your Histogram module inside the FPGA project."
        )

        self.number_of_bins = self._get_bin_size()
        self.data_array = np.zeros(self.number_of_bins, dtype=np.uint64)

        # Reset FPGA histogram module and do some initialization
        self.reset_FPGA_module()

    def _get_bin_size(self):
        return self.wb.read(self.base_address + self.BIN_SIZE_REG)

    def _is_FPGA_module_running(self):
        return self.wb.read(self.base_address + self.IS_RUNNING_REG)

    def reset_FPGA_module(self):
        self.wb.write(self.base_address + self.READ_RESET_REQ_REG, 7)
        self.set_config_flag = 0
        # Storing the result of the previous configuration
        self.prev_data_array = self.data_array
        self.data_array = np.zeros(self.number_of_bins, dtype=np.uint64)


    def set_config(self, start_channel, click_channel, shift=0):

        # When the Histogram module inside the FPGA is active, configuring new settings is restricted.
        # Prior to setting new configurations, it is necessary to retrieve the results from the previous configuration.
        if self._is_FPGA_module_running():
            self.read_data(True)

        # use mask to support both positive and negative channels
        mask = 0b111111  # 6 bits
        wt_data = (start_channel & mask) | ((click_channel & mask) << 6) | ((shift & mask) << 12)

        self.wb.write(self.base_address + self.CONFIG_REG, wt_data)
        self.set_config_flag = 1
        # reset data_array for new measurement
        self.data_array = np.zeros(self.number_of_bins)

    def read_data(self, reset=False):

        # Check whether the config has been set
        if (self.set_config_flag):
            wt_data = 3 if reset else 1
            # send the read request
            self.wb.write(self.base_address + self.READ_RESET_REQ_REG, wt_data)

            # Read in chunks until all data is retrieved
            for updated_bins in range(0, self.number_of_bins, self.wb.MAX_BURST_SIZE):
                # Determine the current chunk size
                chunk_size = min(self.wb.MAX_BURST_SIZE, self.number_of_bins - updated_bins)
                # Perform burst read for the current chunk
                rd_data = np.array(self.wb.burst_read(self.base_address + self.READ_DATA_REG, chunk_size, 0), dtype=np.uint32)
                self.data_array[updated_bins:updated_bins + chunk_size] += rd_data

            if reset:
                self.set_config_flag = 0
                self.prev_data_array = self.data_array

        else:
            print("Warning: No data is abailable to read. Please first set the start and click channels using set_config function to start the measurement.")
