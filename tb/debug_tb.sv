`timescale 1ns/1ps

module debug_tb;

    logic        data_cbuf_wr_en;
    logic [15:0] data_cbuf_wr_addr;
    logic [31:0] data_cbuf_wr_data;
    logic        data_bram_en;
    logic [3:0]  data_bram_we;
    logic [31:0] data_bram_addr;
    logic [31:0] data_bram_wr_data;

    logic        weight_cbuf_wr_en;
    logic [15:0] weight_cbuf_wr_addr;
    logic [31:0] weight_cbuf_wr_data;
    logic        weight_bram_en;
    logic [3:0]  weight_bram_we;
    logic [31:0] weight_bram_addr;
    logic [31:0] weight_bram_wr_data;

    debug u_debug (
        .data_cbuf_wr_en    (data_cbuf_wr_en),
        .data_cbuf_wr_addr  (data_cbuf_wr_addr),
        .data_cbuf_wr_data  (data_cbuf_wr_data),
        .data_bram_en       (data_bram_en),
        .data_bram_we       (data_bram_we),
        .data_bram_addr     (data_bram_addr),
        .data_bram_wr_data  (data_bram_wr_data),
        .weight_cbuf_wr_en  (weight_cbuf_wr_en),
        .weight_cbuf_wr_addr(weight_cbuf_wr_addr),
        .weight_cbuf_wr_data(weight_cbuf_wr_data),
        .weight_bram_en     (weight_bram_en),
        .weight_bram_we     (weight_bram_we),
        .weight_bram_addr   (weight_bram_addr),
        .weight_bram_wr_data(weight_bram_wr_data)
    );

    initial begin
        data_cbuf_wr_en     = 1'b0;
        data_cbuf_wr_addr   = 16'h0000;
        data_cbuf_wr_data   = 32'h00000000;
        weight_cbuf_wr_en   = 1'b0;
        weight_cbuf_wr_addr = 16'h0000;
        weight_cbuf_wr_data = 32'h00000000;
        #1;

        data_cbuf_wr_en     = 1'b1;
        data_cbuf_wr_addr   = 16'h0003;
        data_cbuf_wr_data   = 32'h03020100;
        weight_cbuf_wr_en   = 1'b1;
        weight_cbuf_wr_addr = 16'h0010;
        weight_cbuf_wr_data = 32'hC3C2C1C0;
        #1;

        if (data_bram_en != 1'b1 ||
            data_bram_we != 4'b1111 ||
            data_bram_addr != 32'h0000000C ||
            data_bram_wr_data != 32'h03020100) begin
            $fatal(1, "DATA_DEBUG_BRIDGE_TEST_FAIL");
        end

        if (weight_bram_en != 1'b1 ||
            weight_bram_we != 4'b1111 ||
            weight_bram_addr != 32'h00000040 ||
            weight_bram_wr_data != 32'hC3C2C1C0) begin
            $fatal(1, "WEIGHT_DEBUG_BRIDGE_TEST_FAIL");
        end

        data_cbuf_wr_en   = 1'b0;
        weight_cbuf_wr_en = 1'b0;
        #1;

        if (data_bram_en != 1'b0 ||
            data_bram_we != 4'b0000 ||
            weight_bram_en != 1'b0 ||
            weight_bram_we != 4'b0000) begin
            $fatal(1, "DEBUG_DISABLE_TEST_FAIL");
        end

        $display("DEBUG_BRIDGE_TEST_PASS");
        $finish;
    end

endmodule
