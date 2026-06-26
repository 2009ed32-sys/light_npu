`timescale 1 ns / 1 ps

module sdp_write_master_v1_0 #(
    parameter C_M00_AXI_TARGET_SLAVE_BASE_ADDR = 32'h00000000,
    parameter integer C_M00_AXI_ID_WIDTH   = 1,
    parameter integer C_M00_AXI_ADDR_WIDTH = 32,
    parameter integer C_M00_AXI_DATA_WIDTH = 32
) (
    input wire [C_M00_AXI_ADDR_WIDTH-1:0] sdp_write_addr,
    input wire [C_M00_AXI_DATA_WIDTH-1:0] sdp_write_data,
    input wire [(C_M00_AXI_DATA_WIDTH/8)-1:0] sdp_write_strb,
    input wire sdp_write_valid,
    output wire sdp_write_ready,
    input wire sdp_write_last,
    output wire sdp_write_done,
    output wire sdp_write_error,

    input wire m00_axi_aclk,
    input wire m00_axi_aresetn,
    output wire [C_M00_AXI_ID_WIDTH-1:0] m00_axi_awid,
    output wire [C_M00_AXI_ADDR_WIDTH-1:0] m00_axi_awaddr,
    output wire [7:0] m00_axi_awlen,
    output wire [2:0] m00_axi_awsize,
    output wire [1:0] m00_axi_awburst,
    output wire m00_axi_awlock,
    output wire [3:0] m00_axi_awcache,
    output wire [2:0] m00_axi_awprot,
    output wire [3:0] m00_axi_awqos,
    output wire m00_axi_awvalid,
    input wire m00_axi_awready,
    output wire [C_M00_AXI_DATA_WIDTH-1:0] m00_axi_wdata,
    output wire [(C_M00_AXI_DATA_WIDTH/8)-1:0] m00_axi_wstrb,
    output wire m00_axi_wlast,
    output wire m00_axi_wvalid,
    input wire m00_axi_wready,
    input wire [C_M00_AXI_ID_WIDTH-1:0] m00_axi_bid,
    input wire [1:0] m00_axi_bresp,
    input wire m00_axi_bvalid,
    output wire m00_axi_bready
);

    sdp_write_master_v1_0_M00_AXI #(
        .C_M_TARGET_SLAVE_BASE_ADDR(C_M00_AXI_TARGET_SLAVE_BASE_ADDR),
        .C_M_AXI_ID_WIDTH(C_M00_AXI_ID_WIDTH),
        .C_M_AXI_ADDR_WIDTH(C_M00_AXI_ADDR_WIDTH),
        .C_M_AXI_DATA_WIDTH(C_M00_AXI_DATA_WIDTH)
    ) sdp_write_master_v1_0_M00_AXI_inst (
        .WRITE_REQ_ADDR(sdp_write_addr),
        .WRITE_REQ_DATA(sdp_write_data),
        .WRITE_REQ_STRB(sdp_write_strb),
        .WRITE_REQ_VALID(sdp_write_valid),
        .WRITE_REQ_READY(sdp_write_ready),
        .WRITE_REQ_LAST(sdp_write_last),
        .WRITE_DONE(sdp_write_done),
        .ERROR(sdp_write_error),
        .M_AXI_ACLK(m00_axi_aclk),
        .M_AXI_ARESETN(m00_axi_aresetn),
        .M_AXI_AWID(m00_axi_awid),
        .M_AXI_AWADDR(m00_axi_awaddr),
        .M_AXI_AWLEN(m00_axi_awlen),
        .M_AXI_AWSIZE(m00_axi_awsize),
        .M_AXI_AWBURST(m00_axi_awburst),
        .M_AXI_AWLOCK(m00_axi_awlock),
        .M_AXI_AWCACHE(m00_axi_awcache),
        .M_AXI_AWPROT(m00_axi_awprot),
        .M_AXI_AWQOS(m00_axi_awqos),
        .M_AXI_AWVALID(m00_axi_awvalid),
        .M_AXI_AWREADY(m00_axi_awready),
        .M_AXI_WDATA(m00_axi_wdata),
        .M_AXI_WSTRB(m00_axi_wstrb),
        .M_AXI_WLAST(m00_axi_wlast),
        .M_AXI_WVALID(m00_axi_wvalid),
        .M_AXI_WREADY(m00_axi_wready),
        .M_AXI_BID(m00_axi_bid),
        .M_AXI_BRESP(m00_axi_bresp),
        .M_AXI_BVALID(m00_axi_bvalid),
        .M_AXI_BREADY(m00_axi_bready)
    );

endmodule
