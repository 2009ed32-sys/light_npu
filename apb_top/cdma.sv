`timescale 1 ns / 1 ps
// CDMA integration shell.
//
// Control/configuration registers are supplied by an external CSB/AXI-Lite
// block. AXI read stream words are routed directly into data or weight CBUF
// write ports.

module cdma #(
    parameter int ADDR_WIDTH       = 32,
    parameter int AXI_DATA_WIDTH   = 32,
    parameter int CBUF_WORD_WIDTH  = 32,
    parameter int ELEMENT_WIDTH    = 8,
    parameter int LEN_WIDTH        = 32,
    parameter int CBUF_ADDR_WIDTH = 16,
    parameter int BANK_NUM     = 8,
    parameter int BANK_SEL_WIDTH  = (BANK_NUM <= 2) ? 1 : $clog2(BANK_NUM),
    parameter int BANK_ADDR_WIDTH = 10,
    parameter int CSB_DATA_WIDTH  = 32,
    parameter int AXI_BURST_LEN   = 8
) (
    input  logic                       clk,
    input  logic                       rst_n,

    input  logic [CSB_DATA_WIDTH-1:0]  CDMA_CONTROL,
    output logic [CSB_DATA_WIDTH-1:0]  CDMA_STATUS,
    input  logic [CSB_DATA_WIDTH-1:0]  DATA_MATRIX_WIDTH,
    input  logic [CSB_DATA_WIDTH-1:0]  DATA_MATRIX_HEIGHT,
    input  logic [CSB_DATA_WIDTH-1:0]  DATA_CHANNEL_COUNT,
    input  logic [CSB_DATA_WIDTH-1:0]  DATA_DST_BASE,
    input  logic [CSB_DATA_WIDTH-1:0]  WEIGHT_MATRIX_WIDTH,
    input  logic [CSB_DATA_WIDTH-1:0]  WEIGHT_MATRIX_HEIGHT,
    input  logic [CSB_DATA_WIDTH-1:0]  WEIGHT_CHANNEL_COUNT,
    input  logic [CSB_DATA_WIDTH-1:0]  WEIGHT_DST_BASE,

    output logic [BANK_NUM-1:0] data_cbuf_wr_bank_en,
    output logic [(BANK_NUM*BANK_ADDR_WIDTH)-1:0] data_cbuf_wr_bank_addr,
    output logic [(BANK_NUM*CBUF_WORD_WIDTH)-1:0] data_cbuf_wr_bank_data,

    output logic [BANK_NUM-1:0] weight_cbuf_wr_bank_en,
    output logic [(BANK_NUM*BANK_ADDR_WIDTH)-1:0] weight_cbuf_wr_bank_addr,
    output logic [(BANK_NUM*CBUF_WORD_WIDTH)-1:0] weight_cbuf_wr_bank_data,

    output logic                       axi_load_start,
    output logic [ADDR_WIDTH-1:0]      axi_txn_addr,
    output logic                       axi_init_txn,
    input  logic                       axi_stream_valid,
    output logic                       axi_stream_ready,
    input  logic [AXI_DATA_WIDTH-1:0]      axi_stream_data,
    input  logic                       axi_txn_done,
    input  logic                       axi_error,
    output logic                       axi_stream_sel
);

    logic data_busy;
    logic data_done_pulse;
    logic data_error;
    logic weight_busy;
    logic weight_done_pulse;
    logic weight_error;
    logic data_done_sticky_q;
    logic weight_done_sticky_q;
    logic data_done_status;
    logic weight_done_status;

    logic data_fill_request;
    logic data_fill_done;
    logic weight_fill_request;
    logic weight_fill_done;
    logic data_stream_ready;
    logic weight_stream_ready;
    logic [LEN_WIDTH-1:0] data_load_total_words;
    logic [LEN_WIDTH-1:0] weight_load_total_words;

    assign axi_stream_ready =
        (axi_stream_sel == 1'b0) ? data_stream_ready : weight_stream_ready;
    assign data_done_status =
        (data_done_sticky_q || data_done_pulse) && !CDMA_CONTROL[0];
    assign weight_done_status =
        (weight_done_sticky_q || weight_done_pulse) && !CDMA_CONTROL[1];

    always_comb begin
        CDMA_STATUS    = '0;
        CDMA_STATUS[0] = data_busy;
        CDMA_STATUS[1] = data_done_status;
        CDMA_STATUS[2] = data_error;
        CDMA_STATUS[3] = weight_busy;
        CDMA_STATUS[4] = weight_done_status;
        CDMA_STATUS[5] = weight_error;
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            data_done_sticky_q   <= 1'b0;
            weight_done_sticky_q <= 1'b0;
        end else begin
            if (data_done_pulse) begin
                data_done_sticky_q <= 1'b1;
            end else if (CDMA_CONTROL[0]) begin
                data_done_sticky_q <= 1'b0;
            end

            if (weight_done_pulse) begin
                weight_done_sticky_q <= 1'b1;
            end else if (CDMA_CONTROL[1]) begin
                weight_done_sticky_q <= 1'b0;
            end
        end
    end

    cdma_core #(
        .ADDR_WIDTH     (ADDR_WIDTH),
        .AXI_DATA_WIDTH (AXI_DATA_WIDTH),
        .CBUF_WORD_WIDTH(CBUF_WORD_WIDTH),
        .ELEMENT_WIDTH  (ELEMENT_WIDTH),
        .LEN_WIDTH      (LEN_WIDTH),
        .CBUF_ADDR_WIDTH(CBUF_ADDR_WIDTH),
        .BANK_NUM    (BANK_NUM),
        .BANK_SEL_WIDTH (BANK_SEL_WIDTH),
        .BANK_ADDR_WIDTH(BANK_ADDR_WIDTH),
        .AXI_BURST_LEN  (AXI_BURST_LEN)
    ) u_cdma_core (
        .clk                     (clk),
        .rst_n                   (rst_n),

        .data_start              (CDMA_CONTROL[0]),
        .data_busy               (data_busy),
        .data_done               (data_done_pulse),
        .data_error              (data_error),
        .data_fill_request       (data_fill_request),
        .data_fill_done          (data_fill_done),
        .data_stream_txn_start   (axi_init_txn && (axi_stream_sel == 1'b0)),
        .data_stream_error       (axi_error && (axi_stream_sel == 1'b0)),
        .data_stream_valid       (axi_stream_valid && (axi_stream_sel == 1'b0)),
        .data_stream_ready       (data_stream_ready),
        .data_stream_data        (axi_stream_data),
        .data_cfg_matrix_width   (LEN_WIDTH'(DATA_MATRIX_WIDTH)),
        .data_cfg_matrix_height  (LEN_WIDTH'(DATA_MATRIX_HEIGHT)),
        .data_cfg_channel_count  (LEN_WIDTH'(DATA_CHANNEL_COUNT)),
        .data_cfg_dst_base       (CBUF_ADDR_WIDTH'(DATA_DST_BASE)),
        .data_load_total_words   (data_load_total_words),
        .data_load_last_addr     (),
        .data_mem_rd_addr        (),
        .data_cbuf_wr_bank_en(data_cbuf_wr_bank_en),
        .data_cbuf_wr_bank_addr(data_cbuf_wr_bank_addr),
        .data_cbuf_wr_bank_data    (data_cbuf_wr_bank_data),

        .weight_start            (CDMA_CONTROL[1]),
        .weight_busy             (weight_busy),
        .weight_done             (weight_done_pulse),
        .weight_error            (weight_error),
        .weight_fill_request     (weight_fill_request),
        .weight_fill_done        (weight_fill_done),
        .weight_stream_txn_start (axi_init_txn && (axi_stream_sel == 1'b1)),
        .weight_stream_error     (axi_error && (axi_stream_sel == 1'b1)),
        .weight_stream_valid     (axi_stream_valid && (axi_stream_sel == 1'b1)),
        .weight_stream_ready     (weight_stream_ready),
        .weight_stream_data      (axi_stream_data),
        .weight_cfg_matrix_width (LEN_WIDTH'(WEIGHT_MATRIX_WIDTH)),
        .weight_cfg_matrix_height(LEN_WIDTH'(WEIGHT_MATRIX_HEIGHT)),
        .weight_cfg_channel_count(LEN_WIDTH'(WEIGHT_CHANNEL_COUNT)),
        .weight_cfg_dst_base     (CBUF_ADDR_WIDTH'(WEIGHT_DST_BASE)),
        .weight_load_total_words (weight_load_total_words),
        .weight_load_last_addr   (),
        .weight_mem_rd_addr      (),
        .weight_cbuf_wr_bank_en(weight_cbuf_wr_bank_en),
        .weight_cbuf_wr_bank_addr(weight_cbuf_wr_bank_addr),
        .weight_cbuf_wr_bank_data    (weight_cbuf_wr_bank_data)
    );

    cdma_axi_transaction_ctrl #(
        .ADDR_WIDTH   (ADDR_WIDTH),
        .AXI_DATA_WIDTH (AXI_DATA_WIDTH),
        .CBUF_WORD_WIDTH(CBUF_WORD_WIDTH),
        .LEN_WIDTH    (LEN_WIDTH),
        .AXI_BURST_LEN(AXI_BURST_LEN)
    ) u_axi_transaction_ctrl (
        .clk                    (clk),
        .rst_n                  (rst_n),
        .data_fill_request      (data_fill_request),
        .data_load_total_words  (data_load_total_words),
        .data_fill_done         (data_fill_done),
        .weight_fill_request    (weight_fill_request),
        .weight_load_total_words(weight_load_total_words),
        .weight_fill_done       (weight_fill_done),
        .axi_load_start         (axi_load_start),
        .axi_txn_addr           (axi_txn_addr),
        .axi_init_txn           (axi_init_txn),
        .axi_stream_sel         (axi_stream_sel),
        .axi_txn_done           (axi_txn_done),
        .axi_error              (axi_error)
    );

endmodule
