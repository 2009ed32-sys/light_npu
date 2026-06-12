# MACLane Debug Comparator Plan

## Goal

Full ILA probing of `maccell_data` and `maccell_weight` can be expensive. With the current parameters:

```text
maccell_data   = 8 maccells * 4 lanes * 8 bits = 256 bits
maccell_weight = 8 maccells * 4 lanes * 8 bits = 256 bits
tag/mask/flags = extra control bits
```

A full ILA probe can quickly exceed 500 bits before adding CBUF address, valid/ready, and state signals. The debug module should reduce ILA pressure by checking MACLane placement inside fabric and reporting status to PS through AXI-Lite and fabric interrupt.

## Candidate A: Expected FIFO Compare Mode

This was the first proposed structure.

```text
main.c
  -> calculates expected MACLane packets
  -> pushes expected packets into debug IP through AXI-Lite
  -> starts convcore

CSC output
  -> actual MACLane packet
  -> debug comparator

debug comparator
  -> expected FIFO pop
  -> actual vs expected compare
  -> fail status / snapshot / IRQ
```

### Selected-MACCell FIFO Mode

The lightest first version compares one selected maccell at a time.

Packet width:

```text
tag            32 bits
data_lanes     32 bits  // 4 lanes * 8-bit
weight_lanes   32 bits  // 4 lanes * 8-bit
flags/mask     <=32 bits
total          128-bit aligned
```

AXI-Lite cost:

```text
4 writes per expected packet
```

This is small and easy to implement, but it does not check every maccell in one run unless the test is repeated for each selected maccell.

### All-MACCell FIFO Mode

This compares all maccells in one packet.

Packet width:

```text
data_all       256 bits
weight_all     256 bits
tag/mask/flags extra
total          about 544 to 576 bits
```

AXI-Lite cost:

```text
about 18 writes per expected packet
```

Comparator result:

```text
fail_maccell[7:0]
irq = |fail_maccell
```

Use one fabric interrupt plus a `FAIL_MASK` register instead of eight separate interrupt lines. This tells PS which maccell failed without consuming many interrupt inputs.

### FIFO Mode Pros

- Runs without stopping CSC on every packet.
- Good for longer random regression once the debug IP is stable.
- Can compare all packets automatically.

### FIFO Mode Cons

- Expected FIFO can become wide.
- AXI-Lite writes can become heavy, especially in all-maccell mode.
- main.c must preload enough expected packets before actual packets arrive.
- Expected packet sequence must match actual sequence exactly.

## Candidate B: Single-Step Snapshot Debug Mode

This is the newer proposed structure.

Instead of preloading a large expected FIFO, the debug module snapshots one actual MACLane packet, holds CSC, and lets PS inspect/compare one maccell at a time.

Recommended flow:

```text
1. CSC asserts maccell_in_valid.
2. Debug module snapshots:
     maccell_data
     maccell_weight
     valid_mask
     acc_clear
     acc_last
     tag
3. Debug module asserts debug_hold.
4. debug_hold blocks maccell_ready, so CSC does not advance to the next packet.
5. Debug module asserts packet_ready_irq.
6. PS calculates or already has expected values.
7. PS writes expected data/weight for maccell 0.
8. Debug module compares selected maccell 0.
9. PS repeats for maccell 1..7.
10. Debug module updates CHECKED_MASK and FAIL_MASK.
11. PS writes DEBUG_CONTINUE.
12. Debug module releases debug_hold.
13. CSC proceeds to the next packet.
```

### Required Backpressure

This mode only works if CSC can be stalled while PS is servicing the interrupt.

The debug module should sit on the `maccell_ready` path:

```text
cmac_ready_raw
debug_hold

maccell_ready_to_csc = cmac_ready_raw & !debug_hold
```

If CMAC is not connected yet:

```text
maccell_ready_to_csc = !debug_hold
```

Without `debug_hold`, PS is too slow and will miss later MACLane packets.

### Snapshot Registers

The debug module latches the full actual packet internally:

```text
snapshot_valid_mask[7:0]
snapshot_data[255:0]
snapshot_weight[255:0]
snapshot_acc_clear
snapshot_acc_last
snapshot_tag[31:0]
snapshot_packet_index
```

This is a register snapshot, not an ILA probe. It only captures one packet at a time.

### Per-MACCell Compare

PS writes one expected maccell record:

```text
expected_maccell_idx[2:0]
expected_data_lanes[31:0]
expected_weight_lanes[31:0]
expected_tag[31:0]
expected_flags
```

Debug module extracts actual lanes from the snapshot:

```text
actual_data_lanes   = snapshot_data[expected_maccell_idx]
actual_weight_lanes = snapshot_weight[expected_maccell_idx]
```

Then it compares and updates:

```text
CHECKED_MASK[expected_maccell_idx] = 1
FAIL_MASK[expected_maccell_idx]    = mismatch
```

### Interrupt Strategy

