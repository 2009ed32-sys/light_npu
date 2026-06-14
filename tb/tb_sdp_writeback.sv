`timescale 1ns/1ps

module tb_sdp_writeback;
    localparam int MACCELL_NUM = 8;
    localparam int PSUM_WIDTH = 32;
    localparam int ADDR_WIDTH = 32;
    localparam int AXI_DATA_WIDTH = 32;

    logic clk;
    logic rst_n;

    logic op_enable;
    logic op_start;
    logic op_ready;
    logic op_busy;
    logic op_done;
    logic op_error;

    logic [ADDR_WIDTH-1:0] output_base_addr;
    logic cacc_valid;
    logic cacc_ready;
    logic [MACCELL_NUM-1:0] cacc_mask;
    logic [(MACCELL_NUM*PSUM_WIDTH)-1:0] cacc_data;
    logic cacc_last;

    logic write_req_valid;
    logic write_req_ready;
    logic [ADDR_WIDTH-1:0] write_req_addr;
    logic [PSUM_WIDTH-1:0] write_req_data;
    logic [(PSUM_WIDTH/8)-1:0] write_req_strb;
    logic write_req_last;
    logic write_done;
    logic write_error;

    logic [0:0] m_axi_awid;
    logic [ADDR_WIDTH-1:0] m_axi_awaddr;
    logic [7:0] m_axi_awlen;
    logic [2:0] m_axi_awsize;
    logic [1:0] m_axi_awburst;
    logic m_axi_awlock;
    logic [3:0] m_axi_awcache;
    logic [2:0] m_axi_awprot;
    logic [3:0] m_axi_awqos;
    logic m_axi_awvalid;
    logic m_axi_awready;
    logic [AXI_DATA_WIDTH-1:0] m_axi_wdata;
    logic [(AXI_DATA_WIDTH/8)-1:0] m_axi_wstrb;
    logic m_axi_wlast;
    logic m_axi_wvalid;
    logic m_axi_wready;
    logic [0:0] m_axi_bid;
    logic [1:0] m_axi_bresp;
    logic m_axi_bvalid;
    logic m_axi_bready;
    logic [0:0] m_axi_arid;
    logic [ADDR_WIDTH-1:0] m_axi_araddr;
    logic [7:0] m_axi_arlen;
    logic [2:0] m_axi_arsize;
    logic [1:0] m_axi_arburst;
    logic m_axi_arlock;
    logic [3:0] m_axi_arcache;
    logic [2:0] m_axi_arprot;
    logic [3:0] m_axi_arqos;
    logic m_axi_arvalid;
    logic m_axi_arready;
    logic [0:0] m_axi_rid;
    logic [AXI_DATA_WIDTH-1:0] m_axi_rdata;
    logic [1:0] m_axi_rresp;
    logic m_axi_rlast;
    logic m_axi_rvalid;
    logic m_axi_rready;

    int errors;
    int write_errors;
    int write_count;
    logic [ADDR_WIDTH-1:0] expected_addr [0:3];
    logic [AXI_DATA_WIDTH-1:0] expected_data [0:3];

    sdp #(
        .MACCELL_NUM(MACCELL_NUM),
        .PSUM_WIDTH(PSUM_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .OUTPUT_ADDR_SHIFT(2)
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

    sdp_write_master_v1_0 #(
        .C_M00_AXI_TARGET_SLAVE_BASE_ADDR(32'h0000_0000),
        .C_M00_AXI_ID_WIDTH(1),
        .C_M00_AXI_ADDR_WIDTH(ADDR_WIDTH),
        .C_M00_AXI_DATA_WIDTH(AXI_DATA_WIDTH)
    ) u_write_master (
        .sdp_write_addr(write_req_addr),
        .sdp_write_data(write_req_data),
        .sdp_write_strb(write_req_strb),
        .sdp_write_valid(write_req_valid),
        .sdp_write_ready(write_req_ready),
        .sdp_write_last(write_req_last),
        .sdp_write_busy(),
        .sdp_write_done(write_done),
        .sdp_write_error(write_error),
        .m00_axi_aclk(clk),
        .m00_axi_aresetn(rst_n),
        .m00_axi_awid(m_axi_awid),
        .m00_axi_awaddr(m_axi_awaddr),
        .m00_axi_awlen(m_axi_awlen),
        .m00_axi_awsize(m_axi_awsize),
        .m00_axi_awburst(m_axi_awburst),
        .m00_axi_awlock(m_axi_awlock),
        .m00_axi_awcache(m_axi_awcache),
        .m00_axi_awprot(m_axi_awprot),
        .m00_axi_awqos(m_axi_awqos),
        .m00_axi_awuser(),
        .m00_axi_awvalid(m_axi_awvalid),
        .m00_axi_awready(m_axi_awready),
        .m00_axi_wdata(m_axi_wdata),
        .m00_axi_wstrb(m_axi_wstrb),
        .m00_axi_wlast(m_axi_wlast),
        .m00_axi_wuser(),
        .m00_axi_wvalid(m_axi_wvalid),
        .m00_axi_wready(m_axi_wready),
        .m00_axi_bid(m_axi_bid),
        .m00_axi_bresp(m_axi_bresp),
        .m00_axi_buser('0),
        .m00_axi_bvalid(m_axi_bvalid),
        .m00_axi_bready(m_axi_bready),
        .m00_axi_arid(m_axi_arid),
        .m00_axi_araddr(m_axi_araddr),
        .m00_axi_arlen(m_axi_arlen),
        .m00_axi_arsize(m_axi_arsize),
        .m00_axi_arburst(m_axi_arburst),
        .m00_axi_arlock(m_axi_arlock),
        .m00_axi_arcache(m_axi_arcache),
        .m00_axi_arprot(m_axi_arprot),
        .m00_axi_arqos(m_axi_arqos),
        .m00_axi_aruser(),
        .m00_axi_arvalid(m_axi_arvalid),
        .m00_axi_arready(m_axi_arready),
        .m00_axi_rid(m_axi_rid),
        .m00_axi_rdata(m_axi_rdata),
        .m00_axi_rresp(m_axi_rresp),
        .m00_axi_rlast(m_axi_rlast),
        .m00_axi_ruser('0),
        .m00_axi_rvalid(m_axi_rvalid),
        .m00_axi_rready(m_axi_rready)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    task automatic send_cacc_vector(
        input logic [MACCELL_NUM-1:0] mask,
        input logic [(MACCELL_NUM*PSUM_WIDTH)-1:0] data,
        input logic last
    );
        begin
            @(negedge clk);
            cacc_mask = mask;
            cacc_data = data;
            cacc_last = last;
            cacc_valid = 1'b1;

            while (!cacc_ready) begin
                @(negedge clk);
            end

            @(negedge clk);
            cacc_valid = 1'b0;
            cacc_mask = '0;
            cacc_data = '0;
            cacc_last = 1'b0;
        end
    endtask

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            m_axi_awready <= 1'b0;
            m_axi_wready <= 1'b0;
            m_axi_bvalid <= 1'b0;
            m_axi_bresp <= 2'b00;
            write_count <= 0;
            write_errors <= 0;
        end else begin
            m_axi_awready <= 1'b1;
            m_axi_wready <= 1'b1;
            m_axi_bvalid <= 1'b0;
            m_axi_bresp <= 2'b00;

            if (m_axi_awvalid && m_axi_awready &&
                m_axi_wvalid && m_axi_wready) begin
                $display("AXI write[%0d] addr=0x%08h data=0x%08h strb=0x%0h last=%0b",
                         write_count,
                         m_axi_awaddr,
                         m_axi_wdata,
                         m_axi_wstrb,
                         m_axi_wlast);

                if (m_axi_awaddr !== expected_addr[write_count]) begin
                    $display("ERROR write addr mismatch idx=%0d got=0x%08h expected=0x%08h",
                             write_count, m_axi_awaddr, expected_addr[write_count]);
                    write_errors <= write_errors + 1;
                end

                if (m_axi_wdata !== expected_data[write_count]) begin
                    $display("ERROR write data mismatch idx=%0d got=0x%08h expected=0x%08h",
                             write_count, m_axi_wdata, expected_data[write_count]);
                    write_errors <= write_errors + 1;
                end

                if (m_axi_wstrb !== 4'hf || !m_axi_wlast) begin
                    $display("ERROR write control mismatch strb=0x%0h last=%0b",
                             m_axi_wstrb, m_axi_wlast);
                    write_errors <= write_errors + 1;
                end

                write_count <= write_count + 1;
                m_axi_bvalid <= 1'b1;
            end
        end
    end

    initial begin
        errors = 0;
        rst_n = 1'b0;
        op_enable = 1'b0;
        op_start = 1'b0;
        output_base_addr = 32'h0000_0100;
        cacc_valid = 1'b0;
        cacc_mask = '0;
        cacc_data = '0;
        cacc_last = 1'b0;
        m_axi_bid = '0;
        m_axi_arready = 1'b0;
        m_axi_rid = '0;
        m_axi_rdata = '0;
        m_axi_rresp = 2'b00;
        m_axi_rlast = 1'b0;
        m_axi_rvalid = 1'b0;

        expected_addr[0] = 32'h0000_0400;
        expected_addr[1] = 32'h0000_0404;
        expected_addr[2] = 32'h0000_0408;
        expected_addr[3] = 32'h0000_040c;
        expected_data[0] = 32'h1111_0000;
        expected_data[1] = 32'h1111_0002;
        expected_data[2] = 32'h2222_0001;
        expected_data[3] = 32'h2222_0007;

        repeat (8) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;

        repeat (2) @(posedge clk);
        @(negedge clk);
        op_enable = 1'b1;
        op_start = 1'b1;
        @(negedge clk);
        op_start = 1'b0;

        wait (op_ready);

        send_cacc_vector(
            8'b0000_0101,
            {
                32'h1111_0007, 32'h1111_0006, 32'h1111_0005, 32'h1111_0004,
                32'h1111_0003, 32'h1111_0002, 32'h1111_0001, 32'h1111_0000
            },
            1'b0
        );

        send_cacc_vector(
            8'b1000_0010,
            {
                32'h2222_0007, 32'h2222_0006, 32'h2222_0005, 32'h2222_0004,
                32'h2222_0003, 32'h2222_0002, 32'h2222_0001, 32'h2222_0000
            },
            1'b1
        );

        repeat (40) @(posedge clk);

        if (!op_done) begin
            $display("ERROR SDP op_done was not observed");
            errors = errors + 1;
        end

        if (op_error || write_error) begin
            $display("ERROR unexpected SDP/write error op_error=%0b write_error=%0b",
                     op_error, write_error);
            errors = errors + 1;
        end

        if (write_count != 4) begin
            $display("ERROR write count mismatch got=%0d expected=4", write_count);
            errors = errors + 1;
        end

        errors = errors + write_errors;

        if (errors == 0) begin
            $display("SDP_WRITEBACK_TB_PASS");
        end else begin
            $display("SDP_WRITEBACK_TB_FAIL errors=%0d", errors);
        end

        $finish;
    end

    initial begin
        #20000;
        $fatal(1, "SDP writeback TB timeout");
    end
endmodule
