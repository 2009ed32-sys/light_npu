`timescale 1ns/1ps

module cdma_tb;

    localparam int DATA_WIDTH      = 32;
    localparam int CSB_ADDR_WIDTH  = 7;
    localparam int CBUF_ADDR_WIDTH = 16;
    localparam int AXI_BURST_LEN   = 8;
    localparam int EXPECTED_WORDS  = 10;
    localparam int EXPECTED_DATA_WRITE_EVENTS = 12;

    logic                        clk;
    logic                        rst_n;
    logic [CSB_ADDR_WIDTH-1:0]   awaddr;
    logic [2:0]                  awprot;
    logic                        awvalid;
    logic                        awready;
    logic [DATA_WIDTH-1:0]       wdata;
    logic [3:0]                  wstrb;
    logic                        wvalid;
    logic                        wready;
    logic [1:0]                  bresp;
    logic                        bvalid;
    logic                        bready;
    logic [CSB_ADDR_WIDTH-1:0]   araddr;
    logic [2:0]                  arprot;
    logic                        arvalid;
    logic                        arready;
    logic [DATA_WIDTH-1:0]       rdata;
    logic [1:0]                  rresp;
    logic                        rvalid;
    logic                        rready;

    logic                        data_cbuf_wr_en;
    logic [CBUF_ADDR_WIDTH-1:0]  data_cbuf_wr_addr;
    logic [DATA_WIDTH-1:0]       data_cbuf_wr_data;

    logic                        weight_cbuf_wr_en;
    logic [CBUF_ADDR_WIDTH-1:0]  weight_cbuf_wr_addr;
    logic [DATA_WIDTH-1:0]       weight_cbuf_wr_data;

    logic                        axi_load_start;
    logic [DATA_WIDTH-1:0]       axi_txn_addr;
    logic                        axi_init_txn;
    logic                        axi_stream_valid;
    logic                        axi_stream_ready;
    logic [DATA_WIDTH-1:0]       axi_stream_data;
    logic                        axi_txn_done;
    logic                        axi_error;
    logic                        axi_stream_sel;
    logic [DATA_WIDTH-1:0]       csc_control;
    logic [DATA_WIDTH-1:0]       csc_status;
    logic [DATA_WIDTH-1:0]       csc_atomics;
    logic [DATA_WIDTH-1:0]       csc_data_base;
    logic [DATA_WIDTH-1:0]       csc_weight_base;
    logic [DATA_WIDTH-1:0]       csc_input_width_height;
    logic [DATA_WIDTH-1:0]       csc_input_channels;
    logic [DATA_WIDTH-1:0]       csc_kernel_width_height;
    logic [DATA_WIDTH-1:0]       csc_stride_xy;
    logic [DATA_WIDTH-1:0]       csc_output_width_height;
    logic [DATA_WIDTH-1:0]       csc_output_channels;

    logic                        stream_active_q;
    logic                        active_stream_sel_q;
    logic                        active_stream_error_q;
    logic [DATA_WIDTH-1:0]       active_stream_addr_q;
    logic [$clog2(AXI_BURST_LEN)-1:0] stream_beat_q;

    int data_write_count;
    int weight_write_count;
    int txn_issue_count;
    int load_start_count;

    cdma #(
        .AXI_BURST_LEN(AXI_BURST_LEN)
    ) u_dut (
        .s00_axi_aclk       (clk),
        .s00_axi_aresetn    (rst_n),
        .s00_axi_awaddr     (awaddr),
        .s00_axi_awprot     (awprot),
        .s00_axi_awvalid    (awvalid),
        .s00_axi_awready    (awready),
        .s00_axi_wdata      (wdata),
        .s00_axi_wstrb      (wstrb),
        .s00_axi_wvalid     (wvalid),
        .s00_axi_wready     (wready),
        .s00_axi_bresp      (bresp),
        .s00_axi_bvalid     (bvalid),
        .s00_axi_bready     (bready),
        .s00_axi_araddr     (araddr),
        .s00_axi_arprot     (arprot),
        .s00_axi_arvalid    (arvalid),
        .s00_axi_arready    (arready),
        .s00_axi_rdata      (rdata),
        .s00_axi_rresp      (rresp),
        .s00_axi_rvalid     (rvalid),
        .s00_axi_rready     (rready),
        .data_cbuf_wr_en    (data_cbuf_wr_en),
        .data_cbuf_wr_addr  (data_cbuf_wr_addr),
        .data_cbuf_wr_data  (data_cbuf_wr_data),
        .weight_cbuf_wr_en  (weight_cbuf_wr_en),
        .weight_cbuf_wr_addr(weight_cbuf_wr_addr),
        .weight_cbuf_wr_data(weight_cbuf_wr_data),
        .axi_load_start     (axi_load_start),
        .axi_txn_addr       (axi_txn_addr),
        .axi_init_txn       (axi_init_txn),
        .axi_stream_valid   (axi_stream_valid),
        .axi_stream_ready   (axi_stream_ready),
        .axi_stream_data    (axi_stream_data),
        .axi_txn_done       (axi_txn_done),
        .axi_error          (axi_error),
        .axi_stream_sel     (axi_stream_sel),
        .csc_control        (csc_control),
        .csc_status         (csc_status),
        .csc_atomics        (csc_atomics),
        .csc_data_base      (csc_data_base),
        .csc_weight_base    (csc_weight_base),
        .csc_input_width_height(csc_input_width_height),
        .csc_input_channels (csc_input_channels),
        .csc_kernel_width_height(csc_kernel_width_height),
        .csc_stride_xy      (csc_stride_xy),
        .csc_output_width_height(csc_output_width_height),
        .csc_output_channels(csc_output_channels)
    );

    always #5 clk = ~clk;

    task automatic axi_write(
        input logic [CSB_ADDR_WIDTH-1:0] address,
        input logic [DATA_WIDTH-1:0] data
    );
        begin
            @(negedge clk);
            awaddr  = address;
            wdata   = data;
            awvalid = 1'b1;
            wvalid  = 1'b1;

            wait (awready && wready);
            @(posedge clk);
            @(negedge clk);
            awvalid = 1'b0;
            wvalid  = 1'b0;

            wait (bvalid);
            if (bresp != 2'b00) begin
                $fatal(1, "AXI write response error");
            end
            @(negedge clk);
            bready = 1'b1;
            @(negedge clk);
            bready = 1'b0;
        end
    endtask

    task automatic axi_read(
        input logic [CSB_ADDR_WIDTH-1:0] address,
        input logic [DATA_WIDTH-1:0] expected_data
    );
        begin
            @(negedge clk);
            araddr  = address;
            arvalid = 1'b1;

            wait (arready);
            @(posedge clk);
            @(negedge clk);
            arvalid = 1'b0;

            wait (rvalid);
            if ((rresp != 2'b00) || (rdata != expected_data)) begin
                $fatal(1, "AXI read mismatch at address 0x%0h: expected 0x%08h, got 0x%08h",
                       address, expected_data, rdata);
            end
            @(negedge clk);
            rready = 1'b1;
            @(negedge clk);
            rready = 1'b0;
        end
    endtask

    function automatic logic [DATA_WIDTH-1:0] make_stream_word(
        input logic stream_sel,
        input logic [DATA_WIDTH-1:0] byte_addr,
        input logic [$clog2(AXI_BURST_LEN)-1:0] beat
    );
        logic [DATA_WIDTH-1:0] word_index;
        begin
            word_index = (byte_addr >> 2) + DATA_WIDTH'(beat);
            make_stream_word =
                (stream_sel ? 32'hA000_0000 : 32'hD000_0000) |
                word_index;
        end
    endfunction

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            axi_txn_done          <= 1'b0;
            axi_error             <= 1'b0;
            axi_stream_valid      <= 1'b0;
            axi_stream_data       <= '0;
            stream_active_q       <= 1'b0;
            active_stream_sel_q   <= 1'b0;
            active_stream_error_q <= 1'b0;
            active_stream_addr_q  <= '0;
            stream_beat_q         <= '0;
            txn_issue_count       <= 0;
            load_start_count      <= 0;
        end else begin
            axi_txn_done     <= 1'b0;
            axi_error        <= 1'b0;
            axi_stream_valid <= 1'b0;
            axi_stream_data  <= '0;

            if (axi_load_start) begin
                if ((load_start_count == 0 && axi_stream_sel != 1'b0) ||
                    (load_start_count == 1 && axi_stream_sel != 1'b1)) begin
                    $fatal(1, "Unexpected AXI stream selection at load start");
                end
                load_start_count <= load_start_count + 1;
            end

            if (stream_active_q) begin
                axi_stream_valid <= 1'b1;
                axi_stream_data  <= make_stream_word(
                    active_stream_sel_q,
                    active_stream_addr_q,
                    stream_beat_q
                );

                if (stream_beat_q == AXI_BURST_LEN - 1) begin
                    stream_active_q <= 1'b0;
                    stream_beat_q   <= '0;

                    if (active_stream_error_q) begin
                        axi_error <= 1'b1;
                    end else begin
                        axi_txn_done <= 1'b1;
                    end
                end else begin
                    stream_beat_q <= stream_beat_q + 1'b1;
                end
            end

            if (axi_init_txn) begin
                if (stream_active_q) begin
                    $fatal(1, "New AXI transaction issued while stream is active");
                end

                case (txn_issue_count)
                    0: begin
                        if (axi_stream_sel != 1'b0 || axi_txn_addr != 32'd0) begin
                            $fatal(1, "Unexpected first data transaction");
                        end
                    end
                    1: begin
                        if (axi_stream_sel != 1'b0 || axi_txn_addr != 32'd32) begin
                            $fatal(1, "Unexpected failed data transaction");
                        end
                    end
                    2: begin
                        if (axi_stream_sel != 1'b0 || axi_txn_addr != 32'd32) begin
                            $fatal(1, "Data retry did not keep the previous address");
                        end
                    end
                    3: begin
                        if (axi_stream_sel != 1'b1 || axi_txn_addr != 32'd0) begin
                            $fatal(1, "Unexpected first weight transaction");
                        end
                    end
                    4: begin
                        if (axi_stream_sel != 1'b1 || axi_txn_addr != 32'd32) begin
                            $fatal(1, "Unexpected second weight transaction");
                        end
                    end
                    default: begin
                        $fatal(1, "Unexpected extra AXI transaction");
                    end
                endcase

                stream_active_q       <= 1'b1;
                active_stream_sel_q   <= axi_stream_sel;
                active_stream_error_q <= (txn_issue_count == 1);
                active_stream_addr_q  <= axi_txn_addr;
                stream_beat_q         <= '0;
                txn_issue_count       <= txn_issue_count + 1;
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            data_write_count   <= 0;
            weight_write_count <= 0;
        end else begin
            if (data_cbuf_wr_en) begin
                if ((data_cbuf_wr_addr < CBUF_ADDR_WIDTH'(16)) ||
                    (data_cbuf_wr_addr > CBUF_ADDR_WIDTH'(25)) ||
                    (data_cbuf_wr_data !=
                        (32'hD000_0000 |
                         DATA_WIDTH'(data_cbuf_wr_addr - CBUF_ADDR_WIDTH'(16))))) begin
                    $fatal(1, "Unexpected data CBUF write");
                end
                data_write_count <= data_write_count + 1;
            end

            if (weight_cbuf_wr_en) begin
                if ((weight_cbuf_wr_addr < CBUF_ADDR_WIDTH'(32)) ||
                    (weight_cbuf_wr_addr > CBUF_ADDR_WIDTH'(41)) ||
                    (weight_cbuf_wr_data !=
                        (32'hA000_0000 |
                         DATA_WIDTH'(weight_cbuf_wr_addr - CBUF_ADDR_WIDTH'(32))))) begin
                    $fatal(1, "Unexpected weight CBUF write");
                end
                weight_write_count <= weight_write_count + 1;
            end
        end
    end

    initial begin
        clk                  = 1'b0;
        rst_n                = 1'b0;
        awaddr               = '0;
        awprot               = 3'b000;
        awvalid              = 1'b0;
        wdata                = '0;
        wstrb                = 4'b1111;
        wvalid               = 1'b0;
        bready               = 1'b0;
        araddr               = '0;
        arprot               = 3'b000;
        arvalid              = 1'b0;
        rready               = 1'b0;
        csc_status           = '0;

        repeat (3) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;

        axi_write(7'h08, 32'd10);
        axi_write(7'h0C, 32'd1);
        axi_write(7'h10, 32'd4);
        axi_write(7'h14, 32'd16);
        axi_write(7'h18, 32'd10);
        axi_write(7'h1C, 32'd1);
        axi_write(7'h20, 32'd4);
        axi_write(7'h24, 32'd32);
        axi_write(7'h00, 32'h0000_0003);

        axi_read(7'h04, 32'h0000_0009);
        wait ((data_write_count == EXPECTED_DATA_WRITE_EVENTS) &&
              (weight_write_count == EXPECTED_WORDS) &&
              (txn_issue_count == 5) &&
              (load_start_count == 2));

        axi_write(7'h00, 32'h0000_0000);

        $display("CDMA_CSB_STREAM_INTEGRATION_TEST_PASS");
        $finish;
    end

    initial begin
        #5000;
        $fatal(1, "CDMA CSB integration test timeout");
    end

endmodule
