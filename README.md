# Light NPU

Light NPU is a small FPGA-based convolution accelerator project for a Zynq SoC. The processor system controls the programmable logic through an APB register interface, while the accelerator moves data between DDR and internal buffers using AXI master interfaces.

The current pipeline is organized around the following flow:

```text
PS main.c
  -> APB register control
  -> CDMA DDR read
  -> CBUF data/weight storage
  -> CSC MACLane scheduling
  -> CMAC partial-sum generation
  -> CACC delivery buffering
  -> SDP DDR writeback
  -> PS DDR result check
```

The design focuses on direct convolution. CDMA loads input data and weights from DDR into the banked CBUF, CSC reads the required operands from CBUF and maps them onto MAC lanes, CMAC performs multiply-accumulate operations, CACC collects partial sums, and SDP writes the output data back to DDR.

The main source tree is:

```text
apb_top/      APB register block, convcore integration, CDMA/CBUF/CSC/CMAC/CACC/SDP RTL
axi_master/   AXI read/write master modules
mainc/        Vitis-side C smoke/debug application
tb/           Standalone synthesis and simulation test files
```

The latest verified hardware/software flow uses PS-side C code to prepare DDR input and weight patterns, start the PL accelerator, then compare the DDR output against CPU-computed expected results.
****
