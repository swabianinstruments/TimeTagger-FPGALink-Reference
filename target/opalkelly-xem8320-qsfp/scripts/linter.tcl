open_project xem8320-qsfp-timetagger-fpgalink-reference

update_compile_order -fileset sources_1

generate_target all [get_ips]

create_ip_run [get_ips clk_core]
launch_runs clk_core_synth_1
wait_on_run clk_core_synth_1

create_ip_run [get_ips qsfpp1_eth_40g_phy]
launch_runs qsfpp1_eth_40g_phy_synth_1
wait_on_run qsfpp1_eth_40g_phy_synth_1

source constr/lint_waivers.xdc

synth_design -top xem8320_reference_qsfp -part xcau25p-ffvb676-2-e -lint -file qsfp_prj_lint_log.txt

exit
