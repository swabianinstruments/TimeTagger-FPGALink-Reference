# script to create tt_x vivado project

# Set the reference directory for source file relative paths
set origin_dir "../../"
set target_dir "./"
set frontpanel_dir "/opt/OpalKelly/FrontPanel/FrontPanelHDL/XEM8320-AU25P/Vivado-2021"
set project_name "xem8320-qsfp-timetagger-fpgalink-reference"
set part xcau25p-ffvb676-2-e

# Create project
create_project $project_name . -part $part

# Set the directory path for the new project
set proj_dir [get_property directory [current_project]]

# Set project properties
set obj [current_project]
set_property "default_lib" "xil_defaultlib" $obj
set_property "ip_cache_permissions" "read write" $obj
set_property "ip_output_repo" "$proj_dir/${project_name}.cache/ip" -objects $obj
set_property "part" "$part" $obj
set_property "sim.ip.auto_export_scripts" "1" $obj
set_property "simulator_language" "Verilog" $obj
set_property "xpm_libraries" "XPM_CDC XPM_MEMORY" $obj
set_property "xsim.array_display_limit" "64" $obj
set_property "xsim.trace_limit" "65536" $obj

set files [list \
 "[file normalize "$frontpanel_dir/okBTPipeIn.v"]"\
 "[file normalize "$frontpanel_dir/okBTPipeOut.v"]"\
 "[file normalize "$frontpanel_dir/okCoreHarness.v"]"\
 "[file normalize "$frontpanel_dir/okLibrary.v"]"\
 "[file normalize "$frontpanel_dir/okPipeIn.v"]"\
 "[file normalize "$frontpanel_dir/okPipeOut.v"]"\
 "[file normalize "$frontpanel_dir/okRegisterBridge.v"]"\
 "[file normalize "$frontpanel_dir/okTriggerIn.v"]"\
 "[file normalize "$frontpanel_dir/okTriggerOut.v"]"\
 "[file normalize "$frontpanel_dir/okWireIn.v"]"\
 "[file normalize "$frontpanel_dir/okWireOut.v"]"\
 "[file normalize "$target_dir/hdl/xem8320_reference_qsfp.sv"]"\
 "[file normalize "$target_dir/hdl/sfpp1_eth_10g_axis.sv"]"\
 "[file normalize "$origin_dir/hdl/eth_axis_fcs_checker_128b.sv"]"\
 "[file normalize "$origin_dir/hdl/wb_interface.sv"]"\
 "[file normalize "$origin_dir/hdl/wb_pipe_bridge.sv"]"\
 "[file normalize "$origin_dir/hdl/xgmii_axis_bridge.sv"]"\
 "[file normalize "$origin_dir/hdl/xgmii_axis_bridge_rx_64b.sv"]"\
 "[file normalize "$origin_dir/hdl/xgmii_axis_bridge_tx_64b.sv"]"\
 "[file normalize "$origin_dir/hdl/data_channel.sv"]"\
 "[file normalize "$origin_dir/hdl/header_detacher.sv"]"\
 "[file normalize "$origin_dir/hdl/header_parser.sv"]"\
 "[file normalize "$origin_dir/hdl/user_sample.sv"]"\
 "[file normalize "$origin_dir/hdl/statistics_wb.sv"]"\
 "[file normalize "$origin_dir/hdl/tag_converter.sv"]"\
 "[file normalize "$origin_dir/gen_srcs/eth_crc_128b_comb.v"]"\
 "[file normalize "$origin_dir/3rdparty/verilog-ethernet/rtl/eth_phy_10g.v"]"\
 "[file normalize "$origin_dir/3rdparty/verilog-ethernet/rtl/eth_phy_10g_rx.v"]"\
 "[file normalize "$origin_dir/3rdparty/verilog-ethernet/rtl/eth_phy_10g_rx_if.v"]"\
 "[file normalize "$origin_dir/3rdparty/verilog-ethernet/rtl/eth_phy_10g_rx_frame_sync.v"]"\
 "[file normalize "$origin_dir/3rdparty/verilog-ethernet/rtl/eth_phy_10g_rx_ber_mon.v"]"\
 "[file normalize "$origin_dir/3rdparty/verilog-ethernet/rtl/eth_phy_10g_rx_watchdog.v"]"\
 "[file normalize "$origin_dir/3rdparty/verilog-ethernet/rtl/eth_phy_10g_tx.v"]"\
 "[file normalize "$origin_dir/3rdparty/verilog-ethernet/rtl/eth_phy_10g_tx_if.v"]"\
 "[file normalize "$origin_dir/3rdparty/verilog-ethernet/rtl/xgmii_baser_dec_64.v"]"\
 "[file normalize "$origin_dir/3rdparty/verilog-ethernet/rtl/xgmii_baser_enc_64.v"]"\
 "[file normalize "$origin_dir/3rdparty/verilog-ethernet/rtl/lfsr.v"]"\
 "[file normalize "$origin_dir/3rdparty/verilog-ethernet/lib/axis/rtl/sync_reset.v"]"\
 "[file normalize "$origin_dir/3rdparty/verilog-ethernet/lib/axis/rtl/axis_adapter.v"]"\
 "[file normalize "$origin_dir/3rdparty/verilog-ethernet/lib/axis/rtl/axis_async_fifo.v"]"\
 "[file normalize "$origin_dir/3rdparty/verilog-ethernet/lib/axis/rtl/axis_fifo.v"]"\
 "[file normalize "$origin_dir/3rdparty/i2c/rtl/verilog/i2c_master_top.v"]"\
 "[file normalize "$origin_dir/3rdparty/i2c/rtl/verilog/i2c_master_byte_ctrl.v"]"\
 "[file normalize "$origin_dir/3rdparty/i2c/rtl/verilog/i2c_master_bit_ctrl.v"]"\
]

