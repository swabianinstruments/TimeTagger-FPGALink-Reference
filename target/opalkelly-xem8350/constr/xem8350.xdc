############################################################################
# XEM8350 - Xilinx constraints file
#
# Pin mappings for the XEM8350.  Use this as a template and comment out 
# the pins that are not used in your design.  (By default, map will fail
# if this file contains constraints for signals not in your design).
#
# Copyright (c) 2004-2019 Opal Kelly Incorporated
############################################################################

set_property CFGBVS GND [current_design]
set_property CONFIG_VOLTAGE 1.8 [current_design]
set_property BITSTREAM.GENERAL.COMPRESS True [current_design]

############################################################################
## FrontPanel Host Interface - Primary
############################################################################
set_property PACKAGE_PIN AM12 [get_ports {okHU[0]}]
set_property PACKAGE_PIN AL13 [get_ports {okHU[1]}]
set_property PACKAGE_PIN AE12 [get_ports {okHU[2]}]
set_property SLEW FAST [get_ports {okHU[*]}]
set_property IOSTANDARD LVCMOS18 [get_ports {okHU[*]}]

set_property PACKAGE_PIN AN13 [get_ports {okUH[0]}]
set_property PACKAGE_PIN AD14 [get_ports {okUH[1]}]
set_property PACKAGE_PIN AD13 [get_ports {okUH[2]}]
set_property PACKAGE_PIN AT15 [get_ports {okUH[3]}]
set_property PACKAGE_PIN AN14 [get_ports {okUH[4]}]
set_property IOSTANDARD LVCMOS18 [get_ports {okUH[*]}]

set_property PACKAGE_PIN AJ13 [get_ports {okUHU[0]}]
set_property PACKAGE_PIN AH13 [get_ports {okUHU[1]}]
set_property PACKAGE_PIN AK12 [get_ports {okUHU[2]}]
set_property PACKAGE_PIN AK13 [get_ports {okUHU[3]}]
set_property PACKAGE_PIN AH12 [get_ports {okUHU[4]}]
set_property PACKAGE_PIN AG12 [get_ports {okUHU[5]}]
set_property PACKAGE_PIN AG15 [get_ports {okUHU[6]}]
set_property PACKAGE_PIN AF15 [get_ports {okUHU[7]}]
set_property PACKAGE_PIN AF13 [get_ports {okUHU[8]}]
set_property PACKAGE_PIN AE13 [get_ports {okUHU[9]}]
set_property PACKAGE_PIN AG14 [get_ports {okUHU[10]}]
set_property PACKAGE_PIN AF14 [get_ports {okUHU[11]}]
set_property PACKAGE_PIN AF12 [get_ports {okUHU[12]}]
set_property PACKAGE_PIN AR15 [get_ports {okUHU[13]}]
set_property PACKAGE_PIN AL12 [get_ports {okUHU[14]}]
set_property PACKAGE_PIN AV12 [get_ports {okUHU[15]}]
set_property PACKAGE_PIN AM14 [get_ports {okUHU[16]}]
set_property PACKAGE_PIN AP15 [get_ports {okUHU[17]}]
set_property PACKAGE_PIN AM15 [get_ports {okUHU[18]}]
set_property PACKAGE_PIN AT14 [get_ports {okUHU[19]}]
set_property PACKAGE_PIN AW14 [get_ports {okUHU[20]}]
set_property PACKAGE_PIN AW15 [get_ports {okUHU[21]}]
set_property PACKAGE_PIN AV16 [get_ports {okUHU[22]}]
set_property PACKAGE_PIN AU15 [get_ports {okUHU[23]}]
set_property PACKAGE_PIN AT12 [get_ports {okUHU[24]}]
set_property PACKAGE_PIN AW16 [get_ports {okUHU[25]}]
set_property PACKAGE_PIN AU14 [get_ports {okUHU[26]}]
set_property PACKAGE_PIN AW13 [get_ports {okUHU[27]}]
set_property PACKAGE_PIN AT13 [get_ports {okUHU[28]}]
set_property PACKAGE_PIN AU12 [get_ports {okUHU[29]}]
set_property PACKAGE_PIN AP13 [get_ports {okUHU[30]}]
set_property PACKAGE_PIN AR12 [get_ports {okUHU[31]}]
set_property SLEW FAST [get_ports {okUHU[*]}]
set_property IOSTANDARD LVCMOS18 [get_ports {okUHU[*]}]

set_property PACKAGE_PIN AE15 [get_ports {okAA}]
set_property IOSTANDARD LVCMOS18 [get_ports {okAA}]


create_clock -name okUH0 -period 9.920 [get_ports {okUH[0]}]

set_input_delay -add_delay -max -clock [get_clocks {okUH0}]  8.000 [get_ports {okUH[*]}]
set_input_delay -add_delay -min -clock [get_clocks {okUH0}] 10.000 [get_ports {okUH[*]}]
set_multicycle_path -setup -from [get_ports {okUH[*]}] 2

set_input_delay -add_delay -max -clock [get_clocks {okUH0}]  8.000 [get_ports {okUHU[*]}]
set_input_delay -add_delay -min -clock [get_clocks {okUH0}]  2.000 [get_ports {okUHU[*]}]
set_multicycle_path -setup -from [get_ports {okUHU[*]}] 2

set_output_delay -add_delay -max -clock [get_clocks {okUH0}]  2.000 [get_ports {okHU[*]}]
set_output_delay -add_delay -min -clock [get_clocks {okUH0}]  -0.500 [get_ports {okHU[*]}]

set_output_delay -add_delay -max -clock [get_clocks {okUH0}]  2.000 [get_ports {okUHU[*]}]
set_output_delay -add_delay -min -clock [get_clocks {okUH0}]  -0.500 [get_ports {okUHU[*]}]

# LEDs #####################################################################
set_property PACKAGE_PIN AK22 [get_ports {led[0]}]
set_property PACKAGE_PIN AM20 [get_ports {led[1]}]
set_property PACKAGE_PIN AL22 [get_ports {led[2]}]
set_property PACKAGE_PIN AL20 [get_ports {led[3]}]
set_property PACKAGE_PIN AK23 [get_ports {led[4]}]
set_property PACKAGE_PIN AJ20 [get_ports {led[5]}]
set_property PACKAGE_PIN AL23 [get_ports {led[6]}]
set_property PACKAGE_PIN AJ21 [get_ports {led[7]}]
set_property IOSTANDARD LVCMOS18 [get_ports {led[*]}]

