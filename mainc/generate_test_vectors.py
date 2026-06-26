#!/usr/bin/env python3
"""Generate deterministic NPU test vectors.

The generated CSV files are human-readable references. Later C code can use
the same generation rules, or this script can be extended to emit a C header.
"""

from __future__ import annotations

import csv
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class LayerConfig:
    input_width: int = 64
    input_height: int = 64
    input_channels: int = 4
    kernel_width: int = 5
    kernel_height: int = 5
    kernel_count: int = 3
    stride_x: int = 1
    stride_y: int = 1
    maclane_num: int = 4
    maccell_num: int = 8
    input_base: int = 0x0100_0000
    weight_base: int = 0x0200_0000
    output_base: int = 0x0300_0000

    @property
    def output_width(self) -> int:
        return ((self.input_width - self.kernel_width) // self.stride_x) + 1

    @property
    def output_height(self) -> int:
        return ((self.input_height - self.kernel_height) // self.stride_y) + 1

    @property
    def output_positions(self) -> int:
        return self.output_width * self.output_height

    @property
    def input_words(self) -> int:
        return self.input_width * self.input_height

    @property
    def weight_words(self) -> int:
        return self.kernel_width * self.kernel_height * self.maccell_num

    @property
    def output_words(self) -> int:
        return self.output_positions * self.kernel_count

    @property
    def csc_atomics(self) -> int:
        return self.output_positions * self.kernel_width * self.kernel_height


def u8(value: int) -> int:
    return value & 0xFF


def s8(value: int) -> int:
    value &= 0xFF
    return value - 0x100 if value & 0x80 else value


def u32(value: int) -> int:
    return value & 0xFFFF_FFFF


def s32(value: int) -> int:
    value &= 0xFFFF_FFFF
    return value - 0x1_0000_0000 if value & 0x8000_0000 else value


def hex32(value: int) -> str:
    return f"0x{u32(value):08X}"


def pack_lanes(lanes: list[int]) -> int:
    word = 0
    for lane_idx, value in enumerate(lanes):
        word |= u8(value) << (lane_idx * 8)
    return u32(word)


def input_lane_value(cfg: LayerConfig, x: int, y: int, channel: int) -> int:
    word_idx = y * cfg.input_width + x
    return u8(0x10 + word_idx * cfg.input_channels + channel)


def input_word(cfg: LayerConfig, x: int, y: int) -> int:
    lanes = [input_lane_value(cfg, x, y, ch) for ch in range(cfg.input_channels)]
    return pack_lanes(lanes)


def weight_lane_value(kernel_out: int, kernel_idx: int, channel: int) -> int:
    if kernel_out == 0:
        return 1 + kernel_idx + channel
    if kernel_out == 1:
        return -1 - kernel_idx - channel
    if kernel_out == 2:
        if kernel_idx & 1:
            return -3 - channel
        return 3 + channel
    return 0


def weight_word(cfg: LayerConfig, word_idx: int) -> int:
    lanes: list[int] = []

    for lane in range(cfg.maclane_num):
        elem_idx = word_idx * cfg.maclane_num + lane
        elem_in_kernel_group = elem_idx % (cfg.maccell_num * cfg.maclane_num)
        kernel_idx = elem_idx // (cfg.maccell_num * cfg.maclane_num)
        kernel_out = elem_in_kernel_group // cfg.maclane_num
        channel = elem_in_kernel_group % cfg.maclane_num

        if kernel_idx < (cfg.kernel_width * cfg.kernel_height):
            lanes.append(weight_lane_value(kernel_out, kernel_idx, channel))
        else:
            lanes.append(0)

    return pack_lanes(lanes)


def reference_output_value(cfg: LayerConfig, out_x: int, out_y: int, kernel_out: int) -> int:
    acc = 0

    for kernel_y in range(cfg.kernel_height):
        for kernel_x in range(cfg.kernel_width):
            kernel_idx = kernel_y * cfg.kernel_width + kernel_x
            input_x = out_x * cfg.stride_x + kernel_x
            input_y = out_y * cfg.stride_y + kernel_y

            for channel in range(cfg.input_channels):
                data = s8(input_lane_value(cfg, input_x, input_y, channel))
                weight = s8(weight_lane_value(kernel_out, kernel_idx, channel))
                acc += data * weight

    return s32(acc)


def write_input_csv(cfg: LayerConfig, out_dir: Path) -> None:
    path = out_dir / "input.csv"
    with path.open("w", newline="", encoding="utf-8") as fp:
        writer = csv.writer(fp)
        writer.writerow(
            [
                "word_index",
                "address",
                "x",
                "y",
                "word_hex",
                "c0_u8",
                "c1_u8",
                "c2_u8",
                "c3_u8",
                "c0_s8",
                "c1_s8",
                "c2_s8",
                "c3_s8",
            ]
        )

        for y in range(cfg.input_height):
            for x in range(cfg.input_width):
                word_idx = y * cfg.input_width + x
                lanes = [input_lane_value(cfg, x, y, ch) for ch in range(cfg.input_channels)]
                writer.writerow(
                    [
                        word_idx,
                        hex32(cfg.input_base + word_idx * 4),
                        x,
                        y,
                        hex32(pack_lanes(lanes)),
                        *lanes,
                        *[s8(value) for value in lanes],
                    ]
                )


def write_weight_csv(cfg: LayerConfig, out_dir: Path) -> None:
    path = out_dir / "weight.csv"
    with path.open("w", newline="", encoding="utf-8") as fp:
        writer = csv.writer(fp)
        writer.writerow(
            [
                "word_index",
                "address",
                "kernel_idx",
                "kernel_x",
                "kernel_y",
                "kernel_out",
                "word_hex",
                "w0_u8",
                "w1_u8",
                "w2_u8",
                "w3_u8",
                "w0_s8",
                "w1_s8",
                "w2_s8",
                "w3_s8",
            ]
        )

        for word_idx in range(cfg.weight_words):
            kernel_idx = word_idx // cfg.maccell_num
            kernel_out = word_idx % cfg.maccell_num
            kernel_x = kernel_idx % cfg.kernel_width
            kernel_y = kernel_idx // cfg.kernel_width
            lanes = [
                weight_lane_value(kernel_out, kernel_idx, ch)
                if kernel_out < cfg.kernel_count
                else 0
                for ch in range(cfg.maclane_num)
            ]
            lanes_u8 = [u8(value) for value in lanes]
            writer.writerow(
                [
                    word_idx,
                    hex32(cfg.weight_base + word_idx * 4),
                    kernel_idx,
                    kernel_x,
                    kernel_y,
                    kernel_out,
                    hex32(weight_word(cfg, word_idx)),
                    *lanes_u8,
                    *[s8(value) for value in lanes_u8],
                ]
            )


def write_expected_output_csv(cfg: LayerConfig, out_dir: Path) -> None:
    path = out_dir / "expected_output.csv"
    with path.open("w", newline="", encoding="utf-8") as fp:
        writer = csv.writer(fp)
        writer.writerow(
            [
                "word_index",
                "address",
                "out_x",
                "out_y",
                "kernel_out",
                "word_hex",
                "value_s32",
            ]
        )

        for out_y in range(cfg.output_height):
            for out_x in range(cfg.output_width):
                out_pos = out_y * cfg.output_width + out_x
                for kernel_out in range(cfg.kernel_count):
                    word_idx = out_pos * cfg.kernel_count + kernel_out
                    value = reference_output_value(cfg, out_x, out_y, kernel_out)
                    writer.writerow(
                        [
                            word_idx,
                            hex32(cfg.output_base + word_idx * 4),
                            out_x,
                            out_y,
                            kernel_out,
                            hex32(value),
                            value,
                        ]
                    )


def format_c_array(name: str, values: list[int], words_per_line: int = 4) -> list[str]:
    lines = [f"static const u32 {name}[{len(values)}] = {{"]

    for idx in range(0, len(values), words_per_line):
        chunk = values[idx : idx + words_per_line]
        suffix = "," if idx + words_per_line < len(values) else ""
        words = ", ".join(f"0x{u32(value):08X}U" for value in chunk)
        lines.append(f"    {words}{suffix}")

    lines.append("};")
    return lines


def write_c_header(cfg: LayerConfig, out_dir: Path) -> None:
    path = out_dir / "npu_test_vectors.h"

    input_values = [
        input_word(cfg, x, y)
        for y in range(cfg.input_height)
        for x in range(cfg.input_width)
    ]
    weight_values = [weight_word(cfg, idx) for idx in range(cfg.weight_words)]
    expected_values = [
        u32(reference_output_value(cfg, out_x, out_y, kernel_out))
        for out_y in range(cfg.output_height)
        for out_x in range(cfg.output_width)
        for kernel_out in range(cfg.kernel_count)
    ]

    lines = [
        "#ifndef NPU_TEST_VECTORS_H",
        "#define NPU_TEST_VECTORS_H",
        "",
        "#include \"xil_types.h\"",
        "",
        "/* Auto-generated by generate_test_vectors.py. */",
        "",
        f"#define NPU_TEST_INPUT_BASE             0x{cfg.input_base:08X}U",
        f"#define NPU_TEST_WEIGHT_BASE            0x{cfg.weight_base:08X}U",
        f"#define NPU_TEST_OUTPUT_BASE            0x{cfg.output_base:08X}U",
        "",
        f"#define NPU_TEST_INPUT_WIDTH            {cfg.input_width}U",
        f"#define NPU_TEST_INPUT_HEIGHT           {cfg.input_height}U",
        f"#define NPU_TEST_INPUT_CHANNELS         {cfg.input_channels}U",
        f"#define NPU_TEST_KERNEL_WIDTH           {cfg.kernel_width}U",
        f"#define NPU_TEST_KERNEL_HEIGHT          {cfg.kernel_height}U",
        f"#define NPU_TEST_KERNEL_COUNT           {cfg.kernel_count}U",
        f"#define NPU_TEST_STRIDE_X               {cfg.stride_x}U",
        f"#define NPU_TEST_STRIDE_Y               {cfg.stride_y}U",
        f"#define NPU_TEST_OUTPUT_WIDTH           {cfg.output_width}U",
        f"#define NPU_TEST_OUTPUT_HEIGHT          {cfg.output_height}U",
        f"#define NPU_TEST_OUTPUT_CHANNELS        {cfg.kernel_count}U",
        "",
        f"#define NPU_TEST_INPUT_WORDS            {cfg.input_words}U",
        f"#define NPU_TEST_WEIGHT_WORDS           {cfg.weight_words}U",
        f"#define NPU_TEST_OUTPUT_WORDS           {cfg.output_words}U",
        f"#define NPU_TEST_CSC_ATOMICS            {cfg.csc_atomics}U",
        "",
        *format_c_array("npu_test_input_words", input_values),
        "",
        *format_c_array("npu_test_weight_words", weight_values),
        "",
        *format_c_array("npu_test_expected_output_words", expected_values),
        "",
        "#endif",
        "",
    ]

    path.write_text("\n".join(lines), encoding="utf-8")


def run_self_check(cfg: LayerConfig) -> None:
    assert cfg.input_words == 4096
    assert cfg.weight_words == 200
    assert cfg.output_width == 60
    assert cfg.output_height == 60
    assert cfg.output_words == 10800
    assert cfg.csc_atomics == 90000
    assert input_word(cfg, 0, 0) == 0x1312_1110
    assert input_word(cfg, 1, 0) == 0x1716_1514
    assert weight_word(cfg, 0) == 0x0403_0201
    assert weight_word(cfg, 1) == 0xFCFD_FEFF
    assert weight_word(cfg, 2) == 0x0605_0403


def main() -> None:
    cfg = LayerConfig()
    out_dir = Path(__file__).resolve().parent / "generated_vectors"
    out_dir.mkdir(parents=True, exist_ok=True)

    run_self_check(cfg)
    write_input_csv(cfg, out_dir)
    write_weight_csv(cfg, out_dir)
    write_expected_output_csv(cfg, out_dir)
    write_c_header(cfg, out_dir)

    print("Generated NPU test vectors")
    print(f"  output dir      : {out_dir}")
    print(f"  input base      : {hex32(cfg.input_base)}")
    print(f"  weight base     : {hex32(cfg.weight_base)}")
    print(f"  output base     : {hex32(cfg.output_base)}")
    print(f"  input words     : {cfg.input_words}")
    print(f"  weight words    : {cfg.weight_words}")
    print(f"  output words    : {cfg.output_words}")
    print(f"  csc atomics     : {cfg.csc_atomics}")
    print(f"  first input     : {hex32(input_word(cfg, 0, 0))}")
    print(f"  first weight    : {hex32(weight_word(cfg, 0))}")
    print(f"  first output    : {hex32(reference_output_value(cfg, 0, 0, 0))}")
    print("  generated files : input.csv, weight.csv, expected_output.csv, npu_test_vectors.h")


if __name__ == "__main__":
    main()
