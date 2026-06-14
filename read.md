# Light NPU 진행 요약

현재 설계는 Zynq 기반 SoC에서 PS가 PL 내부 NPU를 제어하는 구조이다. PS는 APB 제어 레지스터를 통해 CDMA, CSC, CACC/SDP의 설정값과 시작 신호를 전달하고, 각 블록의 ready, busy, done 상태를 polling하면서 연산 흐름을 확인한다.

PL 내부에서는 CDMA가 AXI read master를 통해 DDR에서 input data와 weight를 읽어 CBUF에 저장한다. 이후 CSC가 CBUF에서 필요한 data와 weight를 읽어 MACLane/MACCell에 배치하고, CMAC이 곱셈과 누산을 수행해 partial sum을 만든다.

CACC는 CMAC에서 나온 partial sum을 받아 delivery FIFO에 저장하고, SDP는 이 데이터를 순서대로 꺼내 AXI write master를 통해 DDR에 다시 기록한다. 현재 main.c에서는 DDR에 입력과 가중치를 준비한 뒤 NPU를 실행하고, 최종 DDR output을 CPU 계산 결과와 비교해 동작을 검증한다.

현재 검증된 기본 흐름은 다음과 같다.

```text
PS main.c
  -> APB register write/read
  -> CDMA DDR read
  -> CBUF store
  -> CSC MACLane scheduling
  -> CMAC partial sum
  -> CACC delivery FIFO
  -> SDP DDR write
  -> PS DDR result check
```

최근 검증에서는 `16x16x4` input과 `3x3x4` weight, output kernel 3개를 사용해 `14x14x3` output을 DDR에 저장했고, CPU expected result와 비교하여 pass를 확인했다.
