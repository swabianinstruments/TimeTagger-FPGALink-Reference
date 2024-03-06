/**
 * This file is part of the Time Tagger software defined digital data
 * acquisition FPGA-link reference design.
 *
 * Copyright (C) 2022-2024 Swabian Instruments, All Rights Reserved
 *
 * Authors:
 * - 2024 Ehsan Jokar <ehsan@swabianinstruments.com>
 *
 * This file is provided under the terms and conditions of the BSD 3-Clause
 * license, accessible under https://opensource.org/licenses/BSD-3-Clause.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

package pkg_base_address;

    /*
    If you want to add new modules that require the Wishbone interface, you'll need to:

    1. Define base addresses and depths: Specify the starting memory address (base address)
    and memory size (depth) for each of your new modules. This allocates the necessary memory
    spaces for your modules to use with the Wishbone interface.

    2. To make connecting modules and selecting signals easier, please give distinct and descriptive
    names to the new modules using the Wishbone interface. Add these names to the modules enum
    defined in this file.

    3. Add the created base addresses and depths into base_address_space and memory_space, respectively.

    Ensure that the added name, base address, and memory size are in the correct order.
    */

    localparam DEFAULT_DEPTH = 256;

    localparam base_address_top_module = 32'h00000000;
    localparam memory_size_top_module = DEFAULT_DEPTH;

    localparam base_address_sfpp_i2c = 32'h80000200;
    localparam memory_size_sfpp_i2c = DEFAULT_DEPTH;

    localparam base_address_ethernet = 32'h80001500;
    localparam memory_size_ethernet = DEFAULT_DEPTH;

    localparam base_address_statistics = 32'h80005100;
    localparam memory_size_statistics = DEFAULT_DEPTH;

    localparam base_address_user_design = 32'h80005200;
    localparam memory_size_user_design = 512;

    localparam base_address_histogram = 32'h80006000;
    localparam memory_size_histogram = DEFAULT_DEPTH;

    enum {
        top_module,
        i2c_master,
        ethernet,
        statistics,
        user_sample,
        histogram
    } wb_instances;

    localparam WB_SIZE = wb_instances.num();

    localparam integer base_address[WB_SIZE] = '{
        base_address_top_module,
        base_address_sfpp_i2c,
        base_address_ethernet,
        base_address_statistics,
        base_address_user_design,
        base_address_histogram
    };

    localparam integer memory_space[WB_SIZE] = '{
        memory_size_top_module,
        memory_size_sfpp_i2c,
        memory_size_ethernet,
        memory_size_statistics,
        memory_size_user_design,
        memory_size_histogram
    };

endpackage
