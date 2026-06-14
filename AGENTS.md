# AGENTS.md

## Project Goal

This repository is for building an NVDLA-inspired NPU, starting with the convolution core. The first implementation target is a simple, deterministic direct-convolution datapath rather than a fully featured NVDLA clone.

## Design Direction

- Do not use `'0` for signals whose bit width is already fixed and obvious, such as 1-bit control signals. Use explicit-width constants such as `1'b0` there. For parameterized vectors, `'0` is allowed and preferred when it clearly means all bits zero.
- `DATA_WIDTH` is expected to be a power of two and at least 32 bits. Use shift-based scaling for byte-address and channel-group calculations.
- Do not use `initial begin` blocks in synthesizable RTL. Put parameter checks and setup-only behavior in testbenches, scripts, or lint rules instead.
- Keep synthesizable RTL files module-scoped: one module per `.sv` file, with the file name matching the module name.
- CDMA load channels derive their word count and last read address from matrix width, matrix height, and channel count instead of taking a precomputed total word count.
- AXI master owns the data/weight BRAMs and fills them from AXI read data. CDMA exposes native BRAM read ports and consumes those BRAMs through block-design wiring.
- `cdma.sv` is the AXI-Lite-controlled integration top. It instantiates `axi_slave_csb_v1_0`, connects CSB configuration registers to `cdma_core`, and exposes only the AXI-Lite slave, native data/weight BRAM read ports, and CBUF write ports.
- `CDMA_CONTROL[0]` starts the data channel and `CDMA_CONTROL[1]` starts the weight channel. `CDMA_STATUS[5:0]` reports weight error/done/busy and data error/done/busy.
- CDMA load channels still expose legacy per-cycle `mem_rd_addr` outputs internally, but the shared AXI transaction controller does not use them and the CDMA top discards them.
- CDMA uses a shared fixed-length AXI transaction controller. It sends `axi_txn_addr` with a one-cycle `axi_init_txn`, advances the address only after `axi_txn_done`, and retries the same address after `axi_error`.
- `AXI_BURST_LEN` must be configured to the same power-of-two value in CDMA and the AXI master. The AXI master always reads the full fixed burst, while CDMA ignores words beyond its configured total.
- `axi_load_start` resets the selected AXI-master-owned BRAM write pointer once per complete data or weight load. It must not be driven for every burst.
- The AXI master is read-only and performs one fixed-length read burst per `m00_axi_init_axi_txn` pulse. Its `m00_axi_txn_done` and `m00_axi_error` outputs are one-cycle result pulses.
- Keep inferred BRAM cores close to vendor-friendly synchronous RAM templates. Put conflict handling in a wrapper around the BRAM core.
- CDMA BRAM reads use a simple ready/request/valid response: CDMA issues reads only when `bram_rd_ready` is high, drives `bram_rd_en` and `bram_rd_addr`, then writes CBUF only when `bram_rd_valid` is asserted.
- For same-address BRAM read/write conflicts, write first and delay the read until the conflicting write has completed.

## Initial Convolution Assumptions

- Single batch
- INT8 activation
- INT8 weight
- INT32 accumulation
- Stride and padding supported
- Dilation disabled or fixed to 1
- Initial channel constraints may be:
  - `input_channel % ATOMIC_C == '0`
  - `output_channel % ATOMIC_K == '0`

Tail-channel masks can be added later.

## Verification

Use Xilinx xsim for testbenches and simulation.

Typical command flow:

```powershell
xvlog -sv <rtl_files> <tb_files>
xelab <tb_top> -s <snapshot_name>
xsim <snapshot_name> -runall
```

When adding a new RTL block, prefer adding a small focused testbench before integrating it into the full convcore.

Recommended verification order:

1. Unit test `cdma`
2. Unit test `cbuf`
3. Unit test `cmac`
4. Unit test `cacc`
5. Unit test `csc`
6. Integrate `csc + cbuf + cmac + cacc`
7. Integrate `cdma`
8. Compare end-to-end direct convolution against a software golden model

## Coding Style

- Keep module interfaces explicit and small.
- When asked to analyze code, focus on the structure and behavior present in the requested files. Do not speculate about integration with other modules unless an explicit connection exists or integration analysis is specifically requested.
- Use parameters for widths and fixed latencies.
- Use `_q` and `_d` suffixes for registered state and next-state signals.
- Use `always_ff` for sequential logic and `always_comb` for combinational logic.
- Prefer clear counters and FSMs over clever compact logic.
- Add comments only for non-obvious timing or alignment behavior.
- Do not add unrelated refactors while implementing a requested block.

## Documentation

Store Markdown design notes directly under `C:\Users\2009e\npusources`.

- Do not create `.md` design notes inside block-specific source directories such as `convcore/`, `axi_master/`, or `tb/`.
- Keep debug-related Markdown plans under the `npusources` root as well, for example `debug_maclane_compare_plan.md`.
- When architecture changes meaningfully, update the relevant root-level Markdown note instead of creating scattered copies in subdirectories.
- For NVDLA documentation questions, prefer checking these references first:
  - https://nvdla.org/hw/v1/ias/unit_description.html
  - https://nvdla.org/hw/v1/hwarch.html
  - https://github.com/nvdla/hw/blob/master/vmod/nvdla/cdma/NV_NVDLA_CDMA_cvt.v
