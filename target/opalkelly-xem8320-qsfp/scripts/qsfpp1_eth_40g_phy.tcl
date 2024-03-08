# Check the Vivado Version

set scripts_vivado_version 2023.1
set current_vivado_version [version -short]

if { [string first $scripts_vivado_version $current_vivado_version] == -1 } {
  catch {common::send_msg_id "IPS_TCL-100" "ERROR" "This script was generated using Vivado <$scripts_vivado_version> and is being run in <$current_vivado_version> of Vivado. Please run the script in Vivado <$scripts_vivado_version> then open the design in Vivado <$current_vivado_version>. Upgrade the design by running \"Tools => Report => Report IP Status...\", then run write_ip_tcl to create an updated script."}
  return 1
}

# Base IP core configuration

set base_name {qsfpp1_eth_40g_phy}

set freerun_freq {100.8}
set refclk_freq {156.25}

set gt_type {GTY}
set gt_quad {Quad_X0Y0}
set gt_lane1_loc {X0Y0}
set gt_lane2_loc {X0Y1}
set gt_lane3_loc {X0Y2}
set gt_lane4_loc {X0Y3}

# Generate IP core

set config [dict create]

dict set config CORE {Ethernet PCS/PMA}
dict set config DATA_PATH_INTERFACE {MII}
dict set config BASE_R_KR {BASE-R}
dict set config INCLUDE_USER_FIFO {0}
dict set config GT_LOCATION {1}
dict set config GT_TYPE $gt_type
dict set config GT_DRP_CLK $freerun_freq
dict set config GT_REF_CLK_FREQ $refclk_freq
dict set config GT_GROUP_SELECT $gt_quad
dict set config LANE1_GT_LOC $gt_lane1_loc
dict set config LANE2_GT_LOC $gt_lane2_loc
dict set config LANE3_GT_LOC $gt_lane3_loc
dict set config LANE4_GT_LOC $gt_lane4_loc
dict set config ENABLE_PIPELINE_REG {1}
dict set config ADD_GT_CNTRL_STS_PORTS {0}
dict set config INCLUDE_SHARED_LOGIC {1}

create_ip \
    -name l_ethernet \
    -vendor xilinx.com \
    -library ip \
    -version 3.3  \
    -module_name $base_name

set ip [get_ips $base_name]

set config_list {}
dict for {name value} $config {
    lappend config_list "CONFIG.${name}" $value
}
set_property -dict $config_list $ip

# Now, generate an example project for the generated core, which will contain
# HDL sources to be included in our design.

# open_example_project -force -in_process -dir ./ [get_ips $base_name]
# puts [current_project]
# close_project
# puts [current_project]
# set exdes_dir "./${base_name}_ex"

# # The generated files have an incorrect QPLL0REFCLKSEL value inserted in the
# # common wrapper. We fix it here:
# set f_common_wrapper "$exdes_dir/imports/${base_name}_common_wrapper.v"
# set f_common_wrapper_m "$exdes_dir/imports/${base_name}_common_wrapper_fixed.v"
# set f_in [open $f_common_wrapper r]
# set f_out [open $f_common_wrapper_m w]
# while {[gets $f_in line] != -1} {
#     set line [string map {"QPLL0REFCLKSEL(3'b001)" "QPLL0REFCLKSEL(3'b101)"} $line]
#     puts $f_out $line
# }
# close $f_in
# close $f_out

# # Finally, we can add the required files from the example design to our project
# # sources:
# set obj [get_filesets sources_1]
# add_files -norecurse -fileset $obj [list \
#     "[file normalize "$exdes_dir/imports/${base_name}_common_wrapper_fixed.v"]"\
#     "[file normalize "$exdes_dir/imports/${base_name}_reset_wrapper.v"]"\
#     "[file normalize "$exdes_dir/imports/${base_name}_gt_gtye4_common_wrapper.v"]"\
#     "[file normalize "$exdes_dir/imports/gtwizard_ultrascale_v1_7_gtye4_common.v"]"\
# ]
