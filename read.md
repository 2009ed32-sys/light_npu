# Light NPU

Light NPU is a Zynq FPGA based INT8 convolution accelerator project inspired by the NVDLA data path. The design uses the PS to configure the accelerator through an APB register interface, reads input data and weights from DDR through an AXI read master, stores operands in BRAM based internal buffers, performs direct convolution, and writes output data back to DDR through a dedicated AXI write path.

## Current Data Path

```text
Vitis main.c
  -> APB CSB register programming
  -> CDMA AXI DDR read
  -> CBUF data/weight BRAM banks
  -> CSC scheduler and MACLane formatting
  -> CMAC INT8 multiply-accumulate
  -> CACC delivery FIFO
  -> SDP AXI DDR writeback
  -> PS-side DDR output comparison
```

## Main Blocks

- `apb_top/`: Top-level APB controlled NPU integration. It connects the APB register block, convcore, CDMA control, CBUF, CSC, CMAC, CACC, and SDP-side writeback signals.
- `axi_master/`: AXI master source files. The current read-side master is used by CDMA to fetch DDR data and weights. The write-side master is used by SDP to store output data back to DDR.
- `mainc/`: Vitis application support code. It generates or includes test vectors, programs CSB registers, starts CDMA/CSC/CACC/SDP operation, and compares DDR output against CPU-generated expected data.
- `tb/`: Protocol and block-level simulation testbenches for APB, AXI, CDMA/CBUF, SDP writeback, and integrated APB-top smoke testing.
- `vivado_log_check/`: Tcl support for exporting Vivado warning messages so repeated warnings can be classified and reviewed more systematically.

## Current Verification Flow

The current software flow prepares input and weight vectors in DDR, flushes cache, programs the APB register map once for a layer or tile, runs CDMA data and weight load, starts the convolution pipeline, invalidates output DDR, and compares the hardware output with expected values generated from the same test vectors.

The currently used full-layer smoke test targets direct convolution with INT8 packed channels. A 32-bit word contains four signed INT8 lane values, matching the current MACLane grouping.

## 128x128 Verification Direction

For larger images such as `128x128x4` with a `5x5x4` kernel set, the full input does not fit into the current CBUF capacity in one pass. The preferred near-term approach is PS-driven full-width row tiling:

- keep the full output width in each tile,
- reload overlapping input rows between adjacent tiles,
- keep CSC address generation local to the tile,
- update `DATA_SRC_BASE_ADDR`, input height, output height, atomics, and output DDR base for each tile,
- compare the final full DDR output against the Python-generated expected result.

This avoids immediate RTL changes for 2D block scheduling, CDMA gather, CSC global output coordinates, and SDP scatter writeback. A more general hardware block scheduler can be added later if x/y tiling or automatic CBUF refill becomes necessary.

## FPGA-Oriented Design Notes

The design intentionally adapts NVDLA-like concepts to FPGA resources rather than copying the ASIC structure directly. CBUF and delivery storage are mapped to BRAM-friendly structures, CMAC uses FPGA DSP-oriented INT8 multiply-accumulate logic, and control/status behavior is verified through APB register access, simulation, Vitis software, and Vivado ILA when needed.
