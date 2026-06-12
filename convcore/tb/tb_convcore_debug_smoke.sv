module tb_convcore_debug_smoke;
    localparam integer ADDR_WIDTH      = 32;
    localparam integer AXI_DATA_WIDTH  = 32;
    localparam integer CBUF_WORD_WIDTH = 32;
    localparam integer LEN_WIDTH       = 32;
    localparam integer CBUF_ADDR_WIDTH = 16;
    localparam integer CSB_DATA_WIDTH  = 32;
    localparam integer CSB_ADDR_WIDTH  = 7;
    localparam integer ELEMENT_WIDTH   = 8;
    localparam integer BANK_NUM        = 8;
    localparam integer MACCELL_NUM     = 8;
    localparam integer MACLANE_NUM     = 4;
    localparam integer DEBUG_TAG_WIDTH = 32;
    localparam integer DEBUG_SELECT_WIDTH = 3;
    localparam integer DEBUG_LANE_WIDTH = MACLANE_NUM * ELEMENT_WIDTH;
    localparam integer DEBUG_CONTROL_WIDTH = 8;
    localparam integer DEBUG_EXPECTED_PACKET_WIDTH =
        (2 * DEBUG_LANE_WIDTH) + DEBUG_TAG_WIDTH + DEBUG_SELECT_WIDTH + 4;
    localparam integer DEBUG_STATUS_PACKET_BASE_WIDTH =
        129 + DEBUG_TAG_WIDTH + (2 * MACCELL_NUM) + (2 * DEBUG_LANE_WIDTH);
    localparam integer DEBUG_STATUS_PACKET_WIDTH =
        (((DEBUG_STATUS_PACKET_BASE_WIDTH + 31) / 32) * 32) + 32;

    localparam integer DBG_CTRL_ENABLE_BIT = 0;
    localparam integer DBG_CTRL_CLEAR_BIT = 1;
    localparam integer DBG_CTRL_IRQ_ENABLE_BIT = 2;
    localparam integer DBG_CTRL_HOLD_ENABLE_BIT = 3;
    localparam integer DBG_CTRL_COMPARE_ENABLE_BIT = 4;
    localparam integer DBG_CTRL_CONTINUE_BIT = 5;
    localparam integer DBG_CTRL_COMPARE_STROBE_BIT = 6;

    localparam integer DBG_EXP_DATA_LSB = 0;
    localparam integer DBG_EXP_WEIGHT_LSB =
        DBG_EXP_DATA_LSB + DEBUG_LANE_WIDTH;
    localparam integer DBG_EXP_TAG_LSB =
        DBG_EXP_WEIGHT_LSB + DEBUG_LANE_WIDTH;
    localparam integer DBG_EXP_SELECT_LSB =
        DBG_EXP_TAG_LSB + DEBUG_TAG_WIDTH;
    localparam integer DBG_EXP_FLAGS_LSB =
        DBG_EXP_SELECT_LSB + DEBUG_SELECT_WIDTH;
    localparam integer DBG_EXP_VALID_BIT = DBG_EXP_FLAGS_LSB;
    localparam integer DBG_EXP_ACC_CLEAR_BIT = DBG_EXP_FLAGS_LSB + 1;
    localparam integer DBG_EXP_ACC_LAST_BIT = DBG_EXP_FLAGS_LSB + 2;

    localparam integer DBG_STAT_STATUS_LSB = 0;
    localparam integer DBG_STAT_IRQ_STATUS_LSB =
        DBG_STAT_STATUS_LSB + 32;
    localparam integer DBG_STAT_CHECKED_MASK_LSB =
        DBG_STAT_IRQ_STATUS_LSB + 32;
    localparam integer DBG_STAT_FAIL_MASK_LSB =
        DBG_STAT_CHECKED_MASK_LSB + MACCELL_NUM;
    localparam integer DBG_STAT_PACKET_INDEX_LSB =
        DBG_STAT_FAIL_MASK_LSB + MACCELL_NUM;
    localparam integer DBG_STAT_SNAPSHOT_TAG_LSB =
        DBG_STAT_PACKET_INDEX_LSB + 32;
    localparam integer DBG_STAT_SNAPSHOT_FLAGS_LSB =
        DBG_STAT_SNAPSHOT_TAG_LSB + DEBUG_TAG_WIDTH;
    localparam integer DBG_STAT_ACTUAL_DATA_LSB =
        DBG_STAT_SNAPSHOT_FLAGS_LSB + 32;
    localparam integer DBG_STAT_ACTUAL_WEIGHT_LSB =
        DBG_STAT_ACTUAL_DATA_LSB + DEBUG_LANE_WIDTH;
    localparam integer DBG_STAT_HOLD_BIT =
        DBG_STAT_ACTUAL_WEIGHT_LSB + DEBUG_LANE_WIDTH;
    localparam integer DBG_STAT_FAIL_BITMAP_LSB =
        ((DBG_STAT_HOLD_BIT + 1 + 31) / 32) * 32;

    localparam integer REG_CDMA_CONTROL = 7'h00;
    localparam integer REG_DATA_WIDTH   = 7'h08;
    localparam integer REG_DATA_HEIGHT  = 7'h0c;
    localparam integer REG_DATA_CH      = 7'h10;
    localparam integer REG_DATA_BASE    = 7'h14;
    localparam integer REG_WEIGHT_WIDTH = 7'h18;
    localparam integer REG_WEIGHT_HEIGHT = 7'h1c;
    localparam integer REG_WEIGHT_CH    = 7'h20;
    localparam integer REG_WEIGHT_BASE  = 7'h24;
    localparam integer REG_CSC_CONTROL  = 7'h28;
    localparam integer REG_CSC_ATOMICS  = 7'h30;
    localparam integer REG_CSC_DATA_BASE = 7'h34;
    localparam integer REG_CSC_WEIGHT_BASE = 7'h38;
    localparam integer REG_CSC_INPUT_WH = 7'h3c;
    localparam integer REG_CSC_INPUT_CH = 7'h40;
    localparam integer REG_CSC_KERNEL_WH = 7'h44;
    localparam integer REG_CSC_STRIDE_XY = 7'h48;
    localparam integer REG_CSC_OUTPUT_WH = 7'h4c;
    localparam integer REG_CSC_OUTPUT_CH = 7'h50;

    reg clk;
    reg rst_n;

    reg [CSB_ADDR_WIDTH-1:0] s00_axi_awaddr;
    reg [2:0] s00_axi_awprot;
    reg s00_axi_awvalid;
    wire s00_axi_awready;
    reg [CSB_DATA_WIDTH-1:0] s00_axi_wdata;
    reg [(CSB_DATA_WIDTH/8)-1:0] s00_axi_wstrb;
    reg s00_axi_wvalid;
    wire s00_axi_wready;
    wire [1:0] s00_axi_bresp;
    wire s00_axi_bvalid;
    reg s00_axi_bready;
    reg [CSB_ADDR_WIDTH-1:0] s00_axi_araddr;
    reg [2:0] s00_axi_arprot;
    reg s00_axi_arvalid;
    wire s00_axi_arready;
    wire [CSB_DATA_WIDTH-1:0] s00_axi_rdata;
    wire [1:0] s00_axi_rresp;
    wire s00_axi_rvalid;
    reg s00_axi_rready;

    wire axi_load_start;
    wire [ADDR_WIDTH-1:0] axi_txn_addr;
    wire axi_init_txn;
    reg axi_stream_valid;
    wire axi_stream_ready;
    reg [AXI_DATA_WIDTH-1:0] axi_stream_data;
    reg axi_txn_done;
    reg axi_error;
    wire axi_stream_sel;

    reg [DEBUG_CONTROL_WIDTH-1:0] debug_control_packet;
    reg [DEBUG_EXPECTED_PACKET_WIDTH-1:0] debug_expected_packet;
    wire [DEBUG_STATUS_PACKET_WIDTH-1:0] debug_status_packet;
    wire debug_irq;

    integer errors;
    integer timeout;

    convcore #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .CBUF_WORD_WIDTH(CBUF_WORD_WIDTH),
        .LEN_WIDTH(LEN_WIDTH),
        .CBUF_ADDR_WIDTH(CBUF_ADDR_WIDTH),
        .CSB_DATA_WIDTH(CSB_DATA_WIDTH),
        .CSB_ADDR_WIDTH(CSB_ADDR_WIDTH),
        .ELEMENT_WIDTH(ELEMENT_WIDTH),
        .BANK_NUM(BANK_NUM),
        .MACCELL_NUM(MACCELL_NUM),
        .MACLANE_NUM(MACLANE_NUM),
        .DEBUG_TAG_WIDTH(DEBUG_TAG_WIDTH),
        .DEBUG_SELECT_WIDTH(DEBUG_SELECT_WIDTH),
        .DEBUG_LANE_WIDTH(DEBUG_LANE_WIDTH),
        .DEBUG_CONTROL_WIDTH(DEBUG_CONTROL_WIDTH),
        .DEBUG_EXPECTED_PACKET_WIDTH(DEBUG_EXPECTED_PACKET_WIDTH),
        .DEBUG_STATUS_PACKET_WIDTH(DEBUG_STATUS_PACKET_WIDTH)
    ) dut (
        .s00_axi_aclk(clk),
        .s00_axi_aresetn(rst_n),
        .s00_axi_awaddr(s00_axi_awaddr),
        .s00_axi_awprot(s00_axi_awprot),
        .s00_axi_awvalid(s00_axi_awvalid),
        .s00_axi_awready(s00_axi_awready),
        .s00_axi_wdata(s00_axi_wdata),
        .s00_axi_wstrb(s00_axi_wstrb),
        .s00_axi_wvalid(s00_axi_wvalid),
        .s00_axi_wready(s00_axi_wready),
        .s00_axi_bresp(s00_axi_bresp),
        .s00_axi_bvalid(s00_axi_bvalid),
        .s00_axi_bready(s00_axi_bready),
        .s00_axi_araddr(s00_axi_araddr),
        .s00_axi_arprot(s00_axi_arprot),
        .s00_axi_arvalid(s00_axi_arvalid),
        .s00_axi_arready(s00_axi_arready),
        .s00_axi_rdata(s00_axi_rdata),
        .s00_axi_rresp(s00_axi_rresp),
        .s00_axi_rvalid(s00_axi_rvalid),
        .s00_axi_rready(s00_axi_rready),
        .axi_load_start(axi_load_start),
        .axi_txn_addr(axi_txn_addr),
        .axi_init_txn(axi_init_txn),
        .axi_stream_valid(axi_stream_valid),
        .axi_stream_ready(axi_stream_ready),
        .axi_stream_data(axi_stream_data),
        .axi_txn_done(axi_txn_done),
        .axi_error(axi_error),
        .axi_stream_sel(axi_stream_sel),
        .debug_control_packet(debug_control_packet),
        .debug_expected_packet(debug_expected_packet),
        .debug_status_packet(debug_status_packet),
        .debug_irq(debug_irq)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    function [31:0] data_beat;
        begin
            data_beat = 32'h04030201;
        end
    endfunction

    function [31:0] weight_beat;
        input integer beat_idx;
        integer elem_base;
        reg [7:0] lane0;
        reg [7:0] lane1;
        reg [7:0] lane2;
        reg [7:0] lane3;
        begin
            elem_base = beat_idx * 4;
            lane0 = 8'hA0 + elem_base[7:0] + 8'd0;
            lane1 = 8'hA0 + elem_base[7:0] + 8'd1;
            lane2 = 8'hA0 + elem_base[7:0] + 8'd2;
            lane3 = 8'hA0 + elem_base[7:0] + 8'd3;
            weight_beat = {lane3, lane2, lane1, lane0};
        end
    endfunction

    task axi_lite_write;
        input [CSB_ADDR_WIDTH-1:0] addr;
        input [CSB_DATA_WIDTH-1:0] data;
        begin
            @(negedge clk);
            s00_axi_awaddr  = addr;
            s00_axi_wdata   = data;
            s00_axi_awvalid = 1'b1;
            s00_axi_wvalid  = 1'b1;
            s00_axi_bready  = 1'b1;

            while (!(s00_axi_awready && s00_axi_wready)) begin
                @(negedge clk);
            end

            @(negedge clk);
            s00_axi_awvalid = 1'b0;
            s00_axi_wvalid  = 1'b0;

            while (!s00_axi_bvalid) begin
                @(negedge clk);
            end

            @(negedge clk);
            s00_axi_bready = 1'b0;
        end
    endtask

    task wait_data_done;
        begin
            timeout = 0;
            while (!dut.u_cdma.u_cdma_core.data_done && timeout < 500) begin
                timeout = timeout + 1;
                @(posedge clk);
            end

            if (!dut.u_cdma.u_cdma_core.data_done) begin
                $display("ERROR timeout: data CDMA did not complete");
                errors = errors + 1;
            end
        end
    endtask

    task wait_weight_done;
        begin
            timeout = 0;
            while (!dut.u_cdma.u_cdma_core.weight_done && timeout < 500) begin
                timeout = timeout + 1;
                @(posedge clk);
            end

            if (!dut.u_cdma.u_cdma_core.weight_done) begin
                $display("ERROR timeout: weight CDMA did not complete");
                errors = errors + 1;
            end
        end
    endtask

    task wait_debug_snapshot;
        begin
            timeout = 0;
            while (!debug_status_packet[0] && timeout < 500) begin
                timeout = timeout + 1;
                @(posedge clk);
            end

            if (!debug_status_packet[0]) begin
                $display("ERROR timeout: debug snapshot was not captured");
                errors = errors + 1;
            end
        end
    endtask

    task wait_csc_ready;
        reg [31:0] csc_status;
        begin
            timeout = 0;
            csc_status = 32'b0;
            while (!dut.csc_status_w[0] && timeout < 500) begin
                timeout = timeout + 1;
                @(posedge clk);
            end

            if (!dut.csc_status_w[0]) begin
                $display("ERROR timeout: CSC ready was not asserted");
                errors = errors + 1;
            end
        end
    endtask

    task drive_burst;
        integer beat_count;
        integer beat_idx;
        reg sel;
        begin
            @(posedge axi_init_txn);
            sel = axi_stream_sel;
            beat_count = 8;
            $display("AXI burst start sel=%0d addr=0x%08h beats=%0d",
                     sel, axi_txn_addr, beat_count);

            @(posedge clk);
            for (beat_idx = 0; beat_idx < beat_count; beat_idx = beat_idx + 1) begin
                @(negedge clk);
                axi_stream_data = sel ? weight_beat(beat_idx) : data_beat();
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
    endtask

    task arm_debug;
        begin
            debug_control_packet = '0;
            debug_control_packet[DBG_CTRL_ENABLE_BIT] = 1'b1;
            debug_control_packet[DBG_CTRL_IRQ_ENABLE_BIT] = 1'b1;
            debug_control_packet[DBG_CTRL_HOLD_ENABLE_BIT] = 1'b1;
            debug_control_packet[DBG_CTRL_COMPARE_ENABLE_BIT] = 1'b1;
        end
    endtask

    task set_expected_cell0;
        begin
            debug_expected_packet = '0;
            debug_expected_packet[DBG_EXP_DATA_LSB+:DEBUG_LANE_WIDTH] =
                32'h04030201;
            debug_expected_packet[DBG_EXP_WEIGHT_LSB+:DEBUG_LANE_WIDTH] =
                32'hA3A2A1A0;
            debug_expected_packet[DBG_EXP_TAG_LSB+:DEBUG_TAG_WIDTH] =
                32'h00000000;
            debug_expected_packet[DBG_EXP_SELECT_LSB+:DEBUG_SELECT_WIDTH] =
                DEBUG_SELECT_WIDTH'(0);
            debug_expected_packet[DBG_EXP_VALID_BIT] = 1'b1;
            debug_expected_packet[DBG_EXP_ACC_CLEAR_BIT] = 1'b1;
            debug_expected_packet[DBG_EXP_ACC_LAST_BIT] = 1'b1;
        end
    endtask

    task pulse_compare;
        begin
            @(negedge clk);
            debug_control_packet[DBG_CTRL_COMPARE_STROBE_BIT] = 1'b1;
            @(negedge clk);
            debug_control_packet[DBG_CTRL_COMPARE_STROBE_BIT] = 1'b0;
        end
    endtask

    initial begin
        errors = 0;
        rst_n = 1'b0;

        s00_axi_awaddr = '0;
        s00_axi_awprot = '0;
        s00_axi_awvalid = 1'b0;
        s00_axi_wdata = '0;
        s00_axi_wstrb = 4'hf;
        s00_axi_wvalid = 1'b0;
        s00_axi_bready = 1'b0;
        s00_axi_araddr = '0;
        s00_axi_arprot = '0;
        s00_axi_arvalid = 1'b0;
        s00_axi_rready = 1'b0;

        axi_stream_valid = 1'b0;
        axi_stream_data = '0;
        axi_txn_done = 1'b0;
        axi_error = 1'b0;
        debug_control_packet = '0;
        debug_expected_packet = '0;

        repeat (8) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;
        repeat (4) @(posedge clk);

        arm_debug();

        axi_lite_write(REG_DATA_WIDTH, 32'd1);
        axi_lite_write(REG_DATA_HEIGHT, 32'd1);
        axi_lite_write(REG_DATA_CH, 32'd4);
        axi_lite_write(REG_DATA_BASE, 32'd0);
        axi_lite_write(REG_WEIGHT_WIDTH, 32'd8);
        axi_lite_write(REG_WEIGHT_HEIGHT, 32'd1);
        axi_lite_write(REG_WEIGHT_CH, 32'd4);
        axi_lite_write(REG_WEIGHT_BASE, 32'd0);

        fork
            drive_burst();
            begin
                axi_lite_write(REG_CDMA_CONTROL, 32'h00000001);
                wait_data_done();
            end
        join

        repeat (4) @(posedge clk);

        fork
            drive_burst();
            begin
                axi_lite_write(REG_CDMA_CONTROL, 32'h00000002);
                wait_weight_done();
            end
        join

        repeat (8) @(posedge clk);

        set_expected_cell0();

        axi_lite_write(REG_CSC_ATOMICS, 32'd1);
        axi_lite_write(REG_CSC_DATA_BASE, 32'd0);
        axi_lite_write(REG_CSC_WEIGHT_BASE, 32'd0);
        axi_lite_write(REG_CSC_INPUT_WH, {16'd1, 16'd1});
        axi_lite_write(REG_CSC_INPUT_CH, 32'd4);
        axi_lite_write(REG_CSC_KERNEL_WH, {16'd1, 16'd1});
        axi_lite_write(REG_CSC_STRIDE_XY, {16'd1, 16'd1});
        axi_lite_write(REG_CSC_OUTPUT_WH, {16'd1, 16'd1});
        axi_lite_write(REG_CSC_OUTPUT_CH, 32'd1);
        axi_lite_write(REG_CSC_CONTROL, 32'h00000002);
        wait_csc_ready();
        axi_lite_write(REG_CSC_CONTROL, 32'h00000003);

        wait_debug_snapshot();

        if (!debug_irq) begin
            $display("ERROR debug_irq was not asserted after snapshot");
            errors = errors + 1;
        end

        pulse_compare();
        repeat (2) @(posedge clk);

        if (!debug_status_packet[2]) begin
            $display("ERROR debug pass bit was not asserted");
            errors = errors + 1;
        end

        if (debug_status_packet[3]) begin
            $display("ERROR debug fail bit was asserted");
            errors = errors + 1;
        end

        if (debug_status_packet[DBG_STAT_FAIL_MASK_LSB+:MACCELL_NUM] != 8'h00) begin
            $display("ERROR fail mask unexpected: 0x%02h",
                     debug_status_packet[DBG_STAT_FAIL_MASK_LSB+:MACCELL_NUM]);
            errors = errors + 1;
        end

        if (debug_status_packet[DBG_STAT_FAIL_BITMAP_LSB+:32] != 32'h00000000) begin
            $display("ERROR fail bitmap unexpected: 0x%08h",
                     debug_status_packet[DBG_STAT_FAIL_BITMAP_LSB+:32]);
            errors = errors + 1;
        end

        if (debug_status_packet[DBG_STAT_CHECKED_MASK_LSB+:MACCELL_NUM] != 8'h01) begin
            $display("ERROR checked mask unexpected: 0x%02h",
                     debug_status_packet[DBG_STAT_CHECKED_MASK_LSB+:MACCELL_NUM]);
            errors = errors + 1;
        end

        if (debug_status_packet[DBG_STAT_ACTUAL_DATA_LSB+:32] != 32'h04030201) begin
            $display("ERROR actual data got=0x%08h exp=0x04030201",
                     debug_status_packet[DBG_STAT_ACTUAL_DATA_LSB+:32]);
            errors = errors + 1;
        end

        if (debug_status_packet[DBG_STAT_ACTUAL_WEIGHT_LSB+:32] != 32'hA3A2A1A0) begin
            $display("ERROR actual weight got=0x%08h exp=0xA3A2A1A0",
                     debug_status_packet[DBG_STAT_ACTUAL_WEIGHT_LSB+:32]);
            errors = errors + 1;
        end

        if (errors == 0) begin
            $display("CONVCORE_DEBUG_SMOKE_TEST_PASS");
        end else begin
            $display("CONVCORE_DEBUG_SMOKE_TEST_FAIL errors=%0d", errors);
        end

        $finish;
    end
endmodule
