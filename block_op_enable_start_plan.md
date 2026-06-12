# Block op_enable/start Control Plan

## Goal

Convcore 내부 블록을 공통 제어 방식으로 정리한다.

핵심 규칙:

- `*_op_enable`은 해당 블록이 이번 operation에 참여한다는 level 신호다.
- `*_op_start`는 실제 operation을 시작시키는 1-cycle pulse다.
- `*_op_enable`과 `*_op_start`는 분리한다.
- Processor 또는 convcore 내부 controller는 enable된 블록만 start sequence에 포함한다.
- 각 블록은 `op_enable`이 0이면 내부 start를 무시하고 idle 상태를 유지한다.

공통 블록 인터페이스 초안:

```systemverilog
input  logic op_enable;
input  logic op_start;
output logic op_ready;
output logic op_busy;
output logic op_done;
output logic op_error;
```

`op_ready`는 설정값을 받을 준비가 되었거나 start 가능한 상태를 의미한다.

`op_done`은 pulse 또는 sticky status 중 하나로 정해야 한다. 현재 CSB polling 흐름을 고려하면 status register에는 sticky done bit를 두고, 내부 block interface에는 1-cycle done pulse를 쓰는 방향이 좋다.

## Current Sticky Done Policy

Current smoke-test software polls CSB register-map status bits through
AXI-Lite. Therefore, any block completion exposed to software must be sticky
enough for the processor to observe it.

Rules:

```text
1. Internal datapath/controller done pulses may remain 1-cycle pulses.
2. CSB-visible done status bits must be sticky.
3. Sticky done is cleared by reset or by starting/enabling the next operation.
4. CDMA currently keeps data_done/weight_done sticky in CDMA_STATUS.
5. CSC currently keeps op_done sticky until the next op_enable rising edge.
6. Future CMAC/CACC/SDP/PDP status bits should follow the same rule.
```

This matches the NVDLA-style CPU flow more closely: software should observe
completion through stable status/idle state or interrupt, not by racing a
single-cycle done pulse.

## Current CSB Auto-Clear Policy

`CSC_CONTROL[0]` is treated as a software-written start pulse. The CSB slave
auto-clears this bit after accepting a write of `1`, so the CSC block sees a
bounded start request instead of a permanently high start level.

`CSC_CONTROL[1]` is treated as `op_enable`. It must not be auto-cleared together
with the start bit, because CSC prefill/run logic depends on enable remaining
asserted across the operation. If software wants to reload the same operation,
it should explicitly write enable low and then high again.

```text
CSC_CONTROL[0] = op_start pulse, auto-cleared by CSB
CSC_CONTROL[1] = op_enable level, cleared only by software/reset
```

## Register Structure

Convcore 공통 control register를 둔다.

```text
NPU_CONTROL
bit0  npu_start
bit1  npu_abort
bit2  npu_clear_status

OP_ENABLE
bit0  cdma_op_enable
bit1  csc_op_enable
bit2  cmac_op_enable
bit3  cacc_op_enable
bit4  sdp_op_enable
bit5  pdp_op_enable

OP_START
bit0  cdma_op_start
bit1  csc_op_start
bit2  cmac_op_start
bit3  cacc_op_start
bit4  sdp_op_start
bit5  pdp_op_start
```

초기 개발 단계에서는 processor가 `OP_START`를 직접 write할 수 있다.

나중에는 processor가 `NPU_CONTROL.npu_start`만 write하고, convcore 내부 operation controller가 `OP_START` pulse를 순서대로 만들어도 된다.

## Common op_enable Behavior

각 블록은 `op_enable`이 1이 되면 다음 동작을 수행한다.

```text
1. config register 값을 유효한 설정으로 간주한다.
2. 내부 ready 조건을 만든다.
3. 이전 operation의 임시 상태를 clear할 준비를 한다.
4. op_start pulse를 기다린다.
5. op_start가 들어오면 config를 latch하고 busy 상태로 진입한다.
```

`op_enable`이 0이면:

```text
1. op_start를 무시한다.
2. downstream valid를 만들지 않는다.
3. upstream ready는 블록 특성에 따라 0 또는 idle-ready로 둔다.
4. status는 disabled/idle로 유지한다.
```

