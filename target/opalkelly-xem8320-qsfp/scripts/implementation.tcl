open_project xem8320-qsfp-timetagger-fpgalink-reference.xpr
launch_runs impl_1 -to_step write_bitstream
wait_on_run impl_1

open_run impl_1
report_timing_summary -delay_type min_max -max_paths 4 -nworst 2 -no_header -path_type short -file timing_report.txt

puts "Generated bitstream for project xem8320-qsfp-timetagger-fpgalink-reference!"
exit