# sources_1 fileset ###########################################################
if {[string equal [get_filesets -quiet sources_1] ""]} {
  create_fileset -srcset sources_1
}

set obj [get_filesets sources_1]
add_files -norecurse -fileset $obj $files
source "$target_dir/scripts/sfpp1_eth_10g_gth.tcl"
set_property "top" "xem8320_reference_qsfp" $obj

# constrs_1 fileset ###########################################################
if {[string equal [get_filesets -quiet constrs_1] ""]} {
  create_fileset -constrset constrs_1
}

# Set 'constrs_1' fileset object
set files [list \
 "[file normalize "$target_dir/constr/xem8320.xdc"]"\
 "[file normalize "$target_dir/constr/loc_constr.xdc"]"\
]
set obj [get_filesets constrs_1]
add_files -norecurse -fileset $obj $files

set files_obj [get_files -of_objects [get_filesets constrs_1] "$files"]
set_property "file_type" "XDC" $files_obj

# sim_1 fileset ###############################################################
if {[string equal [get_filesets -quiet sim_1] ""]} {
  create_fileset -simset sim_1
}

# Set 'sim_1' fileset object
set obj [get_filesets sim_1]

# Set 'sim_1' fileset properties
set obj [get_filesets sim_1]
set_property "top" "xem8320_reference_qsfp" $obj
set_property "transport_int_delay" "0" $obj
set_property "transport_path_delay" "0" $obj
set_property "xelab.nosort" "1" $obj
set_property "xelab.unifast" "" $obj

# create synth_1 run ##########################################################
if {[string equal [get_runs -quiet synth_1] ""]} {
  create_run -name synth_1 -part $part -flow {Vivado Synthesis 2022} -strategy "Vivado Synthesis Defaults" -constrset constrs_1
} else {
  set_property strategy "Vivado Synthesis Defaults" [get_runs synth_1]
  set_property flow "Vivado Synthesis 2022" [get_runs synth_1]
}
set obj [get_runs synth_1]
set_property "part" "$part" $obj

# set the current synth run
current_run -synthesis [get_runs synth_1]

# create impl_1 run ###########################################################
if {[string equal [get_runs -quiet impl_1] ""]} {
  create_run -name impl_1 -part $part -flow {Vivado Implementation 2022} -strategy "Vivado Implementation Defaults" -constrset constrs_1 -parent_run synth_1
} else {
  set_property strategy "Vivado Implementation Defaults" [get_runs impl_1]
  set_property flow "Vivado Implementation 2022" [get_runs impl_1]
}
set obj [get_runs impl_1]
set_property "part" "$part" $obj
#set_property "steps.opt_design.args.directive" "Explore" $obj
#set_property "steps.place_design.args.directive" "Explore" $obj
#set_property "steps.phys_opt_design.is_enabled" "1" $obj
#set_property "steps.phys_opt_design.args.directive" "Explore" $obj
#set_property "steps.route_design.args.directive" "Explore" $obj
set_property -name {steps.route_design.args.more options} -value {-tns_cleanup} -objects $obj
#set_property "steps.post_route_phys_opt_design.is_enabled" "1" $obj
#set_property "steps.post_route_phys_opt_design.args.directive" "Explore" $obj
set_property "steps.write_bitstream.args.readback_file" "0" $obj
set_property "steps.write_bitstream.args.verbose" "0" $obj

# set the current impl run
current_run -implementation [get_runs impl_1]

puts "Successfully created project ${project_name}!"
exit
