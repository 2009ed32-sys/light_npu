set src_dir "C:/Users/2009e/npusources/apb_top"
set out_dir "C:/Users/2009e/npusources/.synth_csc_sg_compare"

file mkdir $out_dir

read_verilog -sv "$src_dir/csc_sg.sv"
synth_design -top csc_sg -part xc7z020clg400-1 -mode out_of_context -flatten_hierarchy none
create_clock -period 20.000 -name clk [get_ports clk]
report_utilization -file "$out_dir/csc_sg_util.rpt"
report_timing_summary -file "$out_dir/csc_sg_timing.rpt"
write_checkpoint -force "$out_dir/csc_sg_synth.dcp"