## CDMA

### Purpose

DDR 또는 외부 memory에 있는 input data와 weight를 AXI master를 통해 읽고, CBUF에 저장한다.

현재는 `CDMA_CONTROL[0] = data_start`, `CDMA_CONTROL[1] = weight_start` 구조다.

변경 방향:

```text
cdma_op_enable
cdma_op_start
```

로 통합한다.

CDMA 내부에는 data load와 weight load phase가 있다. 둘을 하나의 CDMA operation 안에서 순차 실행할 수 있게 한다.

### op_enable Asserted

`cdma_op_enable = 1`이면 CDMA는 다음을 준비한다.

```text
1. DATA source base address register 확인
2. DATA CBUF destination base 확인
3. DATA shape 확인
   - matrix_width
   - matrix_height
   - channel_count
4. WEIGHT source base address register 확인
5. WEIGHT CBUF destination base 확인
6. WEIGHT shape 확인
   - matrix_width
   - matrix_height
   - channel_count
7. AXI master request를 만들 준비
8. CBUF write address generator clear 준비
```

### op_start Pulse

`cdma_op_start`가 들어오면:

```text
1. config 값을 latch한다.
2. data load phase를 시작한다.
3. axi_master_dram에 DATA transaction 정보를 전달한다.
4. AXI stream beat를 받아 CBUF data bank에 저장한다.
5. data load done 이후 weight load phase로 넘어간다.
6. axi_master_dram에 WEIGHT transaction 정보를 전달한다.
7. AXI stream beat를 받아 CBUF weight bank에 저장한다.
8. data와 weight가 모두 완료되면 cdma_done을 올린다.
```

AXI master로 넘겨야 하는 정보:

```text
axi_req_valid
axi_req_ready
axi_req_addr
axi_req_bytes 또는 axi_req_words
axi_req_stream_sel
```

`axi_req_stream_sel`은 data/weight 구분이다.

현재의 `axi_load_start`, `axi_init_txn`, `axi_txn_addr`, `axi_stream_sel`은 이 구조로 정리될 수 있다.

추천 register:

```text
CDMA_DATA_SRC_BASE
CDMA_DATA_DST_BASE
CDMA_DATA_WIDTH
CDMA_DATA_HEIGHT
CDMA_DATA_CHANNELS

CDMA_WEIGHT_SRC_BASE
CDMA_WEIGHT_DST_BASE
CDMA_WEIGHT_WIDTH
CDMA_WEIGHT_HEIGHT
CDMA_WEIGHT_CHANNELS
```

## CSC

### Purpose

CBUF에 저장된 data/weight를 convolution 순서에 맞게 읽고, MACCell/MACLane operand packet으로 배치한다.

CSC는 `op_enable`과 `op_start`의 역할을 확실히 나누는 것이 좋다.

```text
csc_op_enable = scheduler 주소 계산 및 FIFO prefill 시작
csc_op_start  = FIFO pop, CBUF read, MACLane operand 전달 시작
```

즉 CSC는 enable 시점에 이미 필요한 주소 packet을 만들기 시작한다. start는 계산된 packet을 실제 compute path로 흘려보내는 트리거다.

### op_enable Asserted

`csc_op_enable = 1`이면 CSC는 다음을 준비한다.

```text
1. convolution shape config 확인
   - input_width
   - input_height
   - input_channels
   - kernel_width
   - kernel_height
   - stride_x
   - stride_y
   - output_width
   - output_height
   - output_channels
2. data_base, weight_base 확인
3. scheduler FIFO clear 준비
4. packet generation counter clear 준비
5. CBUF read request path 준비
6. CMAC ready를 기다릴 준비
7. scheduler generator enable
8. scheduler FIFO prefill 시작
9. FIFO에 일정량 이상 packet이 차면 csc_ready=1
```

`op_enable` 상태에서 scheduler generator는 다음 정보를 계산한다.

```text
1. output position
2. kernel position
3. channel group
4. output channel group
5. data CBUF bank/address
6. weight CBUF bank/address
7. MACCell valid mask
8. acc_clear / acc_last
9. tag
```

