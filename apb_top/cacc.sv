`timescale 1ns/1ps

module cacc #(
    parameter int MACCELL_NUM = 8,
    parameter int PSUM_WIDTH  = 32,
    parameter int TAG_WIDTH   = 32,
    parameter int CFG_WIDTH   = 32,
    parameter int DELIVERY_DEPTH = 1024
) (
    input  logic clk,
    input  logic rst_n,

    input  logic op_enable,
    input  logic op_start,
    output logic op_ready,
    output logic op_busy,
    output logic op_done,
    output logic op_error,

    input  logic [CFG_WIDTH-1:0] d_dataout_size_0,
    input  logic [CFG_WIDTH-1:0] d_dataout_size_1,
    input  logic [CFG_WIDTH-1:0] d_dataout_addr,
    input  logic [CFG_WIDTH-1:0] d_line_stride,
    input  logic [CFG_WIDTH-1:0] d_surf_stride,
    input  logic [CFG_WIDTH-1:0] d_dataout_map,

    input  logic prepare_valid,
    input  logic prepare_read,
    input  logic [MACCELL_NUM-1:0] prepare_mask,
    input  logic prepare_acc_clear,
    input  logic prepare_acc_last,

    input  logic psum_valid,
    output logic psum_ready,
    input  logic [MACCELL_NUM-1:0] psum_valid_mask,
    input  logic [(MACCELL_NUM*PSUM_WIDTH)-1:0] psum_data,
    input  logic psum_acc_clear,
    input  logic psum_acc_last,
    input  logic [TAG_WIDTH-1:0] psum_tag,

    output logic                       sdp_valid,
    input  logic                       sdp_ready,
    output logic [MACCELL_NUM-1:0]     sdp_mask,
    output logic [(MACCELL_NUM*PSUM_WIDTH)-1:0] sdp_data,
    output logic                       sdp_last
);

    localparam int DELIVERY_PTR_WIDTH =
        (DELIVERY_DEPTH <= 2) ? 1 : $clog2(DELIVERY_DEPTH);
    localparam int DELIVERY_COUNT_WIDTH = DELIVERY_PTR_WIDTH + 1;
    localparam int DELIVERY_DATA_WIDTH = MACCELL_NUM * PSUM_WIDTH;

    logic prepare_pending_q;
    logic prepare_acc_last_q;

    logic [CFG_WIDTH-1:0] d_dataout_size_0_q;
    logic [CFG_WIDTH-1:0] d_dataout_size_1_q;
    logic [CFG_WIDTH-1:0] d_dataout_addr_q;
    logic [CFG_WIDTH-1:0] d_line_stride_q;
    logic [CFG_WIDTH-1:0] d_surf_stride_q;

    logic op_done_q;
    logic op_error_q;

    logic delivery_push_ready_w;
    logic delivery_pop_valid_w;
    logic delivery_pop_ready_w;
    logic [MACCELL_NUM-1:0] delivery_pop_mask_w;
    logic [DELIVERY_DATA_WIDTH-1:0] delivery_pop_data_w;
    logic delivery_full_w;
    logic delivery_empty_unused;
    logic [DELIVERY_COUNT_WIDTH-1:0] delivery_count_unused;

    logic rd_done_unused;
    logic rd_error_w;
    logic rd_out_valid_w;
    logic [MACCELL_NUM-1:0] rd_out_mask_w;
    logic [DELIVERY_DATA_WIDTH-1:0] rd_out_data_w;
    logic [(MACCELL_NUM*CFG_WIDTH)-1:0] rd_out_addr_unused;
    logic rd_out_last_w;

    logic prepare_accept_w;
    logic psum_accept_w;
    logic prepare_overrun_w;
    logic psum_unexpected_w;
    logic delivery_push_w;
    logic delivery_overflow_w;
    logic psum_nonfinal_w;

    assign prepare_accept_w = op_enable && prepare_valid;

    // prepare_acc_last arrives before the psum vector. Use that early hint to
    // stop CMAC before a final psum reaches a full delivery FIFO.
    assign psum_ready =
        op_enable &&
        prepare_pending_q &&
        (!prepare_acc_last_q || delivery_push_ready_w);
    assign psum_accept_w = psum_valid && psum_ready;
    assign delivery_push_w = psum_accept_w && psum_acc_last;
    assign delivery_overflow_w = delivery_push_w && !delivery_push_ready_w;
    assign psum_nonfinal_w = psum_accept_w && !psum_acc_last;

    assign prepare_overrun_w =
        prepare_accept_w && prepare_pending_q && !psum_accept_w;
    assign psum_unexpected_w =
        op_enable && psum_valid && !prepare_pending_q;

    assign op_ready = op_enable && !prepare_pending_q && !delivery_full_w;
    assign op_busy = op_enable && prepare_pending_q;
    assign op_done = op_done_q;
    assign op_error = op_error_q || rd_error_w;

    cacc_delivery_fifo #(
        .MACCELL_NUM(MACCELL_NUM),
        .PSUM_WIDTH (PSUM_WIDTH),
        .DEPTH      (DELIVERY_DEPTH),
        .COUNT_WIDTH(DELIVERY_COUNT_WIDTH)
    ) u_delivery_fifo (
        .clk         (clk),
        .rst_n       (rst_n),
        .clear       (!op_enable || op_start),
        .push_valid  (delivery_push_w),
        .push_ready  (delivery_push_ready_w),
        .push_mask   (psum_valid_mask),
        .push_data   (psum_data),
        .pop_valid   (delivery_pop_valid_w),
        .pop_ready   (delivery_pop_ready_w),
        .pop_mask    (delivery_pop_mask_w),
        .pop_data    (delivery_pop_data_w),
        .full        (delivery_full_w),
        .empty       (delivery_empty_unused),
        .stored_count(delivery_count_unused)
    );

    cacc_rd_ptr #(
        .MACCELL_NUM(MACCELL_NUM),
        .PSUM_WIDTH (PSUM_WIDTH),
        .CFG_WIDTH  (CFG_WIDTH)
    ) u_rd_ptr (
        .clk               (clk),
        .rst_n             (rst_n),
        .op_enable         (op_enable),
        .op_start          (op_start),
        .op_done           (rd_done_unused),
        .op_error          (rd_error_w),
        .d_dataout_size_0  (d_dataout_size_0_q),
        .d_dataout_size_1  (d_dataout_size_1_q),
        .d_dataout_addr    (d_dataout_addr_q),
        .d_line_stride     (d_line_stride_q),
        .d_surf_stride     (d_surf_stride_q),
        .fifo_valid        (delivery_pop_valid_w),
        .fifo_ready        (delivery_pop_ready_w),
        .fifo_mask         (delivery_pop_mask_w),
        .fifo_data         (delivery_pop_data_w),
        .out_valid         (rd_out_valid_w),
        .out_ready         (sdp_ready),
        .out_mask          (rd_out_mask_w),
        .out_data          (rd_out_data_w),
        .out_addr          (rd_out_addr_unused),
        .out_last          (rd_out_last_w)
    );

    assign sdp_valid = rd_out_valid_w;
    assign sdp_mask  = rd_out_mask_w;
    assign sdp_data  = rd_out_data_w;
    assign sdp_last  = rd_out_last_w;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            prepare_pending_q <= 1'b0;
            prepare_acc_last_q <= 1'b0;
            d_dataout_size_0_q <= '0;
            d_dataout_size_1_q <= '0;
            d_dataout_addr_q <= '0;
            d_line_stride_q <= '0;
            d_surf_stride_q <= '0;
            op_done_q <= 1'b0;
            op_error_q <= 1'b0;
        end else if (!op_enable || op_start) begin
            prepare_pending_q <= 1'b0;
            prepare_acc_last_q <= 1'b0;
            d_dataout_size_0_q <= d_dataout_size_0;
            d_dataout_size_1_q <= d_dataout_size_1;
            d_dataout_addr_q <= d_dataout_addr;
            d_line_stride_q <= d_line_stride;
            d_surf_stride_q <= d_surf_stride;
            op_done_q <= 1'b0;
            op_error_q <= 1'b0;
        end else begin
            op_done_q <= 1'b0;

            if (prepare_overrun_w ||
                psum_unexpected_w ||
                delivery_overflow_w ||
                psum_nonfinal_w) begin
                op_error_q <= 1'b1;
            end

            if (prepare_accept_w && !prepare_overrun_w) begin
                prepare_pending_q <= 1'b1;
                prepare_acc_last_q <= prepare_acc_last;
            end

            if (psum_accept_w) begin
                prepare_pending_q <= 1'b0;
                op_done_q <= psum_acc_last;
            end
        end
    end

endmodule
