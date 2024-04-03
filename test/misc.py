# Common Test Infrastructure.
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

import tempfile
from pathlib import Path
from cocotb_test.simulator import run


def cocotb_test(dut, test_module, verilog_sources, parameters={}, extra_env={}):
    tests_dir = Path(__file__).parent
    sim_build_dir = tests_dir / "sim_build" / dut

    params_string = "".join([
        f"_{k}-{v}"
        for k, v in parameters.items()
    ])
    run(
        simulator="verilator",
        python_search=[str(tests_dir)],
        verilog_sources=[str(path) for path in verilog_sources],
        toplevel=[dut],
        module=test_module,
        parameters=parameters,
        sim_build=sim_build_dir,

        extra_args=["-Wno-fatal", "--trace-fst", "-Wno-TIMESCALEMOD"],
        # Won't work until https://github.com/cocotb/cocotb/pull/3683 is released
        # Until then, all output will be dump.fst
        test_args=["--trace-file", f"{(sim_build_dir / (dut + params_string)).resolve()}.fst"],
        waves=False,
        extra_env=extra_env,
    )