이 계산 결과는 scheduler FIFO에 compact packet으로 저장한다.

권장 동작:

```text
1. csc_op_enable rising 또는 config reload 시 FIFO/counter clear
2. config latch
3. scheduler generator start
4. FIFO가 full이 아니면 address packet push
5. FIFO prefill threshold 이상이면 csc_ready=1
6. csc_op_start가 들어오기 전까지 FIFO pop은 하지 않는다
```

prefill threshold는 초기에는 1 packet이면 충분하다. 나중에 CBUF/CMAC stall을 더 안정적으로 흡수하려면 2 packet 이상으로 늘릴 수 있다.

### op_start Pulse

`csc_op_start`가 들어오면:

```text
1. csc_ready가 1인지 확인한다.
2. scheduler FIFO pop을 시작한다.
3. CBUF read scheduler가 packet의 bank/address로 CBUF read 요청을 낸다.
4. CBUF에서 data/weight row를 읽는다.
5. MACLane formatter가 data/weight를 MACCell별 lane에 배치한다.
6. CMAC으로 valid/ready handshake를 통해 operand packet을 전달한다.
7. scheduler generator는 FIFO 공간이 생길 때마다 계속 다음 packet을 push한다.
8. 마지막 packet 이후 FIFO가 비고 pending read/output이 모두 drain되면 csc_done을 올린다.
```

현재 timing 문제를 고려하면 CSC 주소 계산은 pipeline화하는 것이 좋다.

권장 pipeline:

```text
stage0: loop counter latch
stage1: input_x/input_y/kernel_index
stage2: input_pixel_index/data_group_index/weight_group_partial
stage3: data_elem_start/weight_elem_start
stage4: bank/address/tag packet 생성
stage5: scheduler FIFO push
```

이 구조에서는 주소 계산 pipeline이 `op_enable` 이후 미리 돌기 때문에, `op_start` 이후의 critical path는 주로 FIFO pop, CBUF read request, MACLane formatting으로 제한된다.

## CMAC

### Purpose

CSC에서 받은 data/weight lane을 곱하고 MACCell별 partial sum을 만든다.

### op_enable Asserted

`cmac_op_enable = 1`이면 CMAC은 다음을 준비한다.

```text
1. MACCell/MACLane array enable
2. accumulator input path 초기화 준비
3. CSC operand valid/ready 수신 준비
4. CACC output valid/ready 송신 준비
5. debug 또는 monitor path enable 준비
```

### op_start Pulse

`cmac_op_start`가 들어오면:

```text
1. internal valid pipeline clear
2. CSC operand를 받을 준비 완료
3. maccell_data * maccell_weight 연산 수행
4. lane별 product를 MACCell 단위로 sum
5. acc_clear가 들어오면 해당 output accumulator 시작값으로 처리
6. acc_last가 들어오면 해당 partial sum을 CACC로 전달
7. 마지막 expected packet 처리 후 cmac_done을 올린다.
```

CMAC은 CSC와 tightly-coupled block이므로, 실제로는 `cmac_op_start` 이후 `csc_op_start`가 시작되어야 한다.

## CACC

### Purpose

CMAC의 partial sum을 output channel/output position 단위로 누적하고 최종 convolution result를 만든다.

### op_enable Asserted

`cacc_op_enable = 1`이면 CACC는 다음을 준비한다.

```text
1. accumulator storage clear 준비
2. output channel group config 확인
3. output feature map shape 확인
4. CMAC partial sum input ready 준비
5. SDP 또는 output write path ready 확인
```

### op_start Pulse

`cacc_op_start`가 들어오면:

```text
1. accumulator 상태 초기화
2. CMAC partial sum 수신
3. acc_clear 시 새 accumulation 시작
4. acc_last 시 최종 accumulated value 확정
5. 최종 result를 SDP 또는 output buffer로 전달
6. 모든 output accumulation 완료 후 cacc_done을 올린다.
```

## SDP

### Purpose

CACC output에 bias, activation, scaling 같은 post-processing을 적용한다.

초기 구현에서는 bypass 가능하게 두는 것이 좋다.

### op_enable Asserted

`sdp_op_enable = 1`이면 SDP는 다음을 준비한다.

