open_project xem8320-timetagger-fpgalink-reference.xpr
launch_runs synth_1
wait_on_run synth_1

set fp [open synthesis_result.txt w]
puts $fp [get_property STATUS [get_runs synth_1]]
close $fp

exit
