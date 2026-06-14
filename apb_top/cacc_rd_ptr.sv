`timescale 1ns/1ps

module cacc_rd_ptr #(
    parameter int MACCELL_NUM = 8,
    parameter int PSUM_WIDTH  = 32,
    parameter int CFG_WIDTH   = 32
) (
    input  logic clk,
    input  logic rst_n,

    input  logic op_enable,
    input  logic op_start,
    output logic op_done,
    output logic op_error,

    input  logic [CFG_WIDTH-1:0] d_dataout_size_0,
    input  logic [CFG_WIDTH-1:0] d_dataout_size_1,
    input  logic [CFG_WIDTH-1:0] d_dataout_addr,
    input  logic [CFG_WIDTH-1:0] d_line_stride,
    input  logic [CFG_WIDTH-1:0] d_surf_stride,

    input  logic fifo_valid,
    output logic fifo_ready,
    input  logic [MACCELL_NUM-1:0] fifo_mask,
    input  logic [(MACCELL_NUM*PSUM_WIDTH)-1:0] fifo_data,

    output logic out_valid,
    input  logic out_ready,
    output logic [MACCELL_NUM-1:0] out_mask,
    output logic [(MACCELL_NUM*PSUM_WIDTH)-1:0] out_data,
    output logic [(MACCELL_NUM*CFG_WIDTH)-1:0] out_addr,
    output logic out_last
);

    logic [CFG_WIDTH-1:0] output_width_q;
    logic [CFG_WIDTH-1:0] output_height_q;
    logic [CFG_WIDTH-1:0] output_channels_q;
    logic [CFG_WIDTH-1:0] line_stride_q;
    logic [CFG_WIDTH-1:0] surf_stride_q;
    logic [CFG_WIDTH-1:0] x_q;
    logic [CFG_WIDTH-1:0] y_q;
    logic [CFG_WIDTH-1:0] ocg_q;
    logic [CFG_WIDTH-1:0] row_offset_q;
    logic [CFG_WIDTH-1:0] cell_base_addr_q [0:MACCELL_NUM-1];

    logic out_valid_q;
    logic [MACCELL_NUM-1:0] out_mask_q;
    logic [(MACCELL_NUM*PSUM_WIDTH)-1:0] out_data_q;
    logic [(MACCELL_NUM*CFG_WIDTH)-1:0] out_addr_q;
    logic out_last_q;
    logic op_done_q;
    logic op_error_q;
    logic config_invalid_q;

    logic fifo_fire_w;
    logic x_last_w;
    logic y_last_w;
    logic ocg_last_w;
    logic entry_last_w;
    logic [CFG_WIDTH-1:0] group_addr_step_w;

    assign group_addr_step_w = CFG_WIDTH'(MACCELL_NUM) * surf_stride_q;
    assign x_last_w = (x_q + 1'b1) >= output_width_q;
    assign y_last_w = (y_q + 1'b1) >= output_height_q;
    assign ocg_last_w =
        ((ocg_q + 1'b1) * CFG_WIDTH'(MACCELL_NUM)) >= output_channels_q;
    assign entry_last_w = x_last_w && y_last_w && ocg_last_w;

    assign fifo_ready =
        op_enable &&
        !config_invalid_q &&
        (!out_valid_q || out_ready);
    assign fifo_fire_w = fifo_valid && fifo_ready;

    assign out_valid = out_valid_q;
    assign out_mask = out_mask_q;
    assign out_data = out_data_q;
    assign out_addr = out_addr_q;
    assign out_last = out_last_q;
    assign op_done = op_done_q;
    assign op_error = op_error_q;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            output_width_q <= '0;
            output_height_q <= '0;
            output_channels_q <= '0;
            line_stride_q <= '0;
            surf_stride_q <= '0;
            x_q <= '0;
            y_q <= '0;
            ocg_q <= '0;
            row_offset_q <= '0;
            out_valid_q <= 1'b0;
            out_mask_q <= '0;
            out_data_q <= '0;
            out_addr_q <= '0;
            out_last_q <= 1'b0;
            op_done_q <= 1'b0;
            op_error_q <= 1'b0;
            config_invalid_q <= 1'b0;
            for (int cell_idx = 0; cell_idx < MACCELL_NUM; cell_idx = cell_idx + 1) begin
                cell_base_addr_q[cell_idx] <= '0;
            end
        end else if (!op_enable) begin
            output_width_q <= '0;
            output_height_q <= '0;
            output_channels_q <= '0;
            line_stride_q <= '0;
            surf_stride_q <= '0;
            x_q <= '0;
            y_q <= '0;
            ocg_q <= '0;
            row_offset_q <= '0;
            out_valid_q <= 1'b0;
            out_mask_q <= '0;
            out_data_q <= '0;
            out_addr_q <= '0;
            out_last_q <= 1'b0;
            op_done_q <= 1'b0;
            op_error_q <= 1'b0;
            config_invalid_q <= 1'b0;
            for (int cell_idx = 0; cell_idx < MACCELL_NUM; cell_idx = cell_idx + 1) begin
                cell_base_addr_q[cell_idx] <= '0;
            end
        end else if (op_start) begin
            output_width_q <= CFG_WIDTH'(d_dataout_size_0[15:0]);
            output_height_q <= CFG_WIDTH'(d_dataout_size_0[31:16]);
            output_channels_q <= d_dataout_size_1;
            line_stride_q <= d_line_stride;
            surf_stride_q <= d_surf_stride;
            x_q <= '0;
            y_q <= '0;
            ocg_q <= '0;
            row_offset_q <= '0;
            out_valid_q <= 1'b0;
            out_mask_q <= '0;
            out_data_q <= '0;
            out_addr_q <= '0;
            out_last_q <= 1'b0;
            op_done_q <= 1'b0;
            config_invalid_q <=
                (d_dataout_size_0[15:0] == 16'h0000) ||
                (d_dataout_size_0[31:16] == 16'h0000) ||
                (d_dataout_size_1 == '0);
            op_error_q <=
                (d_dataout_size_0[15:0] == 16'h0000) ||
                (d_dataout_size_0[31:16] == 16'h0000) ||
                (d_dataout_size_1 == '0);

            for (int cell_idx = 0; cell_idx < MACCELL_NUM; cell_idx = cell_idx + 1) begin
                cell_base_addr_q[cell_idx] <=
                    d_dataout_addr +
                    (CFG_WIDTH'(cell_idx) * d_surf_stride);
            end
        end else begin
            op_done_q <= 1'b0;

            if (out_valid_q && out_ready) begin
                out_valid_q <= 1'b0;
                out_last_q <= 1'b0;
            end

            if (fifo_fire_w) begin
                out_valid_q <= 1'b1;
                out_mask_q <= fifo_mask;
                out_data_q <= fifo_data;
                out_last_q <= entry_last_w;

                for (int cell_idx = 0; cell_idx < MACCELL_NUM; cell_idx = cell_idx + 1) begin
                    out_addr_q[(cell_idx*CFG_WIDTH) +: CFG_WIDTH] <=
                        cell_base_addr_q[cell_idx] + row_offset_q + x_q;
                end

                if (entry_last_w) begin
                    op_done_q <= 1'b1;
                end

                if (!x_last_w) begin
                    x_q <= x_q + 1'b1;
                end else begin
                    x_q <= '0;

                    if (!y_last_w) begin
                        y_q <= y_q + 1'b1;
                        row_offset_q <= row_offset_q + line_stride_q;
                    end else begin
                        y_q <= '0;
                        row_offset_q <= '0;

                        if (!ocg_last_w) begin
                            ocg_q <= ocg_q + 1'b1;
                            for (int cell_idx = 0; cell_idx < MACCELL_NUM; cell_idx = cell_idx + 1) begin
                                cell_base_addr_q[cell_idx] <=
                                    cell_base_addr_q[cell_idx] + group_addr_step_w;
                            end
                        end
                    end
                end
            end
        end
    end

endmodule
