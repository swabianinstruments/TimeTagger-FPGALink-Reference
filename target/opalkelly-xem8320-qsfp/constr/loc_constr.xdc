############################################################################
# QSFP Port E
set_property PACKAGE_PIN AF2 [get_ports {qsfpp1_rx_p[0]}]
set_property PACKAGE_PIN AF1 [get_ports {qsfpp1_rx_n[0]}]
set_property PACKAGE_PIN AF7 [get_ports {qsfpp1_tx_p[0]}]
set_property PACKAGE_PIN AF6 [get_ports {qsfpp1_tx_n[0]}]
set_property PACKAGE_PIN AE4 [get_ports {qsfpp1_rx_p[1]}]
set_property PACKAGE_PIN AE3 [get_ports {qsfpp1_rx_n[1]}]
set_property PACKAGE_PIN AE9 [get_ports {qsfpp1_tx_p[1]}]
set_property PACKAGE_PIN AE8 [get_ports {qsfpp1_tx_n[1]}]
set_property PACKAGE_PIN AD2 [get_ports {qsfpp1_rx_p[2]}]
set_property PACKAGE_PIN AD1 [get_ports {qsfpp1_rx_n[2]}]
set_property PACKAGE_PIN AD7 [get_ports {qsfpp1_tx_p[2]}]
set_property PACKAGE_PIN AD6 [get_ports {qsfpp1_tx_n[2]}]
set_property PACKAGE_PIN AB2 [get_ports {qsfpp1_rx_p[3]}]
set_property PACKAGE_PIN AB1 [get_ports {qsfpp1_rx_n[3]}]
set_property PACKAGE_PIN AC5 [get_ports {qsfpp1_tx_p[3]}]
set_property PACKAGE_PIN AC4 [get_ports {qsfpp1_tx_n[3]}]


set_property PACKAGE_PIN AB6 [get_ports qsfpp1_mgtrefclk_n]
set_property PACKAGE_PIN AB7 [get_ports qsfpp1_mgtrefclk_p]

############################################################################
# QSFP Port E logic
set_property IOSTANDARD LVCMOS33 [get_ports qsfpp1_i2c_sda]
set_property PACKAGE_PIN G9 [get_ports qsfpp1_i2c_sda]
set_property IOSTANDARD LVCMOS33 [get_ports qsfpp1_i2c_scl]
set_property PACKAGE_PIN H11 [get_ports qsfpp1_i2c_scl]

set_property IOSTANDARD LVCMOS33 [get_ports qsfpp1_modsel_b]
set_property PACKAGE_PIN K9 [get_ports qsfpp1_modsel_b]
set_property IOSTANDARD LVCMOS33 [get_ports qsfpp1_reset_b]
set_property PACKAGE_PIN K10 [get_ports qsfpp1_reset_b]
set_property IOSTANDARD LVCMOS33 [get_ports qsfpp1_lp_mode]
set_property PACKAGE_PIN J10 [get_ports qsfpp1_lp_mode]
set_property IOSTANDARD LVCMOS33 [get_ports qsfpp1_modprs_b]
set_property PACKAGE_PIN H9 [get_ports qsfpp1_modprs_b]
set_property IOSTANDARD LVCMOS33 [get_ports qsfpp1_int_b]
set_property PACKAGE_PIN J9 [get_ports qsfpp1_int_b]
# QSFP_THREESTATE is unused & unconnected per default

############################################################################

