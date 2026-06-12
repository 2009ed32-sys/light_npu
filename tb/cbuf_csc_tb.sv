module cbuf_csc_tb;

    localparam int DATA_WIDTH    = 32;
    localparam int ELEMENT_WIDTH = 8;
    localparam int MACCELL_NUM   = 8;
    localparam int MACLANE_NUM   = DATA_WIDTH / ELEMENT_WIDTH;
    localparam int ADDR_WIDTH    = 8;
    localparam int LEN_WIDTH     = 16;
    localparam int TAG_WIDTH     = 16;
    localparam int DATA_DEPTH    = 16;
    localparam int WEIGHT_DEPTH  = 16;

    localparam int VEC_WIDTH = MACCELL_NUM * MACLANE_NUM * ELEMENT_WIDTH;

    logic clk;
    logic rst_n;

    logic data_wr_en;
    logic [ADDR_WIDTH-1:0] data_wr_addr;
    logic [DATA_WIDTH-1:0] data_wr_data;
    logic data_rd_en;
    logic [MACCELL_NUM-1:0] data_rd_bank_en;
    logic [(MACCELL_NUM*ADDR_WIDTH)-1:0] data_rd_bank_addr;
    logic data_rd_valid;
    logic [VEC_WIDTH-1:0] data_rd_data;

    logic weight_wr_en;
    logic [ADDR_WIDTH-1:0] weight_wr_addr;
    logic [DATA_WIDTH-1:0] weight_wr_data;
    logic weight_rd_en;
    logic [MACCELL_NUM-1:0] weight_rd_bank_en;
    logic [(MACCELL_NUM*ADDR_WIDTH)-1:0] weight_rd_bank_addr;
    logic weight_rd_valid;
    logic [VEC_WIDTH-1:0] weight_rd_data;

    logic csc_start;
    logic csc_busy;
    logic csc_done;
    logic csc_error;
    logic [LEN_WIDTH-1:0] csc_atomics;
    logic [ADDR_WIDTH-1:0] csc_data_base;
    logic [ADDR_WIDTH-1:0] csc_weight_base;
    logic [LEN_WIDTH-1:0] csc_input_width;
    logic [LEN_WIDTH-1:0] csc_input_height;
    logic [LEN_WIDTH-1:0] csc_input_channels;
    logic [LEN_WIDTH-1:0] csc_kernel_width;
    logic [LEN_WIDTH-1:0] csc_kernel_height;
    logic [LEN_WIDTH-1:0] csc_stride_x;
    logic [LEN_WIDTH-1:0] csc_stride_y;
    logic [LEN_WIDTH-1:0] csc_output_width;
    logic [LEN_WIDTH-1:0] csc_output_height;
    logic [LEN_WIDTH-1:0] csc_output_channels;
    logic maccell_ready;
    logic maccell_in_valid;
    logic [MACCELL_NUM-1:0] maccell_valid_mask;
    logic [VEC_WIDTH-1:0] maccell_data;
    logic [VEC_WIDTH-1:0] maccell_weight;
    logic maccell_acc_clear;
    logic maccell_acc_last;
    logic [TAG_WIDTH-1:0] maccell_tag;

    int valid_count;
    logic done_seen;

    cbuf #(
        .DATA_WIDTH   (DATA_WIDTH),
        .ADDR_WIDTH   (ADDR_WIDTH),
        .ELEMENT_WIDTH(ELEMENT_WIDTH),
        .MACCELL_NUM  (MACCELL_NUM),
        .MACLANE_NUM  (MACLANE_NUM),
        .DATA_DEPTH   (DATA_DEPTH),
        .WEIGHT_DEPTH (WEIGHT_DEPTH)
    ) u_cbuf (
        .clk            (clk),
        .rst_n          (rst_n),
        .data_wr_en     (data_wr_en),
        .data_wr_addr   (data_wr_addr),
        .data_wr_data   (data_wr_data),
        .data_rd_en     (data_rd_en),
        .data_rd_bank_en(data_rd_bank_en),
        .data_rd_bank_addr(data_rd_bank_addr),
        .data_rd_valid  (data_rd_valid),
        .data_rd_data   (data_rd_data),
        .weight_wr_en   (weight_wr_en),
        .weight_wr_addr (weight_wr_addr),
        .weight_wr_data (weight_wr_data),
        .weight_rd_en   (weight_rd_en),
        .weight_rd_bank_en(weight_rd_bank_en),
        .weight_rd_bank_addr(weight_rd_bank_addr),
        .weight_rd_valid(weight_rd_valid),
        .weight_rd_data (weight_rd_data)
    );

    csc #(
        .ELEMENT_WIDTH(ELEMENT_WIDTH),
        .MACCELL_NUM  (MACCELL_NUM),
        .MACLANE_NUM  (MACLANE_NUM),
        .ADDR_WIDTH   (ADDR_WIDTH),
        .LEN_WIDTH    (LEN_WIDTH),
        .TAG_WIDTH    (TAG_WIDTH)
    ) u_csc (
        .clk                    (clk),
        .rst_n                  (rst_n),
        .start                  (csc_start),
        .busy                   (csc_busy),
        .done                   (csc_done),
        .error                  (csc_error),
        .atomics                (csc_atomics),
        .data_base              (csc_data_base),
        .weight_base            (csc_weight_base),
        .input_width            (csc_input_width),
        .input_height           (csc_input_height),
        .input_channels         (csc_input_channels),
        .kernel_width           (csc_kernel_width),
        .kernel_height          (csc_kernel_height),
        .stride_x               (csc_stride_x),
        .stride_y               (csc_stride_y),
        .output_width           (csc_output_width),
        .output_height          (csc_output_height),
        .output_channels        (csc_output_channels),
        .data_cbuf_rd_en        (data_rd_en),
        .data_cbuf_rd_bank_en   (data_rd_bank_en),
        .data_cbuf_rd_bank_addr (data_rd_bank_addr),
        .data_cbuf_rd_valid     (data_rd_valid),
        .data_cbuf_rd_data      (data_rd_data),
        .weight_cbuf_rd_en      (weight_rd_en),
        .weight_cbuf_rd_bank_en (weight_rd_bank_en),
        .weight_cbuf_rd_bank_addr(weight_rd_bank_addr),
        .weight_cbuf_rd_valid   (weight_rd_valid),
        .weight_cbuf_rd_data    (weight_rd_data),
        .maccell_ready          (maccell_ready),
        .maccell_in_valid       (maccell_in_valid),
        .maccell_valid_mask     (maccell_valid_mask),
        .maccell_data           (maccell_data),
        .maccell_weight         (maccell_weight),
        .maccell_acc_clear      (maccell_acc_clear),
        .maccell_acc_last       (maccell_acc_last),
        .maccell_tag            (maccell_tag)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    function automatic logic [VEC_WIDTH-1:0] expected_row(
        input logic [DATA_WIDTH-1:0] prefix,
        input int row
    );
        logic [VEC_WIDTH-1:0] value;
        begin
            value = '0;
            for (int bank = 0; bank < MACCELL_NUM; bank++) begin
                value[(bank*DATA_WIDTH)+:DATA_WIDTH] =
                    prefix | DATA_WIDTH'(row * MACCELL_NUM + bank);
            end
            expected_row = value;
        end
    endfunction

    function automatic logic [VEC_WIDTH-1:0] expected_cells(
        input logic [DATA_WIDTH-1:0] prefix,
        input logic [MACCELL_NUM-1:0] mask,
        input int w0,
        input int w1,
        input int w2,
        input int w3,
        input int w4,
        input int w5,
        input int w6,
        input int w7
    );
        logic [VEC_WIDTH-1:0] value;
        int words [0:MACCELL_NUM-1];
        begin
            value = '0;
            words[0] = w0;
            words[1] = w1;
            words[2] = w2;
            words[3] = w3;
            words[4] = w4;
            words[5] = w5;
            words[6] = w6;
            words[7] = w7;

            for (int mac = 0; mac < MACCELL_NUM; mac++) begin
                if (mask[mac]) begin
                    value[(mac*DATA_WIDTH)+:DATA_WIDTH] =
                        prefix | DATA_WIDTH'(words[mac]);
                end
            end

            expected_cells = value;
        end
    endfunction

    task automatic write_data_row(
        input int row
    );
        begin
            for (int bank = 0; bank < MACCELL_NUM; bank++) begin
                write_data_word(
                    ADDR_WIDTH'(row * MACCELL_NUM + bank),
                    32'hD000_0000 | DATA_WIDTH'(row * MACCELL_NUM + bank)
                );
            end
        end
    endtask

    task automatic write_weight_row(
        input int row
    );
        begin
            for (int bank = 0; bank < MACCELL_NUM; bank++) begin
                write_weight_word(
                    ADDR_WIDTH'(row * MACCELL_NUM + bank),
                    32'hA000_0000 | DATA_WIDTH'(row * MACCELL_NUM + bank)
                );
            end
        end
    endtask

    task automatic write_data_word(
        input logic [ADDR_WIDTH-1:0] addr,
        input logic [DATA_WIDTH-1:0] data
    );
        begin
            @(negedge clk);
            data_wr_en   = 1'b1;
            data_wr_addr = addr;
            data_wr_data = data;
            @(negedge clk);
            data_wr_en   = 1'b0;
            data_wr_addr = '0;
            data_wr_data = '0;
        end
    endtask

    task automatic write_weight_word(
        input logic [ADDR_WIDTH-1:0] addr,
        input logic [DATA_WIDTH-1:0] data
    );
        begin
            @(negedge clk);
            weight_wr_en   = 1'b1;
            weight_wr_addr = addr;
            weight_wr_data = data;
            @(negedge clk);
            weight_wr_en   = 1'b0;
            weight_wr_addr = '0;
            weight_wr_data = '0;
        end
    endtask

    task automatic check_issue(
        input int index,
        input logic [MACCELL_NUM-1:0] expected_mask,
        input logic [VEC_WIDTH-1:0] expected_data,
        input logic [VEC_WIDTH-1:0] expected_weight,
        input logic expected_clear,
        input logic expected_last,
        input logic [TAG_WIDTH-1:0] expected_tag
    );
        begin
            if (maccell_valid_mask !== expected_mask) begin
                $error("valid mask mismatch issue %0d: got 0x%02x expected 0x%02x",
                    index, maccell_valid_mask, expected_mask);
            end

            if (maccell_data !== expected_data) begin
                $error("data mismatch issue %0d: got 0x%064x expected 0x%064x",
                    index, maccell_data, expected_data);
            end

            if (maccell_weight !== expected_weight) begin
                $error("weight mismatch issue %0d: got 0x%064x expected 0x%064x",
                    index, maccell_weight, expected_weight);
            end

            if (maccell_acc_clear !== expected_clear) begin
                $error("acc_clear mismatch issue %0d", index);
            end

            if (maccell_acc_last !== expected_last) begin
                $error("acc_last mismatch issue %0d", index);
            end

            if (maccell_tag !== expected_tag) begin
                $error("tag mismatch issue %0d: got %0d expected %0d",
                    index, maccell_tag, expected_tag);
            end
        end
    endtask

    initial begin
        rst_n = 1'b0;
        data_wr_en = 1'b0;
        data_wr_addr = '0;
        data_wr_data = '0;
        weight_wr_en = 1'b0;
        weight_wr_addr = '0;
        weight_wr_data = '0;
        csc_start = 1'b0;
        csc_atomics = '0;
        csc_data_base = '0;
        csc_weight_base = '0;
        csc_input_width = '0;
        csc_input_height = '0;
        csc_input_channels = '0;
        csc_kernel_width = '0;
        csc_kernel_height = '0;
        csc_stride_x = '0;
        csc_stride_y = '0;
        csc_output_width = '0;
        csc_output_height = '0;
        csc_output_channels = '0;
        maccell_ready = 1'b1;
        valid_count = 0;
        done_seen = 1'b0;

        repeat (4) @(posedge clk);
        rst_n = 1'b1;

        for (int row = 0; row < 8; row++) begin
            write_data_row(row);
            write_weight_row(row);
        end

        csc_atomics = LEN_WIDTH'(2);
        @(negedge clk);
        csc_start = 1'b1;
        @(negedge clk);
        csc_start = 1'b0;

        repeat (20) begin
            @(posedge clk);
            #1;

            if (maccell_in_valid) begin
                case (valid_count)
                    0: check_issue(
                        0,
                        8'hff,
                        expected_row(32'hD000_0000, 0),
                        expected_row(32'hA000_0000, 0),
                        1'b1,
                        1'b0,
                        16'd0
                    );
                    1: check_issue(
                        1,
                        8'hff,
                        expected_row(32'hD000_0000, 1),
                        expected_row(32'hA000_0000, 1),
                        1'b0,
                        1'b1,
                        16'd1
                    );
                    default: $error("unexpected extra maccell_in_valid");
                endcase

                valid_count++;
            end

            if (csc_done) begin
                done_seen = 1'b1;
            end
        end

        if (valid_count != 2) begin
            $error("expected 2 maccell issues, got %0d", valid_count);
        end

        if (!done_seen) begin
            $error("CSC done pulse was not observed");
        end

        if (csc_error) begin
            $error("CSC error asserted");
        end

        if ((valid_count == 2) && done_seen && !csc_error) begin
            $display("cbuf_csc linear fallback PASSED");
        end

        valid_count = 0;
        done_seen = 1'b0;

        csc_atomics = '0;
        csc_data_base = ADDR_WIDTH'(0);
        csc_weight_base = ADDR_WIDTH'(0);
        csc_input_width = LEN_WIDTH'(4);
        csc_input_height = LEN_WIDTH'(4);
        csc_input_channels = LEN_WIDTH'(4);
        csc_kernel_width = LEN_WIDTH'(3);
        csc_kernel_height = LEN_WIDTH'(3);
        csc_stride_x = LEN_WIDTH'(1);
        csc_stride_y = LEN_WIDTH'(1);
        csc_output_width = LEN_WIDTH'(2);
        csc_output_height = LEN_WIDTH'(2);
        csc_output_channels = LEN_WIDTH'(2);

        @(negedge clk);
        csc_start = 1'b1;
        @(negedge clk);
        csc_start = 1'b0;

        repeat (80) begin
            @(posedge clk);
            #1;

            if (maccell_in_valid) begin
                case (valid_count)
                    0: check_issue(
                        0,
                        8'h3f,
                        expected_cells(32'hD000_0000, 8'h3f, 0, 1, 2, 4, 5, 6, 0, 0),
                        expected_cells(32'hA000_0000, 8'h3f, 0, 1, 2, 3, 4, 5, 0, 0),
                        1'b1,
                        1'b0,
                        16'd0
                    );
                    1: check_issue(
                        1,
                        8'hc0,
                        expected_cells(32'hD000_0000, 8'hc0, 0, 0, 0, 0, 0, 0, 8, 9),
                        expected_cells(32'hA000_0000, 8'hc0, 0, 0, 0, 0, 0, 0, 6, 7),
                        1'b0,
                        1'b0,
                        16'd0
                    );
                    2: check_issue(
                        2,
                        8'h01,
                        expected_cells(32'hD000_0000, 8'h01, 10, 0, 0, 0, 0, 0, 0, 0),
                        expected_cells(32'hA000_0000, 8'h01, 8, 0, 0, 0, 0, 0, 0, 0),
                        1'b0,
                        1'b1,
                        16'd0
                    );
                    3: check_issue(
                        3,
                        8'h3f,
                        expected_cells(32'hD000_0000, 8'h3f, 0, 1, 2, 4, 5, 6, 0, 0),
                        expected_cells(32'hA000_0000, 8'h3f, 9, 10, 11, 12, 13, 14, 0, 0),
                        1'b1,
                        1'b0,
                        16'd1
                    );
                    4: check_issue(
                        4,
                        8'hc0,
                        expected_cells(32'hD000_0000, 8'hc0, 0, 0, 0, 0, 0, 0, 8, 9),
                        expected_cells(32'hA000_0000, 8'hc0, 0, 0, 0, 0, 0, 0, 15, 16),
                        1'b0,
                        1'b0,
                        16'd1
                    );
                    5: check_issue(
                        5,
                        8'h01,
                        expected_cells(32'hD000_0000, 8'h01, 10, 0, 0, 0, 0, 0, 0, 0),
                        expected_cells(32'hA000_0000, 8'h01, 17, 0, 0, 0, 0, 0, 0, 0),
                        1'b0,
                        1'b1,
                        16'd1
                    );
                    21: check_issue(
                        21,
                        8'h3f,
                        expected_cells(32'hD000_0000, 8'h3f, 5, 6, 7, 9, 10, 11, 0, 0),
                        expected_cells(32'hA000_0000, 8'h3f, 9, 10, 11, 12, 13, 14, 0, 0),
                        1'b1,
                        1'b0,
                        16'd7
                    );
                    22: check_issue(
                        22,
                        8'hc0,
                        expected_cells(32'hD000_0000, 8'hc0, 0, 0, 0, 0, 0, 0, 13, 14),
                        expected_cells(32'hA000_0000, 8'hc0, 0, 0, 0, 0, 0, 0, 15, 16),
                        1'b0,
                        1'b0,
                        16'd7
                    );
                    23: check_issue(
                        23,
                        8'h01,
                        expected_cells(32'hD000_0000, 8'h01, 15, 0, 0, 0, 0, 0, 0, 0),
                        expected_cells(32'hA000_0000, 8'h01, 17, 0, 0, 0, 0, 0, 0, 0),
                        1'b0,
                        1'b1,
                        16'd7
                    );
                    default: begin
                        if (valid_count > 23) begin
                            $error("unexpected extra geometry maccell_in_valid");
                        end
                    end
                endcase

                valid_count++;
            end

            if (csc_done) begin
                done_seen = 1'b1;
            end
        end

        if (valid_count != 24) begin
            $error("expected 24 geometry maccell issues, got %0d", valid_count);
        end

        if (!done_seen) begin
            $error("CSC geometry done pulse was not observed");
        end

        if (csc_error) begin
            $error("CSC geometry error asserted");
        end

        if ((valid_count == 24) && done_seen && !csc_error) begin
            $display("cbuf_csc geometry address generator PASSED");
            $display("cbuf_csc_tb PASSED");
        end

        $finish;
    end

endmodule
