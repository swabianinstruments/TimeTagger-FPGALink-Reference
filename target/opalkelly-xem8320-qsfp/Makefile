SHELL := /bin/bash
PROJECT_NAME := xem8320-timetagger-fpgalink-reference

.PHONY : all project synthesis implementation clean lint

all : implementation

project : $(PROJECT_NAME).xpr

synthesis : project
	 vivado -mode tcl -source scripts/synthesis.tcl

implementation : synthesis
	 vivado -mode tcl -source scripts/implementation.tcl

lint : project
	 vivado -mode batch -source scripts/linter.tcl
	 python3 ../../scripts/parse_lint_txt.py qsfp_prj_lint_log.txt

clean :
	rm -rf $(filter-out Makefile constr hdl scripts config host README.md . .., $(wildcard *) $(wildcard .*)) .Xil

$(PROJECT_NAME).xpr:
	 vivado -mode tcl -source scripts/create_project.tcl
