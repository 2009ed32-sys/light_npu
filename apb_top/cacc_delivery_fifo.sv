`timescale 1ns/1ps

module cacc_delivery_fifo #(
    parameter int MACCELL_NUM = 8,
    parameter int PSUM_WIDTH  = 32,
    parameter int DEPTH       = 1024,
    parameter int COUNT_WIDTH =
        (((DEPTH <= 2) ? 1 : $clog2(DEPTH)) + 1)
) (
    input  logic clk,
    input  logic rst_n,
    input  logic clear,

    input  logic push_valid,
    output logic push_ready,
    input  logic [MACCELL_NUM-1:0] push_mask,
    input  logic [(MACCELL_NUM*PSUM_WIDTH)-1:0] push_data,

    output logic pop_valid,
    input  logic pop_ready,
    output logic [MACCELL_NUM-1:0] pop_mask,
    output logic [(MACCELL_NUM*PSUM_WIDTH)-1:0] pop_data,

    output logic full,
    output logic empty,
    output logic [COUNT_WIDTH-1:0] stored_count
);

    localparam int PTR_WIDTH =
        (DEPTH <= 2) ? 1 : $clog2(DEPTH);

    logic [PTR_WIDTH-1:0] push_ptr_q;
    logic [PTR_WIDTH-1:0] pop_ptr_q;
    logic [COUNT_WIDTH-1:0] mem_count_q;
    logic [COUNT_WIDTH-1:0] stored_count_w;
    logic pop_valid_q;
    logic [MACCELL_NUM-1:0] pop_mask_q;

    (* ram_style = "block" *) logic [MACCELL_NUM-1:0] mask_mem [0:DEPTH-1];
    logic [PSUM_WIDTH-1:0] pop_data_lane_q [0:MACCELL_NUM-1];

    logic pop_space_w;
    logic push_fire_w;
    logic pop_issue_w;

    function automatic logic [PTR_WIDTH-1:0] next_ptr(
        input logic [PTR_WIDTH-1:0] ptr
    );
        begin
            if (ptr == PTR_WIDTH'(DEPTH - 1)) begin
                next_ptr = '0;
            end else begin
                next_ptr = ptr + 1'b1;
            end
        end
    endfunction

    assign stored_count_w = mem_count_q + COUNT_WIDTH'(pop_valid_q);
    assign pop_space_w = pop_valid_q && pop_ready;

    assign full = stored_count_w >= COUNT_WIDTH'(DEPTH);
    assign empty = (stored_count_w == '0);
    assign stored_count = stored_count_w;

    assign push_ready = !full || pop_space_w;
    assign push_fire_w = push_valid && push_ready;

    assign pop_valid = pop_valid_q;
    assign pop_mask = pop_mask_q;

    assign pop_issue_w =
        (mem_count_q != '0) &&
        (!pop_valid_q || pop_ready);

    genvar lane_idx;
    generate
        for (lane_idx = 0; lane_idx < MACCELL_NUM; lane_idx = lane_idx + 1) begin : g_lane_fifo
            (* ram_style = "block" *) logic [PSUM_WIDTH-1:0] data_mem [0:DEPTH-1];

            assign pop_data[(lane_idx*PSUM_WIDTH) +: PSUM_WIDTH] =
                pop_data_lane_q[lane_idx];

            always_ff @(posedge clk) begin
                if (!rst_n) begin
                    pop_data_lane_q[lane_idx] <= '0;
                end else if (clear) begin
                    pop_data_lane_q[lane_idx] <= '0;
                end else begin
                    if (push_fire_w) begin
                        data_mem[push_ptr_q] <=
                            push_data[(lane_idx*PSUM_WIDTH) +: PSUM_WIDTH];
                    end

                    if (pop_issue_w) begin
                        pop_data_lane_q[lane_idx] <= data_mem[pop_ptr_q];
                    end
                end
            end
        end
    endgenerate

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            push_ptr_q <= '0;
            pop_ptr_q <= '0;
            mem_count_q <= '0;
            pop_valid_q <= 1'b0;
            pop_mask_q <= '0;
        end else if (clear) begin
            push_ptr_q <= '0;
            pop_ptr_q <= '0;
            mem_count_q <= '0;
            pop_valid_q <= 1'b0;
            pop_mask_q <= '0;
        end else begin
            if (push_fire_w) begin
                mask_mem[push_ptr_q] <= push_mask;
                push_ptr_q <= next_ptr(push_ptr_q);
            end

            if (pop_issue_w) begin
                pop_ptr_q <= next_ptr(pop_ptr_q);
                pop_valid_q <= 1'b1;
                pop_mask_q <= mask_mem[pop_ptr_q];
            end else if (pop_valid_q && pop_ready) begin
                pop_valid_q <= 1'b0;
                pop_mask_q <= '0;
            end

            case ({push_fire_w, pop_issue_w})
                2'b10: mem_count_q <= mem_count_q + 1'b1;
                2'b01: mem_count_q <= mem_count_q - 1'b1;
                default: mem_count_q <= mem_count_q;
            endcase
        end
    end

endmodule
