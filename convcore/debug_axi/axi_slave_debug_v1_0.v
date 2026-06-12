`timescale 1 ns / 1 ps

// AXI-Lite wrapper for the MACLane debug packet interface.
//
// Suggested Vivado Address Editor base address:
//   0x4001_0000
//
// The base address is assigned by the block design address map, not by RTL.
// Keep this value different from the existing CSB base address 0x4000_0000.

module axi_slave_debug_v1_0 #(
    parameter integer C_S00_AXI_DATA_WIDTH = 32,
    parameter integer C_S00_AXI_ADDR_WIDTH = 7,
    parameter integer MACCELL_NUM = 8,
    parameter integer DEBUG_TAG_WIDTH = 32,
    parameter integer DEBUG_SELECT_WIDTH = 3,
    parameter integer DEBUG_LANE_WIDTH = 32,
    parameter integer DEBUG_CONTROL_WIDTH = 8,
    parameter integer DEBUG_EXPECTED_PACKET_WIDTH =
        (2 * DEBUG_LANE_WIDTH) + DEBUG_TAG_WIDTH + DEBUG_SELECT_WIDTH + 4,
    parameter integer DEBUG_STATUS_PACKET_BASE_WIDTH =
        129 + DEBUG_TAG_WIDTH + (2 * MACCELL_NUM) + (2 * DEBUG_LANE_WIDTH),
    parameter integer DEBUG_STATUS_PACKET_WIDTH =
        (((DEBUG_STATUS_PACKET_BASE_WIDTH + 31) / 32) * 32) + 32,
    parameter integer C_DEBUG_BASEADDR = 32'h4001_0000
) (
    output wire [DEBUG_CONTROL_WIDTH-1:0] DEBUG_CONTROL_PACKET,
    output wire [DEBUG_EXPECTED_PACKET_WIDTH-1:0] DEBUG_EXPECTED_PACKET,
    input  wire [DEBUG_STATUS_PACKET_WIDTH-1:0] DEBUG_STATUS_PACKET,

    input  wire s00_axi_aclk,
    input  wire s00_axi_aresetn,
    input  wire [C_S00_AXI_ADDR_WIDTH-1:0] s00_axi_awaddr,
    input  wire [2:0] s00_axi_awprot,
    input  wire s00_axi_awvalid,
    output wire s00_axi_awready,
    input  wire [C_S00_AXI_DATA_WIDTH-1:0] s00_axi_wdata,
    input  wire [(C_S00_AXI_DATA_WIDTH/8)-1:0] s00_axi_wstrb,
    input  wire s00_axi_wvalid,
    output wire s00_axi_wready,
    output wire [1:0] s00_axi_bresp,
    output wire s00_axi_bvalid,
    input  wire s00_axi_bready,
    input  wire [C_S00_AXI_ADDR_WIDTH-1:0] s00_axi_araddr,
    input  wire [2:0] s00_axi_arprot,
    input  wire s00_axi_arvalid,
    output wire s00_axi_arready,
    output wire [C_S00_AXI_DATA_WIDTH-1:0] s00_axi_rdata,
    output wire [1:0] s00_axi_rresp,
    output wire s00_axi_rvalid,
    input  wire s00_axi_rready
);

    axi_slave_debug_v1_0_S00_AXI #(
        .C_S_AXI_DATA_WIDTH(C_S00_AXI_DATA_WIDTH),
        .C_S_AXI_ADDR_WIDTH(C_S00_AXI_ADDR_WIDTH),
        .MACCELL_NUM(MACCELL_NUM),
        .DEBUG_TAG_WIDTH(DEBUG_TAG_WIDTH),
        .DEBUG_SELECT_WIDTH(DEBUG_SELECT_WIDTH),
        .DEBUG_LANE_WIDTH(DEBUG_LANE_WIDTH),
        .DEBUG_CONTROL_WIDTH(DEBUG_CONTROL_WIDTH),
        .DEBUG_EXPECTED_PACKET_WIDTH(DEBUG_EXPECTED_PACKET_WIDTH),
        .DEBUG_STATUS_PACKET_BASE_WIDTH(DEBUG_STATUS_PACKET_BASE_WIDTH),
        .DEBUG_STATUS_PACKET_WIDTH(DEBUG_STATUS_PACKET_WIDTH),
        .C_DEBUG_BASEADDR(C_DEBUG_BASEADDR)
    ) axi_slave_debug_v1_0_S00_AXI_inst (
        .DEBUG_CONTROL_PACKET(DEBUG_CONTROL_PACKET),
        .DEBUG_EXPECTED_PACKET(DEBUG_EXPECTED_PACKET),
        .DEBUG_STATUS_PACKET(DEBUG_STATUS_PACKET),
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

endmodule
