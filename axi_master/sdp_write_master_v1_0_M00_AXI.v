`timescale 1 ns / 1 ps

// Single-beat AXI write master for SDP writeback.
//
// WRITE_REQ_* is a simple request stream. Each accepted request becomes one
// AXI4 single-beat write transaction. WRITE_DONE pulses after the B response
// for a request with WRITE_REQ_LAST set.

module sdp_write_master_v1_0_M00_AXI #(
    parameter C_M_TARGET_SLAVE_BASE_ADDR = 32'h00000000,
    parameter integer C_M_AXI_ID_WIDTH   = 1,
    parameter integer C_M_AXI_ADDR_WIDTH = 32,
    parameter integer C_M_AXI_DATA_WIDTH = 32
) (
    input wire [C_M_AXI_ADDR_WIDTH-1:0] WRITE_REQ_ADDR,
    input wire [C_M_AXI_DATA_WIDTH-1:0] WRITE_REQ_DATA,
    input wire [(C_M_AXI_DATA_WIDTH/8)-1:0] WRITE_REQ_STRB,
    input wire WRITE_REQ_VALID,
    output wire WRITE_REQ_READY,
    input wire WRITE_REQ_LAST,

    output reg  WRITE_DONE,
    output reg  ERROR,

    input wire M_AXI_ACLK,
    input wire M_AXI_ARESETN,

    output wire [C_M_AXI_ID_WIDTH-1:0] M_AXI_AWID,
    output wire [C_M_AXI_ADDR_WIDTH-1:0] M_AXI_AWADDR,
    output wire [7:0] M_AXI_AWLEN,
    output wire [2:0] M_AXI_AWSIZE,
    output wire [1:0] M_AXI_AWBURST,
    output wire M_AXI_AWLOCK,
    output wire [3:0] M_AXI_AWCACHE,
    output wire [2:0] M_AXI_AWPROT,
    output wire [3:0] M_AXI_AWQOS,
    output wire M_AXI_AWVALID,
    input wire M_AXI_AWREADY,

    output wire [C_M_AXI_DATA_WIDTH-1:0] M_AXI_WDATA,
    output wire [(C_M_AXI_DATA_WIDTH/8)-1:0] M_AXI_WSTRB,
    output wire M_AXI_WLAST,
    output wire M_AXI_WVALID,
    input wire M_AXI_WREADY,

    input wire [C_M_AXI_ID_WIDTH-1:0] M_AXI_BID,
    input wire [1:0] M_AXI_BRESP,
    input wire M_AXI_BVALID,
    output wire M_AXI_BREADY
);

    function integer clogb2(input integer bit_depth);
        integer depth;
        begin
            depth = bit_depth;
            for (clogb2 = 0; depth > 0; clogb2 = clogb2 + 1) begin
                depth = depth >> 1;
            end
        end
    endfunction

    localparam [1:0] ST_IDLE   = 2'b00;
    localparam [1:0] ST_WRITE  = 2'b01;
    localparam [1:0] ST_WAIT_B = 2'b10;

    reg [1:0] state_q;
    reg [C_M_AXI_ADDR_WIDTH-1:0] req_addr_q;
    reg [C_M_AXI_DATA_WIDTH-1:0] req_data_q;
    reg [(C_M_AXI_DATA_WIDTH/8)-1:0] req_strb_q;
    reg req_last_q;
    reg axi_awvalid_q;
    reg axi_wvalid_q;
    reg axi_bready_q;

    wire req_fire_w;
    wire aw_fire_w;
    wire w_fire_w;
    wire b_fire_w;

    assign WRITE_REQ_READY = (state_q == ST_IDLE);
    assign req_fire_w = WRITE_REQ_VALID && WRITE_REQ_READY;

    assign aw_fire_w = M_AXI_AWVALID && M_AXI_AWREADY;
    assign w_fire_w  = M_AXI_WVALID && M_AXI_WREADY;
    assign b_fire_w  = M_AXI_BVALID && M_AXI_BREADY;

    assign M_AXI_AWID    = {C_M_AXI_ID_WIDTH{1'b0}};
    assign M_AXI_AWADDR  = C_M_TARGET_SLAVE_BASE_ADDR + req_addr_q;
    assign M_AXI_AWLEN   = 8'd0;
    assign M_AXI_AWSIZE  = clogb2((C_M_AXI_DATA_WIDTH/8)-1);
    assign M_AXI_AWBURST = 2'b01;
    assign M_AXI_AWLOCK  = 1'b0;
    assign M_AXI_AWCACHE = 4'b0010;
    assign M_AXI_AWPROT  = 3'b000;
    assign M_AXI_AWQOS   = 4'b0000;
    assign M_AXI_AWVALID = axi_awvalid_q;

    assign M_AXI_WDATA   = req_data_q;
    assign M_AXI_WSTRB   = req_strb_q;
    assign M_AXI_WLAST   = 1'b1;
    assign M_AXI_WVALID  = axi_wvalid_q;
    assign M_AXI_BREADY  = axi_bready_q;

    always @(posedge M_AXI_ACLK) begin
        if (M_AXI_ARESETN == 1'b0) begin
            state_q       <= ST_IDLE;
            req_addr_q    <= {C_M_AXI_ADDR_WIDTH{1'b0}};
            req_data_q    <= {C_M_AXI_DATA_WIDTH{1'b0}};
            req_strb_q    <= {(C_M_AXI_DATA_WIDTH/8){1'b0}};
            req_last_q    <= 1'b0;
            axi_awvalid_q <= 1'b0;
            axi_wvalid_q  <= 1'b0;
            axi_bready_q  <= 1'b0;
            WRITE_DONE    <= 1'b0;
            ERROR         <= 1'b0;
        end else begin
            WRITE_DONE <= 1'b0;
            ERROR      <= 1'b0;

            case (state_q)
                ST_IDLE: begin
                    axi_awvalid_q <= 1'b0;
                    axi_wvalid_q  <= 1'b0;
                    axi_bready_q  <= 1'b0;

                    if (req_fire_w) begin
                        req_addr_q    <= WRITE_REQ_ADDR;
                        req_data_q    <= WRITE_REQ_DATA;
                        req_strb_q    <= WRITE_REQ_STRB;
                        req_last_q    <= WRITE_REQ_LAST;
                        axi_awvalid_q <= 1'b1;
                        axi_wvalid_q  <= 1'b1;
                        state_q       <= ST_WRITE;
                    end
                end

                ST_WRITE: begin
                    if (aw_fire_w) begin
                        axi_awvalid_q <= 1'b0;
                    end

                    if (w_fire_w) begin
                        axi_wvalid_q <= 1'b0;
                    end

                    if ((!axi_awvalid_q || aw_fire_w) &&
                        (!axi_wvalid_q || w_fire_w)) begin
                        axi_bready_q <= 1'b1;
                        state_q      <= ST_WAIT_B;
                    end
                end

                ST_WAIT_B: begin
                    if (b_fire_w) begin
                        axi_bready_q <= 1'b0;
                        state_q      <= ST_IDLE;

                        if ((M_AXI_BRESP != 2'b00) ||
                            (M_AXI_BID != {C_M_AXI_ID_WIDTH{1'b0}})) begin
                            ERROR <= 1'b1;
                        end else if (req_last_q) begin
                            WRITE_DONE <= 1'b1;
                        end
                    end
                end

                default: begin
                    state_q       <= ST_IDLE;
                    axi_awvalid_q <= 1'b0;
                    axi_wvalid_q  <= 1'b0;
                    axi_bready_q  <= 1'b0;
                end
            endcase
        end
    end

endmodule
