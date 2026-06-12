`timescale 1ns/1ps

module cdma_load_cbuf_handshake_tb;

    localparam int ADDR_WIDTH      = 32;
    localparam int AXI_DATA_WIDTH  = 32;
    localparam int CBUF_WORD_WIDTH = 32;
    localparam int ELEMENT_WIDTH   = 8;
    localparam int LEN_WIDTH       = 32;
    localparam int CBUF_ADDR_WIDTH = 16;
    localparam int BANK_NUM        = 8;
    localparam int BANK_SEL_WIDTH  = 3;
    localparam int BANK_ADDR_WIDTH = 4;
    localparam int MACLANE_NUM     = 4;
    localparam int BANK_WORD_WIDTH = 32;
    localparam int TOTAL_BEATS     = 10;

    logic clk;
    logic rst_n;

    logic                       start;
    logic                       busy;
    logic                       done;
    logic                       error;
    logic                       fill_request;
    logic                       fill_done;
    logic [LEN_WIDTH-1:0]       load_total_words;
    logic [ADDR_WIDTH-1:0]      load_last_addr;
    logic [ADDR_WIDTH-1:0]      mem_rd_addr;
    logic                       stream_txn_start;
    logic                       stream_error;
    logic                       stream_valid;
    logic                       stream_ready;
    logic [AXI_DATA_WIDTH-1:0]  stream_data;

    logic [BANK_NUM-1:0] cbuf_wr_bank_en;
    logic [(BANK_NUM*BANK_ADDR_WIDTH)-1:0] cbuf_wr_bank_addr;
    logic [(BANK_NUM*CBUF_WORD_WIDTH)-1:0] cbuf_wr_bank_data;

    logic                       data_rd_en;
    logic [BANK_NUM-1:0]        data_rd_bank_en;
    logic [(BANK_NUM*BANK_ADDR_WIDTH)-1:0] data_rd_bank_addr;
    logic                       data_rd_valid;
    logic [(BANK_NUM*BANK_WORD_WIDTH)-1:0] data_rd_data;

    logic                       weight_rd_valid_unused;
    logic [(BANK_NUM*BANK_WORD_WIDTH)-1:0] weight_rd_data_unused;

    int accepted_count;
    int write_pulse_count;

    cdma_load_channel #(
        .ADDR_WIDTH      (ADDR_WIDTH),
        .AXI_DATA_WIDTH  (AXI_DATA_WIDTH),
        .CBUF_WORD_WIDTH (CBUF_WORD_WIDTH),
        .ELEMENT_WIDTH   (ELEMENT_WIDTH),
        .LEN_WIDTH       (LEN_WIDTH),
        .CBUF_ADDR_WIDTH (CBUF_ADDR_WIDTH),
        .BANK_NUM        (BANK_NUM),
        .BANK_SEL_WIDTH  (BANK_SEL_WIDTH),
        .BANK_ADDR_WIDTH (BANK_ADDR_WIDTH)
    ) u_load_channel (
        .clk              (clk),
        .rst_n            (rst_n),
        .start            (start),
        .busy             (busy),
        .done             (done),
        .error            (error),
        .fill_request     (fill_request),
        .fill_done        (fill_done),
        .cfg_matrix_width (LEN_WIDTH'(TOTAL_BEATS)),
        .cfg_matrix_height(LEN_WIDTH'(1)),
        .cfg_channel_count(LEN_WIDTH'(4)),
        .cfg_dst_base     (CBUF_ADDR_WIDTH'(0)),
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

    cbuf #(
        .DATA_WIDTH      (CBUF_WORD_WIDTH),
        .ADDR_WIDTH      (CBUF_ADDR_WIDTH),
        .ELEMENT_WIDTH   (ELEMENT_WIDTH),
        .BANK_NUM        (BANK_NUM),
        .BANK_SEL_WIDTH  (BANK_SEL_WIDTH),
        .MACLANE_NUM     (MACLANE_NUM),
        .DATA_DEPTH      (16),
        .WEIGHT_DEPTH    (16),
        .BANK_ADDR_WIDTH (BANK_ADDR_WIDTH)
    ) u_cbuf (
        .clk                 (clk),
        .rst_n               (rst_n),
        .data_wr_bank_en     (cbuf_wr_bank_en),
        .data_wr_bank_addr   (cbuf_wr_bank_addr),
        .data_wr_bank_data   (cbuf_wr_bank_data),
        .data_rd_en          (data_rd_en),
        .data_rd_bank_en     (data_rd_bank_en),
        .data_rd_bank_addr   (data_rd_bank_addr),
        .data_rd_valid       (data_rd_valid),
        .data_rd_data        (data_rd_data),
        .weight_wr_bank_en   (8'h00),
        .weight_wr_bank_addr (32'h0000_0000),
        .weight_wr_bank_data (256'h0),
        .weight_rd_en        (1'b0),
        .weight_rd_bank_en   (8'h00),
        .weight_rd_bank_addr (32'h0000_0000),
        .weight_rd_valid     (weight_rd_valid_unused),
        .weight_rd_data      (weight_rd_data_unused)
    );

    always #5 clk = ~clk;

    function automatic logic [7:0] ev(input int idx);
        begin
            ev = 8'h40 + idx[7:0];
        end
    endfunction

    function automatic logic [31:0] make_stream_word(input int beat);
        begin
            make_stream_word = {
                ev((beat * 4) + 3),
                ev((beat * 4) + 2),
                ev((beat * 4) + 1),
                ev((beat * 4) + 0)
            };
        end
    endfunction

    function automatic logic [31:0] expected_word(input int row, input int bank);
        begin
            if (row == 0) begin
                expected_word = {
                    ev(bank + 24),
                    ev(bank + 16),
                    ev(bank + 8),
                    ev(bank)
                };
            end else if (row == 1) begin
                expected_word = {
                    8'h00,
                    8'h00,
                    8'h00,
                    ev(bank + 32)
                };
            end else begin
                expected_word = 32'h0000_0000;
            end
        end
    endfunction

    function automatic logic [(BANK_NUM*BANK_ADDR_WIDTH)-1:0] addr_vec(input int row);
        begin
            addr_vec = {
                BANK_ADDR_WIDTH'(row),
                BANK_ADDR_WIDTH'(row),
                BANK_ADDR_WIDTH'(row),
                BANK_ADDR_WIDTH'(row),
                BANK_ADDR_WIDTH'(row),
                BANK_ADDR_WIDTH'(row),
                BANK_ADDR_WIDTH'(row),
                BANK_ADDR_WIDTH'(row)
            };
        end
    endfunction

    task automatic check_bank(input int row, input int bank, input logic [31:0] got);
        logic [31:0] exp;
        begin
            exp = expected_word(row, bank);
            if (got !== exp) begin
                $fatal(1,
                       "CBUF row %0d bank %0d mismatch: expected 0x%08h got 0x%08h",
                       row, bank, exp, got);
            end
        end
    endtask

    task automatic read_and_check_row(input int row);
        begin
            @(negedge clk);
            data_rd_en        = 1'b1;
            data_rd_bank_en   = 8'hff;
            data_rd_bank_addr = addr_vec(row);

            @(posedge clk);
            #1;
            if (!data_rd_valid) begin
                $fatal(1, "CBUF read valid did not assert for row %0d", row);
            end

            check_bank(row, 0, data_rd_data[31:0]);
            check_bank(row, 1, data_rd_data[63:32]);
            check_bank(row, 2, data_rd_data[95:64]);
            check_bank(row, 3, data_rd_data[127:96]);
            check_bank(row, 4, data_rd_data[159:128]);
            check_bank(row, 5, data_rd_data[191:160]);
            check_bank(row, 6, data_rd_data[223:192]);
            check_bank(row, 7, data_rd_data[255:224]);

            @(negedge clk);
            data_rd_en        = 1'b0;
            data_rd_bank_en   = 8'h00;
            data_rd_bank_addr = 32'h0000_0000;
        end
    endtask

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            accepted_count    <= 0;
            write_pulse_count <= 0;
        end else begin
            if (stream_valid && stream_ready) begin
                accepted_count <= accepted_count + 1;
            end

            if (|cbuf_wr_bank_en) begin
                write_pulse_count <= write_pulse_count + 1;

                if (cbuf_wr_bank_en !== 8'hff) begin
                    $fatal(1, "Unexpected partial CBUF write enable: 0x%0h",
                           cbuf_wr_bank_en);
                end
            end
        end
    end

    initial begin
        clk               = 1'b0;
        rst_n             = 1'b0;
        start             = 1'b0;
        fill_done         = 1'b0;
        stream_txn_start  = 1'b0;
        stream_error      = 1'b0;
        stream_valid      = 1'b0;
        stream_data       = 32'h0000_0000;
        data_rd_en        = 1'b0;
        data_rd_bank_en   = 8'h00;
        data_rd_bank_addr = 32'h0000_0000;

        repeat (4) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;

        stream_valid = 1'b1;
        stream_data  = 32'hDEAD_BEEF;
        repeat (3) @(posedge clk);
        #1;
        if (stream_ready) begin
            $fatal(1, "stream_ready asserted before start");
        end
        if (accepted_count != 0 || write_pulse_count != 0) begin
            $fatal(1, "Stream was accepted before load start");
        end

        @(negedge clk);
        stream_valid = 1'b0;
        stream_data  = 32'h0000_0000;
        start = 1'b1;
        @(negedge clk);
        start = 1'b0;

        for (int beat = 0; beat < TOTAL_BEATS; beat = beat + 1) begin
            @(negedge clk);
            stream_valid = 1'b1;
            stream_data  = make_stream_word(beat);
            #1;
            if (!stream_ready) begin
                $fatal(1, "stream_ready unexpectedly low for beat %0d", beat);
            end
            @(posedge clk);
        end

        @(negedge clk);
        stream_valid = 1'b1;
        stream_data  = 32'hCAFE_BABE;
        @(posedge clk);
        #1;
        if (stream_ready) begin
            $fatal(1, "stream_ready stayed high after all expected beats");
        end

        @(negedge clk);
        fill_done = 1'b1;
        @(negedge clk);
        fill_done = 1'b0;

        wait (done);
        @(posedge clk);
        #1;

        if (error) begin
            $fatal(1, "cdma_load_channel reported error");
        end
        if (accepted_count != TOTAL_BEATS) begin
            $fatal(1, "Accepted beat count mismatch: expected %0d got %0d",
                   TOTAL_BEATS, accepted_count);
        end
        if (write_pulse_count != 2) begin
            $fatal(1, "CBUF write pulse count mismatch: expected 2 got %0d",
                   write_pulse_count);
        end

        read_and_check_row(0);
        read_and_check_row(1);

        $display("CDMA_LOAD_CBUF_HANDSHAKE_TEST_PASS");
        $finish;
    end

    initial begin
        #5000;
        $fatal(1, "CDMA load CBUF handshake test timeout");
    end

endmodule
