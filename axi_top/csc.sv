`timescale 1ns/1ps
// Convolution sequence controller top.
//
// csc_sg owns scheduler/FIFO/CBUF read-address generation. csc_maclane owns
// CBUF read-data placement into MACCell lane vectors. This wrapper keeps the
// original CSC external interface and latches formatted operands until the
// downstream MACCell side accepts them.

(* use_dsp = "no" *)
module csc #(
    parameter int ELEMENT_WIDTH       = 8,
    parameter int BANK_NUM            = 8,
    parameter int MACCELL_NUM         = 8,
    parameter int MACLANE_NUM         = 4,
    parameter int ADDR_WIDTH          = 16,
    parameter int BANK_ADDR_WIDTH     = 10,
    parameter int LEN_WIDTH           = 32,
    parameter int TAG_WIDTH           = 32,
    parameter int ADDR_FIFO_DEPTH     = 4,
    parameter int PREFILL_THRESHOLD   = 1
) (
    input  logic                                   clk,
    input  logic                                   rst_n,

    input  logic                                   op_enable,
    input  logic                                   op_start,
    output logic                                   op_ready,
    output logic                                   op_busy,
    output logic                                   op_done,
    output logic                                   op_error,

    input  logic [LEN_WIDTH-1:0]                   atomics,
    input  logic [ADDR_WIDTH-1:0]                  data_base,
    input  logic [ADDR_WIDTH-1:0]                  weight_base,
    input  logic [LEN_WIDTH-1:0]                   input_width,
    input  logic [LEN_WIDTH-1:0]                   input_height,
    input  logic [LEN_WIDTH-1:0]                   input_channels,
    input  logic [LEN_WIDTH-1:0]                   kernel_width,
    input  logic [LEN_WIDTH-1:0]                   kernel_height,
    input  logic [LEN_WIDTH-1:0]                   stride_x,
    input  logic [LEN_WIDTH-1:0]                   stride_y,
    input  logic [LEN_WIDTH-1:0]                   output_width,
    input  logic [LEN_WIDTH-1:0]                   output_height,
    input  logic [LEN_WIDTH-1:0]                   output_channels,

    output logic                                   data_cbuf_rd_en,
    output logic [BANK_NUM-1:0]                    data_cbuf_rd_bank_en,
    output logic [(BANK_NUM*BANK_ADDR_WIDTH)-1:0]  data_cbuf_rd_bank_addr,
    input  logic                                   data_cbuf_rd_valid,
    input  logic [(BANK_NUM*MACLANE_NUM*ELEMENT_WIDTH)-1:0] data_cbuf_rd_data,

    output logic                                   weight_cbuf_rd_en,
    output logic [BANK_NUM-1:0]                    weight_cbuf_rd_bank_en,
    output logic [(BANK_NUM*BANK_ADDR_WIDTH)-1:0]  weight_cbuf_rd_bank_addr,
    input  logic                                   weight_cbuf_rd_valid,
    input  logic [(BANK_NUM*MACLANE_NUM*ELEMENT_WIDTH)-1:0] weight_cbuf_rd_data,

    input  logic                                   maccell_ready,
    output logic                                   maccell_in_valid,
    output logic [MACCELL_NUM-1:0]                 maccell_valid_mask,
    output logic [(MACCELL_NUM*MACLANE_NUM*ELEMENT_WIDTH)-1:0] maccell_data,
    output logic [(MACCELL_NUM*MACLANE_NUM*ELEMENT_WIDTH)-1:0] maccell_weight,
    output logic                                   maccell_acc_clear,
    output logic                                   maccell_acc_last,
    output logic [TAG_WIDTH-1:0]                   maccell_tag
);

    localparam int BANK_SEL_WIDTH =
        (BANK_NUM <= 2) ? 1 : $clog2(BANK_NUM);
    localparam int PACK_LANE_WIDTH =
        (MACLANE_NUM <= 2) ? 1 : $clog2(MACLANE_NUM);
    localparam int MAC_VEC_WIDTH =
        MACCELL_NUM * MACLANE_NUM * ELEMENT_WIDTH;

    typedef enum logic [2:0] {
        ST_IDLE,
        ST_PREFILL,
        ST_RUN,
        ST_DONE,
        ST_ERROR
    } state_e;

    state_e state_q;
    state_e state_d;
    logic op_enable_q;
    logic op_start_q;
    logic op_enable_rise_w;
    logic op_start_pulse_w;

    logic sg_config_load_w;
    logic sg_clear_w;
    logic sg_scheduler_enable_w;
    logic sg_read_enable_w;
    logic sg_config_invalid_w;
    logic sg_prefill_ready_w;
    logic sg_scheduler_done_w;

    logic operand_slot_ready_w;
    logic operand_idle_w;
    logic sg_operand_capture_w;
    logic [BANK_SEL_WIDTH-1:0] sg_data_bank_start_w;
    logic [PACK_LANE_WIDTH-1:0] sg_data_pack_lane_w;
    logic [BANK_SEL_WIDTH-1:0] sg_weight_bank_start_w;
    logic [PACK_LANE_WIDTH-1:0] sg_weight_pack_lane_w;
    logic [MACCELL_NUM-1:0] sg_valid_mask_w;
    logic sg_acc_clear_w;
    logic sg_acc_last_w;
    logic [TAG_WIDTH-1:0] sg_tag_w;

    logic [MAC_VEC_WIDTH-1:0] formatted_data_w;
    logic [MAC_VEC_WIDTH-1:0] formatted_weight_w;

    logic operand_valid_q;
    logic [MACCELL_NUM-1:0] operand_valid_mask_q;
    logic [MAC_VEC_WIDTH-1:0] operand_data_q;
    logic [MAC_VEC_WIDTH-1:0] operand_weight_q;
    logic operand_acc_clear_q;
    logic operand_acc_last_q;
    logic [TAG_WIDTH-1:0] operand_tag_q;
    logic op_done_q;

    assign op_enable_rise_w = op_enable && !op_enable_q;
    assign op_start_pulse_w = op_enable && op_start && !op_start_q;

    assign sg_config_load_w =
        (state_q == ST_IDLE) && op_enable_rise_w && !sg_config_invalid_w;
    assign sg_clear_w =
        (state_q == ST_DONE) ||
        (state_q == ST_ERROR) ||
        ((state_q == ST_PREFILL) && !op_enable);
    assign sg_scheduler_enable_w =
        (state_q == ST_PREFILL) || (state_q == ST_RUN);
    assign sg_read_enable_w = (state_q == ST_RUN);

    assign operand_slot_ready_w =
        !operand_valid_q || (operand_valid_q && maccell_ready);
    assign operand_idle_w = !operand_valid_q;

    assign op_ready = (state_q == ST_PREFILL) && sg_prefill_ready_w;
    assign op_busy = (state_q == ST_PREFILL) || (state_q == ST_RUN);
    assign op_done = op_done_q;
    assign op_error = (state_q == ST_ERROR);

    assign maccell_in_valid = operand_valid_q;
    assign maccell_valid_mask = operand_valid_mask_q;
    assign maccell_data = operand_data_q;
    assign maccell_weight = operand_weight_q;
    assign maccell_acc_clear = operand_acc_clear_q;
    assign maccell_acc_last = operand_acc_last_q;
    assign maccell_tag = operand_tag_q;

    csc_sg #(
        .ELEMENT_WIDTH      (ELEMENT_WIDTH),
        .BANK_NUM           (BANK_NUM),
        .MACCELL_NUM        (MACCELL_NUM),
        .MACLANE_NUM        (MACLANE_NUM),
        .ADDR_WIDTH         (ADDR_WIDTH),
        .BANK_ADDR_WIDTH    (BANK_ADDR_WIDTH),
        .LEN_WIDTH          (LEN_WIDTH),
        .TAG_WIDTH          (TAG_WIDTH),
        .ADDR_FIFO_DEPTH    (ADDR_FIFO_DEPTH),
        .PREFILL_THRESHOLD  (PREFILL_THRESHOLD),
        .BANK_SEL_WIDTH     (BANK_SEL_WIDTH),
        .PACK_LANE_WIDTH    (PACK_LANE_WIDTH)
    ) u_sg (
        .clk                    (clk),
        .rst_n                  (rst_n),
        .config_load            (sg_config_load_w),
        .clear                  (sg_clear_w),
        .scheduler_enable       (sg_scheduler_enable_w),
        .read_enable            (sg_read_enable_w),
        .config_invalid         (sg_config_invalid_w),
        .prefill_ready          (sg_prefill_ready_w),
        .scheduler_done         (sg_scheduler_done_w),
        .atomics                (atomics),
        .data_base              (data_base),
        .weight_base            (weight_base),
        .input_width            (input_width),
        .input_height           (input_height),
        .input_channels         (input_channels),
        .kernel_width           (kernel_width),
        .kernel_height          (kernel_height),
        .stride_x               (stride_x),
        .stride_y               (stride_y),
        .output_width           (output_width),
        .output_height          (output_height),
        .output_channels        (output_channels),
        .data_cbuf_rd_en        (data_cbuf_rd_en),
        .data_cbuf_rd_bank_en   (data_cbuf_rd_bank_en),
        .data_cbuf_rd_bank_addr (data_cbuf_rd_bank_addr),
        .data_cbuf_rd_valid     (data_cbuf_rd_valid),
        .weight_cbuf_rd_en      (weight_cbuf_rd_en),
        .weight_cbuf_rd_bank_en (weight_cbuf_rd_bank_en),
        .weight_cbuf_rd_bank_addr(weight_cbuf_rd_bank_addr),
        .weight_cbuf_rd_valid   (weight_cbuf_rd_valid),
        .operand_slot_ready     (operand_slot_ready_w),
        .operand_capture        (sg_operand_capture_w),
        .operand_data_bank_start(sg_data_bank_start_w),
        .operand_data_pack_lane (sg_data_pack_lane_w),
        .operand_weight_bank_start(sg_weight_bank_start_w),
        .operand_weight_pack_lane(sg_weight_pack_lane_w),
        .operand_valid_mask     (sg_valid_mask_w),
        .operand_acc_clear      (sg_acc_clear_w),
        .operand_acc_last       (sg_acc_last_w),
        .operand_tag            (sg_tag_w)
    );

    csc_maclane #(
        .ELEMENT_WIDTH      (ELEMENT_WIDTH),
        .BANK_NUM           (BANK_NUM),
        .MACCELL_NUM        (MACCELL_NUM),
        .MACLANE_NUM        (MACLANE_NUM),
        .BANK_SEL_WIDTH     (BANK_SEL_WIDTH),
        .PACK_LANE_WIDTH    (PACK_LANE_WIDTH)
    ) u_maclane (
        .data_bank_start    (sg_data_bank_start_w),
        .data_pack_lane     (sg_data_pack_lane_w),
        .weight_bank_start  (sg_weight_bank_start_w),
        .weight_pack_lane   (sg_weight_pack_lane_w),
        .data_cbuf_rd_data  (data_cbuf_rd_data),
        .weight_cbuf_rd_data(weight_cbuf_rd_data),
        .maccell_data       (formatted_data_w),
        .maccell_weight     (formatted_weight_w)
    );

    always_comb begin
        state_d = state_q;

        case (state_q)
            ST_IDLE: begin
                if (op_enable_rise_w) begin
                    if (sg_config_invalid_w) begin
                        state_d = ST_ERROR;
                    end else begin
                        state_d = ST_PREFILL;
                    end
                end
            end

            ST_PREFILL: begin
                if (!op_enable) begin
                    state_d = ST_IDLE;
                end else if (op_start_pulse_w && sg_prefill_ready_w) begin
                    state_d = ST_RUN;
                end
            end

            ST_RUN: begin
                if (op_start_pulse_w) begin
                    state_d = ST_ERROR;
                end else if (sg_scheduler_done_w && operand_idle_w) begin
                    state_d = ST_DONE;
                end
            end

            ST_DONE: begin
                state_d = ST_IDLE;
            end

            ST_ERROR: begin
                state_d = ST_IDLE;
            end

            default: begin
                state_d = ST_ERROR;
            end
        endcase
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_q <= ST_IDLE;
            op_enable_q <= 1'b0;
            op_start_q <= 1'b0;
            op_done_q <= 1'b0;
        end else begin
            state_q <= state_d;
            op_enable_q <= op_enable;
            op_start_q <= op_start;

            if (op_enable_rise_w || (state_q == ST_ERROR)) begin
                op_done_q <= 1'b0;
            end else if ((state_q != ST_DONE) && (state_d == ST_DONE)) begin
                op_done_q <= 1'b1;
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            operand_valid_q <= 1'b0;
            operand_valid_mask_q <= '0;
            operand_data_q <= '0;
            operand_weight_q <= '0;
            operand_acc_clear_q <= 1'b0;
            operand_acc_last_q <= 1'b0;
            operand_tag_q <= '0;
        end else begin
            if (operand_valid_q && maccell_ready) begin
                operand_valid_q <= 1'b0;
            end

            if (sg_operand_capture_w) begin
                operand_valid_q <= 1'b1;
                operand_valid_mask_q <= sg_valid_mask_w;
                operand_data_q <= formatted_data_w;
                operand_weight_q <= formatted_weight_w;
                operand_acc_clear_q <= sg_acc_clear_w;
                operand_acc_last_q <= sg_acc_last_w;
                operand_tag_q <= sg_tag_w;
            end

            if (op_error) begin
                operand_valid_q <= 1'b0;
                operand_valid_mask_q <= '0;
                operand_data_q <= '0;
                operand_weight_q <= '0;
                operand_acc_clear_q <= 1'b0;
                operand_acc_last_q <= 1'b0;
                operand_tag_q <= '0;
            end
        end
    end

endmodule
