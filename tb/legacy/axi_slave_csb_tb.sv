`timescale 1ns/1ps

module axi_slave_csb_tb;

    localparam int DATA_WIDTH = 32;
    localparam int ADDR_WIDTH = 7;

    logic                  clk;
    logic                  rst_n;
    logic [ADDR_WIDTH-1:0] awaddr;
    logic [2:0]            awprot;
    logic                  awvalid;
    logic                  awready;
    logic [DATA_WIDTH-1:0] wdata;
    logic [3:0]            wstrb;
    logic                  wvalid;
    logic                  wready;
    logic [1:0]            bresp;
    logic                  bvalid;
    logic                  bready;
    logic [ADDR_WIDTH-1:0] araddr;
    logic [2:0]            arprot;
    logic                  arvalid;
    logic                  arready;
    logic [DATA_WIDTH-1:0] rdata;
    logic [1:0]            rresp;
    logic                  rvalid;
    logic                  rready;
    logic [DATA_WIDTH-1:0] cdma_control;
    logic [DATA_WIDTH-1:0] cdma_status;
    logic [DATA_WIDTH-1:0] data_matrix_width;
    logic [DATA_WIDTH-1:0] data_matrix_height;
    logic [DATA_WIDTH-1:0] data_channel_count;
    logic [DATA_WIDTH-1:0] data_dst_base;
    logic [DATA_WIDTH-1:0] weight_matrix_width;
    logic [DATA_WIDTH-1:0] weight_matrix_height;
    logic [DATA_WIDTH-1:0] weight_channel_count;
    logic [DATA_WIDTH-1:0] weight_dst_base;
    logic [DATA_WIDTH-1:0] csc_control;
    logic [DATA_WIDTH-1:0] csc_status;
    logic [DATA_WIDTH-1:0] csc_atomics;
    logic [DATA_WIDTH-1:0] csc_data_base;
    logic [DATA_WIDTH-1:0] csc_weight_base;
    logic [DATA_WIDTH-1:0] csc_input_width_height;
    logic [DATA_WIDTH-1:0] csc_input_channels;
    logic [DATA_WIDTH-1:0] csc_kernel_width_height;
    logic [DATA_WIDTH-1:0] csc_stride_xy;
    logic [DATA_WIDTH-1:0] csc_output_width_height;
    logic [DATA_WIDTH-1:0] csc_output_channels;

    axi_slave_csb_v1_0 #(
        .C_S00_AXI_DATA_WIDTH(DATA_WIDTH),
        .C_S00_AXI_ADDR_WIDTH(ADDR_WIDTH)
    ) u_dut (
        .CDMA_CONTROL         (cdma_control),
        .CDMA_STATUS          (cdma_status),
        .DATA_MATRIX_WIDTH    (data_matrix_width),
        .DATA_MATRIX_HEIGHT   (data_matrix_height),
        .DATA_CHANNEL_COUNT   (data_channel_count),
        .DATA_DST_BASE        (data_dst_base),
        .WEIGHT_MATRIX_WIDTH  (weight_matrix_width),
        .WEIGHT_MATRIX_HEIGHT (weight_matrix_height),
        .WEIGHT_CHANNEL_COUNT (weight_channel_count),
        .WEIGHT_DST_BASE      (weight_dst_base),
        .CSC_CONTROL          (csc_control),
        .CSC_STATUS           (csc_status),
        .CSC_ATOMICS          (csc_atomics),
        .CSC_DATA_BASE        (csc_data_base),
        .CSC_WEIGHT_BASE      (csc_weight_base),
        .CSC_INPUT_WIDTH_HEIGHT(csc_input_width_height),
        .CSC_INPUT_CHANNELS   (csc_input_channels),
        .CSC_KERNEL_WIDTH_HEIGHT(csc_kernel_width_height),
        .CSC_STRIDE_XY        (csc_stride_xy),
        .CSC_OUTPUT_WIDTH_HEIGHT(csc_output_width_height),
        .CSC_OUTPUT_CHANNELS  (csc_output_channels),
        .s00_axi_aclk   (clk),
        .s00_axi_aresetn(rst_n),
        .s00_axi_awaddr (awaddr),
        .s00_axi_awprot (awprot),
        .s00_axi_awvalid(awvalid),
        .s00_axi_awready(awready),
        .s00_axi_wdata  (wdata),
        .s00_axi_wstrb  (wstrb),
        .s00_axi_wvalid (wvalid),
        .s00_axi_wready (wready),
        .s00_axi_bresp  (bresp),
        .s00_axi_bvalid (bvalid),
        .s00_axi_bready (bready),
        .s00_axi_araddr (araddr),
        .s00_axi_arprot (arprot),
        .s00_axi_arvalid(arvalid),
        .s00_axi_arready(arready),
        .s00_axi_rdata  (rdata),
        .s00_axi_rresp  (rresp),
        .s00_axi_rvalid (rvalid),
        .s00_axi_rready (rready)
    );

    always #5 clk = ~clk;

    task automatic axi_write(
        input logic [ADDR_WIDTH-1:0] address,
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
        input logic [ADDR_WIDTH-1:0] address,
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
            if (rresp != 2'b00) begin
                $fatal(1, "AXI read response error");
            end
            if (rdata != expected_data) begin
                $fatal(1, "Read mismatch at address 0x%0h: expected 0x%08h, got 0x%08h",
                       address, expected_data, rdata);
            end
            @(negedge clk);
            rready = 1'b1;
            @(negedge clk);
            rready = 1'b0;
        end
    endtask

    initial begin
        clk     = 1'b0;
        rst_n   = 1'b0;
        awaddr  = '0;
        awprot  = 3'b000;
        awvalid = 1'b0;
        wdata   = '0;
        wstrb   = 4'b1111;
        wvalid  = 1'b0;
        bready  = 1'b0;
        araddr  = '0;
        arprot  = 3'b000;
        arvalid = 1'b0;
        rready  = 1'b0;
        cdma_status = 32'h0000_002D;
        csc_status  = 32'h0000_005A;

        repeat (3) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;

        for (int index = 0; index < 21; index++) begin
            axi_write(ADDR_WIDTH'(index * 4), DATA_WIDTH'(32'h1000_0000 + index));
        end

        for (int index = 0; index < 21; index++) begin
            if (index == 1) begin
                axi_read(ADDR_WIDTH'(index * 4), cdma_status);
            end else if (index == 11) begin
                axi_read(ADDR_WIDTH'(index * 4), csc_status);
            end else begin
                axi_read(ADDR_WIDTH'(index * 4), DATA_WIDTH'(32'h1000_0000 + index));
            end
        end

        if (cdma_control         != 32'h1000_0000 ||
            data_matrix_width    != 32'h1000_0002 ||
            data_matrix_height   != 32'h1000_0003 ||
            data_channel_count   != 32'h1000_0004 ||
            data_dst_base        != 32'h1000_0005 ||
            weight_matrix_width  != 32'h1000_0006 ||
            weight_matrix_height != 32'h1000_0007 ||
            weight_channel_count != 32'h1000_0008 ||
            weight_dst_base      != 32'h1000_0009 ||
            csc_control          != 32'h1000_000A ||
            csc_atomics          != 32'h1000_000C ||
            csc_data_base        != 32'h1000_000D ||
            csc_weight_base      != 32'h1000_000E ||
            csc_input_width_height  != 32'h1000_000F ||
            csc_input_channels      != 32'h1000_0010 ||
            csc_kernel_width_height != 32'h1000_0011 ||
            csc_stride_xy           != 32'h1000_0012 ||
            csc_output_width_height != 32'h1000_0013 ||
            csc_output_channels     != 32'h1000_0014) begin
            $fatal(1, "External CSB register port mapping mismatch");
        end

        $display("AXI_SLAVE_CSB_21_REG_TEST_PASS");
        $finish;
    end

    initial begin
        #5000;
        $fatal(1, "AXI slave CSB test timeout");
    end

endmodule
