open_project xem8320-timetagger-fpgalink-reference.xpr

update_compile_order -fileset sources_1

generate_target all [get_ips]

create_ip_run [get_ips clk_core]
launch_runs clk_core_synth_1
wait_on_run clk_core_synth_1

create_ip_run [get_ips sfpp1_eth_10g_gth]
launch_runs sfpp1_eth_10g_gth_synth_1
wait_on_run sfpp1_eth_10g_gth_synth_1

source constr/lint_waivers.xdc

synth_design -top xem8320_reference -part xcau25p-ffvb676-2-e -lint -file sfp_prj_lint_log.txt

exit
