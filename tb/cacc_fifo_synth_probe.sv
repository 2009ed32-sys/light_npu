`timescale 1ns/1ps

module cacc_fifo_synth_probe #(
    parameter int MACCELL_NUM = 8,
    parameter int PSUM_WIDTH = 32,
    parameter int DEPTH = 1024
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
    output logic empty
);

    localparam int COUNT_WIDTH =
        ((DEPTH <= 2) ? 1 : $clog2(DEPTH)) + 1;

    logic [COUNT_WIDTH-1:0] stored_count_unused;

    cacc_delivery_fifo #(
        .MACCELL_NUM(MACCELL_NUM),
        .PSUM_WIDTH (PSUM_WIDTH),
        .DEPTH      (DEPTH),
        .COUNT_WIDTH(COUNT_WIDTH)
    ) u_delivery_fifo (
        .clk         (clk),
        .rst_n       (rst_n),
        .clear       (clear),
        .push_valid  (push_valid),
        .push_ready  (push_ready),
        .push_mask   (push_mask),
        .push_data   (push_data),
        .pop_valid   (pop_valid),
        .pop_ready   (pop_ready),
        .pop_mask    (pop_mask),
        .pop_data    (pop_data),
        .full        (full),
        .empty       (empty),
        .stored_count(stored_count_unused)
    );

endmodule
