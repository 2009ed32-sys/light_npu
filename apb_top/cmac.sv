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
    output logic [TAG_WIDTH-1:0] psum_tag,

    output logic cacc_prepare_valid,
    output logic cacc_prepare_read,
    output logic [MACCELL_NUM-1:0] cacc_prepare_mask,
    output logic cacc_prepare_acc_clear,
    output logic cacc_prepare_acc_last
);

    localparam int MACCELL_OPERAND_WIDTH = MACLANE_NUM * ELEMENT_WIDTH;

    logic [MACCELL_NUM-1:0] cell_op_ready_w;
    logic [MACCELL_NUM-1:0] cell_op_busy_w;
    logic [MACCELL_NUM-1:0] cell_op_done_w;
    logic [MACCELL_NUM-1:0] cell_op_error_w;
    logic [MACCELL_NUM-1:0] cell_operand_ready_w;
    logic [MACCELL_NUM-1:0] cell_psum_valid_w;
    logic [MACCELL_NUM-1:0] cell_psum_acc_clear_w;
    logic [MACCELL_NUM-1:0] cell_psum_acc_last_w;
    logic [(MACCELL_NUM*TAG_WIDTH)-1:0] cell_psum_tag_w;
    logic [(MACCELL_NUM*PSUM_WIDTH)-1:0] cell_psum_data_w;
    logic last_operand_accept_w;

    genvar cell_idx;
    generate
        for (cell_idx = 0; cell_idx < MACCELL_NUM; cell_idx = cell_idx + 1) begin : g_maccell
            maccell #(
                .ELEMENT_WIDTH(ELEMENT_WIDTH),
                .MACLANE_NUM  (MACLANE_NUM),
                .PSUM_WIDTH   (PSUM_WIDTH),
                .TAG_WIDTH    (TAG_WIDTH)
            ) u_maccell (
                .clk               (clk),
                .rst_n             (rst_n),

                .op_enable         (op_enable),
                .op_start          (op_start),
                .op_ready          (cell_op_ready_w[cell_idx]),
                .op_busy           (cell_op_busy_w[cell_idx]),
                .op_done           (cell_op_done_w[cell_idx]),
                .op_error          (cell_op_error_w[cell_idx]),

                .operand_valid     (maccell_in_valid),
                .operand_ready     (cell_operand_ready_w[cell_idx]),
                .operand_valid_mask(maccell_valid_mask[cell_idx]),
                .operand_data      (maccell_data[
                    (cell_idx*MACCELL_OPERAND_WIDTH) +: MACCELL_OPERAND_WIDTH
                ]),
                .operand_weight    (maccell_weight[
                    (cell_idx*MACCELL_OPERAND_WIDTH) +: MACCELL_OPERAND_WIDTH
                ]),
                .operand_acc_clear (maccell_acc_clear),
                .operand_acc_last  (maccell_acc_last),
                .operand_tag       (maccell_tag),

                .psum_valid        (cell_psum_valid_w[cell_idx]),
                .psum_ready        (psum_ready),
                .psum_data         (cell_psum_data_w[
                    (cell_idx*PSUM_WIDTH) +: PSUM_WIDTH
                ]),
                .psum_acc_clear    (cell_psum_acc_clear_w[cell_idx]),
                .psum_acc_last     (cell_psum_acc_last_w[cell_idx]),
                .psum_tag          (cell_psum_tag_w[
                    (cell_idx*TAG_WIDTH) +: TAG_WIDTH
                ])
            );
        end
    endgenerate

    assign op_ready = &cell_op_ready_w;
    assign op_busy = |cell_op_busy_w;
    assign op_done = &cell_op_done_w;
    assign op_error = |cell_op_error_w;

    assign maccell_ready = &cell_operand_ready_w;

    assign last_operand_accept_w =
        op_enable &&
        maccell_in_valid &&
        maccell_ready &&
        maccell_acc_last &&
        (|maccell_valid_mask);

    assign psum_valid = |cell_psum_valid_w;
    assign psum_valid_mask = cell_psum_valid_w;
    assign psum_data = cell_psum_data_w;
    assign psum_acc_clear = |cell_psum_acc_clear_w;
    assign psum_acc_last = |cell_psum_acc_last_w;
    assign psum_tag = cell_psum_tag_w[0 +: TAG_WIDTH];

    assign cacc_prepare_valid = last_operand_accept_w;
    assign cacc_prepare_read = last_operand_accept_w && !maccell_acc_clear;
    assign cacc_prepare_mask =
        last_operand_accept_w ? maccell_valid_mask : '0;
    assign cacc_prepare_acc_clear =
        last_operand_accept_w && maccell_acc_clear;
    assign cacc_prepare_acc_last =
        last_operand_accept_w && maccell_acc_last;

endmodule
