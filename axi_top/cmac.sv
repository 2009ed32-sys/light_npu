`timescale 1ns/1ps
// Convolution MAC array placeholder.
//
// CMAC consumes CSC-formatted MACCell lane operands and will produce one
// partial-sum word per MACCell for CACC.  Internal multiply/add logic is
// intentionally left empty for the first integration step.

module cmac #(
    parameter int ELEMENT_WIDTH = 8,
    parameter int MACCELL_NUM   = 8,
    parameter int MACLANE_NUM   = 4,
    parameter int PSUM_WIDTH    = 32,
    parameter int TAG_WIDTH     = 32
) (
    input  logic clk,
    input  logic rst_n,

    input  logic op_enable,
    input  logic op_start,
    output logic op_ready,
    output logic op_busy,
    output logic op_done,
    output logic op_error,

    input  logic maccell_in_valid,
    output logic maccell_ready,
    input  logic [MACCELL_NUM-1:0] maccell_valid_mask,
    input  logic [(MACCELL_NUM*MACLANE_NUM*ELEMENT_WIDTH)-1:0] maccell_data,
    input  logic [(MACCELL_NUM*MACLANE_NUM*ELEMENT_WIDTH)-1:0] maccell_weight,
    input  logic maccell_acc_clear,
    input  logic maccell_acc_last,
    input  logic [TAG_WIDTH-1:0] maccell_tag,

    output logic psum_valid,
    input  logic psum_ready,
    output logic [MACCELL_NUM-1:0] psum_valid_mask,
    output logic [(MACCELL_NUM*PSUM_WIDTH)-1:0] psum_data,
    output logic psum_acc_clear,
    output logic psum_acc_last,
    output logic [TAG_WIDTH-1:0] psum_tag
);

    // TODO: implement MACLane multiply, per-MACCell product sum, and
    // valid/ready pipeline.

endmodule
