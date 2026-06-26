`timescale 1ns/1ps

module tb_apb3_slave;

    localparam int ADDR_WIDTH = 32;
    localparam int DATA_WIDTH = 32;
    localparam int SLVREG_NUM = 40;

    localparam logic [31:0] REG_CDMA_CONTROL = 32'h00;
    localparam logic [31:0] REG_CDMA_STATUS  = 32'h04;
    localparam logic [31:0] REG_DATA_WIDTH   = 32'h08;
    localparam logic [31:0] REG_DATA_HEIGHT  = 32'h0c;
    localparam logic [31:0] REG_CSC_CONTROL  = 32'h28;
    localparam logic [31:0] REG_CSC_STATUS   = 32'h2c;
    localparam logic [31:0] REG_CSC_ATOMICS  = 32'h30;
    localparam logic [31:0] REG_CACC_STATUS  = 32'h54;
    localparam logic [31:0] REG_CACC_CONTROL = 32'h58;
    localparam logic [31:0] REG_CACC_ADDR    = 32'h64;
    localparam logic [31:0] REG_BLOCK_OUTPUT_XY = 32'h74;
    localparam logic [31:0] REG_BLOCK_OUTPUT_SIZE = 32'h78;
    localparam logic [31:0] REG_BLOCK_INPUT_XY = 32'h7c;
    localparam logic [31:0] REG_BLOCK_INPUT_SIZE = 32'h80;
    localparam logic [31:0] REG_VALID_INPUT_XY = 32'h84;
    localparam logic [31:0] REG_VALID_INPUT_SIZE = 32'h88;
    localparam logic [31:0] REG_BLOCK_CHANNEL_INFO = 32'h8c;
    localparam logic [31:0] REG_BLOCK_OUTPUT_CHANNEL_INFO = 32'h90;
    localparam logic [31:0] REG_BLOCK_OUTPUT_ADDR = 32'h94;
    localparam logic [31:0] REG_PADDING_SIZE_RESERVED = 32'h98;
    localparam logic [31:0] REG_PADDING_VALUE_RESERVED = 32'h9c;
    localparam logic [31:0] REG_INVALID_ADDR = 32'ha0;

    logic PCLK;
    logic PRESETn;
    logic PSEL;
    logic PENABLE;
    logic PWRITE;
    logic [ADDR_WIDTH-1:0] PADDR;
    logic [DATA_WIDTH-1:0] PWDATA;
    logic [DATA_WIDTH-1:0] PRDATA;
    logic PREADY;
    logic PSLVERR;

    logic [DATA_WIDTH-1:0] CDMA_CONTROL;
    logic [DATA_WIDTH-1:0] CDMA_STATUS;
    logic [DATA_WIDTH-1:0] DATA_MATRIX_WIDTH;
    logic [DATA_WIDTH-1:0] DATA_MATRIX_HEIGHT;
    logic [DATA_WIDTH-1:0] DATA_CHANNEL_COUNT;
    logic [DATA_WIDTH-1:0] DATA_DST_BASE;
    logic [DATA_WIDTH-1:0] WEIGHT_MATRIX_WIDTH;
    logic [DATA_WIDTH-1:0] WEIGHT_MATRIX_HEIGHT;
    logic [DATA_WIDTH-1:0] WEIGHT_CHANNEL_COUNT;
    logic [DATA_WIDTH-1:0] WEIGHT_DST_BASE;
    logic [DATA_WIDTH-1:0] CSC_CONTROL;
    logic [DATA_WIDTH-1:0] CSC_STATUS;
    logic [DATA_WIDTH-1:0] CSC_ATOMICS;
    logic [DATA_WIDTH-1:0] CSC_DATA_BASE;
    logic [DATA_WIDTH-1:0] CSC_WEIGHT_BASE;
    logic [DATA_WIDTH-1:0] CSC_INPUT_WIDTH_HEIGHT;
    logic [DATA_WIDTH-1:0] CSC_INPUT_CHANNELS;
    logic [DATA_WIDTH-1:0] CSC_KERNEL_WIDTH_HEIGHT;
    logic [DATA_WIDTH-1:0] CSC_STRIDE_XY;
    logic [DATA_WIDTH-1:0] CSC_OUTPUT_WIDTH_HEIGHT;
    logic [DATA_WIDTH-1:0] CSC_OUTPUT_CHANNELS;
    logic [DATA_WIDTH-1:0] CACC_S_STATUS;
    logic [DATA_WIDTH-1:0] CACC_D_OP_ENABLE;
    logic [DATA_WIDTH-1:0] CACC_D_DATAOUT_SIZE_0;
    logic [DATA_WIDTH-1:0] CACC_D_DATAOUT_SIZE_1;
    logic [DATA_WIDTH-1:0] CACC_D_DATAOUT_ADDR;
    logic [DATA_WIDTH-1:0] CACC_D_LINE_STRIDE;
    logic [DATA_WIDTH-1:0] CACC_D_SURF_STRIDE;
    logic [DATA_WIDTH-1:0] CACC_D_DATAOUT_MAP;
    logic [DATA_WIDTH-1:0] BLOCK_OUTPUT_XY;
    logic [DATA_WIDTH-1:0] BLOCK_OUTPUT_SIZE;
    logic [DATA_WIDTH-1:0] BLOCK_INPUT_XY;
    logic [DATA_WIDTH-1:0] BLOCK_INPUT_SIZE;
    logic [DATA_WIDTH-1:0] VALID_INPUT_XY;
    logic [DATA_WIDTH-1:0] VALID_INPUT_SIZE;
    logic [DATA_WIDTH-1:0] BLOCK_CHANNEL_INFO;
    logic [DATA_WIDTH-1:0] BLOCK_OUTPUT_CHANNEL_INFO;
    logic [DATA_WIDTH-1:0] BLOCK_OUTPUT_ADDR;
    logic [DATA_WIDTH-1:0] PADDING_SIZE_RESERVED;
    logic [DATA_WIDTH-1:0] PADDING_VALUE_RESERVED;

    int errors;

    apb3_slave #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .SLVREG_NUM(SLVREG_NUM)
    ) dut (
        .PCLK(PCLK),
        .PRESETn(PRESETn),
        .PSEL(PSEL),
        .PENABLE(PENABLE),
        .PWRITE(PWRITE),
        .PADDR(PADDR),
        .PWDATA(PWDATA),
        .PRDATA(PRDATA),
        .PREADY(PREADY),
        .PSLVERR(PSLVERR),
        .CDMA_CONTROL(CDMA_CONTROL),
        .CDMA_STATUS(CDMA_STATUS),
        .DATA_MATRIX_WIDTH(DATA_MATRIX_WIDTH),
        .DATA_MATRIX_HEIGHT(DATA_MATRIX_HEIGHT),
        .DATA_CHANNEL_COUNT(DATA_CHANNEL_COUNT),
        .DATA_DST_BASE(DATA_DST_BASE),
        .WEIGHT_MATRIX_WIDTH(WEIGHT_MATRIX_WIDTH),
        .WEIGHT_MATRIX_HEIGHT(WEIGHT_MATRIX_HEIGHT),
        .WEIGHT_CHANNEL_COUNT(WEIGHT_CHANNEL_COUNT),
        .WEIGHT_DST_BASE(WEIGHT_DST_BASE),
        .CSC_CONTROL(CSC_CONTROL),
        .CSC_STATUS(CSC_STATUS),
        .CSC_ATOMICS(CSC_ATOMICS),
        .CSC_DATA_BASE(CSC_DATA_BASE),
        .CSC_WEIGHT_BASE(CSC_WEIGHT_BASE),
        .CSC_INPUT_WIDTH_HEIGHT(CSC_INPUT_WIDTH_HEIGHT),
        .CSC_INPUT_CHANNELS(CSC_INPUT_CHANNELS),
        .CSC_KERNEL_WIDTH_HEIGHT(CSC_KERNEL_WIDTH_HEIGHT),
        .CSC_STRIDE_XY(CSC_STRIDE_XY),
        .CSC_OUTPUT_WIDTH_HEIGHT(CSC_OUTPUT_WIDTH_HEIGHT),
        .CSC_OUTPUT_CHANNELS(CSC_OUTPUT_CHANNELS),
        .CACC_S_STATUS(CACC_S_STATUS),
        .CACC_D_OP_ENABLE(CACC_D_OP_ENABLE),
        .CACC_D_DATAOUT_SIZE_0(CACC_D_DATAOUT_SIZE_0),
        .CACC_D_DATAOUT_SIZE_1(CACC_D_DATAOUT_SIZE_1),
        .CACC_D_DATAOUT_ADDR(CACC_D_DATAOUT_ADDR),
        .CACC_D_LINE_STRIDE(CACC_D_LINE_STRIDE),
        .CACC_D_SURF_STRIDE(CACC_D_SURF_STRIDE),
        .CACC_D_DATAOUT_MAP(CACC_D_DATAOUT_MAP),
        .BLOCK_OUTPUT_XY(BLOCK_OUTPUT_XY),
        .BLOCK_OUTPUT_SIZE(BLOCK_OUTPUT_SIZE),
        .BLOCK_INPUT_XY(BLOCK_INPUT_XY),
        .BLOCK_INPUT_SIZE(BLOCK_INPUT_SIZE),
        .VALID_INPUT_XY(VALID_INPUT_XY),
        .VALID_INPUT_SIZE(VALID_INPUT_SIZE),
        .BLOCK_CHANNEL_INFO(BLOCK_CHANNEL_INFO),
        .BLOCK_OUTPUT_CHANNEL_INFO(BLOCK_OUTPUT_CHANNEL_INFO),
        .BLOCK_OUTPUT_ADDR(BLOCK_OUTPUT_ADDR),
        .PADDING_SIZE_RESERVED(PADDING_SIZE_RESERVED),
        .PADDING_VALUE_RESERVED(PADDING_VALUE_RESERVED)
    );

    apb3_protocol_checker #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .ZERO_WAIT(1'b1)
    ) u_apb_checker (
        .PCLK(PCLK),
        .PRESETn(PRESETn),
        .PSEL(PSEL),
        .PENABLE(PENABLE),
        .PWRITE(PWRITE),
        .PADDR(PADDR),
        .PWDATA(PWDATA),
        .PRDATA(PRDATA),
        .PREADY(PREADY),
        .PSLVERR(PSLVERR)
    );

    always #5 PCLK = ~PCLK;

    task automatic apb_idle;
        begin
            PSEL    = 1'b0;
            PENABLE = 1'b0;
            PWRITE  = 1'b0;
            PADDR   = '0;
            PWDATA  = '0;
        end
    endtask

    task automatic apb_write(
        input logic [ADDR_WIDTH-1:0] addr,
        input logic [DATA_WIDTH-1:0] data,
        input logic                  expect_error
    );
        begin
            @(negedge PCLK);
            PADDR   = addr;
            PWDATA  = data;
            PWRITE  = 1'b1;
            PSEL    = 1'b1;
            PENABLE = 1'b0;

            @(negedge PCLK);
            PENABLE = 1'b1;

            do begin
                @(posedge PCLK);
                #1;
            end while (!PREADY);

            if (PSLVERR !== expect_error) begin
                $display("ERROR APB write response addr=0x%08h PSLVERR=%0b expected=%0b",
                         addr, PSLVERR, expect_error);
                errors = errors + 1;
            end

            @(negedge PCLK);
            apb_idle();
        end
    endtask

    task automatic apb_read(
        input logic [ADDR_WIDTH-1:0] addr,
        input logic [DATA_WIDTH-1:0] expected_data,
        input logic                  expect_error
    );
        begin
            @(negedge PCLK);
            PADDR   = addr;
            PWDATA  = '0;
            PWRITE  = 1'b0;
            PSEL    = 1'b1;
            PENABLE = 1'b0;

            @(negedge PCLK);
            PENABLE = 1'b1;

            do begin
                @(posedge PCLK);
                #1;
            end while (!PREADY);

            if (PSLVERR !== expect_error) begin
                $display("ERROR APB read response addr=0x%08h PSLVERR=%0b expected=%0b",
                         addr, PSLVERR, expect_error);
                errors = errors + 1;
            end
            if (!expect_error && PRDATA !== expected_data) begin
                $display("ERROR APB read data addr=0x%08h got=0x%08h expected=0x%08h",
                         addr, PRDATA, expected_data);
                errors = errors + 1;
            end

            @(negedge PCLK);
            apb_idle();
        end
    endtask

    task automatic apb_back_to_back_write(
        input logic [ADDR_WIDTH-1:0] first_addr,
        input logic [DATA_WIDTH-1:0] first_data,
        input logic [ADDR_WIDTH-1:0] second_addr,
        input logic [DATA_WIDTH-1:0] second_data
    );
        begin
            @(negedge PCLK);
            PSEL    = 1'b1;
            PENABLE = 1'b0;
            PWRITE  = 1'b1;
            PADDR   = first_addr;
            PWDATA  = first_data;

            @(negedge PCLK);
            PENABLE = 1'b1;
            @(posedge PCLK);
            #1;
            if (!PREADY || PSLVERR) begin
                $display("ERROR first APB back-to-back transfer failed");
                errors = errors + 1;
            end

            @(negedge PCLK);
            PENABLE = 1'b0;
            PADDR   = second_addr;
            PWDATA  = second_data;

            @(negedge PCLK);
            PENABLE = 1'b1;
            @(posedge PCLK);
            #1;
            if (!PREADY || PSLVERR) begin
                $display("ERROR second APB back-to-back transfer failed");
                errors = errors + 1;
            end

            @(negedge PCLK);
            apb_idle();
        end
    endtask

    initial begin
        errors = 0;
        PCLK = 1'b0;
        PRESETn = 1'b0;
        CDMA_STATUS = '0;
        CSC_STATUS = '0;
        CACC_S_STATUS = '0;
        apb_idle();

        repeat (4) @(posedge PCLK);
        @(negedge PCLK);
        PRESETn = 1'b1;

        apb_read(REG_DATA_WIDTH, 32'h0000_0000, 1'b0);
        apb_write(REG_DATA_WIDTH, 32'h0000_0010, 1'b0);
        apb_write(REG_DATA_HEIGHT, 32'h0000_0008, 1'b0);
        apb_write(REG_CSC_ATOMICS, 32'h0000_0123, 1'b0);
        apb_write(REG_CACC_ADDR, 32'h0100_0000, 1'b0);
        apb_read(REG_DATA_WIDTH, 32'h0000_0010, 1'b0);
        apb_read(REG_DATA_HEIGHT, 32'h0000_0008, 1'b0);
        apb_read(REG_CSC_ATOMICS, 32'h0000_0123, 1'b0);
        apb_read(REG_CACC_ADDR, 32'h0100_0000, 1'b0);

        apb_write(REG_BLOCK_OUTPUT_XY, 32'h0002_0001, 1'b0);
        apb_write(REG_BLOCK_OUTPUT_SIZE, 32'h0004_0005, 1'b0);
        apb_write(REG_BLOCK_INPUT_XY, 32'h0002_0001, 1'b0);
        apb_write(REG_BLOCK_INPUT_SIZE, 32'h0006_0007, 1'b0);
        apb_write(REG_VALID_INPUT_XY, 32'h0002_0001, 1'b0);
        apb_write(REG_VALID_INPUT_SIZE, 32'h0006_0007, 1'b0);
        apb_write(REG_BLOCK_CHANNEL_INFO, 32'h0004_0000, 1'b0);
        apb_write(REG_BLOCK_OUTPUT_CHANNEL_INFO, 32'h0003_0000, 1'b0);
        apb_write(REG_BLOCK_OUTPUT_ADDR, 32'h0100_0020, 1'b0);
        apb_write(REG_PADDING_SIZE_RESERVED, 32'h0000_0000, 1'b0);
        apb_write(REG_PADDING_VALUE_RESERVED, 32'h0000_0000, 1'b0);
        apb_read(REG_BLOCK_OUTPUT_XY, 32'h0002_0001, 1'b0);
        apb_read(REG_BLOCK_OUTPUT_SIZE, 32'h0004_0005, 1'b0);
        apb_read(REG_BLOCK_INPUT_XY, 32'h0002_0001, 1'b0);
        apb_read(REG_BLOCK_INPUT_SIZE, 32'h0006_0007, 1'b0);
        apb_read(REG_VALID_INPUT_XY, 32'h0002_0001, 1'b0);
        apb_read(REG_VALID_INPUT_SIZE, 32'h0006_0007, 1'b0);
        apb_read(REG_BLOCK_CHANNEL_INFO, 32'h0004_0000, 1'b0);
        apb_read(REG_BLOCK_OUTPUT_CHANNEL_INFO, 32'h0003_0000, 1'b0);
        apb_read(REG_BLOCK_OUTPUT_ADDR, 32'h0100_0020, 1'b0);

        CDMA_STATUS = 32'h0000_0012;
        CSC_STATUS = 32'h0000_0003;
        CACC_S_STATUS = 32'h0000_0001;
        repeat (2) @(posedge PCLK);
        apb_read(REG_CDMA_STATUS, 32'h0000_0012, 1'b0);
        apb_read(REG_CSC_STATUS, 32'h0000_0003, 1'b0);
        apb_read(REG_CACC_STATUS, 32'h0000_0001, 1'b0);

        // Status registers are read-only except for sticky-flag W1C bits.
        apb_write(REG_CDMA_STATUS, 32'h0000_0000, 1'b0);
        apb_read(REG_CDMA_STATUS, 32'h0000_0012, 1'b0);

        // CSC/CACC bit 0 is a one-cycle start pulse. Bit 1 remains enabled.
        CDMA_STATUS = '0;
        CSC_STATUS = 32'h0000_0001;
        CACC_S_STATUS = 32'h0000_0001;
        repeat (2) @(posedge PCLK);

        apb_write(REG_CSC_CONTROL, 32'h0000_0002, 1'b0);
        apb_write(REG_CSC_CONTROL, 32'h0000_0003, 1'b0);
        if (CSC_CONTROL !== 32'h0000_0003) begin
            $display("ERROR CSC start pulse was not visible after APB write");
            errors = errors + 1;
        end
        @(posedge PCLK);
        #1;
        if (CSC_CONTROL !== 32'h0000_0002) begin
            $display("ERROR CSC start bit did not auto-clear");
            errors = errors + 1;
        end
        apb_write(REG_CSC_CONTROL, 32'h0000_0000, 1'b0);

        apb_write(REG_CACC_CONTROL, 32'h0000_0002, 1'b0);
        apb_write(REG_CACC_CONTROL, 32'h0000_0003, 1'b0);
        if (CACC_D_OP_ENABLE !== 32'h0000_0003) begin
            $display("ERROR CACC start pulse was not visible after APB write");
            errors = errors + 1;
        end
        @(posedge PCLK);
        #1;
        if (CACC_D_OP_ENABLE !== 32'h0000_0002) begin
            $display("ERROR CACC start bit did not auto-clear");
            errors = errors + 1;
        end
        apb_write(REG_CACC_CONTROL, 32'h0000_0000, 1'b0);

        // Invalid and unaligned accesses must assert PSLVERR and set bit 31.
        CSC_STATUS = '0;
        CACC_S_STATUS = '0;
        apb_read(REG_INVALID_ADDR, 32'h0000_0000, 1'b1);
        repeat (2) @(posedge PCLK);
        apb_read(REG_CDMA_STATUS, 32'h8000_0000, 1'b0);
        apb_write(REG_CDMA_STATUS, 32'h8000_0000, 1'b0);
        repeat (2) @(posedge PCLK);
        apb_read(REG_CDMA_STATUS, 32'h0000_0000, 1'b0);

        apb_write(32'h0000_0002, 32'h1234_5678, 1'b1);
        repeat (2) @(posedge PCLK);
        apb_read(REG_CDMA_STATUS, 32'h8000_0000, 1'b0);
        apb_write(REG_CDMA_STATUS, 32'h8000_0000, 1'b0);

        // Configuration writes are blocked while hardware reports busy.
        apb_write(REG_DATA_WIDTH, 32'h0000_0011, 1'b0);
        CDMA_STATUS = 32'h0000_0001;
        repeat (2) @(posedge PCLK);
        apb_write(REG_DATA_WIDTH, 32'h0000_0022, 1'b1);
        apb_read(REG_DATA_WIDTH, 32'h0000_0011, 1'b0);
        repeat (2) @(posedge PCLK);
        apb_read(REG_CDMA_STATUS, 32'h4000_0001, 1'b0);
        apb_write(REG_CDMA_STATUS, 32'h4000_0000, 1'b0);
        CDMA_STATUS = '0;
        repeat (2) @(posedge PCLK);
        apb_read(REG_CDMA_STATUS, 32'h0000_0000, 1'b0);

        apb_back_to_back_write(
            REG_DATA_WIDTH, 32'h0000_0020,
            REG_DATA_HEIGHT, 32'h0000_0030
        );
        apb_read(REG_DATA_WIDTH, 32'h0000_0020, 1'b0);
        apb_read(REG_DATA_HEIGHT, 32'h0000_0030, 1'b0);

        // Synchronous reset must clear software-visible configuration state.
        @(negedge PCLK);
        PRESETn = 1'b0;
        repeat (3) @(posedge PCLK);
        @(negedge PCLK);
        PRESETn = 1'b1;
        apb_read(REG_DATA_WIDTH, 32'h0000_0000, 1'b0);
        apb_read(REG_DATA_HEIGHT, 32'h0000_0000, 1'b0);

        if (errors == 0) begin
            $display("APB3_CSB_REGISTER_PROTOCOL_TEST_PASS");
        end else begin
            $display("APB3_CSB_REGISTER_PROTOCOL_TEST_FAIL errors=%0d", errors);
            $fatal(1);
        end
        $finish;
    end

    initial begin
        #20000;
        $fatal(1, "APB3 slave test timeout");
    end

endmodule