```text
1. SDP mode 확인
   - bypass
   - bias
   - activation
   - scale/shift
2. CACC output input-ready 준비
3. PDP 또는 output write path 준비
4. parameter buffer 또는 register 값 latch 준비
```

### op_start Pulse

`sdp_op_start`가 들어오면:

```text
1. mode/config latch
2. CACC output stream 수신
3. configured operation 적용
4. 결과를 PDP 또는 output write path로 전달
5. 마지막 element 처리 후 sdp_done을 올린다.
```

## PDP

### Purpose

Pooling을 수행한다. 초기 구현에서는 bypass 가능하게 둔다.

### op_enable Asserted

`pdp_op_enable = 1`이면 PDP는 다음을 준비한다.

```text
1. pooling mode 확인
   - bypass
   - max pooling
   - average pooling
2. pooling kernel size 확인
3. stride 확인
4. input/output feature map shape 확인
5. line buffer 또는 window buffer 초기화 준비
```

### op_start Pulse

`pdp_op_start`가 들어오면:

```text
1. mode/config latch
2. SDP output 또는 CACC output 수신
3. pooling window 구성
4. pooling result 계산
5. output write path로 전달
6. 마지막 output 처리 후 pdp_done을 올린다.
```

## Operation Controller

초기에는 processor가 block start를 직접 제어할 수 있다.

권장 순서:

```text
1. Processor writes config registers.
2. Processor writes OP_ENABLE.
3. CSC op_enable starts scheduler FIFO prefill.
4. Processor waits until compute-side ready bits are set.
5. Processor pulses CDMA_OP_START.
6. Wait CDMA_DONE.
7. Processor pulses CACC_OP_START and CMAC_OP_START.
8. Processor pulses CSC_OP_START.
9. CSC pops prefetched scheduler packets and feeds CMAC.
10. CMAC feeds CACC.
11. Wait CACC_DONE.
12. If SDP enabled, pulse SDP_OP_START.
13. If PDP enabled, pulse PDP_OP_START.
14. Final done interrupt/status set.
```

나중에 내부 controller를 추가하면:

```text
Processor writes config + OP_ENABLE.
Processor pulses NPU_START.
Internal controller sequences CDMA -> CSC/CMAC/CACC -> SDP -> PDP.
Processor only polls NPU_STATUS or waits interrupt.
```

## Status Register Recommendation

각 블록마다 다음 status bit를 둔다.

```text
bit0 ready
bit1 busy
bit2 done
bit3 error
bit4 disabled
bit5 config_error
bit6 underflow
bit7 overflow
```

`done/error`는 processor가 clear할 때까지 sticky로 두는 것이 디버깅에 유리하다.

내부 block-to-controller 신호는 pulse여도 되지만, CSB status register에는 sticky bit로 저장한다.

## Migration From Current Design

현재 구조:

```text
CDMA_CONTROL[0] = data_start
CDMA_CONTROL[1] = weight_start
CSC_CONTROL[0]  = csc_start
```

변경 후 구조:

```text
OP_ENABLE[0] = cdma_op_enable
OP_ENABLE[1] = csc_op_enable
OP_ENABLE[2] = cmac_op_enable
OP_ENABLE[3] = cacc_op_enable
OP_ENABLE[4] = sdp_op_enable
OP_ENABLE[5] = pdp_op_enable

OP_START[0] = cdma_op_start
OP_START[1] = csc_op_start
OP_START[2] = cmac_op_start
OP_START[3] = cacc_op_start
OP_START[4] = sdp_op_start
OP_START[5] = pdp_op_start
```

첫 단계에서는 `cdma_op_start`가 내부에서 data load와 weight load를 순차 실행하게 만든다.

두 번째 단계에서는 `NPU_CONTROL.npu_start` 하나로 전체 sequence를 자동 실행하는 convcore operation controller를 추가한다.

## Important Design Rule

`op_enable`은 start가 아니다.

```text
op_enable = 이 블록을 operation에 포함한다
op_start  = 이번 operation을 시작한다
```

이 구분을 유지해야 같은 블록을 enable 상태로 둔 채 여러 tile/layer operation을 반복 실행할 수 있다.
