`timescale 1ns/1ps
// Banked convolution buffer backed by inferred block RAM.
//
// cbuf_address_generator splits one AXI stream beat into ELEMENT_WIDTH channel
// elements, gathers them into one 8-bank row packet, and then writes CBUF.
// The generator performs the element-index split before CBUF:
//   element_index = dst_base + beat_index * elements_per_beat + beat_lane
//   bank = element_index[log2(BANK_NUM)-1:0]
//   pack_lane = (element_index >> log2(BANK_NUM)) % MACLANE_NUM
//   addr = element_index >> (log2(BANK_NUM) + log2(MACLANE_NUM))
//   MACLANE_NUM means number of channels 
//
// With the default 8 maccells and 4 maclanes:
//   beat0 lane0 -> bank0 addr0 byte0
//   beat0 lane1 -> bank1 addr0 byte0
//   beat0 lane2 -> bank2 addr0 byte0
//   beat0 lane3 -> bank3 addr0 byte0
//   beat1 lane0 -> bank4 addr0 byte0
//   ...
//   beat2 lane0 -> bank0 addr0 byte1
//
// Each bank write slot is still DATA_WIDTH wide for interface stability; the
// generator packs MACLANE_NUM channel elements into each selected bank word.
// Both read and write sides use bank-local addresses. The read side exposes one
// address per physical bank so CSC can gather words from the DRAM-order layout.

module cbuf #(
    parameter int DATA_WIDTH    = 32,
    parameter int ADDR_WIDTH    = 16,
    parameter int ELEMENT_WIDTH = 8,
    parameter int BANK_NUM   = 8,
    parameter int BANK_SEL_WIDTH = (BANK_NUM <= 2) ? 1 : $clog2(BANK_NUM),
    parameter int MACLANE_NUM   = DATA_WIDTH / ELEMENT_WIDTH,
    parameter int DATA_DEPTH    = 1024,
    parameter int WEIGHT_DEPTH  = 1024,
    parameter int BANK_ADDR_WIDTH = 10
) (
    input  logic                       clk,
    input  logic                       rst_n,

    input logic [BANK_NUM-1:0] data_wr_bank_en,
    input logic [(BANK_NUM*BANK_ADDR_WIDTH)-1:0] data_wr_bank_addr,
    input logic [(BANK_NUM*DATA_WIDTH)-1:0] data_wr_bank_data,
    input  logic                       data_rd_en,
    input  logic [BANK_NUM-1:0]     data_rd_bank_en,
    input  logic [(BANK_NUM*BANK_ADDR_WIDTH)-1:0] data_rd_bank_addr,
    output logic                       data_rd_valid,
    output logic [(BANK_NUM*MACLANE_NUM*ELEMENT_WIDTH)-1:0] data_rd_data,

    input logic [BANK_NUM-1:0] weight_wr_bank_en,
    input logic [(BANK_NUM*BANK_ADDR_WIDTH)-1:0] weight_wr_bank_addr,
    input logic [(BANK_NUM*DATA_WIDTH)-1:0] weight_wr_bank_data,
    input  logic                       weight_rd_en,
    input  logic [BANK_NUM-1:0]     weight_rd_bank_en,
    input  logic [(BANK_NUM*BANK_ADDR_WIDTH)-1:0] weight_rd_bank_addr,
    output logic                       weight_rd_valid,
    output logic [(BANK_NUM*MACLANE_NUM*ELEMENT_WIDTH)-1:0] weight_rd_data
);

    localparam int BANK_WORD_WIDTH       = MACLANE_NUM * ELEMENT_WIDTH;
    localparam int DATA_MEM_ADDR_WIDTH   = (DATA_DEPTH <= 2) ? 1 : $clog2(DATA_DEPTH);
    localparam int WEIGHT_MEM_ADDR_WIDTH = (WEIGHT_DEPTH <= 2) ? 1 : $clog2(WEIGHT_DEPTH);

    function automatic logic data_bank_addr_in_range(
        input logic [BANK_ADDR_WIDTH-1:0] addr
    );
        begin
            data_bank_addr_in_range = ADDR_WIDTH'(addr) < ADDR_WIDTH'(DATA_DEPTH);
        end
    endfunction

    function automatic logic weight_bank_addr_in_range(
        input logic [BANK_ADDR_WIDTH-1:0] addr
    );
        begin
            weight_bank_addr_in_range = ADDR_WIDTH'(addr) < ADDR_WIDTH'(WEIGHT_DEPTH);
        end
    endfunction

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            data_rd_valid   <= 1'b0;
            weight_rd_valid <= 1'b0;
        end else begin
            data_rd_valid   <= data_rd_en;
            weight_rd_valid <= weight_rd_en;
        end
    end

    genvar data_bank;
    generate
        for (data_bank = 0; data_bank < BANK_NUM; data_bank = data_bank + 1) begin : g_data_bank
            (* ram_style = "block" *)
            logic [BANK_WORD_WIDTH-1:0] mem [0:DATA_DEPTH-1];
            logic [BANK_WORD_WIDTH-1:0] rd_data_q;
            logic [BANK_ADDR_WIDTH-1:0] rd_bank_addr_w;
            logic [BANK_ADDR_WIDTH-1:0] wr_bank_addr_w;
            logic [DATA_WIDTH-1:0]      wr_bank_data_w;

            assign rd_bank_addr_w = data_rd_bank_addr[
                (data_bank*BANK_ADDR_WIDTH)+:BANK_ADDR_WIDTH
            ];
            assign wr_bank_addr_w = data_wr_bank_addr[
                (data_bank*BANK_ADDR_WIDTH)+:BANK_ADDR_WIDTH
            ];
            assign wr_bank_data_w = data_wr_bank_data[
                (data_bank*DATA_WIDTH)+:DATA_WIDTH
            ];

            always_ff @(posedge clk) begin
                if (!rst_n) begin
                    rd_data_q <= '0;
                end else begin
                    if (data_wr_bank_en[data_bank] &&
                        data_bank_addr_in_range(wr_bank_addr_w)) begin
                        mem[wr_bank_addr_w[DATA_MEM_ADDR_WIDTH-1:0]] <=
                            wr_bank_data_w;
                    end

                    if (data_rd_en &&
                        data_rd_bank_en[data_bank] &&
                        data_bank_addr_in_range(rd_bank_addr_w)) begin
                        rd_data_q <= mem[rd_bank_addr_w[DATA_MEM_ADDR_WIDTH-1:0]];
                    end
                end
            end

            assign data_rd_data[(data_bank*BANK_WORD_WIDTH)+:BANK_WORD_WIDTH] = rd_data_q;
        end
    endgenerate

    genvar weight_bank;
    generate
        for (weight_bank = 0; weight_bank < BANK_NUM; weight_bank = weight_bank + 1) begin : g_weight_bank
            (* ram_style = "block" *)
            logic [BANK_WORD_WIDTH-1:0] mem [0:WEIGHT_DEPTH-1];
            logic [BANK_WORD_WIDTH-1:0] rd_data_q;
            logic [BANK_ADDR_WIDTH-1:0] rd_bank_addr_w;
            logic [BANK_ADDR_WIDTH-1:0] wr_bank_addr_w;
            logic [DATA_WIDTH-1:0]      wr_bank_data_w;

            assign rd_bank_addr_w = weight_rd_bank_addr[
                (weight_bank*BANK_ADDR_WIDTH)+:BANK_ADDR_WIDTH
            ];
            assign wr_bank_addr_w = weight_wr_bank_addr[
                (weight_bank*BANK_ADDR_WIDTH)+:BANK_ADDR_WIDTH
            ];
            assign wr_bank_data_w = weight_wr_bank_data[
                (weight_bank*DATA_WIDTH)+:DATA_WIDTH
            ];

            always_ff @(posedge clk) begin
                if (!rst_n) begin
                    rd_data_q <= '0;
                end else begin
                    if (weight_wr_bank_en[weight_bank] &&
                        weight_bank_addr_in_range(wr_bank_addr_w)) begin
                        mem[wr_bank_addr_w[WEIGHT_MEM_ADDR_WIDTH-1:0]] <=
                            wr_bank_data_w;
                    end

                    if (weight_rd_en &&
                        weight_rd_bank_en[weight_bank] &&
                        weight_bank_addr_in_range(rd_bank_addr_w)) begin
                        rd_data_q <= mem[rd_bank_addr_w[WEIGHT_MEM_ADDR_WIDTH-1:0]];
                    end
                end
            end

            assign weight_rd_data[(weight_bank*BANK_WORD_WIDTH)+:BANK_WORD_WIDTH] = rd_data_q;
        end
    endgenerate

endmodule
