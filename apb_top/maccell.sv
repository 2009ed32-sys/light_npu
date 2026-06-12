`timescale 1ns/1ps
// One MACCell.
//
// Minimal two-cycle MAC structure:
//   cycle 1: product_q[lane] <= data[lane] * weight[lane]
//   cycle 2: lane_acc_q[lane] <= lane_acc_q[lane] + product_q[lane]
//
// The wider CMAC/CACC handshake will be refined after this datapath shape is
// confirmed in synthesis.

module maccell #(
    parameter int ELEMENT_WIDTH = 8,
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

    input  logic operand_valid,
    output logic operand_ready,
    input  logic operand_valid_mask,
    input  logic [(MACLANE_NUM*ELEMENT_WIDTH)-1:0] operand_data,
    input  logic [(MACLANE_NUM*ELEMENT_WIDTH)-1:0] operand_weight,
    input  logic operand_acc_clear,
    input  logic operand_acc_last,
    input  logic [TAG_WIDTH-1:0] operand_tag,

    output logic psum_valid,
    input  logic psum_ready,
    output logic [PSUM_WIDTH-1:0] psum_data,
    output logic psum_acc_clear,
    output logic psum_acc_last,
    output logic [TAG_WIDTH-1:0] psum_tag
);

    localparam int PRODUCT_WIDTH = ELEMENT_WIDTH * 2;

    (* use_dsp = "yes" *) logic signed [PRODUCT_WIDTH-1:0] product_q [0:MACLANE_NUM-1];
    (* use_dsp = "yes" *) logic signed [PSUM_WIDTH-1:0] lane_acc_q [0:MACLANE_NUM-1];

    logic product_valid_q;
    logic product_clear_q;
    logic product_last_q;
    logic [TAG_WIDTH-1:0] product_tag_q;

    logic psum_valid_q;
    logic psum_acc_clear_q;
    logic psum_acc_last_q;
    logic [TAG_WIDTH-1:0] psum_tag_q;
    logic signed [PSUM_WIDTH-1:0] psum_sum_w;

    assign operand_ready = op_enable && (!psum_valid_q || psum_ready);
    assign op_ready = op_enable && operand_ready;
    assign op_busy = op_enable && (product_valid_q || psum_valid_q);
    assign op_done = psum_valid_q && psum_ready;
    assign op_error = 1'b0;

    assign psum_valid = psum_valid_q;
    assign psum_data = psum_sum_w;
    assign psum_acc_clear = psum_acc_clear_q;
    assign psum_acc_last = psum_acc_last_q;
    assign psum_tag = psum_tag_q;

    always_comb begin
        psum_sum_w = '0;
        for (int lane_idx = 0; lane_idx < MACLANE_NUM; lane_idx = lane_idx + 1) begin
            psum_sum_w = psum_sum_w + lane_acc_q[lane_idx];
        end
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            product_valid_q <= 1'b0;
            product_clear_q <= 1'b0;
            product_last_q <= 1'b0;
            product_tag_q <= '0;
            psum_valid_q <= 1'b0;
            psum_acc_clear_q <= 1'b0;
            psum_acc_last_q <= 1'b0;
            psum_tag_q <= '0;

            for (int lane_idx = 0; lane_idx < MACLANE_NUM; lane_idx = lane_idx + 1) begin
                product_q[lane_idx] <= '0;
                lane_acc_q[lane_idx] <= '0;
            end
        end else if (!op_enable || op_start) begin
            product_valid_q <= 1'b0;
            product_clear_q <= 1'b0;
            product_last_q <= 1'b0;
            product_tag_q <= '0;
            psum_valid_q <= 1'b0;
            psum_acc_clear_q <= 1'b0;
            psum_acc_last_q <= 1'b0;
            psum_tag_q <= '0;

            for (int lane_idx = 0; lane_idx < MACLANE_NUM; lane_idx = lane_idx + 1) begin
                product_q[lane_idx] <= '0;
                lane_acc_q[lane_idx] <= '0;
            end
        end else begin
            if (psum_valid_q && psum_ready) begin
                psum_valid_q <= 1'b0;
            end

            if (product_valid_q) begin
                for (int lane_idx = 0; lane_idx < MACLANE_NUM; lane_idx = lane_idx + 1) begin
                    if (product_clear_q) begin
                        lane_acc_q[lane_idx] <= PSUM_WIDTH'(product_q[lane_idx]);
                    end else begin
                        lane_acc_q[lane_idx] <=
                            lane_acc_q[lane_idx] + PSUM_WIDTH'(product_q[lane_idx]);
                    end
                end

                if (product_last_q) begin
                    psum_valid_q <= 1'b1;
                    psum_acc_clear_q <= product_clear_q;
                    psum_acc_last_q <= product_last_q;
                    psum_tag_q <= product_tag_q;
                end
            end

            product_valid_q <= operand_valid && operand_ready && operand_valid_mask;
            product_clear_q <= operand_acc_clear;
            product_last_q <= operand_acc_last;
            product_tag_q <= operand_tag;

            if (operand_valid && operand_ready && operand_valid_mask) begin
                for (int lane_idx = 0; lane_idx < MACLANE_NUM; lane_idx = lane_idx + 1) begin
                    product_q[lane_idx] <=
                        $signed(operand_data[(lane_idx*ELEMENT_WIDTH) +: ELEMENT_WIDTH]) *
                        $signed(operand_weight[(lane_idx*ELEMENT_WIDTH) +: ELEMENT_WIDTH]);
                end
            end
        end
    end

endmodule
