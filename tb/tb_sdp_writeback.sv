`timescale 1ns / 1ps

module tb_sdp_writeback;

    localparam int MACCELL_NUM     = 8;
    localparam int PSUM_WIDTH      = 32;
    localparam int ADDR_WIDTH      = 32;
    localparam int AXI_ID_WIDTH    = 1;
    localparam int AXI_DATA_WIDTH  = 32;
    localparam int AXI_ADDR_WIDTH  = 32;

    logic clk;
    logic rst_n;

    logic                         op_enable;
    logic                         op_start;
    logic [ADDR_WIDTH-1:0]        output_base_addr;
    logic                         cacc_valid;
    logic                         cacc_ready;
    logic [MACCELL_NUM-1:0]       cacc_mask;
    logic [MACCELL_NUM*PSUM_WIDTH-1:0] cacc_data;
    logic                         cacc_last;

    logic                         write_req_valid;
    logic                         write_req_ready;
    logic [ADDR_WIDTH-1:0]        write_req_addr;
    logic [AXI_DATA_WIDTH-1:0]    write_req_data;
    logic [AXI_DATA_WIDTH/8-1:0]  write_req_strb;
    logic                         write_req_last;
    logic                         write_done;
    logic                         write_error;

    logic                         op_ready;
    logic                         op_busy;
    logic                         op_done;
    logic                         op_error;

    logic [AXI_ID_WIDTH-1:0]      m_axi_awid;
    logic [AXI_ADDR_WIDTH-1:0]    m_axi_awaddr;
    logic [7:0]                   m_axi_awlen;
    logic [2:0]                   m_axi_awsize;
    logic [1:0]                   m_axi_awburst;
    logic                         m_axi_awvalid;
    logic                         m_axi_awready;
    logic [AXI_DATA_WIDTH-1:0]    m_axi_wdata;
    logic [AXI_DATA_WIDTH/8-1:0]  m_axi_wstrb;
    logic                         m_axi_wlast;
    logic                         m_axi_wvalid;
    logic                         m_axi_wready;
    logic [AXI_ID_WIDTH-1:0]      m_axi_bid;
    logic [1:0]                   m_axi_bresp;
    logic                         m_axi_bvalid;
    logic                         m_axi_bready;

    logic [31:0] expected_addr [0:4];
    logic [31:0] expected_data [0:4];

    int errors;
    int write_errors;
    int write_count;
    int aw_first_count;
    int w_first_count;
    int simultaneous_count;

    logic slave_aw_seen_q;
    logic slave_w_seen_q;
    logic response_pending_q;
    logic [2:0] response_delay_q;
    logic [2:0] ready_delay_q;
    logic write_error_seen_q;

    wire aw_fire = m_axi_awvalid && m_axi_awready;
    wire w_fire  = m_axi_wvalid && m_axi_wready;

    sdp #(
        .MACCELL_NUM(MACCELL_NUM),
        .PSUM_WIDTH(PSUM_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) u_sdp (
        .clk(clk),
        .rst_n(rst_n),
        .op_enable(op_enable),
        .op_start(op_start),
        .op_ready(op_ready),
        .op_busy(op_busy),
        .op_done(op_done),
        .op_error(op_error),
        .output_base_addr(output_base_addr),
        .cacc_valid(cacc_valid),
        .cacc_ready(cacc_ready),
        .cacc_mask(cacc_mask),
        .cacc_data(cacc_data),
        .cacc_last(cacc_last),
        .write_req_valid(write_req_valid),
        .write_req_ready(write_req_ready),
        .write_req_addr(write_req_addr),
        .write_req_data(write_req_data),
        .write_req_strb(write_req_strb),
        .write_req_last(write_req_last),
        .write_done(write_done),
        .write_error(write_error)
    );

    sdp_write_master_v1_0_M00_AXI #(
        .C_M_AXI_ID_WIDTH(AXI_ID_WIDTH),
        .C_M_AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .C_M_AXI_DATA_WIDTH(AXI_DATA_WIDTH)
    ) u_write_master (
        .WRITE_REQ_VALID(write_req_valid),
        .WRITE_REQ_READY(write_req_ready),
        .WRITE_REQ_ADDR(write_req_addr),
        .WRITE_REQ_DATA(write_req_data),
        .WRITE_REQ_STRB(write_req_strb),
        .WRITE_REQ_LAST(write_req_last),
        .WRITE_DONE(write_done),
        .ERROR(write_error),
        .M_AXI_ACLK(clk),
        .M_AXI_ARESETN(rst_n),
        .M_AXI_AWID(m_axi_awid),
        .M_AXI_AWADDR(m_axi_awaddr),
        .M_AXI_AWLEN(m_axi_awlen),
        .M_AXI_AWSIZE(m_axi_awsize),
        .M_AXI_AWBURST(m_axi_awburst),
        .M_AXI_AWLOCK(),
        .M_AXI_AWCACHE(),
        .M_AXI_AWPROT(),
        .M_AXI_AWQOS(),
        .M_AXI_AWVALID(m_axi_awvalid),
        .M_AXI_AWREADY(m_axi_awready),
        .M_AXI_WDATA(m_axi_wdata),
        .M_AXI_WSTRB(m_axi_wstrb),
        .M_AXI_WLAST(m_axi_wlast),
        .M_AXI_WVALID(m_axi_wvalid),
        .M_AXI_WREADY(m_axi_wready),
        .M_AXI_BID(m_axi_bid),
        .M_AXI_BRESP(m_axi_bresp),
        .M_AXI_BVALID(m_axi_bvalid),
        .M_AXI_BREADY(m_axi_bready)
    );

    axi_write_protocol_checker #(
        .ADDR_WIDTH(AXI_ADDR_WIDTH),
        .DATA_WIDTH(AXI_DATA_WIDTH)
    ) u_axi_write_checker (
        .ACLK(clk),
        .ARESETn(rst_n),
        .AWADDR(m_axi_awaddr),
        .AWLEN(m_axi_awlen),
        .AWSIZE(m_axi_awsize),
        .AWBURST(m_axi_awburst),
        .AWVALID(m_axi_awvalid),
        .AWREADY(m_axi_awready),
        .WDATA(m_axi_wdata),
        .WSTRB(m_axi_wstrb),
        .WLAST(m_axi_wlast),
        .WVALID(m_axi_wvalid),
        .WREADY(m_axi_wready),
        .BRESP(m_axi_bresp),
        .BVALID(m_axi_bvalid),
        .BREADY(m_axi_bready)
    );

    always #5 clk = ~clk;

    task automatic send_cacc_vector(
        input logic [MACCELL_NUM-1:0] mask,
        input logic [31:0] lane0,
        input logic [31:0] lane1,
        input logic last
    );
        logic [MACCELL_NUM*PSUM_WIDTH-1:0] payload;
        begin
            payload = '0;
            payload[0*PSUM_WIDTH +: PSUM_WIDTH] = lane0;
            payload[1*PSUM_WIDTH +: PSUM_WIDTH] = lane1;
            @(negedge clk);
            cacc_mask  = mask;
            cacc_data  = payload;
            cacc_last  = last;
            cacc_valid = 1'b1;
            do @(posedge clk); while (!cacc_ready);
            @(negedge clk);
            cacc_valid = 1'b0;
        end
    endtask

    /*
     * The slave deliberately accepts AW and W in different orders. This
     * catches masters that incorrectly require both READY signals together.
     */
    always_comb begin
        m_axi_awready = 1'b0;
        m_axi_wready  = 1'b0;

        if (rst_n && !response_pending_q && !m_axi_bvalid) begin
            case (write_count % 3)
                0: begin
                    m_axi_awready = !slave_aw_seen_q;
                    m_axi_wready  = slave_aw_seen_q && !slave_w_seen_q;
                end
                1: begin
                    m_axi_wready  = !slave_w_seen_q;
                    m_axi_awready = slave_w_seen_q && !slave_aw_seen_q;
                end
                default: begin
                    m_axi_awready = (ready_delay_q >= 2) && !slave_aw_seen_q;
                    m_axi_wready  = (ready_delay_q >= 2) && !slave_w_seen_q;
                end
            endcase
        end
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            m_axi_bvalid        <= 1'b0;
            m_axi_bresp         <= 2'b00;
            write_count         <= 0;
            write_errors        <= 0;
            aw_first_count      <= 0;
            w_first_count       <= 0;
            simultaneous_count  <= 0;
            slave_aw_seen_q     <= 1'b0;
            slave_w_seen_q      <= 1'b0;
            response_pending_q  <= 1'b0;
            response_delay_q    <= '0;
            ready_delay_q       <= '0;
            write_error_seen_q  <= 1'b0;
        end else begin
            if (write_error)
                write_error_seen_q <= 1'b1;

            if ((write_count % 3) == 2 &&
                !response_pending_q && !m_axi_bvalid &&
                (m_axi_awvalid || m_axi_wvalid) && ready_delay_q < 2)
                ready_delay_q <= ready_delay_q + 1'b1;

            if (aw_fire) begin
                slave_aw_seen_q <= 1'b1;
                if (m_axi_awaddr !== expected_addr[write_count]) begin
                    $error("AWADDR[%0d] actual=%08x expected=%08x",
                           write_count, m_axi_awaddr, expected_addr[write_count]);
                    write_errors <= write_errors + 1;
                end
                if (m_axi_awlen != 0 || m_axi_awsize != 3'd2 ||
                    m_axi_awburst != 2'b01) begin
                    $error("AW control mismatch len=%0d size=%0d burst=%0d",
                           m_axi_awlen, m_axi_awsize, m_axi_awburst);
                    write_errors <= write_errors + 1;
                end
            end

            if (w_fire) begin
                slave_w_seen_q <= 1'b1;
                if (m_axi_wdata !== expected_data[write_count]) begin
                    $error("WDATA[%0d] actual=%08x expected=%08x",
                           write_count, m_axi_wdata, expected_data[write_count]);
                    write_errors <= write_errors + 1;
                end
                if (m_axi_wstrb != 4'hF || !m_axi_wlast) begin
                    $error("W control mismatch strb=%x last=%b",
                           m_axi_wstrb, m_axi_wlast);
                    write_errors <= write_errors + 1;
                end
            end

            if (aw_fire && w_fire)
                simultaneous_count <= simultaneous_count + 1;
            else if (aw_fire && !slave_w_seen_q)
                aw_first_count <= aw_first_count + 1;
            else if (w_fire && !slave_aw_seen_q)
                w_first_count <= w_first_count + 1;

            if ((slave_aw_seen_q || aw_fire) &&
                (slave_w_seen_q || w_fire) &&
                !response_pending_q && !m_axi_bvalid) begin
                response_pending_q <= 1'b1;
                response_delay_q   <= 3'd2;
            end

            if (response_pending_q) begin
                if (response_delay_q != 0) begin
                    response_delay_q <= response_delay_q - 1'b1;
                end else begin
                    response_pending_q <= 1'b0;
                    m_axi_bvalid       <= 1'b1;
                    m_axi_bresp        <= (write_count == 4) ? 2'b10 : 2'b00;
                end
            end

            if (m_axi_bvalid && m_axi_bready) begin
                m_axi_bvalid       <= 1'b0;
                m_axi_bresp        <= 2'b00;
                write_count        <= write_count + 1;
                slave_aw_seen_q    <= 1'b0;
                slave_w_seen_q     <= 1'b0;
                ready_delay_q      <= '0;
            end
        end
    end

    assign m_axi_bid = '0;

    initial begin
        clk                   = 1'b0;
        rst_n                 = 1'b0;
        op_enable             = 1'b0;
        op_start              = 1'b0;
        output_base_addr      = 32'h0000_0100;
        cacc_valid            = 1'b0;
        cacc_mask             = '0;
        cacc_data             = '0;
        cacc_last             = 1'b0;
        errors                = 0;

        expected_addr[0] = 32'h0000_0400;
        expected_addr[1] = 32'h0000_0404;
        expected_addr[2] = 32'h0000_0408;
        expected_addr[3] = 32'h0000_040C;
        expected_addr[4] = 32'h0000_0400;
        expected_data[0] = 32'h1111_0000;
        expected_data[1] = 32'h2222_0000;
        expected_data[2] = 32'h1111_0001;
        expected_data[3] = 32'h2222_0001;
        expected_data[4] = 32'h3333_0000;

        repeat (16) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        @(negedge clk);
        op_enable = 1'b1;
        op_start  = 1'b1;
        @(negedge clk);
        op_start = 1'b0;

        wait (op_ready);
        send_cacc_vector(8'h03, 32'h1111_0000, 32'h2222_0000, 1'b0);
        send_cacc_vector(8'h03, 32'h1111_0001, 32'h2222_0001, 1'b1);

        repeat (50) @(posedge clk);

        if (!op_done || op_busy || op_error) begin
            $error("normal operation status ready=%b busy=%b done=%b error=%b",
                   op_ready, op_busy, op_done, op_error);
            errors = errors + 1;
        end
        if (write_count != 4) begin
            $error("normal write count actual=%0d expected=4", write_count);
            errors = errors + 1;
        end
        if (aw_first_count == 0 || w_first_count == 0 ||
            simultaneous_count == 0) begin
            $error("AW/W ordering coverage missing aw_first=%0d w_first=%0d simultaneous=%0d",
                   aw_first_count, w_first_count, simultaneous_count);
            errors = errors + 1;
        end

        op_enable = 1'b0;
        repeat (2) @(posedge clk);
        @(negedge clk);
        op_enable = 1'b1;
        op_start  = 1'b1;
        @(negedge clk);
        op_start = 1'b0;

        wait (op_ready);
        send_cacc_vector(8'h01, 32'h3333_0000, 32'h0000_0000, 1'b1);
        repeat (30) @(posedge clk);

        if (!write_error_seen_q || !op_error || op_done) begin
            $error("BRESP error propagation failed seen=%b op_error=%b op_done=%b",
                   write_error_seen_q, op_error, op_done);
            errors = errors + 1;
        end
        if (write_count != 5) begin
            $error("error operation write count actual=%0d expected=5", write_count);
            errors = errors + 1;
        end

        errors = errors + write_errors;
        if (errors == 0)
            $display("SDP_AXI_WRITEBACK_PROTOCOL_TEST_PASS");
        else
            $fatal(1, "SDP_AXI_WRITEBACK_PROTOCOL_TEST_FAIL errors=%0d", errors);

        $finish;
    end

    initial begin
        #30000;
        $fatal(1, "SDP_AXI_WRITEBACK_PROTOCOL_TEST_TIMEOUT");
    end

endmodule
