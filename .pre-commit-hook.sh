#!/usr/bin/env bash

set -e

cd "$(dirname "$(readlink -f "$0")")"
codespell -s ./*.md hdl/ host/ scripts/ target/*/{hdl,scripts,host,*.md} tb/ test/
find host/ target/*/host/ scripts/ test/*.py -iname "*.py" -print0 | xargs -0 autopep8 --exit-code --diff
find hdl/ tb/ target/*/hdl/ -iname "*.sv" -print0 | xargs -0 -n1 verible-verilog-format --verify --flagfile .verible-verilog-format.conf --inplace
