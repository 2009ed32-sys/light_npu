`timescale 1 ns / 1 ps

// Fixed-length, read-only AXI master.
//
// INIT_AXI_TXN starts one read burst at TXN_ADDR. TXN_DONE and ERROR are
// one-cycle result pulses generated after the final read beat.

module axi_master_dram_v1_0_M00_AXI #(
    parameter C_M_TARGET_SLAVE_BASE_ADDR = 32'h00000000,
    parameter integer C_M_AXI_BURST_LEN  = 8,
    parameter integer C_M_AXI_ID_WIDTH   = 1,
    parameter integer C_M_AXI_ADDR_WIDTH = 32,
    parameter integer C_M_AXI_DATA_WIDTH = 32,
    parameter integer C_M_AXI_AWUSER_WIDTH = 0,
    parameter integer C_M_AXI_ARUSER_WIDTH = 0,
    parameter integer C_M_AXI_WUSER_WIDTH  = 0,
    parameter integer C_M_AXI_RUSER_WIDTH  = 0,
    parameter integer C_M_AXI_BUSER_WIDTH  = 0
) (
    input wire [C_M_AXI_ADDR_WIDTH-1:0] TXN_ADDR,
    input wire STREAM_READY,

    input wire  INIT_AXI_TXN,
    output reg  TXN_DONE,
    output reg  ERROR,
    input wire  M_AXI_ACLK,
    input wire  M_AXI_ARESETN,

    output wire [C_M_AXI_ID_WIDTH-1:0] M_AXI_AWID,
    output wire [C_M_AXI_ADDR_WIDTH-1:0] M_AXI_AWADDR,
    output wire [7:0] M_AXI_AWLEN,
    output wire [2:0] M_AXI_AWSIZE,
    output wire [1:0] M_AXI_AWBURST,
    output wire M_AXI_AWLOCK,
    output wire [3:0] M_AXI_AWCACHE,
    output wire [2:0] M_AXI_AWPROT,
    output wire [3:0] M_AXI_AWQOS,
    output wire [C_M_AXI_AWUSER_WIDTH-1:0] M_AXI_AWUSER,
    output wire M_AXI_AWVALID,
    input wire M_AXI_AWREADY,

    output wire [C_M_AXI_DATA_WIDTH-1:0] M_AXI_WDATA,
    output wire [(C_M_AXI_DATA_WIDTH/8)-1:0] M_AXI_WSTRB,
    output wire M_AXI_WLAST,
    output wire [C_M_AXI_WUSER_WIDTH-1:0] M_AXI_WUSER,
    output wire M_AXI_WVALID,
    input wire M_AXI_WREADY,

    input wire [C_M_AXI_ID_WIDTH-1:0] M_AXI_BID,
    input wire [1:0] M_AXI_BRESP,
    input wire [C_M_AXI_BUSER_WIDTH-1:0] M_AXI_BUSER,
    input wire M_AXI_BVALID,
    output wire M_AXI_BREADY,

    output wire [C_M_AXI_ID_WIDTH-1:0] M_AXI_ARID,
    output wire [C_M_AXI_ADDR_WIDTH-1:0] M_AXI_ARADDR,
    output wire [7:0] M_AXI_ARLEN,
    output wire [2:0] M_AXI_ARSIZE,
    output wire [1:0] M_AXI_ARBURST,
    output wire M_AXI_ARLOCK,
    output wire [3:0] M_AXI_ARCACHE,
    output wire [2:0] M_AXI_ARPROT,
    output wire [3:0] M_AXI_ARQOS,
    output wire [C_M_AXI_ARUSER_WIDTH-1:0] M_AXI_ARUSER,
    output wire M_AXI_ARVALID,
    input wire M_AXI_ARREADY,

    input wire [C_M_AXI_ID_WIDTH-1:0] M_AXI_RID,
    input wire [C_M_AXI_DATA_WIDTH-1:0] M_AXI_RDATA,
    input wire [1:0] M_AXI_RRESP,
    input wire M_AXI_RLAST,
    input wire [C_M_AXI_RUSER_WIDTH-1:0] M_AXI_RUSER,
    input wire M_AXI_RVALID,
    output wire M_AXI_RREADY
);

    function integer clogb2(input integer bit_depth);
        begin
            for (clogb2 = 0; bit_depth > 0; clogb2 = clogb2 + 1) begin
                bit_depth = bit_depth >> 1;
            end
        end
    endfunction

    localparam [1:0] ST_IDLE    = 2'b00;
    localparam [1:0] ST_SEND_AR = 2'b01;
    localparam [1:0] ST_READ    = 2'b10;

    reg [1:0] state_q;
    reg [C_M_AXI_ADDR_WIDTH-1:0] txn_addr_q;
    reg axi_arvalid_q;
    reg axi_rready_q;
    reg read_error_q;
    wire read_fire_w;

    assign M_AXI_AWID    = {C_M_AXI_ID_WIDTH{1'b0}};
    assign M_AXI_AWADDR  = {C_M_AXI_ADDR_WIDTH{1'b0}};
    assign M_AXI_AWLEN   = 8'd0;
    assign M_AXI_AWSIZE  = 3'd0;
    assign M_AXI_AWBURST = 2'b01;
    assign M_AXI_AWLOCK  = 1'b0;
    assign M_AXI_AWCACHE = 4'b0010;
    assign M_AXI_AWPROT  = 3'b000;
    assign M_AXI_AWQOS   = 4'b0000;
    assign M_AXI_AWUSER  = 'b0;
    assign M_AXI_AWVALID = 1'b0;

    assign M_AXI_WDATA   = {C_M_AXI_DATA_WIDTH{1'b0}};
    assign M_AXI_WSTRB   = {(C_M_AXI_DATA_WIDTH/8){1'b0}};
    assign M_AXI_WLAST   = 1'b0;
    assign M_AXI_WUSER   = 'b0;
    assign M_AXI_WVALID  = 1'b0;
    assign M_AXI_BREADY  = 1'b0;

    assign M_AXI_ARID    = {C_M_AXI_ID_WIDTH{1'b0}};
    assign M_AXI_ARADDR  = C_M_TARGET_SLAVE_BASE_ADDR + txn_addr_q;
    assign M_AXI_ARLEN   = C_M_AXI_BURST_LEN - 1;
    assign M_AXI_ARSIZE  = clogb2((C_M_AXI_DATA_WIDTH/8)-1);
    assign M_AXI_ARBURST = 2'b01;
    assign M_AXI_ARLOCK  = 1'b0;
    assign M_AXI_ARCACHE = 4'b0010;
    assign M_AXI_ARPROT  = 3'b000;
    assign M_AXI_ARQOS   = 4'b0000;
    assign M_AXI_ARUSER  = 'b0;
    assign M_AXI_ARVALID = axi_arvalid_q;
    assign M_AXI_RREADY  = axi_rready_q && STREAM_READY;
    assign read_fire_w   = M_AXI_RVALID && M_AXI_RREADY;

    always @(posedge M_AXI_ACLK) begin
        if (M_AXI_ARESETN == 1'b0) begin
            state_q       <= ST_IDLE;
            txn_addr_q    <= {C_M_AXI_ADDR_WIDTH{1'b0}};
            axi_arvalid_q <= 1'b0;
            axi_rready_q  <= 1'b0;
            read_error_q  <= 1'b0;
            TXN_DONE      <= 1'b0;
            ERROR         <= 1'b0;
        end else begin
            TXN_DONE <= 1'b0;
            ERROR    <= 1'b0;

            case (state_q)
                ST_IDLE: begin
                    axi_arvalid_q <= 1'b0;
                    axi_rready_q  <= 1'b0;
                    read_error_q  <= 1'b0;

                    if (INIT_AXI_TXN) begin
                        txn_addr_q    <= TXN_ADDR;
                        axi_arvalid_q <= 1'b1;
                        state_q       <= ST_SEND_AR;
                    end
                end

                ST_SEND_AR: begin
                    if (M_AXI_ARREADY && axi_arvalid_q) begin
                        axi_arvalid_q <= 1'b0;
                        axi_rready_q  <= 1'b1;
                        state_q       <= ST_READ;
                    end
                end

                ST_READ: begin
                    if (read_fire_w) begin
                        if (M_AXI_RRESP != 2'b00) begin
                            read_error_q <= 1'b1;
                        end

                        if (M_AXI_RLAST) begin
                            axi_rready_q <= 1'b0;
                            state_q      <= ST_IDLE;

                            if (read_error_q || (M_AXI_RRESP != 2'b00)) begin
                                ERROR <= 1'b1;
                            end else begin
                                TXN_DONE <= 1'b1;
                            end
                        end
                    end
                end

                default: begin
                    state_q       <= ST_IDLE;
                    axi_arvalid_q <= 1'b0;
                    axi_rready_q  <= 1'b0;
                    read_error_q  <= 1'b0;
                end
            endcase
        end
    end

endmodule
