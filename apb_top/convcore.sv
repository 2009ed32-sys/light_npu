`timescale 1ns/1ps
// Top-level convolution core integration shell.
//
// The CDMA load stage fills CBUF. CSC, CMAC, and CACC will connect inside this
// module as the rest of the convolution pipeline is added.

module convcore #(
    parameter int ADDR_WIDTH       = 32,
    parameter int AXI_DATA_WIDTH   = 32,
    parameter int CBUF_WORD_WIDTH  = 32,
    parameter int LEN_WIDTH        = 32,
    parameter int CBUF_ADDR_WIDTH  = 16,
    parameter int CSB_DATA_WIDTH   = 32,
    parameter int AXI_BURST_LEN    = 8,
    parameter int ELEMENT_WIDTH    = 8,
    parameter int BANK_NUM         = 8,
    parameter int MACCELL_NUM      = 8,
    parameter int MACLANE_NUM      = CBUF_WORD_WIDTH / ELEMENT_WIDTH,
    parameter int CSC_TAG_WIDTH    = 32,
    parameter int CMAC_PSUM_WIDTH  = 32,
    parameter int DEBUG_WIDTH      = 256
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

    input  logic [CSB_DATA_WIDTH-1:0]  CSC_CONTROL,
    output logic [CSB_DATA_WIDTH-1:0]  CSC_STATUS,
    input  logic [CSB_DATA_WIDTH-1:0]  CSC_ATOMICS,
    input  logic [CSB_DATA_WIDTH-1:0]  CSC_DATA_BASE,
    input  logic [CSB_DATA_WIDTH-1:0]  CSC_WEIGHT_BASE,
    input  logic [CSB_DATA_WIDTH-1:0]  CSC_INPUT_WIDTH_HEIGHT,
    input  logic [CSB_DATA_WIDTH-1:0]  CSC_INPUT_CHANNELS,
    input  logic [CSB_DATA_WIDTH-1:0]  CSC_KERNEL_WIDTH_HEIGHT,
    input  logic [CSB_DATA_WIDTH-1:0]  CSC_STRIDE_XY,
    input  logic [CSB_DATA_WIDTH-1:0]  CSC_OUTPUT_WIDTH_HEIGHT,
    input  logic [CSB_DATA_WIDTH-1:0]  CSC_OUTPUT_CHANNELS,
    input  logic [CSB_DATA_WIDTH-1:0]  CACC_D_OP_ENABLE,
    output logic [CSB_DATA_WIDTH-1:0]  CACC_S_STATUS,
    input  logic [CSB_DATA_WIDTH-1:0]  CACC_D_DATAOUT_SIZE_0,
    input  logic [CSB_DATA_WIDTH-1:0]  CACC_D_DATAOUT_SIZE_1,
    input  logic [CSB_DATA_WIDTH-1:0]  CACC_D_DATAOUT_ADDR,
    input  logic [CSB_DATA_WIDTH-1:0]  CACC_D_LINE_STRIDE,
    input  logic [CSB_DATA_WIDTH-1:0]  CACC_D_SURF_STRIDE,
    input  logic [CSB_DATA_WIDTH-1:0]  CACC_D_DATAOUT_MAP,

    output logic                       axi_load_start,
    output logic [ADDR_WIDTH-1:0]      axi_txn_addr,
    output logic                       axi_init_txn,
    input  logic                       axi_stream_valid,
    output logic                       axi_stream_ready,
    input  logic [AXI_DATA_WIDTH-1:0]  axi_stream_data,
    input  logic                       axi_txn_done,
    input  logic                       axi_error,
    output logic                       axi_stream_sel,

    output logic                       sdp_write_valid,
    input  logic                       sdp_write_ready,
    output logic [ADDR_WIDTH-1:0]      sdp_write_addr,
    output logic [CMAC_PSUM_WIDTH-1:0] sdp_write_data,
    output logic [(CMAC_PSUM_WIDTH/8)-1:0] sdp_write_strb,
    output logic                       sdp_write_last,
    input  logic                       sdp_write_done,
    input  logic                       sdp_write_error
);

    localparam int CBUF_DATA_DEPTH   = 1024;
    localparam int CBUF_WEIGHT_DEPTH = 1024;
    localparam int CBUF_BANK_VEC_WIDTH =
        BANK_NUM * MACLANE_NUM * ELEMENT_WIDTH;
    localparam int MACCELL_VEC_WIDTH =
        MACCELL_NUM * MACLANE_NUM * ELEMENT_WIDTH;
    localparam int CMAC_PSUM_VEC_WIDTH =
        MACCELL_NUM * CMAC_PSUM_WIDTH;
    localparam int CBUF_DATA_BANK_ADDR_WIDTH =
        (CBUF_DATA_DEPTH <= 2) ? 1 : $clog2(CBUF_DATA_DEPTH);
    localparam int CBUF_WEIGHT_BANK_ADDR_WIDTH =
        (CBUF_WEIGHT_DEPTH <= 2) ? 1 : $clog2(CBUF_WEIGHT_DEPTH);
    localparam int CBUF_BANK_ADDR_WIDTH =
        (CBUF_DATA_BANK_ADDR_WIDTH > CBUF_WEIGHT_BANK_ADDR_WIDTH) ?
        CBUF_DATA_BANK_ADDR_WIDTH : CBUF_WEIGHT_BANK_ADDR_WIDTH;
    localparam int CBUF_BANK_SEL_WIDTH =
        (BANK_NUM <= 2) ? 1 : $clog2(BANK_NUM);

    logic [BANK_NUM-1:0] data_cbuf_wr_bank_en_w;
    logic [(BANK_NUM*CBUF_BANK_ADDR_WIDTH)-1:0] data_cbuf_wr_bank_addr_w;
    logic [(BANK_NUM*CBUF_WORD_WIDTH)-1:0] data_cbuf_wr_bank_data_w;
    logic [BANK_NUM-1:0] weight_cbuf_wr_bank_en_w;
    logic [(BANK_NUM*CBUF_BANK_ADDR_WIDTH)-1:0] weight_cbuf_wr_bank_addr_w;
    logic [(BANK_NUM*CBUF_WORD_WIDTH)-1:0] weight_cbuf_wr_bank_data_w;

    logic                       data_cbuf_rd_valid_unused;
    logic [CBUF_BANK_VEC_WIDTH-1:0] data_cbuf_rd_data_unused;
    logic                       weight_cbuf_rd_valid_unused;
    logic [CBUF_BANK_VEC_WIDTH-1:0] weight_cbuf_rd_data_unused;

    logic                       csc_ready;
    logic                       csc_busy;
    logic                       csc_done;
    logic                       csc_error;
    logic                       csc_data_cbuf_rd_en;
    logic [BANK_NUM-1:0]     csc_data_cbuf_rd_bank_en;
    logic [(BANK_NUM*CBUF_BANK_ADDR_WIDTH)-1:0] csc_data_cbuf_rd_bank_addr;
    logic                       csc_weight_cbuf_rd_en;
    logic [BANK_NUM-1:0]     csc_weight_cbuf_rd_bank_en;
    logic [(BANK_NUM*CBUF_BANK_ADDR_WIDTH)-1:0] csc_weight_cbuf_rd_bank_addr;
    logic                       csc_maccell_ready_w;
    logic                       csc_maccell_in_valid_w;
    logic [MACCELL_NUM-1:0]     csc_maccell_valid_mask_w;
    logic [MACCELL_VEC_WIDTH-1:0] csc_maccell_data_w;
    logic [MACCELL_VEC_WIDTH-1:0] csc_maccell_weight_w;
    logic                       csc_maccell_acc_clear_w;
    logic                       csc_maccell_acc_last_w;
    logic [CSC_TAG_WIDTH-1:0]   csc_maccell_tag_w;

    logic                       cmac_ready_unused;
    logic                       cmac_busy_unused;
    logic                       cmac_done_unused;
    logic                       cmac_error_unused;
    logic                       cmac_psum_valid_unused;
    logic [MACCELL_NUM-1:0]     cmac_psum_valid_mask_unused;
    logic [CMAC_PSUM_VEC_WIDTH-1:0] cmac_psum_data_unused;
    logic                       cmac_psum_acc_clear_unused;
    logic                       cmac_psum_acc_last_unused;
    logic [CSC_TAG_WIDTH-1:0]   cmac_psum_tag_unused;
    logic                       cmac_psum_ready_w;
    logic                       cmac_cacc_prepare_valid_w;
    logic                       cmac_cacc_prepare_read_w;
    logic [MACCELL_NUM-1:0]     cmac_cacc_prepare_mask_w;
    logic                       cmac_cacc_prepare_acc_clear_w;
    logic                       cmac_cacc_prepare_acc_last_w;
    logic                       cacc_ready_unused;
    logic                       cacc_busy_unused;
    logic                       cacc_done_unused;
    logic                       cacc_error_unused;
    logic                       cacc_sdp_valid_w;
    logic                       cacc_sdp_ready_w;
    logic [MACCELL_NUM-1:0]     cacc_sdp_mask_w;
    logic [CMAC_PSUM_VEC_WIDTH-1:0] cacc_sdp_data_w;
    logic                       cacc_sdp_last_w;
    logic                       sdp_ready_unused;
    logic                       sdp_busy_unused;
    logic                       sdp_done_unused;
    logic                       sdp_error_unused;

    always_comb begin
        CSC_STATUS    = '0;
        CSC_STATUS[0] = csc_ready;
        CSC_STATUS[1] = csc_busy;
        CSC_STATUS[2] = csc_done;
        CSC_STATUS[3] = csc_error;

        CACC_S_STATUS    = '0;
        CACC_S_STATUS[0] = cacc_ready_unused && sdp_ready_unused;
        CACC_S_STATUS[1] = cacc_busy_unused || sdp_busy_unused;
        CACC_S_STATUS[2] = sdp_done_unused;
        CACC_S_STATUS[3] = cacc_error_unused || sdp_error_unused;
    end

    cdma #(
        .ADDR_WIDTH     (ADDR_WIDTH),
        .AXI_DATA_WIDTH (AXI_DATA_WIDTH),
        .CBUF_WORD_WIDTH(CBUF_WORD_WIDTH),
        .ELEMENT_WIDTH  (ELEMENT_WIDTH),
        .LEN_WIDTH      (LEN_WIDTH),
        .CBUF_ADDR_WIDTH(CBUF_ADDR_WIDTH),
        .BANK_NUM    (BANK_NUM),
        .BANK_SEL_WIDTH (CBUF_BANK_SEL_WIDTH),
        .BANK_ADDR_WIDTH(CBUF_BANK_ADDR_WIDTH),
        .CSB_DATA_WIDTH (CSB_DATA_WIDTH),
        .AXI_BURST_LEN  (AXI_BURST_LEN)
    ) u_cdma (
        .clk                 (clk),
        .rst_n               (rst_n),

        .CDMA_CONTROL        (CDMA_CONTROL),
        .CDMA_STATUS         (CDMA_STATUS),
        .DATA_MATRIX_WIDTH   (DATA_MATRIX_WIDTH),
        .DATA_MATRIX_HEIGHT  (DATA_MATRIX_HEIGHT),
        .DATA_CHANNEL_COUNT  (DATA_CHANNEL_COUNT),
        .DATA_DST_BASE       (DATA_DST_BASE),
        .WEIGHT_MATRIX_WIDTH (WEIGHT_MATRIX_WIDTH),
        .WEIGHT_MATRIX_HEIGHT(WEIGHT_MATRIX_HEIGHT),
        .WEIGHT_CHANNEL_COUNT(WEIGHT_CHANNEL_COUNT),
        .WEIGHT_DST_BASE     (WEIGHT_DST_BASE),

        .data_cbuf_wr_bank_en  (data_cbuf_wr_bank_en_w),
        .data_cbuf_wr_bank_addr(data_cbuf_wr_bank_addr_w),
        .data_cbuf_wr_bank_data(data_cbuf_wr_bank_data_w),

        .weight_cbuf_wr_bank_en  (weight_cbuf_wr_bank_en_w),
        .weight_cbuf_wr_bank_addr(weight_cbuf_wr_bank_addr_w),
        .weight_cbuf_wr_bank_data(weight_cbuf_wr_bank_data_w),

        .axi_load_start      (axi_load_start),
        .axi_txn_addr        (axi_txn_addr),
        .axi_init_txn        (axi_init_txn),
        .axi_stream_valid    (axi_stream_valid),
        .axi_stream_ready    (axi_stream_ready),
        .axi_stream_data     (axi_stream_data),
        .axi_txn_done        (axi_txn_done),
        .axi_error           (axi_error),
        .axi_stream_sel      (axi_stream_sel)
    );

    csc #(
        .ELEMENT_WIDTH(ELEMENT_WIDTH),
        .BANK_NUM     (BANK_NUM),
        .MACCELL_NUM  (MACCELL_NUM),
        .MACLANE_NUM  (MACLANE_NUM),
        .ADDR_WIDTH   (CBUF_ADDR_WIDTH),
        .BANK_ADDR_WIDTH(CBUF_BANK_ADDR_WIDTH),
        .LEN_WIDTH    (LEN_WIDTH),
        .TAG_WIDTH    (CSC_TAG_WIDTH)
    ) u_csc (
        .clk                    (clk),
        .rst_n                  (rst_n),
        .op_enable              (CSC_CONTROL[1]),
        .op_start               (CSC_CONTROL[0]),
        .op_ready               (csc_ready),
        .op_busy                (csc_busy),
        .op_done                (csc_done),
        .op_error               (csc_error),
        .atomics                (LEN_WIDTH'(CSC_ATOMICS)),
        .data_base              (CBUF_ADDR_WIDTH'(CSC_DATA_BASE)),
        .weight_base            (CBUF_ADDR_WIDTH'(CSC_WEIGHT_BASE)),
        .input_width            (LEN_WIDTH'(CSC_INPUT_WIDTH_HEIGHT[15:0])),
        .input_height           (LEN_WIDTH'(CSC_INPUT_WIDTH_HEIGHT[31:16])),
        .input_channels         (LEN_WIDTH'(CSC_INPUT_CHANNELS)),
        .kernel_width           (LEN_WIDTH'(CSC_KERNEL_WIDTH_HEIGHT[15:0])),
        .kernel_height          (LEN_WIDTH'(CSC_KERNEL_WIDTH_HEIGHT[31:16])),
        .stride_x               (LEN_WIDTH'(CSC_STRIDE_XY[15:0])),
        .stride_y               (LEN_WIDTH'(CSC_STRIDE_XY[31:16])),
        .output_width           (LEN_WIDTH'(CSC_OUTPUT_WIDTH_HEIGHT[15:0])),
        .output_height          (LEN_WIDTH'(CSC_OUTPUT_WIDTH_HEIGHT[31:16])),
        .output_channels        (LEN_WIDTH'(CSC_OUTPUT_CHANNELS)),
        .data_cbuf_rd_en        (csc_data_cbuf_rd_en),
        .data_cbuf_rd_bank_en   (csc_data_cbuf_rd_bank_en),
        .data_cbuf_rd_bank_addr (csc_data_cbuf_rd_bank_addr),
        .data_cbuf_rd_valid     (data_cbuf_rd_valid_unused),
        .data_cbuf_rd_data      (data_cbuf_rd_data_unused),
        .weight_cbuf_rd_en      (csc_weight_cbuf_rd_en),
        .weight_cbuf_rd_bank_en (csc_weight_cbuf_rd_bank_en),
        .weight_cbuf_rd_bank_addr(csc_weight_cbuf_rd_bank_addr),
        .weight_cbuf_rd_valid   (weight_cbuf_rd_valid_unused),
        .weight_cbuf_rd_data    (weight_cbuf_rd_data_unused),
        .maccell_ready          (csc_maccell_ready_w),
        .maccell_in_valid       (csc_maccell_in_valid_w),
        .maccell_valid_mask     (csc_maccell_valid_mask_w),
        .maccell_data           (csc_maccell_data_w),
        .maccell_weight         (csc_maccell_weight_w),
        .maccell_acc_clear      (csc_maccell_acc_clear_w),
        .maccell_acc_last       (csc_maccell_acc_last_w),
        .maccell_tag            (csc_maccell_tag_w)
    );

    cmac #(
        .ELEMENT_WIDTH(ELEMENT_WIDTH),
        .MACCELL_NUM  (MACCELL_NUM),
        .MACLANE_NUM  (MACLANE_NUM),
        .PSUM_WIDTH   (CMAC_PSUM_WIDTH),
        .TAG_WIDTH    (CSC_TAG_WIDTH)
    ) u_cmac (
        .clk                (clk),
        .rst_n              (rst_n),
        .op_enable          (CSC_CONTROL[1]),
        .op_start           (CSC_CONTROL[0]),
        .op_ready           (cmac_ready_unused),
        .op_busy            (cmac_busy_unused),
        .op_done            (cmac_done_unused),
        .op_error           (cmac_error_unused),
        .maccell_in_valid   (csc_maccell_in_valid_w),
        .maccell_ready      (csc_maccell_ready_w),
        .maccell_valid_mask (csc_maccell_valid_mask_w),
        .maccell_data       (csc_maccell_data_w),
        .maccell_weight     (csc_maccell_weight_w),
        .maccell_acc_clear  (csc_maccell_acc_clear_w),
        .maccell_acc_last   (csc_maccell_acc_last_w),
        .maccell_tag        (csc_maccell_tag_w),
        .psum_valid         (cmac_psum_valid_unused),
        .psum_ready         (cmac_psum_ready_w),
        .psum_valid_mask    (cmac_psum_valid_mask_unused),
        .psum_data          (cmac_psum_data_unused),
        .psum_acc_clear     (cmac_psum_acc_clear_unused),
        .psum_acc_last      (cmac_psum_acc_last_unused),
        .psum_tag           (cmac_psum_tag_unused),
        .cacc_prepare_valid (cmac_cacc_prepare_valid_w),
        .cacc_prepare_read  (cmac_cacc_prepare_read_w),
        .cacc_prepare_mask  (cmac_cacc_prepare_mask_w),
        .cacc_prepare_acc_clear(cmac_cacc_prepare_acc_clear_w),
        .cacc_prepare_acc_last(cmac_cacc_prepare_acc_last_w)
    );

    cacc #(
        .MACCELL_NUM(MACCELL_NUM),
        .PSUM_WIDTH (CMAC_PSUM_WIDTH),
        .TAG_WIDTH  (CSC_TAG_WIDTH),
        .CFG_WIDTH  (CSB_DATA_WIDTH)
    ) u_cacc (
        .clk              (clk),
        .rst_n            (rst_n),
        .op_enable        (CACC_D_OP_ENABLE[1]),
        .op_start         (CACC_D_OP_ENABLE[0]),
        .op_ready         (cacc_ready_unused),
        .op_busy          (cacc_busy_unused),
        .op_done          (cacc_done_unused),
        .op_error         (cacc_error_unused),
        .d_dataout_size_0 (CACC_D_DATAOUT_SIZE_0),
        .d_dataout_size_1 (CACC_D_DATAOUT_SIZE_1),
        .d_dataout_addr   (CACC_D_DATAOUT_ADDR),
        .d_line_stride    (CACC_D_LINE_STRIDE),
        .d_surf_stride    (CACC_D_SURF_STRIDE),
        .d_dataout_map    (CACC_D_DATAOUT_MAP),
        .prepare_valid    (cmac_cacc_prepare_valid_w),
        .prepare_read     (cmac_cacc_prepare_read_w),
        .prepare_mask     (cmac_cacc_prepare_mask_w),
        .prepare_acc_clear(cmac_cacc_prepare_acc_clear_w),
        .prepare_acc_last (cmac_cacc_prepare_acc_last_w),
        .psum_valid       (cmac_psum_valid_unused),
        .psum_ready       (cmac_psum_ready_w),
        .psum_valid_mask  (cmac_psum_valid_mask_unused),
        .psum_data        (cmac_psum_data_unused),
        .psum_acc_clear   (cmac_psum_acc_clear_unused),
        .psum_acc_last    (cmac_psum_acc_last_unused),
        .psum_tag         (cmac_psum_tag_unused),
        .sdp_valid        (cacc_sdp_valid_w),
        .sdp_ready        (cacc_sdp_ready_w),
        .sdp_mask         (cacc_sdp_mask_w),
        .sdp_data         (cacc_sdp_data_w),
        .sdp_last         (cacc_sdp_last_w)
    );

    sdp #(
        .MACCELL_NUM      (MACCELL_NUM),
        .PSUM_WIDTH       (CMAC_PSUM_WIDTH),
        .ADDR_WIDTH       (ADDR_WIDTH),
        .OUTPUT_ADDR_SHIFT(2)
    ) u_sdp (
        .clk              (clk),
        .rst_n            (rst_n),
        .op_enable        (CACC_D_OP_ENABLE[1]),
        .op_start         (CACC_D_OP_ENABLE[0]),
        .op_ready         (sdp_ready_unused),
        .op_busy          (sdp_busy_unused),
        .op_done          (sdp_done_unused),
        .op_error         (sdp_error_unused),
        .output_base_addr (ADDR_WIDTH'(CACC_D_DATAOUT_ADDR)),
        .cacc_valid       (cacc_sdp_valid_w),
        .cacc_ready       (cacc_sdp_ready_w),
        .cacc_mask        (cacc_sdp_mask_w),
        .cacc_data        (cacc_sdp_data_w),
        .cacc_last        (cacc_sdp_last_w),
        .write_req_valid  (sdp_write_valid),
        .write_req_ready  (sdp_write_ready),
        .write_req_addr   (sdp_write_addr),
        .write_req_data   (sdp_write_data),
        .write_req_strb   (sdp_write_strb),
        .write_req_last   (sdp_write_last),
        .write_done       (sdp_write_done),
        .write_error      (sdp_write_error)
    );

    (* keep_hierarchy = "yes", dont_touch = "true" *) cbuf #(
        .DATA_WIDTH(CBUF_WORD_WIDTH),
        .ADDR_WIDTH   (CBUF_ADDR_WIDTH),
        .ELEMENT_WIDTH(ELEMENT_WIDTH),
        .BANK_NUM  (BANK_NUM),
        .BANK_SEL_WIDTH(CBUF_BANK_SEL_WIDTH),
        .MACLANE_NUM  (MACLANE_NUM),
        .DATA_DEPTH   (CBUF_DATA_DEPTH),
        .WEIGHT_DEPTH (CBUF_WEIGHT_DEPTH),
        .BANK_ADDR_WIDTH(CBUF_BANK_ADDR_WIDTH)
    ) u_cbuf (
        .clk            (clk),
        .rst_n          (rst_n),

        .data_wr_bank_en  (data_cbuf_wr_bank_en_w),
        .data_wr_bank_addr(data_cbuf_wr_bank_addr_w),
        .data_wr_bank_data(data_cbuf_wr_bank_data_w),
        .data_rd_en     (csc_data_cbuf_rd_en),
        .data_rd_bank_en(csc_data_cbuf_rd_bank_en),
        .data_rd_bank_addr(csc_data_cbuf_rd_bank_addr),
        .data_rd_valid  (data_cbuf_rd_valid_unused),
        .data_rd_data   (data_cbuf_rd_data_unused),

        .weight_wr_bank_en  (weight_cbuf_wr_bank_en_w),
        .weight_wr_bank_addr(weight_cbuf_wr_bank_addr_w),
        .weight_wr_bank_data(weight_cbuf_wr_bank_data_w),
        .weight_rd_en   (csc_weight_cbuf_rd_en),
        .weight_rd_bank_en(csc_weight_cbuf_rd_bank_en),
        .weight_rd_bank_addr(csc_weight_cbuf_rd_bank_addr),
        .weight_rd_valid(weight_cbuf_rd_valid_unused),
        .weight_rd_data (weight_cbuf_rd_data_unused)
    );

endmodule
