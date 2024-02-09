############################################################################
# SFP+ 1 (BANK 226)
# B226 MGTHTXP3

# B226 MGTHRXP3
set_property PACKAGE_PIN M2 [get_ports sfpp1_rx_p]
set_property PACKAGE_PIN M1 [get_ports sfpp1_rx_n]
set_property PACKAGE_PIN N5 [get_ports sfpp1_tx_p]
set_property PACKAGE_PIN N4 [get_ports sfpp1_tx_n]

# B226 MGTREFCLK0
set_property PACKAGE_PIN P7 [get_ports sfpp_mgtrefclk_p]

set_property PACKAGE_PIN P6 [get_ports sfpp_mgtrefclk_n]

create_clock -period 8 -name sfpp_mgtrefclk [get_ports sfpp_mgtrefclk_p]


############################################################################
# SFP+ logic (BANK 87) -> 3v3
# This runs at the Voltage of SYZYGY Port D
# So set "XEM8320_SMARTVIO_MODE" to hybrid (0x01)
# and "XEM8320_VIO2_VOLTAGE" to "330"
set_property IOSTANDARD LVCMOS33 [get_ports sfpp1_i2c_sda]
set_property PACKAGE_PIN B12 [get_ports sfpp1_i2c_sda]
set_property IOSTANDARD LVCMOS33 [get_ports sfpp1_i2c_scl]
set_property PACKAGE_PIN C12 [get_ports sfpp1_i2c_scl]

set_property IOSTANDARD LVCMOS33 [get_ports sfpp1_rs0]
set_property PACKAGE_PIN D13 [get_ports sfpp1_rs0]
set_property IOSTANDARD LVCMOS33 [get_ports sfpp1_rs1]
set_property PACKAGE_PIN E12 [get_ports sfpp1_rs1]
set_property IOSTANDARD LVCMOS33 [get_ports sfpp1_mod_abs]
set_property PACKAGE_PIN D14 [get_ports sfpp1_mod_abs]
set_property IOSTANDARD LVCMOS33 [get_ports sfpp1_rc_los]
set_property PACKAGE_PIN E13 [get_ports sfpp1_rc_los]
set_property IOSTANDARD LVCMOS33 [get_ports sfpp1_tx_disable]
set_property PACKAGE_PIN C13 [get_ports sfpp1_tx_disable]
set_property IOSTANDARD LVCMOS33 [get_ports sfpp1_tx_fault]
set_property PACKAGE_PIN C14 [get_ports sfpp1_tx_fault]
