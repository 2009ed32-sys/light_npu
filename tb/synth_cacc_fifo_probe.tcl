set root_dir "C:/Users/2009e/npusources"
set run_tag [clock format [clock seconds] -format "%Y%m%d_%H%M%S"]
set proj_dir "$root_dir/.synth_cacc_fifo_probe_$run_tag"

create_project synth_cacc_fifo_probe $proj_dir -part xc7z020clg400-1
set_property target_language Verilog [current_project]

add_files -norecurse [list \
    "$root_dir/apb_top/cacc_delivery_fifo.sv" \
    "$root_dir/tb/cacc_fifo_synth_probe.sv" \
]
set_property file_type SystemVerilog [get_files *.sv]
set_property top cacc_fifo_synth_probe [current_fileset]
update_compile_order -fileset sources_1

launch_runs synth_1 -jobs 8
wait_on_run synth_1

open_run synth_1
report_utilization -file "$proj_dir/cacc_fifo_probe_util.rpt"
report_utilization -hierarchical -file "$proj_dir/cacc_fifo_probe_util_hier.rpt"

puts "CACC_FIFO_PROBE_PROJECT=$proj_dir"
puts "CACC_FIFO_PROBE_UTIL_REPORT=$proj_dir/cacc_fifo_probe_util.rpt"
puts "CACC_FIFO_PROBE_UTIL_HIER_REPORT=$proj_dir/cacc_fifo_probe_util_hier.rpt"
