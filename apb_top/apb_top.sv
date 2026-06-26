`timescale 1ns/1ps
// APB3 CSB + convcore integration wrapper.
//
// APB writes configure apb3_slave registers. The register outputs drive
// convcore configuration ports, and convcore status feeds back into the APB
// status registers.

module apb_top #(
    parameter int ADDR_WIDTH       = 32,
    parameter int APB_ADDR_WIDTH   = 32,
    parameter int APB_DATA_WIDTH   = 32,
    parameter int AXI_DATA_WIDTH   = 32,
    parameter int CBUF_WORD_WIDTH  = 32,
    parameter int LEN_WIDTH        = 32,
    parameter int CBUF_ADDR_WIDTH  = 16,
    parameter int AXI_BURST_LEN    = 8,
    parameter int ELEMENT_WIDTH    = 8,
    parameter int BANK_NUM         = 8,
    parameter int MACCELL_NUM      = 8,
    parameter int MACLANE_NUM      = CBUF_WORD_WIDTH / ELEMENT_WIDTH,
    parameter int CSC_TAG_WIDTH    = 32,
    parameter int CMAC_PSUM_WIDTH  = 32
) (
    input  logic                          PCLK,
    input  logic                          PRESETn,

    input  logic                          PSEL,
    input  logic                          PENABLE,
    input  logic                          PWRITE,
    input  logic [APB_ADDR_WIDTH-1:0]     PADDR,
    input  logic [APB_DATA_WIDTH-1:0]     PWDATA,
    output logic [APB_DATA_WIDTH-1:0]     PRDATA,
    output logic                          PREADY,
    output logic                          PSLVERR,

    output logic [ADDR_WIDTH-1:0]         axi_txn_addr,
    output logic                          axi_init_txn,
    input  logic                          axi_stream_valid,
    output logic                          axi_stream_ready,
    input  logic [AXI_DATA_WIDTH-1:0]     axi_stream_data,
    input  logic                          axi_txn_done,
    input  logic                          axi_error,
    output logic                          sdp_write_valid,
    input  logic                          sdp_write_ready,
    output logic [ADDR_WIDTH-1:0]         sdp_write_addr,
    output logic [CMAC_PSUM_WIDTH-1:0]    sdp_write_data,
    output logic [(CMAC_PSUM_WIDTH/8)-1:0] sdp_write_strb,
    output logic                          sdp_write_last,
    input  logic                          sdp_write_done,
    input  logic                          sdp_write_error
);

    logic axi_load_start_unused;
    logic axi_stream_sel_unused;

    logic [APB_DATA_WIDTH-1:0] cdma_control_w;
    logic [APB_DATA_WIDTH-1:0] cdma_status_w;
    logic [APB_DATA_WIDTH-1:0] data_matrix_width_w;
    logic [APB_DATA_WIDTH-1:0] data_matrix_height_w;
    logic [APB_DATA_WIDTH-1:0] data_channel_count_w;
    logic [APB_DATA_WIDTH-1:0] data_dst_base_w;
    logic [APB_DATA_WIDTH-1:0] data_src_base_addr_w;
    logic [APB_DATA_WIDTH-1:0] weight_matrix_width_w;
    logic [APB_DATA_WIDTH-1:0] weight_matrix_height_w;
    logic [APB_DATA_WIDTH-1:0] weight_channel_count_w;
    logic [APB_DATA_WIDTH-1:0] weight_dst_base_w;
    logic [APB_DATA_WIDTH-1:0] weight_src_base_addr_w;
    logic [APB_DATA_WIDTH-1:0] csc_control_w;
    logic [APB_DATA_WIDTH-1:0] csc_status_w;
    logic [APB_DATA_WIDTH-1:0] csc_atomics_w;
    logic [APB_DATA_WIDTH-1:0] csc_data_base_w;
    logic [APB_DATA_WIDTH-1:0] csc_weight_base_w;
    logic [APB_DATA_WIDTH-1:0] csc_input_width_height_w;
    logic [APB_DATA_WIDTH-1:0] csc_input_channels_w;
    logic [APB_DATA_WIDTH-1:0] csc_kernel_width_height_w;
    logic [APB_DATA_WIDTH-1:0] csc_stride_xy_w;
    logic [APB_DATA_WIDTH-1:0] csc_output_width_height_w;
    logic [APB_DATA_WIDTH-1:0] csc_output_channels_w;
    logic [APB_DATA_WIDTH-1:0] cacc_s_status_w;
    logic [APB_DATA_WIDTH-1:0] cacc_d_op_enable_w;
    logic [APB_DATA_WIDTH-1:0] cacc_d_dataout_size_0_w;
    logic [APB_DATA_WIDTH-1:0] cacc_d_dataout_size_1_w;
    logic [APB_DATA_WIDTH-1:0] cacc_d_dataout_addr_w;
    logic [APB_DATA_WIDTH-1:0] cacc_d_line_stride_w;
    logic [APB_DATA_WIDTH-1:0] cacc_d_surf_stride_w;
    logic [APB_DATA_WIDTH-1:0] cacc_d_dataout_map_w;

    apb3_slave #(
        .ADDR_WIDTH(APB_ADDR_WIDTH),
        .DATA_WIDTH(APB_DATA_WIDTH),
        .SLVREG_NUM(31)
    ) u_apb_csb (
        .PCLK                   (PCLK),
        .PRESETn                (PRESETn),
        .PSEL                   (PSEL),
        .PENABLE                (PENABLE),
        .PWRITE                 (PWRITE),
        .PADDR                  (PADDR),
        .PWDATA                 (PWDATA),
        .PRDATA                 (PRDATA),
        .PREADY                 (PREADY),
        .PSLVERR                (PSLVERR),

        .CDMA_CONTROL           (cdma_control_w),
        .CDMA_STATUS            (cdma_status_w),
        .DATA_MATRIX_WIDTH      (data_matrix_width_w),
        .DATA_MATRIX_HEIGHT     (data_matrix_height_w),
        .DATA_CHANNEL_COUNT     (data_channel_count_w),
        .DATA_DST_BASE          (data_dst_base_w),
        .DATA_SRC_BASE_ADDR     (data_src_base_addr_w),
        .WEIGHT_MATRIX_WIDTH    (weight_matrix_width_w),
        .WEIGHT_MATRIX_HEIGHT   (weight_matrix_height_w),
        .WEIGHT_CHANNEL_COUNT   (weight_channel_count_w),
        .WEIGHT_DST_BASE        (weight_dst_base_w),
        .WEIGHT_SRC_BASE_ADDR   (weight_src_base_addr_w),
        .CSC_CONTROL            (csc_control_w),
        .CSC_STATUS             (csc_status_w),
        .CSC_ATOMICS            (csc_atomics_w),
        .CSC_DATA_BASE          (csc_data_base_w),
        .CSC_WEIGHT_BASE        (csc_weight_base_w),
        .CSC_INPUT_WIDTH_HEIGHT (csc_input_width_height_w),
        .CSC_INPUT_CHANNELS     (csc_input_channels_w),
        .CSC_KERNEL_WIDTH_HEIGHT(csc_kernel_width_height_w),
        .CSC_STRIDE_XY          (csc_stride_xy_w),
        .CSC_OUTPUT_WIDTH_HEIGHT(csc_output_width_height_w),
        .CSC_OUTPUT_CHANNELS    (csc_output_channels_w),
        .CACC_S_STATUS          (cacc_s_status_w),
        .CACC_D_OP_ENABLE       (cacc_d_op_enable_w),
        .CACC_D_DATAOUT_SIZE_0  (cacc_d_dataout_size_0_w),
        .CACC_D_DATAOUT_SIZE_1  (cacc_d_dataout_size_1_w),
        .CACC_D_DATAOUT_ADDR    (cacc_d_dataout_addr_w),
        .CACC_D_LINE_STRIDE     (cacc_d_line_stride_w),
        .CACC_D_SURF_STRIDE     (cacc_d_surf_stride_w),
        .CACC_D_DATAOUT_MAP     (cacc_d_dataout_map_w)
    );

    convcore #(
        .ADDR_WIDTH      (ADDR_WIDTH),
        .AXI_DATA_WIDTH  (AXI_DATA_WIDTH),
        .CBUF_WORD_WIDTH (CBUF_WORD_WIDTH),
        .LEN_WIDTH       (LEN_WIDTH),
        .CBUF_ADDR_WIDTH (CBUF_ADDR_WIDTH),
        .CSB_DATA_WIDTH  (APB_DATA_WIDTH),
        .AXI_BURST_LEN   (AXI_BURST_LEN),
        .ELEMENT_WIDTH   (ELEMENT_WIDTH),
        .BANK_NUM        (BANK_NUM),
        .MACCELL_NUM     (MACCELL_NUM),
        .MACLANE_NUM     (MACLANE_NUM),
        .CSC_TAG_WIDTH   (CSC_TAG_WIDTH),
        .CMAC_PSUM_WIDTH (CMAC_PSUM_WIDTH)
    ) u_convcore (
        .clk                    (PCLK),
        .rst_n                  (PRESETn),

        .CDMA_CONTROL           (cdma_control_w),
        .CDMA_STATUS            (cdma_status_w),
        .DATA_MATRIX_WIDTH      (data_matrix_width_w),
        .DATA_MATRIX_HEIGHT     (data_matrix_height_w),
        .DATA_CHANNEL_COUNT     (data_channel_count_w),
        .DATA_DST_BASE          (data_dst_base_w),
        .DATA_SRC_BASE_ADDR     (data_src_base_addr_w),
        .WEIGHT_MATRIX_WIDTH    (weight_matrix_width_w),
        .WEIGHT_MATRIX_HEIGHT   (weight_matrix_height_w),
        .WEIGHT_CHANNEL_COUNT   (weight_channel_count_w),
        .WEIGHT_DST_BASE        (weight_dst_base_w),
        .WEIGHT_SRC_BASE_ADDR   (weight_src_base_addr_w),

        .CSC_CONTROL            (csc_control_w),
        .CSC_STATUS             (csc_status_w),
        .CSC_ATOMICS            (csc_atomics_w),
        .CSC_DATA_BASE          (csc_data_base_w),
        .CSC_WEIGHT_BASE        (csc_weight_base_w),
        .CSC_INPUT_WIDTH_HEIGHT (csc_input_width_height_w),
        .CSC_INPUT_CHANNELS     (csc_input_channels_w),
        .CSC_KERNEL_WIDTH_HEIGHT(csc_kernel_width_height_w),
        .CSC_STRIDE_XY          (csc_stride_xy_w),
        .CSC_OUTPUT_WIDTH_HEIGHT(csc_output_width_height_w),
        .CSC_OUTPUT_CHANNELS    (csc_output_channels_w),
        .CACC_D_OP_ENABLE       (cacc_d_op_enable_w),
        .CACC_S_STATUS          (cacc_s_status_w),
        .CACC_D_DATAOUT_SIZE_0  (cacc_d_dataout_size_0_w),
        .CACC_D_DATAOUT_SIZE_1  (cacc_d_dataout_size_1_w),
        .CACC_D_DATAOUT_ADDR    (cacc_d_dataout_addr_w),
        .CACC_D_LINE_STRIDE     (cacc_d_line_stride_w),
        .CACC_D_SURF_STRIDE     (cacc_d_surf_stride_w),
        .CACC_D_DATAOUT_MAP     (cacc_d_dataout_map_w),

        .axi_load_start         (axi_load_start_unused),
        .axi_txn_addr           (axi_txn_addr),
        .axi_init_txn           (axi_init_txn),
        .axi_stream_valid       (axi_stream_valid),
        .axi_stream_ready       (axi_stream_ready),
        .axi_stream_data        (axi_stream_data),
        .axi_txn_done           (axi_txn_done),
        .axi_error              (axi_error),
        .axi_stream_sel         (axi_stream_sel_unused),
        .sdp_write_valid        (sdp_write_valid),
        .sdp_write_ready        (sdp_write_ready),
        .sdp_write_addr         (sdp_write_addr),
        .sdp_write_data         (sdp_write_data),
        .sdp_write_strb         (sdp_write_strb),
        .sdp_write_last         (sdp_write_last),
        .sdp_write_done         (sdp_write_done),
        .sdp_write_error        (sdp_write_error)
    );

endmodule
