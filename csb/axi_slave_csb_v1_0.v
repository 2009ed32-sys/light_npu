
`timescale 1 ns / 1 ps

	module axi_slave_csb_v1_0 #
	(
		// Users to add parameters here

		// User parameters ends
		// Do not modify the parameters beyond this line


		// Parameters of Axi Slave Bus Interface S00_AXI
		parameter integer C_S00_AXI_DATA_WIDTH	= 32,
		parameter integer C_S00_AXI_ADDR_WIDTH	= 7
	)
	(
		// Users to add ports here
		output wire [C_S00_AXI_DATA_WIDTH-1 : 0] CDMA_CONTROL,
		input wire [C_S00_AXI_DATA_WIDTH-1 : 0] CDMA_STATUS,
		output wire [C_S00_AXI_DATA_WIDTH-1 : 0] DATA_MATRIX_WIDTH,
		output wire [C_S00_AXI_DATA_WIDTH-1 : 0] DATA_MATRIX_HEIGHT,
		output wire [C_S00_AXI_DATA_WIDTH-1 : 0] DATA_CHANNEL_COUNT,
		output wire [C_S00_AXI_DATA_WIDTH-1 : 0] DATA_DST_BASE,
		output wire [C_S00_AXI_DATA_WIDTH-1 : 0] WEIGHT_MATRIX_WIDTH,
		output wire [C_S00_AXI_DATA_WIDTH-1 : 0] WEIGHT_MATRIX_HEIGHT,
		output wire [C_S00_AXI_DATA_WIDTH-1 : 0] WEIGHT_CHANNEL_COUNT,
		output wire [C_S00_AXI_DATA_WIDTH-1 : 0] WEIGHT_DST_BASE,
		output wire [C_S00_AXI_DATA_WIDTH-1 : 0] CSC_CONTROL,
		input wire [C_S00_AXI_DATA_WIDTH-1 : 0] CSC_STATUS,
		output wire [C_S00_AXI_DATA_WIDTH-1 : 0] CSC_ATOMICS,
		output wire [C_S00_AXI_DATA_WIDTH-1 : 0] CSC_DATA_BASE,
		output wire [C_S00_AXI_DATA_WIDTH-1 : 0] CSC_WEIGHT_BASE,
		output wire [C_S00_AXI_DATA_WIDTH-1 : 0] CSC_INPUT_WIDTH_HEIGHT,
		output wire [C_S00_AXI_DATA_WIDTH-1 : 0] CSC_INPUT_CHANNELS,
		output wire [C_S00_AXI_DATA_WIDTH-1 : 0] CSC_KERNEL_WIDTH_HEIGHT,
		output wire [C_S00_AXI_DATA_WIDTH-1 : 0] CSC_STRIDE_XY,
		output wire [C_S00_AXI_DATA_WIDTH-1 : 0] CSC_OUTPUT_WIDTH_HEIGHT,
		output wire [C_S00_AXI_DATA_WIDTH-1 : 0] CSC_OUTPUT_CHANNELS,

		// User ports ends
		// Do not modify the ports beyond this line


		// Ports of Axi Slave Bus Interface S00_AXI
		input wire  s00_axi_aclk,
		input wire  s00_axi_aresetn,
		input wire [C_S00_AXI_ADDR_WIDTH-1 : 0] s00_axi_awaddr,
		input wire [2 : 0] s00_axi_awprot,
		input wire  s00_axi_awvalid,
		output wire  s00_axi_awready,
		input wire [C_S00_AXI_DATA_WIDTH-1 : 0] s00_axi_wdata,
		input wire [(C_S00_AXI_DATA_WIDTH/8)-1 : 0] s00_axi_wstrb,
		input wire  s00_axi_wvalid,
		output wire  s00_axi_wready,
		output wire [1 : 0] s00_axi_bresp,
		output wire  s00_axi_bvalid,
		input wire  s00_axi_bready,
		input wire [C_S00_AXI_ADDR_WIDTH-1 : 0] s00_axi_araddr,
		input wire [2 : 0] s00_axi_arprot,
		input wire  s00_axi_arvalid,
		output wire  s00_axi_arready,
		output wire [C_S00_AXI_DATA_WIDTH-1 : 0] s00_axi_rdata,
		output wire [1 : 0] s00_axi_rresp,
		output wire  s00_axi_rvalid,
		input wire  s00_axi_rready
	);
// Instantiation of Axi Bus Interface S00_AXI
	axi_slave_csb_v1_0_S00_AXI # ( 
		.C_S_AXI_DATA_WIDTH(C_S00_AXI_DATA_WIDTH),
		.C_S_AXI_ADDR_WIDTH(C_S00_AXI_ADDR_WIDTH)
	) axi_slave_csb_v1_0_S00_AXI_inst (
		.CDMA_CONTROL(CDMA_CONTROL),
		.CDMA_STATUS(CDMA_STATUS),
		.DATA_MATRIX_WIDTH(DATA_MATRIX_WIDTH),
		.DATA_MATRIX_HEIGHT(DATA_MATRIX_HEIGHT),
		.DATA_CHANNEL_COUNT(DATA_CHANNEL_COUNT),
		.DATA_DST_BASE(DATA_DST_BASE),
		.WEIGHT_MATRIX_WIDTH(WEIGHT_MATRIX_WIDTH),
		.WEIGHT_MATRIX_HEIGHT(WEIGHT_MATRIX_HEIGHT),
		.WEIGHT_CHANNEL_COUNT(WEIGHT_CHANNEL_COUNT),
		.WEIGHT_DST_BASE(WEIGHT_DST_BASE),
		.CSC_CONTROL(CSC_CONTROL),
		.CSC_STATUS(CSC_STATUS),
		.CSC_ATOMICS(CSC_ATOMICS),
		.CSC_DATA_BASE(CSC_DATA_BASE),
		.CSC_WEIGHT_BASE(CSC_WEIGHT_BASE),
		.CSC_INPUT_WIDTH_HEIGHT(CSC_INPUT_WIDTH_HEIGHT),
		.CSC_INPUT_CHANNELS(CSC_INPUT_CHANNELS),
		.CSC_KERNEL_WIDTH_HEIGHT(CSC_KERNEL_WIDTH_HEIGHT),
		.CSC_STRIDE_XY(CSC_STRIDE_XY),
		.CSC_OUTPUT_WIDTH_HEIGHT(CSC_OUTPUT_WIDTH_HEIGHT),
		.CSC_OUTPUT_CHANNELS(CSC_OUTPUT_CHANNELS),
		.S_AXI_ACLK(s00_axi_aclk),
		.S_AXI_ARESETN(s00_axi_aresetn),
		.S_AXI_AWADDR(s00_axi_awaddr),
		.S_AXI_AWPROT(s00_axi_awprot),
		.S_AXI_AWVALID(s00_axi_awvalid),
		.S_AXI_AWREADY(s00_axi_awready),
		.S_AXI_WDATA(s00_axi_wdata),
		.S_AXI_WSTRB(s00_axi_wstrb),
		.S_AXI_WVALID(s00_axi_wvalid),
		.S_AXI_WREADY(s00_axi_wready),
		.S_AXI_BRESP(s00_axi_bresp),
		.S_AXI_BVALID(s00_axi_bvalid),
		.S_AXI_BREADY(s00_axi_bready),
		.S_AXI_ARADDR(s00_axi_araddr),
		.S_AXI_ARPROT(s00_axi_arprot),
		.S_AXI_ARVALID(s00_axi_arvalid),
		.S_AXI_ARREADY(s00_axi_arready),
		.S_AXI_RDATA(s00_axi_rdata),
		.S_AXI_RRESP(s00_axi_rresp),
		.S_AXI_RVALID(s00_axi_rvalid),
		.S_AXI_RREADY(s00_axi_rready)
	);

	// Add user logic here

	// User logic ends

	endmodule
