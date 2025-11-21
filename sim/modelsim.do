// ModelSim run script for Open-GPU scaffold
// Usage: in the `sim` directory run `vsim -do modelsim.do` or execute the commands below.

vlib work
// compile RTL
vlog -sv ../rtl/top.sv
// compile testbench
vlog -sv tb_top.sv
// run the testbench (headless)
vsim -c tb_top -do "run 1000ns; quit"
