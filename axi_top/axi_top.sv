`timescale 1ns/1ps
// AXI-Lite CSB + convcore integration wrapper.
//
// This wrapper keeps axi_slave_csb_v1_0 and convcore as separate modules while
// wiring the CSB register outputs directly into convcore configuration ports.

module axi_top #(
    parameter int ADDR_WIDTH       = 32,
    parameter int AXI_DATA_WIDTH   = 32,
    parameter int CBUF_WORD_WIDTH  = 32,
    parameter int LEN_WIDTH        = 32,
    parameter int CBUF_ADDR_WIDTH  = 16,
    parameter int CSB_DATA_WIDTH   = 32,
    parameter int CSB_ADDR_WIDTH   = 7,
    parameter int AXI_BURST_LEN    = 8,
    parameter int ELEMENT_WIDTH    = 8,
    parameter int BANK_NUM         = 8,
    parameter int MACCELL_NUM      = 8,
    parameter int MACLANE_NUM      = CBUF_WORD_WIDTH / ELEMENT_WIDTH,
    parameter int CSC_TAG_WIDTH    = 32
) (
    input  wire                          s00_axi_aclk,
    input  wire                          s00_axi_aresetn,
    input  wire [CSB_ADDR_WIDTH-1:0]     s00_axi_awaddr,
    input  wire [2:0]                    s00_axi_awprot,
    input  wire                          s00_axi_awvalid,
    output wire                          s00_axi_awready,
    input  wire [CSB_DATA_WIDTH-1:0]     s00_axi_wdata,
    input  wire [(CSB_DATA_WIDTH/8)-1:0] s00_axi_wstrb,
    input  wire                          s00_axi_wvalid,
    output wire                          s00_axi_wready,
    output wire [1:0]                    s00_axi_bresp,
    output wire                          s00_axi_bvalid,
    input  wire                          s00_axi_bready,
    input  wire [CSB_ADDR_WIDTH-1:0]     s00_axi_araddr,
    input  wire [2:0]                    s00_axi_arprot,
    input  wire                          s00_axi_arvalid,
    output wire                          s00_axi_arready,
    output wire [CSB_DATA_WIDTH-1:0]     s00_axi_rdata,
    output wire [1:0]                    s00_axi_rresp,
    output wire                          s00_axi_rvalid,
    input  wire                          s00_axi_rready,

    output logic                         axi_load_start,
    output logic [ADDR_WIDTH-1:0]        axi_txn_addr,
    output logic                         axi_init_txn,
    input  logic                         axi_stream_valid,
    output logic                         axi_stream_ready,
    input  logic [AXI_DATA_WIDTH-1:0]    axi_stream_data,
    input  logic                         axi_txn_done,
    input  logic                         axi_error,
    output logic                         axi_stream_sel
);

    logic [CSB_DATA_WIDTH-1:0] cdma_control_w;
    logic [CSB_DATA_WIDTH-1:0] cdma_status_w;
    logic [CSB_DATA_WIDTH-1:0] data_matrix_width_w;
    logic [CSB_DATA_WIDTH-1:0] data_matrix_height_w;
    logic [CSB_DATA_WIDTH-1:0] data_channel_count_w;
    logic [CSB_DATA_WIDTH-1:0] data_dst_base_w;
    logic [CSB_DATA_WIDTH-1:0] weight_matrix_width_w;
    logic [CSB_DATA_WIDTH-1:0] weight_matrix_height_w;
    logic [CSB_DATA_WIDTH-1:0] weight_channel_count_w;
    logic [CSB_DATA_WIDTH-1:0] weight_dst_base_w;
    logic [CSB_DATA_WIDTH-1:0] csc_control_w;
    logic [CSB_DATA_WIDTH-1:0] csc_status_w;
    logic [CSB_DATA_WIDTH-1:0] csc_atomics_w;
    logic [CSB_DATA_WIDTH-1:0] csc_data_base_w;
    logic [CSB_DATA_WIDTH-1:0] csc_weight_base_w;
    logic [CSB_DATA_WIDTH-1:0] csc_input_width_height_w;
    logic [CSB_DATA_WIDTH-1:0] csc_input_channels_w;
    logic [CSB_DATA_WIDTH-1:0] csc_kernel_width_height_w;
    logic [CSB_DATA_WIDTH-1:0] csc_stride_xy_w;
    logic [CSB_DATA_WIDTH-1:0] csc_output_width_height_w;
    logic [CSB_DATA_WIDTH-1:0] csc_output_channels_w;

    axi_slave_csb_v1_0 #(
        .C_S00_AXI_DATA_WIDTH(CSB_DATA_WIDTH),
        .C_S00_AXI_ADDR_WIDTH(CSB_ADDR_WIDTH)
    ) u_csb (
        .CDMA_CONTROL          (cdma_control_w),
        .CDMA_STATUS           (cdma_status_w),
        .DATA_MATRIX_WIDTH     (data_matrix_width_w),
        .DATA_MATRIX_HEIGHT    (data_matrix_height_w),
        .DATA_CHANNEL_COUNT    (data_channel_count_w),
        .DATA_DST_BASE         (data_dst_base_w),
        .WEIGHT_MATRIX_WIDTH   (weight_matrix_width_w),
        .WEIGHT_MATRIX_HEIGHT  (weight_matrix_height_w),
        .WEIGHT_CHANNEL_COUNT  (weight_channel_count_w),
        .WEIGHT_DST_BASE       (weight_dst_base_w),
        .CSC_CONTROL           (csc_control_w),
        .CSC_STATUS            (csc_status_w),
        .CSC_ATOMICS           (csc_atomics_w),
        .CSC_DATA_BASE         (csc_data_base_w),
        .CSC_WEIGHT_BASE       (csc_weight_base_w),
        .CSC_INPUT_WIDTH_HEIGHT(csc_input_width_height_w),
        .CSC_INPUT_CHANNELS    (csc_input_channels_w),
        .CSC_KERNEL_WIDTH_HEIGHT(csc_kernel_width_height_w),
        .CSC_STRIDE_XY         (csc_stride_xy_w),
        .CSC_OUTPUT_WIDTH_HEIGHT(csc_output_width_height_w),
        .CSC_OUTPUT_CHANNELS   (csc_output_channels_w),

        .s00_axi_aclk          (s00_axi_aclk),
        .s00_axi_aresetn       (s00_axi_aresetn),
        .s00_axi_awaddr        (s00_axi_awaddr),
        .s00_axi_awprot        (s00_axi_awprot),
        .s00_axi_awvalid       (s00_axi_awvalid),
        .s00_axi_awready       (s00_axi_awready),
        .s00_axi_wdata         (s00_axi_wdata),
        .s00_axi_wstrb         (s00_axi_wstrb),
        .s00_axi_wvalid        (s00_axi_wvalid),
        .s00_axi_wready        (s00_axi_wready),
        .s00_axi_bresp         (s00_axi_bresp),
        .s00_axi_bvalid        (s00_axi_bvalid),
        .s00_axi_bready        (s00_axi_bready),
        .s00_axi_araddr        (s00_axi_araddr),
        .s00_axi_arprot        (s00_axi_arprot),
        .s00_axi_arvalid       (s00_axi_arvalid),
        .s00_axi_arready       (s00_axi_arready),
        .s00_axi_rdata         (s00_axi_rdata),
        .s00_axi_rresp         (s00_axi_rresp),
        .s00_axi_rvalid        (s00_axi_rvalid),
        .s00_axi_rready        (s00_axi_rready)
    );

    convcore #(
        .ADDR_WIDTH      (ADDR_WIDTH),
        .AXI_DATA_WIDTH  (AXI_DATA_WIDTH),
        .CBUF_WORD_WIDTH (CBUF_WORD_WIDTH),
        .LEN_WIDTH       (LEN_WIDTH),
        .CBUF_ADDR_WIDTH (CBUF_ADDR_WIDTH),
        .CSB_DATA_WIDTH  (CSB_DATA_WIDTH),
        .AXI_BURST_LEN   (AXI_BURST_LEN),
        .ELEMENT_WIDTH   (ELEMENT_WIDTH),
        .BANK_NUM        (BANK_NUM),
        .MACCELL_NUM     (MACCELL_NUM),
        .MACLANE_NUM     (MACLANE_NUM),
        .CSC_TAG_WIDTH   (CSC_TAG_WIDTH)
    ) u_convcore (
        .clk                    (s00_axi_aclk),
        .rst_n                  (s00_axi_aresetn),

        .CDMA_CONTROL           (cdma_control_w),
        .CDMA_STATUS            (cdma_status_w),
        .DATA_MATRIX_WIDTH      (data_matrix_width_w),
        .DATA_MATRIX_HEIGHT     (data_matrix_height_w),
        .DATA_CHANNEL_COUNT     (data_channel_count_w),
        .DATA_DST_BASE          (data_dst_base_w),
        .WEIGHT_MATRIX_WIDTH    (weight_matrix_width_w),
        .WEIGHT_MATRIX_HEIGHT   (weight_matrix_height_w),
        .WEIGHT_CHANNEL_COUNT   (weight_channel_count_w),
        .WEIGHT_DST_BASE        (weight_dst_base_w),

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

        .axi_load_start         (axi_load_start),
        .axi_txn_addr           (axi_txn_addr),
        .axi_init_txn           (axi_init_txn),
        .axi_stream_valid       (axi_stream_valid),
        .axi_stream_ready       (axi_stream_ready),
        .axi_stream_data        (axi_stream_data),
        .axi_txn_done           (axi_txn_done),
        .axi_error              (axi_error),
        .axi_stream_sel         (axi_stream_sel)
    );

endmodule
