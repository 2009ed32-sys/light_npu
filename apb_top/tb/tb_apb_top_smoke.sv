`timescale 1ns/1ps

module tb_apb_top_smoke;
    localparam integer ADDR_WIDTH      = 32;
    localparam integer APB_ADDR_WIDTH  = 32;
    localparam integer APB_DATA_WIDTH  = 32;
    localparam integer AXI_DATA_WIDTH  = 32;
    localparam integer CBUF_WORD_WIDTH = 32;
    localparam integer LEN_WIDTH       = 32;
    localparam integer CBUF_ADDR_WIDTH = 16;
    localparam integer ELEMENT_WIDTH   = 8;
    localparam integer BANK_NUM        = 8;
    localparam integer MACCELL_NUM     = 8;
    localparam integer MACLANE_NUM     = 4;
    localparam integer CSC_TAG_WIDTH   = 32;

    localparam logic [APB_ADDR_WIDTH-1:0] REG_CDMA_CONTROL   = 32'h00;
    localparam logic [APB_ADDR_WIDTH-1:0] REG_CDMA_STATUS    = 32'h04;
    localparam logic [APB_ADDR_WIDTH-1:0] REG_DATA_WIDTH     = 32'h08;
    localparam logic [APB_ADDR_WIDTH-1:0] REG_DATA_HEIGHT    = 32'h0c;
    localparam logic [APB_ADDR_WIDTH-1:0] REG_DATA_CH        = 32'h10;
    localparam logic [APB_ADDR_WIDTH-1:0] REG_DATA_BASE      = 32'h14;
    localparam logic [APB_ADDR_WIDTH-1:0] REG_WEIGHT_WIDTH   = 32'h18;
    localparam logic [APB_ADDR_WIDTH-1:0] REG_WEIGHT_HEIGHT  = 32'h1c;
    localparam logic [APB_ADDR_WIDTH-1:0] REG_WEIGHT_CH      = 32'h20;
    localparam logic [APB_ADDR_WIDTH-1:0] REG_WEIGHT_BASE    = 32'h24;
    localparam logic [APB_ADDR_WIDTH-1:0] REG_CSC_CONTROL    = 32'h28;
    localparam logic [APB_ADDR_WIDTH-1:0] REG_CSC_STATUS     = 32'h2c;
    localparam logic [APB_ADDR_WIDTH-1:0] REG_CSC_ATOMICS    = 32'h30;
    localparam logic [APB_ADDR_WIDTH-1:0] REG_CSC_DATA_BASE  = 32'h34;
    localparam logic [APB_ADDR_WIDTH-1:0] REG_CSC_WEIGHT_BASE = 32'h38;
    localparam logic [APB_ADDR_WIDTH-1:0] REG_CSC_INPUT_WH   = 32'h3c;
    localparam logic [APB_ADDR_WIDTH-1:0] REG_CSC_INPUT_CH   = 32'h40;
    localparam logic [APB_ADDR_WIDTH-1:0] REG_CSC_KERNEL_WH  = 32'h44;
    localparam logic [APB_ADDR_WIDTH-1:0] REG_CSC_STRIDE_XY  = 32'h48;
    localparam logic [APB_ADDR_WIDTH-1:0] REG_CSC_OUTPUT_WH  = 32'h4c;
    localparam logic [APB_ADDR_WIDTH-1:0] REG_CSC_OUTPUT_CH  = 32'h50;
    localparam logic [APB_ADDR_WIDTH-1:0] REG_CACC_STATUS    = 32'h54;
    localparam logic [APB_ADDR_WIDTH-1:0] REG_CACC_OP_ENABLE = 32'h58;
    localparam logic [APB_ADDR_WIDTH-1:0] REG_CACC_SIZE_0    = 32'h5c;
    localparam logic [APB_ADDR_WIDTH-1:0] REG_CACC_SIZE_1    = 32'h60;
    localparam logic [APB_ADDR_WIDTH-1:0] REG_CACC_ADDR      = 32'h64;
    localparam logic [APB_ADDR_WIDTH-1:0] REG_CACC_LINE_STRIDE = 32'h68;
    localparam logic [APB_ADDR_WIDTH-1:0] REG_CACC_SURF_STRIDE = 32'h6c;
    localparam logic [APB_ADDR_WIDTH-1:0] REG_CACC_MAP       = 32'h70;

    localparam logic [APB_DATA_WIDTH-1:0] CDMA_DATA_START    = 32'h0000_0001;
    localparam logic [APB_DATA_WIDTH-1:0] CDMA_WEIGHT_START  = 32'h0000_0002;
    localparam logic [APB_DATA_WIDTH-1:0] CSC_ENABLE         = 32'h0000_0002;
    localparam logic [APB_DATA_WIDTH-1:0] CSC_ENABLE_START   = 32'h0000_0003;
    localparam logic [APB_DATA_WIDTH-1:0] CACC_ENABLE        = 32'h0000_0002;
    localparam logic [APB_DATA_WIDTH-1:0] CACC_ENABLE_START  = 32'h0000_0003;

    logic clk;
    logic rst_n;

    logic PSEL;
    logic PENABLE;
    logic PWRITE;
    logic [APB_ADDR_WIDTH-1:0] PADDR;
    logic [APB_DATA_WIDTH-1:0] PWDATA;
    logic [APB_DATA_WIDTH-1:0] PRDATA;
    logic PREADY;
    logic PSLVERR;

    logic axi_load_start;
    logic [ADDR_WIDTH-1:0] axi_txn_addr;
    logic axi_init_txn;
    logic axi_stream_valid;
    logic axi_stream_ready;
    logic [AXI_DATA_WIDTH-1:0] axi_stream_data;
    logic axi_txn_done;
    logic axi_error;
    logic axi_stream_sel;
    logic sdp_write_valid;
    logic sdp_write_ready;
    logic [ADDR_WIDTH-1:0] sdp_write_addr;
    logic [31:0] sdp_write_data;
    logic [3:0] sdp_write_strb;
    logic sdp_write_last;
    logic sdp_write_done;
    logic sdp_write_error;
    int sdp_write_count;

    integer errors;
    integer timeout;
    longint cycle_count;
    longint csc_start_cycle;

    apb_top #(
        .ADDR_WIDTH      (ADDR_WIDTH),
        .APB_ADDR_WIDTH  (APB_ADDR_WIDTH),
        .APB_DATA_WIDTH  (APB_DATA_WIDTH),
        .AXI_DATA_WIDTH  (AXI_DATA_WIDTH),
        .CBUF_WORD_WIDTH (CBUF_WORD_WIDTH),
        .LEN_WIDTH       (LEN_WIDTH),
        .CBUF_ADDR_WIDTH (CBUF_ADDR_WIDTH),
        .ELEMENT_WIDTH   (ELEMENT_WIDTH),
        .BANK_NUM        (BANK_NUM),
        .MACCELL_NUM     (MACCELL_NUM),
        .MACLANE_NUM     (MACLANE_NUM),
        .CSC_TAG_WIDTH   (CSC_TAG_WIDTH)
    ) dut (
        .PCLK             (clk),
        .PRESETn          (rst_n),
        .PSEL             (PSEL),
        .PENABLE          (PENABLE),
        .PWRITE           (PWRITE),
        .PADDR            (PADDR),
        .PWDATA           (PWDATA),
        .PRDATA           (PRDATA),
        .PREADY           (PREADY),
        .PSLVERR          (PSLVERR),
        .axi_load_start   (axi_load_start),
        .axi_txn_addr     (axi_txn_addr),
        .axi_init_txn     (axi_init_txn),
        .axi_stream_valid (axi_stream_valid),
        .axi_stream_ready (axi_stream_ready),
        .axi_stream_data  (axi_stream_data),
        .axi_txn_done     (axi_txn_done),
        .axi_error        (axi_error),
        .axi_stream_sel   (axi_stream_sel),
        .sdp_write_valid  (sdp_write_valid),
        .sdp_write_ready  (sdp_write_ready),
        .sdp_write_addr   (sdp_write_addr),
        .sdp_write_data   (sdp_write_data),
        .sdp_write_strb   (sdp_write_strb),
        .sdp_write_last   (sdp_write_last),
        .sdp_write_done   (sdp_write_done),
        .sdp_write_error  (sdp_write_error)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            cycle_count <= 0;
        end else begin
            cycle_count <= cycle_count + 1;
        end
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            sdp_write_ready <= 1'b0;
            sdp_write_done <= 1'b0;
            sdp_write_error <= 1'b0;
            sdp_write_count <= 0;
        end else begin
            sdp_write_ready <= 1'b1;
            sdp_write_done <= 1'b0;
            sdp_write_error <= 1'b0;

            if (sdp_write_valid && sdp_write_ready) begin
                $display("SDP write[%0d] addr=0x%08h data=0x%08h strb=0x%0h last=%0b",
                         sdp_write_count,
                         sdp_write_addr,
                         sdp_write_data,
                         sdp_write_strb,
                         sdp_write_last);
                sdp_write_count <= sdp_write_count + 1;
                if (sdp_write_last) begin
                    sdp_write_done <= 1'b1;
                end
            end
        end
    end

    function automatic logic [31:0] data_beat(input int word_idx);
        int elem_base;
        logic [7:0] lane0;
        logic [7:0] lane1;
        logic [7:0] lane2;
        logic [7:0] lane3;
        begin
            elem_base = (word_idx * 4) + 1;
            lane0 = elem_base[7:0] + 8'd0;
            lane1 = elem_base[7:0] + 8'd1;
            lane2 = elem_base[7:0] + 8'd2;
            lane3 = elem_base[7:0] + 8'd3;
            data_beat = {lane3, lane2, lane1, lane0};
        end
    endfunction

    function automatic logic [31:0] weight_beat(input int word_idx);
        int elem_base;
        logic [7:0] lane0;
        logic [7:0] lane1;
        logic [7:0] lane2;
        logic [7:0] lane3;
        begin
            elem_base = word_idx * 4;
            lane0 = 8'hA0 + elem_base[7:0] + 8'd0;
            lane1 = 8'hA0 + elem_base[7:0] + 8'd1;
            lane2 = 8'hA0 + elem_base[7:0] + 8'd2;
            lane3 = 8'hA0 + elem_base[7:0] + 8'd3;
            weight_beat = {lane3, lane2, lane1, lane0};
        end
    endfunction

    function automatic logic signed [ELEMENT_WIDTH-1:0] expected_data_elem(
        input int pixel_idx,
        input int lane_idx
    );
        begin
            expected_data_elem = ELEMENT_WIDTH'((pixel_idx * MACLANE_NUM) +
                                                lane_idx + 1);
        end
    endfunction

    function automatic logic signed [ELEMENT_WIDTH-1:0] expected_weight_elem(
        input int kernel_idx,
        input int cell_idx,
        input int lane_idx
    );
        int elem_idx;
        begin
            elem_idx = (kernel_idx * MACCELL_NUM * MACLANE_NUM) +
                       (cell_idx * MACLANE_NUM) +
                       lane_idx;
            expected_weight_elem = ELEMENT_WIDTH'(8'hA0 + elem_idx[7:0]);
        end
    endfunction

    function automatic logic signed [31:0] expected_cmac_psum(
        input int cell_idx,
        input int tag_value,
        input int input_width,
        input int output_width,
        input int kernel_width,
        input int kernel_height
    );
        logic signed [ELEMENT_WIDTH-1:0] data_lane;
        logic signed [ELEMENT_WIDTH-1:0] weight_lane;
        int out_x;
        int out_y;
        int input_x;
        int input_y;
        int input_pixel_idx;
        int kernel_idx;
        begin
            expected_cmac_psum = '0;
            out_x = tag_value % output_width;
            out_y = tag_value / output_width;

            for (int ky = 0; ky < kernel_height; ky = ky + 1) begin
                for (int kx = 0; kx < kernel_width; kx = kx + 1) begin
                    input_x = out_x + kx;
                    input_y = out_y + ky;
                    input_pixel_idx = (input_y * input_width) + input_x;
                    kernel_idx = (ky * kernel_width) + kx;

                    for (int lane_idx = 0; lane_idx < MACLANE_NUM; lane_idx = lane_idx + 1) begin
                        data_lane = expected_data_elem(input_pixel_idx, lane_idx);
                        weight_lane = expected_weight_elem(kernel_idx, cell_idx, lane_idx);
                        expected_cmac_psum =
                            expected_cmac_psum + (data_lane * weight_lane);
                    end
                end
            end
        end
    endfunction

    task automatic apb_write(
        input logic [APB_ADDR_WIDTH-1:0] addr,
        input logic [APB_DATA_WIDTH-1:0] data
    );
        begin
            @(negedge clk);
            PADDR   = addr;
            PWDATA  = data;
            PWRITE  = 1'b1;
            PSEL    = 1'b1;
            PENABLE = 1'b0;

            @(negedge clk);
            PENABLE = 1'b1;

            while (!PREADY) begin
                @(negedge clk);
            end

            @(posedge clk);
            if (PSLVERR) begin
                $display("ERROR APB write slave error addr=0x%08h data=0x%08h",
                         addr, data);
                errors = errors + 1;
            end

            @(negedge clk);
            PSEL    = 1'b0;
            PENABLE = 1'b0;
            PWRITE  = 1'b0;
            PADDR   = '0;
            PWDATA  = '0;
        end
    endtask

    task automatic apb_read(
        input  logic [APB_ADDR_WIDTH-1:0] addr,
        output logic [APB_DATA_WIDTH-1:0] data
    );
        begin
            @(negedge clk);
            PADDR   = addr;
            PWRITE  = 1'b0;
            PSEL    = 1'b1;
            PENABLE = 1'b0;

            @(negedge clk);
            PENABLE = 1'b1;

            while (!PREADY) begin
                @(negedge clk);
            end

            @(posedge clk);
            data = PRDATA;
            if (PSLVERR) begin
                $display("ERROR APB read slave error addr=0x%08h", addr);
                errors = errors + 1;
            end

            @(negedge clk);
            PSEL    = 1'b0;
            PENABLE = 1'b0;
            PADDR   = '0;
        end
    endtask

    task automatic expect_read(
        input logic [APB_ADDR_WIDTH-1:0] addr,
        input logic [APB_DATA_WIDTH-1:0] expected
    );
        logic [APB_DATA_WIDTH-1:0] got;
        begin
            apb_read(addr, got);
            if (got != expected) begin
                $display("ERROR APB read mismatch addr=0x%08h got=0x%08h expected=0x%08h",
                         addr, got, expected);
                errors = errors + 1;
            end
        end
    endtask

    task automatic wait_status_bit(
        input logic [APB_ADDR_WIDTH-1:0] addr,
        input logic [APB_DATA_WIDTH-1:0] mask,
        input string name
    );
        logic [APB_DATA_WIDTH-1:0] status;
        begin
            status = '0;
            timeout = 0;

            while (((status & mask) == '0) && timeout < 1000) begin
                apb_read(addr, status);
                timeout = timeout + 1;
                @(posedge clk);
            end

            if ((status & mask) == '0) begin
                $display("ERROR timeout waiting for %s status=0x%08h",
                         name, status);
                errors = errors + 1;
            end else begin
                $display("%s observed status=0x%08h", name, status);
            end
        end
    endtask

    task automatic wait_cmac_results(
        input longint start_cycle,
        input int expected_count,
        input int input_width,
        input int output_width,
        input int kernel_width,
        input int kernel_height,
        input string name
    );
        longint fire_cycle;
        longint psum_cycle;
        logic saw_fire;
        logic signed [31:0] psum0;
        logic signed [31:0] expected0;
        logic [MACCELL_NUM-1:0] expected_mask;
        logic [CSC_TAG_WIDTH-1:0] got_tag;
        int result_count;
        begin
            fire_cycle = -1;
            psum_cycle = -1;
            saw_fire = 1'b0;
            result_count = 0;
            expected_mask = {{(MACCELL_NUM-1){1'b0}}, 1'b1};
            timeout = 0;

            while ((result_count < expected_count) && timeout < 5000) begin
                @(posedge clk);
                #1;
                timeout = timeout + 1;

                if (!saw_fire &&
                    dut.u_convcore.csc_maccell_in_valid_w &&
                    dut.u_convcore.csc_maccell_ready_w) begin
                    saw_fire = 1'b1;
                    fire_cycle = cycle_count;
                    $display("CMAC input fire at cycle=%0d latency_from_csc_start=%0d cycles",
                             fire_cycle, fire_cycle - start_cycle);
                end

                if (dut.u_convcore.cmac_psum_valid_unused) begin
                    psum_cycle = cycle_count;
                    psum0 = dut.u_convcore.cmac_psum_data_unused[0 +: 32];
                    got_tag = dut.u_convcore.cmac_psum_tag_unused;
                    expected0 = expected_cmac_psum(
                        0,
                        int'(got_tag),
                        input_width,
                        output_width,
                        kernel_width,
                        kernel_height
                    );
                    $display("CMAC psum valid at cycle=%0d latency_from_csc_start=%0d cycles latency_from_input_fire=%0d cycles",
                             psum_cycle, psum_cycle - start_cycle,
                             saw_fire ? (psum_cycle - fire_cycle) : -1);
                    $display("%s CMAC result[%0d] tag=0x%08h mask=0x%0h psum0=0x%08h expected0=0x%08h",
                             name,
                             result_count,
                             got_tag,
                             dut.u_convcore.cmac_psum_valid_mask_unused,
                             psum0, expected0);

                    if (dut.u_convcore.cmac_psum_valid_mask_unused != expected_mask) begin
                        $display("ERROR CMAC valid mask mismatch got=0x%0h expected=0x%0h",
                                 dut.u_convcore.cmac_psum_valid_mask_unused,
                                 expected_mask);
                        errors = errors + 1;
                    end

                    if (psum0 !== expected0) begin
                        $display("ERROR CMAC psum mismatch got=0x%08h expected=0x%08h",
                                 psum0, expected0);
                        errors = errors + 1;
                    end

                    if (got_tag !== CSC_TAG_WIDTH'(result_count)) begin
                        $display("ERROR CMAC tag mismatch got=0x%08h expected=0x%08h",
                                 got_tag, CSC_TAG_WIDTH'(result_count));
                        errors = errors + 1;
                    end

                    result_count = result_count + 1;
                end
            end

            if (!saw_fire) begin
                $display("ERROR CMAC input handshake was not observed");
                errors = errors + 1;
            end

            if (result_count != expected_count) begin
                $display("ERROR timeout waiting for CMAC psum outputs got=%0d expected=%0d",
                         result_count, expected_count);
                errors = errors + 1;
            end
        end
    endtask

    task automatic drive_bursts(input int burst_count);
        int beat_idx;
        int burst_idx;
        int unsigned base_word;
        logic sel;
        begin
            for (burst_idx = 0; burst_idx < burst_count; burst_idx = burst_idx + 1) begin
                @(posedge axi_init_txn);
                sel = axi_stream_sel;
                base_word = axi_txn_addr >> 2;
                $display("AXI burst start %0d/%0d sel=%0d addr=0x%08h base_word=%0d beats=8",
                         burst_idx + 1, burst_count, sel, axi_txn_addr, base_word);

                @(posedge clk);
                for (beat_idx = 0; beat_idx < 8; beat_idx = beat_idx + 1) begin
                    @(negedge clk);
                    axi_stream_data =
                        sel ? weight_beat(base_word + beat_idx) :
                              data_beat(base_word + beat_idx);
                    axi_stream_valid = 1'b1;

                    while (!axi_stream_ready) begin
                        @(negedge clk);
                    end

                    @(negedge clk);
                    axi_stream_valid = 1'b0;
                end

                @(negedge clk);
                axi_txn_done = 1'b1;
                @(negedge clk);
                axi_txn_done = 1'b0;
            end
        end
    endtask

    initial begin
        errors = 0;
        rst_n = 1'b0;

        PSEL = 1'b0;
        PENABLE = 1'b0;
        PWRITE = 1'b0;
        PADDR = '0;
        PWDATA = '0;

        axi_stream_valid = 1'b0;
        axi_stream_data = '0;
        axi_txn_done = 1'b0;
        axi_error = 1'b0;

        repeat (8) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;
        repeat (4) @(posedge clk);

        apb_write(REG_CDMA_CONTROL, 32'h0000_0000);
        apb_write(REG_CSC_CONTROL, 32'h0000_0000);

        apb_write(REG_DATA_WIDTH, 32'd1);
        apb_write(REG_DATA_HEIGHT, 32'd1);
        apb_write(REG_DATA_CH, 32'd4);
        apb_write(REG_DATA_BASE, 32'd0);
        apb_write(REG_WEIGHT_WIDTH, 32'd8);
        apb_write(REG_WEIGHT_HEIGHT, 32'd1);
        apb_write(REG_WEIGHT_CH, 32'd4);
        apb_write(REG_WEIGHT_BASE, 32'd0);

        expect_read(REG_DATA_WIDTH, 32'd1);
        expect_read(REG_WEIGHT_WIDTH, 32'd8);

        fork
            drive_bursts(1);
            begin
                apb_write(REG_CDMA_CONTROL, CDMA_DATA_START);
                apb_write(REG_CDMA_CONTROL, 32'h0000_0000);
                wait_status_bit(REG_CDMA_STATUS, 32'h0000_0002, "DATA done");
            end
        join

        repeat (4) @(posedge clk);

        fork
            drive_bursts(1);
            begin
                apb_write(REG_CDMA_CONTROL, CDMA_WEIGHT_START);
                apb_write(REG_CDMA_CONTROL, 32'h0000_0000);
                wait_status_bit(REG_CDMA_STATUS, 32'h0000_0010, "WEIGHT done");
            end
        join

        repeat (8) @(posedge clk);

        apb_write(REG_CSC_ATOMICS, 32'd1);
        apb_write(REG_CSC_DATA_BASE, 32'd0);
        apb_write(REG_CSC_WEIGHT_BASE, 32'd0);
        apb_write(REG_CSC_INPUT_WH, {16'd1, 16'd1});
        apb_write(REG_CSC_INPUT_CH, 32'd4);
        apb_write(REG_CSC_KERNEL_WH, {16'd1, 16'd1});
        apb_write(REG_CSC_STRIDE_XY, {16'd1, 16'd1});
        apb_write(REG_CSC_OUTPUT_WH, {16'd1, 16'd1});
        apb_write(REG_CSC_OUTPUT_CH, 32'd1);
        apb_write(REG_CACC_SIZE_0, {16'd1, 16'd1});
        apb_write(REG_CACC_SIZE_1, 32'd1);
        apb_write(REG_CACC_ADDR, 32'd0);
        apb_write(REG_CACC_LINE_STRIDE, 32'd1);
        apb_write(REG_CACC_SURF_STRIDE, 32'd1);
        apb_write(REG_CACC_MAP, 32'd0);

        expect_read(REG_CSC_ATOMICS, 32'd1);
        expect_read(REG_CSC_OUTPUT_CH, 32'd1);

        apb_write(REG_CACC_OP_ENABLE, CACC_ENABLE);
        wait_status_bit(REG_CACC_STATUS, 32'h0000_0001, "CACC ready");
        apb_write(REG_CSC_CONTROL, CSC_ENABLE);
        wait_status_bit(REG_CSC_STATUS, 32'h0000_0001, "CSC ready");

        csc_start_cycle = cycle_count;
        fork
            wait_cmac_results(csc_start_cycle, 1, 1, 1, 1, 1, "1x1/1x1");
            begin
                apb_write(REG_CACC_OP_ENABLE, CACC_ENABLE_START);
                apb_write(REG_CSC_CONTROL, CSC_ENABLE_START);
                wait_status_bit(REG_CSC_STATUS, 32'h0000_0004, "CSC done");
                wait_status_bit(REG_CACC_STATUS, 32'h0000_0004, "CACC/SDP done");
            end
        join

        apb_write(REG_CSC_CONTROL, 32'h0000_0000);
        apb_write(REG_CACC_OP_ENABLE, 32'h0000_0000);
        repeat (8) @(posedge clk);

        $display("Starting extended CMAC test: input=5x5 kernel=3x3 channels=4 outputs=3x3");

        apb_write(REG_DATA_WIDTH, 32'd5);
        apb_write(REG_DATA_HEIGHT, 32'd5);
        apb_write(REG_DATA_CH, 32'd4);
        apb_write(REG_DATA_BASE, 32'd0);
        apb_write(REG_WEIGHT_WIDTH, 32'd72);
        apb_write(REG_WEIGHT_HEIGHT, 32'd1);
        apb_write(REG_WEIGHT_CH, 32'd4);
        apb_write(REG_WEIGHT_BASE, 32'd0);

        expect_read(REG_DATA_WIDTH, 32'd5);
        expect_read(REG_WEIGHT_WIDTH, 32'd72);

        fork
            drive_bursts(4);
            begin
                apb_write(REG_CDMA_CONTROL, CDMA_DATA_START);
                apb_write(REG_CDMA_CONTROL, 32'h0000_0000);
                wait_status_bit(REG_CDMA_STATUS, 32'h0000_0002, "DATA 5x5 done");
            end
        join

        repeat (4) @(posedge clk);

        fork
            drive_bursts(9);
            begin
                apb_write(REG_CDMA_CONTROL, CDMA_WEIGHT_START);
                apb_write(REG_CDMA_CONTROL, 32'h0000_0000);
                wait_status_bit(REG_CDMA_STATUS, 32'h0000_0010, "WEIGHT 3x3 done");
            end
        join

        repeat (8) @(posedge clk);

        apb_write(REG_CSC_ATOMICS, 32'd81);
        apb_write(REG_CSC_DATA_BASE, 32'd0);
        apb_write(REG_CSC_WEIGHT_BASE, 32'd0);
        apb_write(REG_CSC_INPUT_WH, {16'd5, 16'd5});
        apb_write(REG_CSC_INPUT_CH, 32'd4);
        apb_write(REG_CSC_KERNEL_WH, {16'd3, 16'd3});
        apb_write(REG_CSC_STRIDE_XY, {16'd1, 16'd1});
        apb_write(REG_CSC_OUTPUT_WH, {16'd3, 16'd3});
        apb_write(REG_CSC_OUTPUT_CH, 32'd1);
        apb_write(REG_CACC_SIZE_0, {16'd3, 16'd3});
        apb_write(REG_CACC_SIZE_1, 32'd1);
        apb_write(REG_CACC_ADDR, 32'd0);
        apb_write(REG_CACC_LINE_STRIDE, 32'd3);
        apb_write(REG_CACC_SURF_STRIDE, 32'd9);
        apb_write(REG_CACC_MAP, 32'd0);

        expect_read(REG_CSC_ATOMICS, 32'd81);
        expect_read(REG_CSC_OUTPUT_CH, 32'd1);

        apb_write(REG_CACC_OP_ENABLE, CACC_ENABLE);
        wait_status_bit(REG_CACC_STATUS, 32'h0000_0001, "CACC 5x5/3x3 ready");
        apb_write(REG_CSC_CONTROL, CSC_ENABLE);
        wait_status_bit(REG_CSC_STATUS, 32'h0000_0001, "CSC 5x5/3x3 ready");

        csc_start_cycle = cycle_count;
        fork
            wait_cmac_results(csc_start_cycle, 9, 5, 3, 3, 3, "5x5/3x3");
            begin
                apb_write(REG_CACC_OP_ENABLE, CACC_ENABLE_START);
                apb_write(REG_CSC_CONTROL, CSC_ENABLE_START);
                wait_status_bit(REG_CSC_STATUS, 32'h0000_0004, "CSC 5x5/3x3 done");
                wait_status_bit(REG_CACC_STATUS, 32'h0000_0004, "CACC/SDP 5x5/3x3 done");
            end
        join

        if (errors == 0) begin
            $display("APB_TOP_SMOKE_TEST_PASS");
        end else begin
            $display("APB_TOP_SMOKE_TEST_FAIL errors=%0d", errors);
        end

        $finish;
    end

    initial begin
        #50000;
        $fatal(1, "APB top smoke test timeout");
    end
endmodule
