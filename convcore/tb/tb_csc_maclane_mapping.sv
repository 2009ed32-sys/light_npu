module tb_csc_maclane_mapping;
    localparam integer ELEMENT_WIDTH   = 8;
    localparam integer BANK_NUM        = 8;
    localparam integer MACCELL_NUM     = 8;
    localparam integer MACLANE_NUM     = 4;
    localparam integer ADDR_WIDTH      = 16;
    localparam integer BANK_ADDR_WIDTH = 10;
    localparam integer LEN_WIDTH       = 32;
    localparam integer TAG_WIDTH       = 32;
    localparam integer ADDR_FIFO_DEPTH = 4;

    localparam integer MAC_VEC_WIDTH = MACCELL_NUM * MACLANE_NUM * ELEMENT_WIDTH;
    localparam integer CBUF_RD_WIDTH = BANK_NUM * MACLANE_NUM * ELEMENT_WIDTH;
    localparam integer BANK_ADDR_VEC_WIDTH = BANK_NUM * BANK_ADDR_WIDTH;
    localparam integer EXPECTED_PACKETS = 2;
    localparam integer DATA_BASE_ELEM = 6;
    localparam integer WEIGHT_BASE_ELEM = 0;
    localparam integer WEIGHT_PACKET_ELEMENTS = MACCELL_NUM * MACLANE_NUM;

    reg clk;
    reg rst_n;
    reg op_enable;
    reg op_start;
    wire op_ready;
    wire op_busy;
    wire op_done;
    wire op_error;

    reg [LEN_WIDTH-1:0] atomics;
    reg [ADDR_WIDTH-1:0] data_base;
    reg [ADDR_WIDTH-1:0] weight_base;
    reg [LEN_WIDTH-1:0] input_width;
    reg [LEN_WIDTH-1:0] input_height;
    reg [LEN_WIDTH-1:0] input_channels;
    reg [LEN_WIDTH-1:0] kernel_width;
    reg [LEN_WIDTH-1:0] kernel_height;
    reg [LEN_WIDTH-1:0] stride_x;
    reg [LEN_WIDTH-1:0] stride_y;
    reg [LEN_WIDTH-1:0] output_width;
    reg [LEN_WIDTH-1:0] output_height;
    reg [LEN_WIDTH-1:0] output_channels;

    wire data_cbuf_rd_en;
    wire [BANK_NUM-1:0] data_cbuf_rd_bank_en;
    wire [BANK_ADDR_VEC_WIDTH-1:0] data_cbuf_rd_bank_addr;
    reg data_cbuf_rd_valid;
    reg [CBUF_RD_WIDTH-1:0] data_cbuf_rd_data;

    wire weight_cbuf_rd_en;
    wire [BANK_NUM-1:0] weight_cbuf_rd_bank_en;
    wire [BANK_ADDR_VEC_WIDTH-1:0] weight_cbuf_rd_bank_addr;
    reg weight_cbuf_rd_valid;
    reg [CBUF_RD_WIDTH-1:0] weight_cbuf_rd_data;

    reg maccell_ready;
    wire maccell_in_valid;
    wire [MACCELL_NUM-1:0] maccell_valid_mask;
    wire [MAC_VEC_WIDTH-1:0] maccell_data;
    wire [MAC_VEC_WIDTH-1:0] maccell_weight;
    wire maccell_acc_clear;
    wire maccell_acc_last;
    wire [TAG_WIDTH-1:0] maccell_tag;

    integer errors;
    integer timeout;
    integer read_seen;
    integer outputs_seen;
    reg done_seen;

    integer bank_i;
    integer pack_i;
    integer addr_i;

    csc #(
        .ELEMENT_WIDTH(ELEMENT_WIDTH),
        .BANK_NUM(BANK_NUM),
        .MACCELL_NUM(MACCELL_NUM),
        .MACLANE_NUM(MACLANE_NUM),
        .ADDR_WIDTH(ADDR_WIDTH),
        .BANK_ADDR_WIDTH(BANK_ADDR_WIDTH),
        .LEN_WIDTH(LEN_WIDTH),
        .TAG_WIDTH(TAG_WIDTH),
        .ADDR_FIFO_DEPTH(ADDR_FIFO_DEPTH)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .op_enable(op_enable),
        .op_start(op_start),
        .op_ready(op_ready),
        .op_busy(op_busy),
        .op_done(op_done),
        .op_error(op_error),
        .atomics(atomics),
        .data_base(data_base),
        .weight_base(weight_base),
        .input_width(input_width),
        .input_height(input_height),
        .input_channels(input_channels),
        .kernel_width(kernel_width),
        .kernel_height(kernel_height),
        .stride_x(stride_x),
        .stride_y(stride_y),
        .output_width(output_width),
        .output_height(output_height),
        .output_channels(output_channels),
        .data_cbuf_rd_en(data_cbuf_rd_en),
        .data_cbuf_rd_bank_en(data_cbuf_rd_bank_en),
        .data_cbuf_rd_bank_addr(data_cbuf_rd_bank_addr),
        .data_cbuf_rd_valid(data_cbuf_rd_valid),
        .data_cbuf_rd_data(data_cbuf_rd_data),
        .weight_cbuf_rd_en(weight_cbuf_rd_en),
        .weight_cbuf_rd_bank_en(weight_cbuf_rd_bank_en),
        .weight_cbuf_rd_bank_addr(weight_cbuf_rd_bank_addr),
        .weight_cbuf_rd_valid(weight_cbuf_rd_valid),
        .weight_cbuf_rd_data(weight_cbuf_rd_data),
        .maccell_ready(maccell_ready),
        .maccell_in_valid(maccell_in_valid),
        .maccell_valid_mask(maccell_valid_mask),
        .maccell_data(maccell_data),
        .maccell_weight(maccell_weight),
        .maccell_acc_clear(maccell_acc_clear),
        .maccell_acc_last(maccell_acc_last),
        .maccell_tag(maccell_tag)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    function [7:0] data_value;
        input integer bank;
        input integer pack;
        input integer addr;
        begin
            data_value = 8'h80 |
                         ((addr & 3) << 5) |
                         ((bank & 7) << 2) |
                         (pack & 3);
        end
    endfunction

    function [7:0] weight_value;
        input integer bank;
        input integer pack;
        input integer addr;
        begin
            weight_value = 8'h40 |
                           ((addr & 3) << 5) |
                           ((bank & 7) << 2) |
                           (pack & 3);
        end
    endfunction

    function integer elem_bank;
        input integer elem;
        begin
            elem_bank = elem % BANK_NUM;
        end
    endfunction

    function integer elem_pack;
        input integer elem;
        begin
            elem_pack = (elem / BANK_NUM) % MACLANE_NUM;
        end
    endfunction

    function integer elem_addr;
        input integer elem;
        begin
            elem_addr = elem / (BANK_NUM * MACLANE_NUM);
        end
    endfunction

    task check_read;
        input integer packet_idx;
        integer data_start;
        integer weight_start;
        integer elem;
        integer bank;
        integer exp_addr;
        integer got_addr;
        reg [BANK_NUM-1:0] exp_data_en;
        reg [BANK_NUM-1:0] exp_weight_en;
        begin
            data_start = DATA_BASE_ELEM + packet_idx * MACLANE_NUM;
            weight_start = WEIGHT_BASE_ELEM + packet_idx * WEIGHT_PACKET_ELEMENTS;
            exp_data_en = 8'h00;
            exp_weight_en = 8'h00;

            for (elem = 0; elem < MACLANE_NUM; elem = elem + 1) begin
                exp_data_en[elem_bank(data_start + elem)] = 1'b1;
            end

            for (elem = 0; elem < WEIGHT_PACKET_ELEMENTS; elem = elem + 1) begin
                exp_weight_en[elem_bank(weight_start + elem)] = 1'b1;
            end

            if (data_cbuf_rd_bank_en !== exp_data_en) begin
                $display("ERROR data bank_en packet=%0d got=0x%0h exp=0x%0h",
                         packet_idx, data_cbuf_rd_bank_en, exp_data_en);
                errors = errors + 1;
            end

            if (weight_cbuf_rd_bank_en !== exp_weight_en) begin
                $display("ERROR weight bank_en packet=%0d got=0x%0h exp=0x%0h",
                         packet_idx, weight_cbuf_rd_bank_en, exp_weight_en);
                errors = errors + 1;
            end

            for (elem = 0; elem < MACLANE_NUM; elem = elem + 1) begin
                bank = elem_bank(data_start + elem);
                exp_addr = elem_addr(data_start + elem);
                got_addr = data_cbuf_rd_bank_addr[(bank*BANK_ADDR_WIDTH)+:BANK_ADDR_WIDTH];
                if (got_addr != exp_addr) begin
                    $display("ERROR data addr packet=%0d elem=%0d bank=%0d got=%0d exp=%0d",
                             packet_idx, elem, bank, got_addr, exp_addr);
                    errors = errors + 1;
                end
            end

            for (elem = 0; elem < WEIGHT_PACKET_ELEMENTS; elem = elem + 1) begin
                bank = elem_bank(weight_start + elem);
                exp_addr = elem_addr(weight_start + elem);
                got_addr = weight_cbuf_rd_bank_addr[(bank*BANK_ADDR_WIDTH)+:BANK_ADDR_WIDTH];
                if (got_addr != exp_addr) begin
                    $display("ERROR weight addr packet=%0d elem=%0d bank=%0d got=%0d exp=%0d",
                             packet_idx, elem, bank, got_addr, exp_addr);
                    errors = errors + 1;
                end
            end
        end
    endtask

    task check_output;
        input integer packet_idx;
        integer data_start;
        integer weight_start;
        integer data_elem;
        integer weight_elem;
        integer cell_idx;
        integer lane_idx;
        integer bank;
        integer pack;
        integer addr;
        reg [7:0] got;
        reg [7:0] exp;
        begin
            data_start = DATA_BASE_ELEM + packet_idx * MACLANE_NUM;
            weight_start = WEIGHT_BASE_ELEM + packet_idx * WEIGHT_PACKET_ELEMENTS;

            if (maccell_valid_mask !== 8'hff) begin
                $display("ERROR valid_mask packet=%0d got=0x%0h", packet_idx, maccell_valid_mask);
                errors = errors + 1;
            end

            if (maccell_acc_clear !== (packet_idx == 0)) begin
                $display("ERROR acc_clear packet=%0d got=%0b", packet_idx, maccell_acc_clear);
                errors = errors + 1;
            end

            if (maccell_acc_last !== (packet_idx == (EXPECTED_PACKETS - 1))) begin
                $display("ERROR acc_last packet=%0d got=%0b", packet_idx, maccell_acc_last);
                errors = errors + 1;
            end

            for (cell_idx = 0; cell_idx < MACCELL_NUM; cell_idx = cell_idx + 1) begin
                for (lane_idx = 0; lane_idx < MACLANE_NUM; lane_idx = lane_idx + 1) begin
                    data_elem = data_start + lane_idx;
                    bank = elem_bank(data_elem);
                    pack = elem_pack(data_elem);
                    addr = elem_addr(data_elem);
                    exp = data_value(bank, pack, addr);
                    got = maccell_data[((cell_idx*MACLANE_NUM + lane_idx)*ELEMENT_WIDTH)+:ELEMENT_WIDTH];
                    if (got !== exp) begin
                        $display("ERROR data packet=%0d cell=%0d lane=%0d got=0x%0h exp=0x%0h",
                                 packet_idx, cell_idx, lane_idx, got, exp);
                        errors = errors + 1;
                    end

                    weight_elem = weight_start + cell_idx * MACLANE_NUM + lane_idx;
                    bank = elem_bank(weight_elem);
                    pack = elem_pack(weight_elem);
                    addr = elem_addr(weight_elem);
                    exp = weight_value(bank, pack, addr);
                    got = maccell_weight[((cell_idx*MACLANE_NUM + lane_idx)*ELEMENT_WIDTH)+:ELEMENT_WIDTH];
                    if (got !== exp) begin
                        $display("ERROR weight packet=%0d cell=%0d lane=%0d got=0x%0h exp=0x%0h",
                                 packet_idx, cell_idx, lane_idx, got, exp);
                        errors = errors + 1;
                    end
                end
            end

            $display("packet %0d maclane mapping checked", packet_idx);
        end
    endtask

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            data_cbuf_rd_valid <= 1'b0;
            weight_cbuf_rd_valid <= 1'b0;
            data_cbuf_rd_data <= {CBUF_RD_WIDTH{1'b0}};
            weight_cbuf_rd_data <= {CBUF_RD_WIDTH{1'b0}};
        end else begin
            data_cbuf_rd_valid <= data_cbuf_rd_en;
            weight_cbuf_rd_valid <= weight_cbuf_rd_en;

            if (data_cbuf_rd_en) begin
                for (bank_i = 0; bank_i < BANK_NUM; bank_i = bank_i + 1) begin
                    addr_i = data_cbuf_rd_bank_addr[(bank_i*BANK_ADDR_WIDTH)+:BANK_ADDR_WIDTH];
                    for (pack_i = 0; pack_i < MACLANE_NUM; pack_i = pack_i + 1) begin
                        data_cbuf_rd_data[((bank_i*MACLANE_NUM + pack_i)*ELEMENT_WIDTH)+:ELEMENT_WIDTH]
                            <= data_value(bank_i, pack_i, addr_i);
                    end
                end
            end

            if (weight_cbuf_rd_en) begin
                for (bank_i = 0; bank_i < BANK_NUM; bank_i = bank_i + 1) begin
                    addr_i = weight_cbuf_rd_bank_addr[(bank_i*BANK_ADDR_WIDTH)+:BANK_ADDR_WIDTH];
                    for (pack_i = 0; pack_i < MACLANE_NUM; pack_i = pack_i + 1) begin
                        weight_cbuf_rd_data[((bank_i*MACLANE_NUM + pack_i)*ELEMENT_WIDTH)+:ELEMENT_WIDTH]
                            <= weight_value(bank_i, pack_i, addr_i);
                    end
                end
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            read_seen <= 0;
            outputs_seen <= 0;
            done_seen <= 1'b0;
        end else begin
            if (data_cbuf_rd_en) begin
                if (read_seen < EXPECTED_PACKETS) begin
                    check_read(read_seen);
                end else begin
                    $display("ERROR unexpected extra read index=%0d", read_seen);
                    errors = errors + 1;
                end
                read_seen <= read_seen + 1;
            end

            if (maccell_in_valid) begin
                if (outputs_seen < EXPECTED_PACKETS) begin
                    check_output(outputs_seen);
                end else begin
                    $display("ERROR unexpected extra output index=%0d", outputs_seen);
                    errors = errors + 1;
                end
                outputs_seen <= outputs_seen + 1;
            end

            if (op_done) begin
                done_seen <= 1'b1;
            end
        end
    end

    initial begin
        errors = 0;
        op_enable = 1'b0;
        op_start = 1'b0;
        rst_n = 1'b0;
        atomics = {LEN_WIDTH{1'b0}};
        data_base = DATA_BASE_ELEM;
        weight_base = WEIGHT_BASE_ELEM;
        input_width = 1;
        input_height = 1;
        input_channels = 8;
        kernel_width = 1;
        kernel_height = 1;
        stride_x = 1;
        stride_y = 1;
        output_width = 1;
        output_height = 1;
        output_channels = 8;
        maccell_ready = 1'b1;

        repeat (5) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        @(negedge clk);
        op_enable = 1'b1;
        timeout = 0;
        while (!op_ready && timeout < 50) begin
            timeout = timeout + 1;
            @(posedge clk);
        end

        if (!op_ready) begin
            $display("ERROR op_ready was not asserted");
            errors = errors + 1;
        end

        @(negedge clk);
        op_start = 1'b1;
        @(negedge clk);
        op_start = 1'b0;
        op_enable = 1'b0;

        repeat (200) @(posedge clk);

        if (read_seen != EXPECTED_PACKETS) begin
            $display("ERROR read count got=%0d exp=%0d", read_seen, EXPECTED_PACKETS);
            errors = errors + 1;
        end

        if (outputs_seen != EXPECTED_PACKETS) begin
            $display("ERROR output count got=%0d exp=%0d", outputs_seen, EXPECTED_PACKETS);
            errors = errors + 1;
        end

        if (!done_seen) begin
            $display("ERROR done was not observed");
            errors = errors + 1;
        end

        if (op_error) begin
            $display("ERROR csc error asserted");
            errors = errors + 1;
        end

        if (errors == 0) begin
            $display("CSC_MACLANE_MAPPING_TEST_PASS");
        end else begin
            $display("CSC_MACLANE_MAPPING_TEST_FAIL errors=%0d", errors);
        end

        $finish;
    end
endmodule