Use one fabric interrupt, not one interrupt per maccell.

Interrupt causes:

```text
PACKET_READY_IRQ  // snapshot captured and CSC is held
FAIL_IRQ          // mismatch detected, optional immediate IRQ
```

Status registers identify the reason:

```text
IRQ_STATUS[0] = packet_ready
IRQ_STATUS[1] = fail_latched
```

This is cleaner than eight interrupt lines. `FAIL_MASK[7:0]` tells which maccell failed.

### Single-Step Mode Pros

- Avoids large expected FIFO.
- AXI-Lite register map stays small.
- PS can inspect one packet precisely.
- Very useful for bring-up and exact MACLane placement debug.
- No need to preload hundreds of expected packets.

### Single-Step Mode Cons

- Very slow.
- Convcore is intentionally paused at every MACLane packet.
- Not suitable for performance testing.
- Requires correct valid/ready backpressure integration.

## Recommended Direction

For current bring-up, prefer Candidate B first:

```text
single-step snapshot debug mode
```

Reason:

- We are still validating CSC to MACLane placement.
- It avoids a large expected FIFO and heavy AXI-Lite preload.
- It gives precise packet-by-packet visibility.
- It can be disabled later for normal operation.

After this mode is stable, add Candidate A as an optional regression mode:

```text
expected FIFO compare mode
```

## Register Map Draft for Single-Step Mode

```text
0x00 CONTROL
     bit 0  enable
     bit 1  clear_status
     bit 2  irq_enable
     bit 3  hold_enable
     bit 4  compare_enable
     bit 5  continue_packet

0x04 STATUS
     bit 0  snapshot_valid
     bit 1  debug_hold
     bit 2  pass_latched
     bit 3  fail_latched
     bit 4  all_maccells_checked
     bit 5  actual_seen

0x08 SELECT
     bit [2:0] selected_maccell_idx

0x0C PACKET_INDEX
     current snapshot packet index

0x10 SNAPSHOT_TAG

0x14 SNAPSHOT_FLAGS
     bit 0 acc_clear
     bit 1 acc_last
     bit [15:8] valid_mask

0x18 EXPECTED_DATA
     selected maccell expected 4-lane data

0x1C EXPECTED_WEIGHT
     selected maccell expected 4-lane weight

0x20 EXPECTED_TAG

0x24 EXPECTED_FLAGS
     bit 0 acc_clear
     bit 1 acc_last

0x28 COMPARE
     write 1 to compare selected maccell

0x2C CHECKED_MASK
     bit per maccell

0x30 FAIL_MASK
     bit per failed maccell

0x34 ACTUAL_DATA
     selected maccell actual 4-lane data

0x38 ACTUAL_WEIGHT
     selected maccell actual 4-lane weight

0x3C IRQ_STATUS
     bit 0 packet_ready
     bit 1 fail

0x40 IRQ_CLEAR
     write 1 to clear IRQ latch

0x44 DEBUG_CONTINUE
     write 1 to release debug_hold and advance to next packet
```

## main.c Flow for Single-Step Mode

```text
1. Configure debug module:
     enable=1
     irq_enable=1
     hold_enable=1
     compare_enable=1
2. Start convcore/CDMA/CSC.
3. Wait for packet_ready interrupt.
4. Read PACKET_INDEX, SNAPSHOT_TAG, SNAPSHOT_FLAGS.
5. For maccell_idx = 0..7:
     write SELECT
     calculate expected data/weight for that maccell
     write EXPECTED_DATA
     write EXPECTED_WEIGHT
     write EXPECTED_TAG / EXPECTED_FLAGS
     write COMPARE=1
6. Read FAIL_MASK.
7. If FAIL_MASK != 0:
     read ACTUAL_DATA/WEIGHT for failing index
     print mismatch
8. Write DEBUG_CONTINUE=1.
9. Repeat until convcore done or test limit reached.
```

## Implementation Notes

- `maccell_in_valid` can be used as the packet-ready source.
- The debug module should latch the entire actual packet on `maccell_in_valid && maccell_ready_to_csc`.
- In debug mode, `debug_hold` should prevent the next packet from being accepted.
- In normal mode, debug module should pass ready through and avoid changing datapath behavior.
- Keep ILA probes limited to control signals:

```text
maccell_in_valid
maccell_ready_to_csc
debug_hold
packet_ready_irq
fail_latched
fail_mask
packet_index
```

## Suggested Implementation Order

1. Implement `debug_maclane_compare.sv` with single-step snapshot mode.
2. Add AXI-Lite register interface.
3. Add snapshot registers and selected-maccell extractor.
4. Add compare logic and `CHECKED_MASK` / `FAIL_MASK`.
5. Add `debug_hold` and IRQ outputs.
6. Write unit TB for snapshot, compare, fail mask, and continue behavior.
7. Integrate with convcore only after unit TB passes.
8. Later, consider adding expected FIFO mode for faster regression.

