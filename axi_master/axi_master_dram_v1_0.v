
`timescale 1 ns / 1 ps

	module axi_master_dram_v1_0 #
	(
		// Users to add parameters here
	
		// User parameters ends
		// Do not modify the parameters beyond this line
		
		// Parameters of Axi Master Bus Interface M00_AXI
		parameter  C_M00_AXI_TARGET_SLAVE_BASE_ADDR	= 32'h00000000,
		parameter integer C_M00_AXI_BURST_LEN	= 8,
		parameter integer C_M00_AXI_ID_WIDTH	= 1,
		parameter integer C_M00_AXI_ADDR_WIDTH	= 32,
		parameter integer C_M00_AXI_DATA_WIDTH	= 32
	)
	(
		// Users to add ports here
		input wire [C_M00_AXI_ADDR_WIDTH-1 : 0] axi_txn_addr,
		output wire axi_stream_valid,
		input wire axi_stream_ready,
		output wire [C_M00_AXI_DATA_WIDTH-1 : 0] axi_stream_data,

		// User ports ends
		// Do not modify the ports beyond this line


		// Ports of Axi Master Bus Interface M00_AXI
		input wire  m00_axi_init_axi_txn,
		output wire  m00_axi_txn_done,
		output wire  m00_axi_error,
		input wire  m00_axi_aclk,
		input wire  m00_axi_aresetn,
		output wire [C_M00_AXI_ID_WIDTH-1 : 0] m00_axi_arid,
		output wire [C_M00_AXI_ADDR_WIDTH-1 : 0] m00_axi_araddr,
		output wire [7 : 0] m00_axi_arlen,
		output wire [2 : 0] m00_axi_arsize,
		output wire [1 : 0] m00_axi_arburst,
		output wire  m00_axi_arlock,
		output wire [3 : 0] m00_axi_arcache,
		output wire [2 : 0] m00_axi_arprot,
		output wire [3 : 0] m00_axi_arqos,
		output wire  m00_axi_arvalid,
		input wire  m00_axi_arready,
		input wire [C_M00_AXI_ID_WIDTH-1 : 0] m00_axi_rid,
		input wire [C_M00_AXI_DATA_WIDTH-1 : 0] m00_axi_rdata,
		input wire [1 : 0] m00_axi_rresp,
		input wire  m00_axi_rlast,
		input wire  m00_axi_rvalid,
		output wire  m00_axi_rready
	);
// Instantiation of Axi Bus Interface M00_AXI
	axi_master_dram_v1_0_M00_AXI # ( 
		.C_M_TARGET_SLAVE_BASE_ADDR(C_M00_AXI_TARGET_SLAVE_BASE_ADDR),
		.C_M_AXI_BURST_LEN(C_M00_AXI_BURST_LEN),
		.C_M_AXI_ID_WIDTH(C_M00_AXI_ID_WIDTH),
		.C_M_AXI_ADDR_WIDTH(C_M00_AXI_ADDR_WIDTH),
		.C_M_AXI_DATA_WIDTH(C_M00_AXI_DATA_WIDTH)
	) axi_master_dram_v1_0_M00_AXI_inst (
		.TXN_ADDR(axi_txn_addr),
		.STREAM_READY(axi_stream_ready),
		.STREAM_VALID(axi_stream_valid),
		.STREAM_DATA(axi_stream_data),
		.INIT_AXI_TXN(m00_axi_init_axi_txn),
		.TXN_DONE(m00_axi_txn_done),
		.ERROR(m00_axi_error),
		.M_AXI_ACLK(m00_axi_aclk),
		.M_AXI_ARESETN(m00_axi_aresetn),
		.M_AXI_ARID(m00_axi_arid),
		.M_AXI_ARADDR(m00_axi_araddr),
		.M_AXI_ARLEN(m00_axi_arlen),
		.M_AXI_ARSIZE(m00_axi_arsize),
		.M_AXI_ARBURST(m00_axi_arburst),
		.M_AXI_ARLOCK(m00_axi_arlock),
		.M_AXI_ARCACHE(m00_axi_arcache),
		.M_AXI_ARPROT(m00_axi_arprot),
		.M_AXI_ARQOS(m00_axi_arqos),
		.M_AXI_ARVALID(m00_axi_arvalid),
		.M_AXI_ARREADY(m00_axi_arready),
		.M_AXI_RID(m00_axi_rid),
		.M_AXI_RDATA(m00_axi_rdata),
		.M_AXI_RRESP(m00_axi_rresp),
		.M_AXI_RLAST(m00_axi_rlast),
		.M_AXI_RVALID(m00_axi_rvalid),
		.M_AXI_RREADY(m00_axi_rready)
	);

	endmodule
