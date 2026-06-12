`timescale 1ns/1ps

module tb_cdma_load_burst_padding;
    localparam int ADDR_WIDTH      = 32;
    localparam int AXI_DATA_WIDTH  = 32;
    localparam int CBUF_WORD_WIDTH = 32;
    localparam int ELEMENT_WIDTH   = 8;
    localparam int LEN_WIDTH       = 32;
    localparam int CBUF_ADDR_WIDTH = 16;
    localparam int BANK_NUM        = 8;
    localparam int BANK_SEL_WIDTH  = 3;
    localparam int BANK_ADDR_WIDTH = 10;
    localparam int AXI_BURST_LEN   = 8;

    logic clk;
    logic rst_n;
    logic start;
    logic busy;
    logic done;
    logic error;
    logic fill_request;
    logic fill_done;
    logic [LEN_WIDTH-1:0] cfg_matrix_width;
    logic [LEN_WIDTH-1:0] cfg_matrix_height;
    logic [LEN_WIDTH-1:0] cfg_channel_count;
    logic [CBUF_ADDR_WIDTH-1:0] cfg_dst_base;
    logic [LEN_WIDTH-1:0] load_total_words;
    logic [ADDR_WIDTH-1:0] load_last_addr;
    logic [ADDR_WIDTH-1:0] mem_rd_addr;
    logic stream_txn_start;
    logic stream_error;
    logic stream_valid;
    logic stream_ready;
    logic [AXI_DATA_WIDTH-1:0] stream_data;
    logic [BANK_NUM-1:0] cbuf_wr_bank_en;
    logic [(BANK_NUM*BANK_ADDR_WIDTH)-1:0] cbuf_wr_bank_addr;
    logic [(BANK_NUM*CBUF_WORD_WIDTH)-1:0] cbuf_wr_bank_data;

    integer write_events;
    logic [BANK_NUM-1:0] first_bank_en;
    logic [(BANK_NUM*BANK_ADDR_WIDTH)-1:0] first_bank_addr;
    logic [(BANK_NUM*CBUF_WORD_WIDTH)-1:0] first_bank_data;

    cdma_load_channel #(
        .ADDR_WIDTH      (ADDR_WIDTH),
        .AXI_DATA_WIDTH  (AXI_DATA_WIDTH),
        .CBUF_WORD_WIDTH (CBUF_WORD_WIDTH),
        .ELEMENT_WIDTH   (ELEMENT_WIDTH),
        .LEN_WIDTH       (LEN_WIDTH),
        .CBUF_ADDR_WIDTH (CBUF_ADDR_WIDTH),
        .BANK_NUM        (BANK_NUM),
        .BANK_SEL_WIDTH  (BANK_SEL_WIDTH),
        .BANK_ADDR_WIDTH (BANK_ADDR_WIDTH),
        .AXI_BURST_LEN   (AXI_BURST_LEN)
    ) dut (
        .clk              (clk),
        .rst_n            (rst_n),
        .start            (start),
        .busy             (busy),
        .done             (done),
        .error            (error),
        .fill_request     (fill_request),
        .fill_done        (fill_done),
        .cfg_matrix_width (cfg_matrix_width),
        .cfg_matrix_height(cfg_matrix_height),
        .cfg_channel_count(cfg_channel_count),
        .cfg_dst_base     (cfg_dst_base),
        .load_total_words (load_total_words),
        .load_last_addr   (load_last_addr),
        .mem_rd_addr      (mem_rd_addr),
        .stream_txn_start (stream_txn_start),
        .stream_error     (stream_error),
        .stream_valid     (stream_valid),
        .stream_ready     (stream_ready),
        .stream_data      (stream_data),
        .cbuf_wr_bank_en  (cbuf_wr_bank_en),
        .cbuf_wr_bank_addr(cbuf_wr_bank_addr),
        .cbuf_wr_bank_data(cbuf_wr_bank_data)
    );

    always #5 clk = ~clk;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            write_events <= 0;
            first_bank_en <= '0;
            first_bank_addr <= '0;
            first_bank_data <= '0;
        end else if (cbuf_wr_bank_en != '0) begin
            write_events <= write_events + 1;
            if (write_events == 0) begin
                first_bank_en <= cbuf_wr_bank_en;
                first_bank_addr <= cbuf_wr_bank_addr;
                first_bank_data <= cbuf_wr_bank_data;
            end
        end
    end

    task automatic fail(input string msg);
        begin
            $display("ERROR %s", msg);
            $finish;
        end
    endtask

    task automatic expect_bank_word(
        input int bank,
        input logic [CBUF_WORD_WIDTH-1:0] expected
    );
        logic [CBUF_WORD_WIDTH-1:0] actual;
        begin
            actual =
                first_bank_data[(bank*CBUF_WORD_WIDTH)+:CBUF_WORD_WIDTH];
            if (actual !== expected) begin
                $display(
                    "ERROR bank%0d data expected=0x%08x actual=0x%08x",
                    bank,
                    expected,
                    actual
                );
                $finish;
            end
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        start = 1'b0;
        fill_done = 1'b0;
        cfg_matrix_width = 32'd1;
        cfg_matrix_height = 32'd1;
        cfg_channel_count = 32'd4;
        cfg_dst_base = '0;
        stream_txn_start = 1'b0;
        stream_error = 1'b0;
        stream_valid = 1'b0;
        stream_data = 32'h04030201;

        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        @(negedge clk);
        start = 1'b1;
        @(negedge clk);
        start = 1'b0;

        for (int wait_cycle = 0; wait_cycle < 20 && busy !== 1'b1;
             wait_cycle = wait_cycle + 1) begin
            @(posedge clk);
        end
        if (busy !== 1'b1) begin
            fail("busy was not asserted after start");
        end

        if (load_total_words !== 32'd1) begin
            fail("load_total_words should be 1 for 1x1x4ch");
        end

        @(negedge clk);
        stream_txn_start = 1'b1;
        @(negedge clk);
        stream_txn_start = 1'b0;

        for (int beat = 0; beat < AXI_BURST_LEN; beat = beat + 1) begin
            @(negedge clk);
            stream_valid = 1'b1;
            stream_data = 32'h04030201 + beat;
            #1;
            if (stream_ready !== 1'b1) begin
                $display("ERROR stream_ready dropped before burst end at beat %0d", beat);
                $finish;
            end
        end

        @(negedge clk);
        stream_valid = 1'b0;
        stream_data = '0;
        @(negedge clk);
        fill_done = 1'b1;
        @(negedge clk);
        fill_done = 1'b0;

        for (int wait_done = 0; wait_done < 10 && done !== 1'b1;
             wait_done = wait_done + 1) begin
            @(posedge clk);
        end

        if (error !== 1'b0) begin
            fail("channel asserted error");
        end

        if (done !== 1'b1) begin
            fail("channel did not assert done after draining padded burst");
        end

        if (write_events != 1) begin
            $display("ERROR expected exactly one CBUF write event, got %0d", write_events);
            $finish;
        end

        if (first_bank_en !== 8'h0f) begin
            $display("ERROR expected banks[3:0] write enable, got 0x%02x", first_bank_en);
            $finish;
        end

        for (int bank = 0; bank < 4; bank = bank + 1) begin
            if (first_bank_addr[(bank*BANK_ADDR_WIDTH)+:BANK_ADDR_WIDTH] !== '0) begin
                $display("ERROR bank%0d address expected 0", bank);
                $finish;
            end
        end

        expect_bank_word(0, 32'h00000001);
        expect_bank_word(1, 32'h00000002);
        expect_bank_word(2, 32'h00000003);
        expect_bank_word(3, 32'h00000004);

        $display("CDMA_LOAD_BURST_PADDING_TEST_PASS");
        $finish;
    end
endmodule
