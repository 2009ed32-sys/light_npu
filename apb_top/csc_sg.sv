`timescale 1ns/1ps
// CSC scheduler generator.
//
// This block owns the config latch, address generation pipeline, compact
// scheduler FIFO, and CBUF read request generation.  It emits one-cycle
// operand_capture pulses when the CBUF read data for a scheduler packet is
// available to be formatted by csc_maclane.

(* use_dsp = "no" *)
module csc_sg #(
    parameter int ELEMENT_WIDTH       = 8,
    parameter int BANK_NUM            = 8,
    parameter int MACCELL_NUM         = 8,
    parameter int MACLANE_NUM         = 4,
    parameter int ADDR_WIDTH          = 16,
    parameter int BANK_ADDR_WIDTH     = 10,
    parameter int LEN_WIDTH           = 32,
    parameter int TAG_WIDTH           = 32,
    parameter int ADDR_FIFO_DEPTH     = 4,
    parameter int PREFILL_THRESHOLD   = 1,
    parameter int BANK_SEL_WIDTH      = (BANK_NUM <= 2) ? 1 : $clog2(BANK_NUM),
    parameter int PACK_LANE_WIDTH     = (MACLANE_NUM <= 2) ? 1 : $clog2(MACLANE_NUM)
) (
    input  logic                                   clk,
    input  logic                                   rst_n,

    input  logic                                   config_load,
    input  logic                                   clear,
    input  logic                                   scheduler_enable,
    input  logic                                   read_enable,
    output logic                                   config_invalid,
    output logic                                   prefill_ready,
    output logic                                   scheduler_done,

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

    output logic                                   weight_cbuf_rd_en,
    output logic [BANK_NUM-1:0]                    weight_cbuf_rd_bank_en,
    output logic [(BANK_NUM*BANK_ADDR_WIDTH)-1:0]  weight_cbuf_rd_bank_addr,
    input  logic                                   weight_cbuf_rd_valid,

    input  logic                                   operand_slot_ready,
    output logic                                   operand_capture,
    output logic [BANK_SEL_WIDTH-1:0]              operand_data_bank_start,
    output logic [PACK_LANE_WIDTH-1:0]             operand_data_pack_lane,
    output logic [BANK_SEL_WIDTH-1:0]              operand_weight_bank_start,
    output logic [PACK_LANE_WIDTH-1:0]             operand_weight_pack_lane,
    output logic [MACCELL_NUM-1:0]                 operand_valid_mask,
    output logic                                   operand_acc_clear,
    output logic                                   operand_acc_last,
    output logic [TAG_WIDTH-1:0]                   operand_tag
);

    localparam int ROW_ELEMENT_SHIFT = BANK_SEL_WIDTH + PACK_LANE_WIDTH;
    localparam int FIFO_PTR_WIDTH =
        (ADDR_FIFO_DEPTH <= 2) ? 1 : $clog2(ADDR_FIFO_DEPTH);
    localparam int FIFO_COUNT_WIDTH =
        (ADDR_FIFO_DEPTH <= 1) ? 1 : $clog2(ADDR_FIFO_DEPTH + 1);
    localparam int DATA_PACKET_ELEMENTS = MACLANE_NUM;
    localparam int WEIGHT_PACKET_ELEMENTS = MACCELL_NUM * MACLANE_NUM;
    localparam int CBUF_ROW_ELEMENTS = BANK_NUM * MACLANE_NUM;

    typedef struct packed {
        logic [BANK_NUM-1:0] data_bank_en;
        logic [BANK_SEL_WIDTH-1:0] data_bank_start;
        logic [BANK_ADDR_WIDTH-1:0] data_addr;
        logic [PACK_LANE_WIDTH-1:0] data_pack_lane;

        logic [BANK_NUM-1:0] weight_bank_en;
        logic [BANK_SEL_WIDTH-1:0] weight_bank_start;
        logic [BANK_ADDR_WIDTH-1:0] weight_addr;
        logic [PACK_LANE_WIDTH-1:0] weight_pack_lane;

        logic [MACCELL_NUM-1:0] valid_mask;
        logic acc_clear;
        logic acc_last;
        logic [TAG_WIDTH-1:0] tag;
    } sched_packet_t;

    typedef struct packed {
        logic [LEN_WIDTH-1:0] out_x;
        logic [LEN_WIDTH-1:0] out_y;
        logic [LEN_WIDTH-1:0] kernel_x;
        logic [LEN_WIDTH-1:0] kernel_y;
        logic [LEN_WIDTH-1:0] channel_group;
        logic [LEN_WIDTH-1:0] ocg;
    } sched_stage0_t;

    typedef struct packed {
        logic [LEN_WIDTH-1:0] input_x;
        logic [LEN_WIDTH-1:0] input_y;
        logic [LEN_WIDTH-1:0] kernel_index;
        logic [LEN_WIDTH-1:0] out_x;
        logic [LEN_WIDTH-1:0] out_y;
        logic [LEN_WIDTH-1:0] kernel_x;
        logic [LEN_WIDTH-1:0] kernel_y;
        logic [LEN_WIDTH-1:0] channel_group;
        logic [LEN_WIDTH-1:0] ocg;
    } sched_stage1_t;

    typedef struct packed {
        logic [LEN_WIDTH-1:0] data_group_index;
        logic [LEN_WIDTH-1:0] weight_group_partial;
        logic [LEN_WIDTH-1:0] output_pos;
        logic [LEN_WIDTH-1:0] kernel_x;
        logic [LEN_WIDTH-1:0] kernel_y;
        logic [LEN_WIDTH-1:0] channel_group;
        logic [LEN_WIDTH-1:0] ocg;
    } sched_stage2_t;

    typedef struct packed {
        logic [ADDR_WIDTH-1:0] data_elem_start;
        logic [ADDR_WIDTH-1:0] weight_elem_start;
        logic [LEN_WIDTH-1:0] tag_value;
        logic [LEN_WIDTH-1:0] kernel_x;
        logic [LEN_WIDTH-1:0] kernel_y;
        logic [LEN_WIDTH-1:0] channel_group;
        logic [LEN_WIDTH-1:0] ocg;
    } sched_stage3_t;

    logic [LEN_WIDTH-1:0] atomics_q;
    logic [ADDR_WIDTH-1:0] data_base_q;
    logic [ADDR_WIDTH-1:0] weight_base_q;
    logic [LEN_WIDTH-1:0] input_width_q;
    logic [LEN_WIDTH-1:0] input_height_q;
    logic [LEN_WIDTH-1:0] input_channels_q;
    logic [LEN_WIDTH-1:0] kernel_width_q;
    logic [LEN_WIDTH-1:0] kernel_height_q;
    logic [LEN_WIDTH-1:0] stride_x_q;
    logic [LEN_WIDTH-1:0] stride_y_q;
    logic [LEN_WIDTH-1:0] output_width_q;
    logic [LEN_WIDTH-1:0] output_height_q;
    logic [LEN_WIDTH-1:0] output_channels_q;
    logic [LEN_WIDTH-1:0] channel_groups_q;
    logic [LEN_WIDTH-1:0] output_channel_groups_q;

    logic [LEN_WIDTH-1:0] ocg_q;
    logic [LEN_WIDTH-1:0] out_x_q;
    logic [LEN_WIDTH-1:0] out_y_q;
    logic [LEN_WIDTH-1:0] kernel_x_q;
    logic [LEN_WIDTH-1:0] kernel_y_q;
    logic [LEN_WIDTH-1:0] channel_group_q;
    logic [LEN_WIDTH-1:0] packet_count_q;
    logic generation_done_q;

    (* ram_style = "registers" *)
    sched_packet_t fifo_mem [0:ADDR_FIFO_DEPTH-1];
    logic [FIFO_PTR_WIDTH-1:0] fifo_wr_ptr_q;
    logic [FIFO_PTR_WIDTH-1:0] fifo_rd_ptr_q;
    logic [FIFO_COUNT_WIDTH-1:0] fifo_count_q;

    sched_packet_t push_packet_w;
    sched_packet_t sched_s4_packet_q;
    sched_packet_t issue_packet_w;
    sched_packet_t rd_packet_q;
    logic fifo_empty_w;
    logic fifo_full_w;
    logic fifo_push_w;
    logic fifo_pop_w;
    logic issue_read_w;
    logic rd_pending_q;
    logic read_capture_w;

    logic config_invalid_w;
    logic current_last_w;
    logic atomics_limit_w;
    logic prefill_ready_w;
    logic scheduler_active_w;
    logic scheduler_accept_w;
    logic sched_tail_blocked_w;
    logic sched_pipe_advance_w;
    logic sched_pipe_empty_w;

    sched_stage0_t sched_s0_q;
    sched_stage1_t sched_s1_q;
    sched_stage2_t sched_s2_q;
    sched_stage3_t sched_s3_q;
    logic sched_s0_valid_q;
    logic sched_s1_valid_q;
    logic sched_s2_valid_q;
    logic sched_s3_valid_q;
    logic sched_s4_valid_q;

    logic [LEN_WIDTH-1:0] sched_s1_input_x_w;
    logic [LEN_WIDTH-1:0] sched_s1_input_y_w;
    logic [LEN_WIDTH-1:0] sched_s1_kernel_index_w;
    logic [LEN_WIDTH-1:0] sched_s2_input_pixel_index_w;
    logic [LEN_WIDTH-1:0] sched_s2_data_group_index_w;
    logic [LEN_WIDTH-1:0] sched_s2_weight_group_partial_w;
    logic [LEN_WIDTH-1:0] sched_s2_output_pos_w;
    logic [LEN_WIDTH-1:0] sched_s3_weight_group_index_w;
    logic [LEN_WIDTH-1:0] sched_s3_tag_value_w;
    logic [ADDR_WIDTH-1:0] sched_s3_data_elem_start_w;
    logic [ADDR_WIDTH-1:0] sched_s3_weight_elem_start_w;

    function automatic logic [LEN_WIDTH-1:0] ceil_div_const(
        input logic [LEN_WIDTH-1:0] value,
        input int unsigned divisor
    );
        begin
            if (value == '0) begin
                ceil_div_const = '0;
            end else begin
                ceil_div_const =
                    (value + LEN_WIDTH'(divisor - 1)) / LEN_WIDTH'(divisor);
            end
        end
    endfunction

    function automatic logic [FIFO_PTR_WIDTH-1:0] fifo_ptr_inc(
        input logic [FIFO_PTR_WIDTH-1:0] ptr
    );
        begin
            if (ptr == FIFO_PTR_WIDTH'(ADDR_FIFO_DEPTH - 1)) begin
                fifo_ptr_inc = '0;
            end else begin
                fifo_ptr_inc = ptr + 1'b1;
            end
        end
    endfunction

    function automatic logic [BANK_SEL_WIDTH-1:0] calc_bank_sel(
        input logic [ADDR_WIDTH-1:0] element_addr
    );
        begin
            calc_bank_sel = element_addr[BANK_SEL_WIDTH-1:0];
        end
    endfunction

    function automatic logic [PACK_LANE_WIDTH-1:0] calc_pack_lane(
        input logic [ADDR_WIDTH-1:0] element_addr
    );
        begin
            calc_pack_lane =
                PACK_LANE_WIDTH'(element_addr >> BANK_SEL_WIDTH);
        end
    endfunction

    function automatic logic [BANK_ADDR_WIDTH-1:0] calc_bank_addr(
        input logic [ADDR_WIDTH-1:0] element_addr
    );
        begin
            calc_bank_addr =
                BANK_ADDR_WIDTH'(element_addr >> ROW_ELEMENT_SHIFT);
        end
    endfunction

    function automatic logic [BANK_SEL_WIDTH-1:0] packet_bank(
        input logic [BANK_SEL_WIDTH-1:0] bank_start,
        input int unsigned elem_offset
    );
        int unsigned bank_linear;
        begin
            bank_linear = int'(bank_start) + elem_offset;
            packet_bank = BANK_SEL_WIDTH'(bank_linear % BANK_NUM);
        end
    endfunction

    function automatic logic [PACK_LANE_WIDTH-1:0] packet_pack_lane(
        input logic [BANK_SEL_WIDTH-1:0] bank_start,
        input logic [PACK_LANE_WIDTH-1:0] pack_start,
        input int unsigned elem_offset
    );
        int unsigned bank_linear;
        int unsigned pack_linear;
        begin
            bank_linear = int'(bank_start) + elem_offset;
            pack_linear = int'(pack_start) + (bank_linear / BANK_NUM);
            packet_pack_lane = PACK_LANE_WIDTH'(pack_linear % MACLANE_NUM);
        end
    endfunction

    function automatic logic [BANK_ADDR_WIDTH-1:0] packet_bank_addr(
        input logic [BANK_SEL_WIDTH-1:0] bank_start,
        input logic [PACK_LANE_WIDTH-1:0] pack_start,
        input logic [BANK_ADDR_WIDTH-1:0] addr_start,
        input int unsigned elem_offset
    );
        int unsigned bank_linear;
        int unsigned pack_linear;
        int unsigned addr_linear;
        begin
            bank_linear = int'(bank_start) + elem_offset;
            pack_linear = int'(pack_start) + (bank_linear / BANK_NUM);
            addr_linear = int'(addr_start) + (pack_linear / MACLANE_NUM);
            packet_bank_addr = BANK_ADDR_WIDTH'(addr_linear);
        end
    endfunction

    function automatic logic [BANK_NUM-1:0] make_bank_en(
        input logic [BANK_SEL_WIDTH-1:0] bank_start,
        input int unsigned elem_count
    );
        logic [BANK_NUM-1:0] bank_en;
        begin
            bank_en = '0;
            for (int bank_idx = 0; bank_idx < BANK_NUM; bank_idx = bank_idx + 1) begin
                for (int elem_idx = 0;
                     elem_idx < WEIGHT_PACKET_ELEMENTS;
                     elem_idx = elem_idx + 1) begin
                    if ((elem_idx < elem_count) &&
                        (packet_bank(bank_start, elem_idx) ==
                         BANK_SEL_WIDTH'(bank_idx))) begin
                        bank_en[bank_idx] = 1'b1;
                    end
                end
            end

            make_bank_en = bank_en;
        end
    endfunction

    function automatic logic [(BANK_NUM*BANK_ADDR_WIDTH)-1:0] make_bank_addr_vec(
        input logic [BANK_SEL_WIDTH-1:0] bank_start,
        input logic [PACK_LANE_WIDTH-1:0] pack_start,
        input logic [BANK_ADDR_WIDTH-1:0] addr_start,
        input int unsigned elem_count
    );
        logic [(BANK_NUM*BANK_ADDR_WIDTH)-1:0] addr_vec;
        begin
            addr_vec = '0;

            for (int bank_idx = 0; bank_idx < BANK_NUM; bank_idx = bank_idx + 1) begin
                for (int elem_idx = 0;
                     elem_idx < WEIGHT_PACKET_ELEMENTS;
                     elem_idx = elem_idx + 1) begin
                    if ((elem_idx < elem_count) &&
                        (packet_bank(bank_start, elem_idx) ==
                         BANK_SEL_WIDTH'(bank_idx))) begin
                        addr_vec[(bank_idx*BANK_ADDR_WIDTH)+:BANK_ADDR_WIDTH] =
                            packet_bank_addr(
                                bank_start,
                                pack_start,
                                addr_start,
                                elem_idx
                            );
                    end
                end
            end

            make_bank_addr_vec = addr_vec;
        end
    endfunction

    assign sched_s1_input_x_w =
        (sched_s0_q.out_x * stride_x_q) + sched_s0_q.kernel_x;
    assign sched_s1_input_y_w =
        (sched_s0_q.out_y * stride_y_q) + sched_s0_q.kernel_y;
    assign sched_s1_kernel_index_w =
        (sched_s0_q.kernel_y * kernel_width_q) + sched_s0_q.kernel_x;

    assign sched_s2_input_pixel_index_w =
        (sched_s1_q.input_y * input_width_q) + sched_s1_q.input_x;
    assign sched_s2_data_group_index_w =
        (sched_s2_input_pixel_index_w * channel_groups_q) +
        sched_s1_q.channel_group;
    assign sched_s2_weight_group_partial_w =
        (sched_s1_q.kernel_index * channel_groups_q) +
        sched_s1_q.channel_group;
    assign sched_s2_output_pos_w =
        (sched_s1_q.out_y * output_width_q) + sched_s1_q.out_x;

    assign sched_s3_weight_group_index_w =
        (sched_s2_q.weight_group_partial * output_channel_groups_q) +
        sched_s2_q.ocg;
    assign sched_s3_tag_value_w =
        (sched_s2_q.output_pos * output_channel_groups_q) + sched_s2_q.ocg;
    assign sched_s3_data_elem_start_w =
        data_base_q +
        ADDR_WIDTH'(sched_s2_q.data_group_index *
                    LEN_WIDTH'(DATA_PACKET_ELEMENTS));
    assign sched_s3_weight_elem_start_w =
        weight_base_q +
        ADDR_WIDTH'(sched_s3_weight_group_index_w *
                    LEN_WIDTH'(WEIGHT_PACKET_ELEMENTS));

    always_comb begin
        push_packet_w = '0;

        push_packet_w.data_bank_start =
            calc_bank_sel(sched_s3_q.data_elem_start);
        push_packet_w.data_pack_lane  =
            calc_pack_lane(sched_s3_q.data_elem_start);
        push_packet_w.data_addr       =
            calc_bank_addr(sched_s3_q.data_elem_start);
        push_packet_w.data_bank_en    =
            make_bank_en(
                push_packet_w.data_bank_start,
                DATA_PACKET_ELEMENTS
            );

        push_packet_w.weight_bank_start =
            calc_bank_sel(sched_s3_q.weight_elem_start);
        push_packet_w.weight_pack_lane  =
            calc_pack_lane(sched_s3_q.weight_elem_start);
        push_packet_w.weight_addr       =
            calc_bank_addr(sched_s3_q.weight_elem_start);
        push_packet_w.weight_bank_en    =
            make_bank_en(
                push_packet_w.weight_bank_start,
                WEIGHT_PACKET_ELEMENTS
            );

        push_packet_w.acc_clear =
            (sched_s3_q.kernel_x == '0) &&
            (sched_s3_q.kernel_y == '0) &&
            (sched_s3_q.channel_group == '0);

        push_packet_w.acc_last =
            ((sched_s3_q.kernel_x + 1'b1) >= kernel_width_q) &&
            ((sched_s3_q.kernel_y + 1'b1) >= kernel_height_q) &&
            ((sched_s3_q.channel_group + 1'b1) >= channel_groups_q);

        push_packet_w.tag = TAG_WIDTH'(sched_s3_q.tag_value);

        for (int cell_idx = 0; cell_idx < MACCELL_NUM; cell_idx = cell_idx + 1) begin
            push_packet_w.valid_mask[cell_idx] =
                ((sched_s3_q.ocg * LEN_WIDTH'(MACCELL_NUM)) +
                 LEN_WIDTH'(cell_idx)) <
                output_channels_q;
        end
    end

    assign fifo_empty_w = fifo_count_q == '0;
    assign fifo_full_w =
        fifo_count_q == FIFO_COUNT_WIDTH'(ADDR_FIFO_DEPTH);
    assign prefill_ready_w =
        fifo_count_q >= FIFO_COUNT_WIDTH'(PREFILL_THRESHOLD);
    assign issue_packet_w = fifo_mem[fifo_rd_ptr_q];
    assign scheduler_active_w = scheduler_enable;
    assign sched_tail_blocked_w =
        sched_s4_valid_q && fifo_full_w && !fifo_pop_w;
    assign sched_pipe_advance_w = !sched_tail_blocked_w;
    assign scheduler_accept_w =
        scheduler_active_w &&
        !generation_done_q &&
        sched_pipe_advance_w;
    assign sched_pipe_empty_w =
        !sched_s0_valid_q &&
        !sched_s1_valid_q &&
        !sched_s2_valid_q &&
        !sched_s3_valid_q &&
        !sched_s4_valid_q;

    assign issue_read_w =
        read_enable &&
        !fifo_empty_w &&
        !rd_pending_q &&
        operand_slot_ready;

    assign fifo_push_w = sched_s4_valid_q && !sched_tail_blocked_w;
    assign fifo_pop_w = issue_read_w;

    assign read_capture_w =
        rd_pending_q &&
        data_cbuf_rd_valid &&
        weight_cbuf_rd_valid &&
        operand_slot_ready;

    assign current_last_w =
        ((channel_group_q + 1'b1) >= channel_groups_q) &&
        ((kernel_x_q + 1'b1) >= kernel_width_q) &&
        ((kernel_y_q + 1'b1) >= kernel_height_q) &&
        ((out_x_q + 1'b1) >= output_width_q) &&
        ((out_y_q + 1'b1) >= output_height_q) &&
        ((ocg_q + 1'b1) >= output_channel_groups_q);

    assign atomics_limit_w =
        (atomics_q != '0) &&
        ((packet_count_q + 1'b1) >= atomics_q);

    assign config_invalid_w =
        (input_width == '0) ||
        (input_height == '0) ||
        (input_channels == '0) ||
        (kernel_width == '0) ||
        (kernel_height == '0) ||
        (stride_x == '0) ||
        (stride_y == '0) ||
        (output_width == '0) ||
        (output_height == '0) ||
        (output_channels == '0) ||
        (DATA_PACKET_ELEMENTS > CBUF_ROW_ELEMENTS) ||
        (WEIGHT_PACKET_ELEMENTS > CBUF_ROW_ELEMENTS);

    assign config_invalid = config_invalid_w;
    assign prefill_ready = prefill_ready_w;
    assign scheduler_done =
        generation_done_q &&
        sched_pipe_empty_w &&
        fifo_empty_w &&
        !rd_pending_q;

    assign data_cbuf_rd_en = issue_read_w;
    assign data_cbuf_rd_bank_en =
        issue_read_w ? issue_packet_w.data_bank_en : '0;
    assign data_cbuf_rd_bank_addr =
        issue_read_w ?
        make_bank_addr_vec(
            issue_packet_w.data_bank_start,
            issue_packet_w.data_pack_lane,
            issue_packet_w.data_addr,
            DATA_PACKET_ELEMENTS
        ) : '0;

    assign weight_cbuf_rd_en = issue_read_w;
    assign weight_cbuf_rd_bank_en =
        issue_read_w ? issue_packet_w.weight_bank_en : '0;
    assign weight_cbuf_rd_bank_addr =
        issue_read_w ?
        make_bank_addr_vec(
            issue_packet_w.weight_bank_start,
            issue_packet_w.weight_pack_lane,
            issue_packet_w.weight_addr,
            WEIGHT_PACKET_ELEMENTS
        ) : '0;

    assign operand_capture = read_capture_w;
    assign operand_data_bank_start = rd_packet_q.data_bank_start;
    assign operand_data_pack_lane = rd_packet_q.data_pack_lane;
    assign operand_weight_bank_start = rd_packet_q.weight_bank_start;
    assign operand_weight_pack_lane = rd_packet_q.weight_pack_lane;
    assign operand_valid_mask = rd_packet_q.valid_mask;
    assign operand_acc_clear = rd_packet_q.acc_clear;
    assign operand_acc_last = rd_packet_q.acc_last;
    assign operand_tag = rd_packet_q.tag;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            atomics_q <= '0;
            data_base_q <= '0;
            weight_base_q <= '0;
            input_width_q <= '0;
            input_height_q <= '0;
            input_channels_q <= '0;
            kernel_width_q <= '0;
            kernel_height_q <= '0;
            stride_x_q <= '0;
            stride_y_q <= '0;
            output_width_q <= '0;
            output_height_q <= '0;
            output_channels_q <= '0;
            channel_groups_q <= '0;
            output_channel_groups_q <= '0;

            ocg_q <= '0;
            out_x_q <= '0;
            out_y_q <= '0;
            kernel_x_q <= '0;
            kernel_y_q <= '0;
            channel_group_q <= '0;
            packet_count_q <= '0;
            generation_done_q <= 1'b0;

            fifo_wr_ptr_q <= '0;
            fifo_rd_ptr_q <= '0;
            fifo_count_q <= '0;
            rd_packet_q <= '0;
            rd_pending_q <= 1'b0;

            sched_s0_q <= '0;
            sched_s1_q <= '0;
            sched_s2_q <= '0;
            sched_s3_q <= '0;
            sched_s4_packet_q <= '0;
            sched_s0_valid_q <= 1'b0;
            sched_s1_valid_q <= 1'b0;
            sched_s2_valid_q <= 1'b0;
            sched_s3_valid_q <= 1'b0;
            sched_s4_valid_q <= 1'b0;
        end else begin
            if (clear) begin
                generation_done_q <= 1'b0;
                fifo_wr_ptr_q <= '0;
                fifo_rd_ptr_q <= '0;
                fifo_count_q <= '0;
                rd_packet_q <= '0;
                rd_pending_q <= 1'b0;

                sched_s0_q <= '0;
                sched_s1_q <= '0;
                sched_s2_q <= '0;
                sched_s3_q <= '0;
                sched_s4_packet_q <= '0;
                sched_s0_valid_q <= 1'b0;
                sched_s1_valid_q <= 1'b0;
                sched_s2_valid_q <= 1'b0;
                sched_s3_valid_q <= 1'b0;
                sched_s4_valid_q <= 1'b0;
            end else if (config_load && !config_invalid_w) begin
                atomics_q <= atomics;
                data_base_q <= data_base;
                weight_base_q <= weight_base;
                input_width_q <= input_width;
                input_height_q <= input_height;
                input_channels_q <= input_channels;
                kernel_width_q <= kernel_width;
                kernel_height_q <= kernel_height;
                stride_x_q <= stride_x;
                stride_y_q <= stride_y;
                output_width_q <= output_width;
                output_height_q <= output_height;
                output_channels_q <= output_channels;
                channel_groups_q <= ceil_div_const(input_channels, MACLANE_NUM);
                output_channel_groups_q <=
                    ceil_div_const(output_channels, MACCELL_NUM);

                ocg_q <= '0;
                out_x_q <= '0;
                out_y_q <= '0;
                kernel_x_q <= '0;
                kernel_y_q <= '0;
                channel_group_q <= '0;
                packet_count_q <= '0;
                generation_done_q <= 1'b0;

                fifo_wr_ptr_q <= '0;
                fifo_rd_ptr_q <= '0;
                fifo_count_q <= '0;
                rd_packet_q <= '0;
                rd_pending_q <= 1'b0;

                sched_s0_q <= '0;
                sched_s1_q <= '0;
                sched_s2_q <= '0;
                sched_s3_q <= '0;
                sched_s4_packet_q <= '0;
                sched_s0_valid_q <= 1'b0;
                sched_s1_valid_q <= 1'b0;
                sched_s2_valid_q <= 1'b0;
                sched_s3_valid_q <= 1'b0;
                sched_s4_valid_q <= 1'b0;
            end else begin
                if (fifo_push_w) begin
                    fifo_mem[fifo_wr_ptr_q] <= sched_s4_packet_q;
                    fifo_wr_ptr_q <= fifo_ptr_inc(fifo_wr_ptr_q);
                end

                if (sched_pipe_advance_w) begin
                    sched_s4_valid_q <= sched_s3_valid_q;
                    sched_s4_packet_q <= push_packet_w;

                    sched_s3_valid_q <= sched_s2_valid_q;
                    sched_s3_q <= '{
                        data_elem_start:   sched_s3_data_elem_start_w,
                        weight_elem_start: sched_s3_weight_elem_start_w,
                        tag_value:         sched_s3_tag_value_w,
                        kernel_x:          sched_s2_q.kernel_x,
                        kernel_y:          sched_s2_q.kernel_y,
                        channel_group:     sched_s2_q.channel_group,
                        ocg:               sched_s2_q.ocg
                    };

                    sched_s2_valid_q <= sched_s1_valid_q;
                    sched_s2_q <= '{
                        data_group_index:    sched_s2_data_group_index_w,
                        weight_group_partial:sched_s2_weight_group_partial_w,
                        output_pos:          sched_s2_output_pos_w,
                        kernel_x:            sched_s1_q.kernel_x,
                        kernel_y:            sched_s1_q.kernel_y,
                        channel_group:       sched_s1_q.channel_group,
                        ocg:                 sched_s1_q.ocg
                    };

                    sched_s1_valid_q <= sched_s0_valid_q;
                    sched_s1_q <= '{
                        input_x:       sched_s1_input_x_w,
                        input_y:       sched_s1_input_y_w,
                        kernel_index:  sched_s1_kernel_index_w,
                        out_x:         sched_s0_q.out_x,
                        out_y:         sched_s0_q.out_y,
                        kernel_x:      sched_s0_q.kernel_x,
                        kernel_y:      sched_s0_q.kernel_y,
                        channel_group: sched_s0_q.channel_group,
                        ocg:           sched_s0_q.ocg
                    };

                    sched_s0_valid_q <= scheduler_accept_w;
                    sched_s0_q <= '{
                        out_x:         out_x_q,
                        out_y:         out_y_q,
                        kernel_x:      kernel_x_q,
                        kernel_y:      kernel_y_q,
                        channel_group: channel_group_q,
                        ocg:           ocg_q
                    };
                end

                if (scheduler_accept_w) begin
                    packet_count_q <= packet_count_q + 1'b1;

                    if (current_last_w || atomics_limit_w) begin
                        generation_done_q <= 1'b1;
                    end else if ((channel_group_q + 1'b1) < channel_groups_q) begin
                        channel_group_q <= channel_group_q + 1'b1;
                    end else begin
                        channel_group_q <= '0;

                        if ((kernel_x_q + 1'b1) < kernel_width_q) begin
                            kernel_x_q <= kernel_x_q + 1'b1;
                        end else begin
                            kernel_x_q <= '0;

                            if ((kernel_y_q + 1'b1) < kernel_height_q) begin
                                kernel_y_q <= kernel_y_q + 1'b1;
                            end else begin
                                kernel_y_q <= '0;

                                if ((out_x_q + 1'b1) < output_width_q) begin
                                    out_x_q <= out_x_q + 1'b1;
                                end else begin
                                    out_x_q <= '0;

                                    if ((out_y_q + 1'b1) < output_height_q) begin
                                        out_y_q <= out_y_q + 1'b1;
                                    end else begin
                                        out_y_q <= '0;
                                        ocg_q <= ocg_q + 1'b1;
                                    end
                                end
                            end
                        end
                    end
                end

                if (fifo_pop_w) begin
                    rd_packet_q <= issue_packet_w;
                    fifo_rd_ptr_q <= fifo_ptr_inc(fifo_rd_ptr_q);
                    rd_pending_q <= 1'b1;
                end

                case ({fifo_push_w, fifo_pop_w})
                    2'b10: fifo_count_q <= fifo_count_q + 1'b1;
                    2'b01: fifo_count_q <= fifo_count_q - 1'b1;
                    default: fifo_count_q <= fifo_count_q;
                endcase

                if (read_capture_w) begin
                    rd_pending_q <= 1'b0;
                end

            end
        end
    end

endmodule
