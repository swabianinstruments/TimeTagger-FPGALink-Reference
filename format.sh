#!/usr/bin/env sh

cd $(dirname "$0")

find test/ hdl/ tb/ target/*/hdl/ -iname "*.sv" -print0 | xargs -0 -n1 verible-verilog-format --flagfile .verible-verilog-format.conf --inplace
find host/ target/*/host/ scripts/ test/*.py -iname "*.py" -print0 | xargs -0 autopep8 --exit-code -i
