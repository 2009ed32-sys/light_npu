# CACC Output Layout And Padding Plan

## Purpose

This note records the current decision for CACC output addressing and the
future modification plan around NVDLA-style line/surface stride and zero
padding.

The important distinction is:

- CACC line/surface stride controls output memory layout.
- CDMA/CSC zero padding controls convolution input padding values.

These two should not be mixed.

## NVDLA References Checked

Official documentation:

- `D_LINE_STRIDE`: line stride of output cube
- `D_SURF_STRIDE`: surface stride of output cube
- `D_DATAOUT_MAP`: whether output cube is line packed or surface packed
- `D_ZERO_PADDING`: left/right/top/bottom padding size
- `D_ZERO_PADDING_VALUE`: padding value

Reference:

- https://nvdla.org/hw/v1/hwarch.html

Official GitHub RTL checked:

- https://github.com/nvdla/hw/blob/master/vmod/nvdla/cdma/NV_NVDLA_CDMA_cvt.v

In `NV_NVDLA_CDMA_cvt.v`, `reg2dp_pad_value` is latched into
`cfg_pad_value`, and padding-masked data lanes select `cfg_pad_value` instead
of the converted input data. Therefore `D_ZERO_PADDING_VALUE` is the fill value
for convolution padding regions, not output memory alignment padding.

## Current Local Register Map

Current compact APB CACC map in `apb_top/apb3_slave.sv`:

```text
0x54 CACC_S_STATUS
0x58 CACC_D_OP_ENABLE
0x5c CACC_D_DATAOUT_SIZE_0   [15:0] width, [31:16] height
0x60 CACC_D_DATAOUT_SIZE_1   output channels
0x64 CACC_D_DATAOUT_ADDR
0x68 CACC_D_LINE_STRIDE
0x6c CACC_D_SURF_STRIDE
0x70 CACC_D_DATAOUT_MAP
```

Current status convention:

```text
CACC_S_STATUS[0] = ready
CACC_S_STATUS[1] = busy
CACC_S_STATUS[2] = done
CACC_S_STATUS[3] = error
```

Current control convention:

```text
CACC_D_OP_ENABLE[0] = op_start pulse
CACC_D_OP_ENABLE[1] = op_enable level
```

## Output Addressing Direction

Initial implementation should assume a surface/cube output layout.

Address formula:

```text
output_addr =
    D_DATAOUT_ADDR
  + surface_idx * D_SURF_STRIDE
  + y           * D_LINE_STRIDE
  + x
```

For the packed case:

```text
D_LINE_STRIDE = output_width
D_SURF_STRIDE = output_width * output_height
```

If output rows or surfaces need alignment padding later, software can program
larger stride values without changing the core addressing rule.

## CACC Implementation Plan

1. Keep current CACC shell handshake stable.

   CMAC already provides:

   ```text
   prepare_valid
   prepare_read
   prepare_mask
   prepare_acc_clear
   prepare_acc_last
   psum_valid
   psum_ready
   psum_data
   psum_mask
   psum_acc_clear
   psum_acc_last
   ```

2. Add an output-position counter inside CACC.

   Track at least:

   ```text
   x
   y
   surface_idx
   ```

   Do not use debug `tag` as output position metadata.

3. Add CACC output address generator.

   Use the formula above and latch generated addresses around the CMAC prepare
   event. `prepare_valid` is the earliest useful hint that the final psum for an
   output position is coming.

4. Add accumulator storage.

   Initial version can be simple:

   ```text
   if acc_clear:
       accumulated_value = psum_data
   else:
       accumulated_value = previous_value + psum_data
   ```

   Later version can use BRAM when partial sums must survive across multiple
   CMAC passes.

5. Add output write or downstream stream.

   First practical target:

   ```text
   CACC final psum -> debug/APB-visible capture or simple output buffer
   ```

   Later target:

   ```text
   CACC final psum -> SDP
   ```

6. Add non-packed layout tests.

   Verify:

   ```text
   D_LINE_STRIDE > output_width
   D_SURF_STRIDE > output_width * output_height
   ```

   Expected behavior: output address skips padding/alignment space.

7. Add true convolution padding later in CDMA/CSC.

   `D_ZERO_PADDING` and `D_ZERO_PADDING_VALUE` belong on the input-window side.
   When padding is enabled, CSC/CDMA should provide padded input values where
   the convolution window falls outside the valid input region.

## Near-Term Verification Plan

1. Unit test CACC handshake only.
2. Unit test packed address generation.
3. Unit test non-packed line stride.
4. Unit test non-packed surface stride.
5. Integrate `CSC + CMAC + CACC` and compare psum sequence.
6. Run `apb_top` smoke test after source update/repackage in Vivado.

## Design Rules

- Use synchronous reset.
- Do not use `tag` as functional metadata.
- Keep APB register addresses word-aligned.
- Keep CACC addressing based on explicit counters and CSB/APB config.
- Treat NVDLA docs as guidance, not a requirement to clone every register.
