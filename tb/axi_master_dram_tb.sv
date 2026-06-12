`timescale 1ns/1ps

module axi_master_dram_tb;

    localparam int ADDR_WIDTH      = 32;
    localparam int DATA_WIDTH      = 32;
    localparam int AXI_BURST_LEN   = 8;
    localparam logic [ADDR_WIDTH-1:0] AXI_BASE_ADDR = 32'h0000_1000;

    logic clk;
    logic rst_n;

    logic [ADDR_WIDTH-1:0] axi_txn_addr;
    logic axi_stream_valid;
    logic axi_stream_ready;
    logic [DATA_WIDTH-1:0] axi_stream_data;

    logic m00_axi_init_axi_txn;
    logic m00_axi_txn_done;
    logic m00_axi_error;

    logic [0:0] m00_axi_awid;
    logic [ADDR_WIDTH-1:0] m00_axi_awaddr;
    logic [7:0] m00_axi_awlen;
    logic [2:0] m00_axi_awsize;
    logic [1:0] m00_axi_awburst;
    logic m00_axi_awlock;
    logic [3:0] m00_axi_awcache;
    logic [2:0] m00_axi_awprot;
    logic [3:0] m00_axi_awqos;
    logic [0:0] m00_axi_awuser;
    logic m00_axi_awvalid;
    logic m00_axi_awready;

    logic [DATA_WIDTH-1:0] m00_axi_wdata;
    logic [(DATA_WIDTH/8)-1:0] m00_axi_wstrb;
    logic m00_axi_wlast;
    logic [0:0] m00_axi_wuser;
    logic m00_axi_wvalid;
    logic m00_axi_wready;

    logic [0:0] m00_axi_bid;
    logic [1:0] m00_axi_bresp;
    logic [0:0] m00_axi_buser;
    logic m00_axi_bvalid;
    logic m00_axi_bready;

    logic [0:0] m00_axi_arid;
    logic [ADDR_WIDTH-1:0] m00_axi_araddr;
    logic [7:0] m00_axi_arlen;
    logic [2:0] m00_axi_arsize;
    logic [1:0] m00_axi_arburst;
    logic m00_axi_arlock;
    logic [3:0] m00_axi_arcache;
    logic [2:0] m00_axi_arprot;
    logic [3:0] m00_axi_arqos;
    logic [0:0] m00_axi_aruser;
    logic m00_axi_arvalid;
    logic m00_axi_arready;

    logic [0:0] m00_axi_rid;
    logic [DATA_WIDTH-1:0] m00_axi_rdata;
    logic [1:0] m00_axi_rresp;
    logic m00_axi_rlast;
    logic [0:0] m00_axi_ruser;
    logic m00_axi_rvalid;
    logic m00_axi_rready;

    logic read_active_q;
    logic active_error_q;
    logic inject_error;
    logic [$clog2(AXI_BURST_LEN)-1:0] beat_count_q;
    logic [7:0] active_sequence_q;
    int ready_stall_count_q;
    int ar_count_q;
    int stream_count_q;
    int stream_valid_only_count_q;

    axi_master_dram_v1_0 #(
        .C_M00_AXI_TARGET_SLAVE_BASE_ADDR(AXI_BASE_ADDR),
        .C_M00_AXI_BURST_LEN(AXI_BURST_LEN),
        .C_M00_AXI_ADDR_WIDTH(ADDR_WIDTH),
        .C_M00_AXI_DATA_WIDTH(DATA_WIDTH),
        .C_M00_AXI_AWUSER_WIDTH(1),
        .C_M00_AXI_ARUSER_WIDTH(1),
        .C_M00_AXI_WUSER_WIDTH(1),
        .C_M00_AXI_RUSER_WIDTH(1),
        .C_M00_AXI_BUSER_WIDTH(1)
    ) u_dut (
        .axi_txn_addr          (axi_txn_addr),
        .axi_stream_valid      (axi_stream_valid),
        .axi_stream_ready      (axi_stream_ready),
        .axi_stream_data       (axi_stream_data),
        .m00_axi_init_axi_txn  (m00_axi_init_axi_txn),
        .m00_axi_txn_done      (m00_axi_txn_done),
        .m00_axi_error         (m00_axi_error),
        .m00_axi_aclk          (clk),
        .m00_axi_aresetn       (rst_n),
        .m00_axi_awid          (m00_axi_awid),
        .m00_axi_awaddr        (m00_axi_awaddr),
        .m00_axi_awlen         (m00_axi_awlen),
        .m00_axi_awsize        (m00_axi_awsize),
        .m00_axi_awburst       (m00_axi_awburst),
        .m00_axi_awlock        (m00_axi_awlock),
        .m00_axi_awcache       (m00_axi_awcache),
        .m00_axi_awprot        (m00_axi_awprot),
        .m00_axi_awqos         (m00_axi_awqos),
        .m00_axi_awuser        (m00_axi_awuser),
        .m00_axi_awvalid       (m00_axi_awvalid),
        .m00_axi_awready       (m00_axi_awready),
        .m00_axi_wdata         (m00_axi_wdata),
        .m00_axi_wstrb         (m00_axi_wstrb),
        .m00_axi_wlast         (m00_axi_wlast),
        .m00_axi_wuser         (m00_axi_wuser),
        .m00_axi_wvalid        (m00_axi_wvalid),
        .m00_axi_wready        (m00_axi_wready),
        .m00_axi_bid           (m00_axi_bid),
        .m00_axi_bresp         (m00_axi_bresp),
        .m00_axi_buser         (m00_axi_buser),
        .m00_axi_bvalid        (m00_axi_bvalid),
        .m00_axi_bready        (m00_axi_bready),
        .m00_axi_arid          (m00_axi_arid),
        .m00_axi_araddr        (m00_axi_araddr),
        .m00_axi_arlen         (m00_axi_arlen),
        .m00_axi_arsize        (m00_axi_arsize),
        .m00_axi_arburst       (m00_axi_arburst),
        .m00_axi_arlock        (m00_axi_arlock),
        .m00_axi_arcache       (m00_axi_arcache),
        .m00_axi_arprot        (m00_axi_arprot),
        .m00_axi_arqos         (m00_axi_arqos),
        .m00_axi_aruser        (m00_axi_aruser),
        .m00_axi_arvalid       (m00_axi_arvalid),
        .m00_axi_arready       (m00_axi_arready),
        .m00_axi_rid           (m00_axi_rid),
        .m00_axi_rdata         (m00_axi_rdata),
        .m00_axi_rresp         (m00_axi_rresp),
        .m00_axi_rlast         (m00_axi_rlast),
        .m00_axi_ruser         (m00_axi_ruser),
        .m00_axi_rvalid        (m00_axi_rvalid),
        .m00_axi_rready        (m00_axi_rready)
    );

    assign m00_axi_arready = !read_active_q;
    assign m00_axi_rvalid  = read_active_q;
    assign m00_axi_rdata   =
        32'hA000_0000 |
        (DATA_WIDTH'(active_sequence_q) << 8) |
        DATA_WIDTH'(beat_count_q);
    assign m00_axi_rresp =
        (active_error_q && (beat_count_q == 1)) ? 2'b10 : 2'b00;
    assign m00_axi_rlast =
        read_active_q && (beat_count_q == AXI_BURST_LEN - 1);
    assign m00_axi_rid    = 1'b0;
    assign m00_axi_ruser  = 1'b0;

    always #5 clk = ~clk;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            read_active_q     <= 1'b0;
            active_error_q    <= 1'b0;
            beat_count_q      <= '0;
            active_sequence_q <= 8'd0;
            axi_stream_ready  <= 1'b1;
            ready_stall_count_q <= 0;
            ar_count_q        <= 0;
            stream_count_q    <= 0;
            stream_valid_only_count_q <= 0;
        end else begin
            if (read_active_q &&
                (beat_count_q == 2) &&
                (ready_stall_count_q < 2)) begin
                axi_stream_ready    <= 1'b0;
                ready_stall_count_q <= ready_stall_count_q + 1;
            end else begin
                axi_stream_ready <= 1'b1;
            end

            if (m00_axi_arvalid && m00_axi_arready) begin
                case (ar_count_q)
                    0: if (m00_axi_araddr != AXI_BASE_ADDR + 32'h20)
                        $fatal(1, "Unexpected first AXI read address");
                    1: if (m00_axi_araddr != AXI_BASE_ADDR + 32'h40)
                        $fatal(1, "Unexpected failed AXI read address");
                    2: if (m00_axi_araddr != AXI_BASE_ADDR + 32'h40)
                        $fatal(1, "AXI retry address changed");
                    3: if (m00_axi_araddr != AXI_BASE_ADDR + 32'h60)
                        $fatal(1, "Unexpected post-retry AXI read address");
                    default: $fatal(1, "Unexpected extra AXI read request");
                endcase

                if (m00_axi_arlen != AXI_BURST_LEN - 1) begin
                    $fatal(1, "AXI burst length changed");
                end

                read_active_q     <= 1'b1;
                active_error_q    <= inject_error;
                beat_count_q      <= '0;
                active_sequence_q <= ar_count_q[7:0];
                ar_count_q        <= ar_count_q + 1;
            end else if (m00_axi_rvalid && m00_axi_rready) begin
                if (m00_axi_rlast) begin
                    read_active_q <= 1'b0;
                end else begin
                    beat_count_q <= beat_count_q + 1'b1;
                end
            end

            if (axi_stream_valid) begin
                if (axi_stream_data != m00_axi_rdata) begin
                    $fatal(1, "AXI stream data does not match RDATA");
                end
            end

            if (axi_stream_valid && !axi_stream_ready) begin
                stream_valid_only_count_q <= stream_valid_only_count_q + 1;
            end

            if (!axi_stream_ready && m00_axi_rready) begin
                $fatal(1, "M_AXI_RREADY stayed high while stream_ready was low");
            end

            if (axi_stream_valid && axi_stream_ready) begin
                stream_count_q <= stream_count_q + 1;
            end

            if (m00_axi_awvalid || m00_axi_wvalid) begin
                $fatal(1, "Read-only AXI master drove a write transaction");
            end
        end
    end

    task automatic start_transaction(
        input logic [ADDR_WIDTH-1:0] address,
        input logic expect_error
    );
        begin
            @(negedge clk);
            axi_txn_addr         = address;
            inject_error         = expect_error;
            m00_axi_init_axi_txn = 1'b1;
            @(negedge clk);
            m00_axi_init_axi_txn = 1'b0;

            if (expect_error) begin
                wait (m00_axi_error);
            end else begin
                wait (m00_axi_txn_done);
            end

            @(negedge clk);
            inject_error = 1'b0;
        end
    endtask

    initial begin
        clk                  = 1'b0;
        rst_n                = 1'b0;
        axi_txn_addr         = '0;
        m00_axi_init_axi_txn = 1'b0;
        inject_error         = 1'b0;
        m00_axi_awready      = 1'b0;
        m00_axi_wready       = 1'b0;
        m00_axi_bid          = 1'b0;
        m00_axi_bresp        = 2'b00;
        m00_axi_buser        = 1'b0;
        m00_axi_bvalid       = 1'b0;

        repeat (3) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;

        start_transaction(32'h20, 1'b0);
        start_transaction(32'h40, 1'b1);
        start_transaction(32'h40, 1'b0);
        start_transaction(32'h60, 1'b0);

        if (ar_count_q != 4) begin
            $fatal(1, "Unexpected AXI read transaction count");
        end

        if (stream_count_q != 4 * AXI_BURST_LEN) begin
            $fatal(1, "Unexpected AXI stream beat count");
        end

        if (stream_valid_only_count_q == 0) begin
            $fatal(1, "AXI stream ready backpressure was not exercised");
        end

        $display("AXI_MASTER_DRAM_STREAM_BURST_TEST_PASS");
        $finish;
    end

    initial begin
        #5000;
        $fatal(1, "AXI master DRAM test timeout");
    end

endmodule
