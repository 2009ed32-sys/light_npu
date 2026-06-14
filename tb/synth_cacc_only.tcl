set root_dir "C:/Users/2009e/npusources"
set run_tag [clock format [clock seconds] -format "%Y%m%d_%H%M%S"]
set proj_dir "$root_dir/.synth_cacc_only_$run_tag"

create_project synth_cacc_only $proj_dir -part xc7z020clg400-1
set_property target_language Verilog [current_project]

add_files -norecurse [list \
    "$root_dir/apb_top/cacc_delivery_fifo.sv" \
    "$root_dir/apb_top/cacc_rd_ptr.sv" \
    "$root_dir/apb_top/cacc.sv" \
]
set_property file_type SystemVerilog [get_files *.sv]
set_property top cacc [current_fileset]
update_compile_order -fileset sources_1

launch_runs synth_1 -jobs 8
wait_on_run synth_1

open_run synth_1
report_utilization -file "$proj_dir/cacc_util.rpt"
report_utilization -hierarchical -file "$proj_dir/cacc_util_hier.rpt"
report_synth -file "$proj_dir/cacc_synth.rpt"

puts "CACC_SYNTH_PROJECT=$proj_dir"
puts "CACC_UTIL_REPORT=$proj_dir/cacc_util.rpt"
puts "CACC_UTIL_HIER_REPORT=$proj_dir/cacc_util_hier.rpt"
