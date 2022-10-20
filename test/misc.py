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

    with tempfile.NamedTemporaryFile(prefix="dump_insn_mod_", suffix=".v") as dump_insn_mod:
        dump_insn_mod_name = Path(dump_insn_mod.name).stem
        params_string = "".join([
            f"_{k}-{v}"
            for k, v in parameters.items()
        ])
        dump_insn_mod.write(f"""
            module {dump_insn_mod_name} ();
                initial begin
                    $dumpfile("{(sim_build_dir / (dut + params_string)).resolve()}.fst");
                    $dumpvars(0, {dut});
                end
            endmodule
        """.encode("utf-8"))
        dump_insn_mod.flush()

        verilog_sources += [
            dump_insn_mod.name,
        ]

        run(
            python_search=[str(tests_dir)],
            verilog_sources=[str(path) for path in verilog_sources],
            toplevel=[dut, dump_insn_mod_name],
            module=test_module,
            parameters=parameters,
            sim_build=sim_build_dir,
            plus_args=["-fst"],
            # Don't use the builtin waveform tracer, doesn't allow us to save
            # different wave files for each pytest parameterized fixture run.
            waves=False,
            extra_env=extra_env,
        )
