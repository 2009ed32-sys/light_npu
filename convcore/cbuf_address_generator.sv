`timescale 1ns/1ps

module cbuf_address_generator #(
    parameter int AXI_DATA_WIDTH    = 32,
    parameter int CBUF_WORD_WIDTH   = 32,
    parameter int ELEMENT_WIDTH     = 8,
    parameter int CBUF_ADDR_WIDTH   = 16,
    parameter int LEN_WIDTH         = 32,
    parameter int BANK_NUM          = 8,
    parameter int BANK_SEL_WIDTH    = (BANK_NUM <= 2) ? 1 : $clog2(BANK_NUM),
    parameter int BANK_ADDR_WIDTH   = 10
) (
    input  logic                       clk,
    input  logic                       rst_n,

    // Clear gather buffer at load start or retry/error rewind.
    input  logic                       clear,

    // One-cycle pulse when an AXI stream beat is accepted.
    // In current cdma_load_channel this can be:
    //   stream_write && !stream_error
    input  logic                       stream_fire,

    // Current accepted beat/word index.
    // In current cdma_load_channel this can be return_count_q.
    input  logic [LEN_WIDTH-1:0]       word_index,

    // Total number of CBUF words expected.
    // In current cdma_load_channel this can be total_words_q.
    input  logic [LEN_WIDTH-1:0]       total_words,

    // CBUF destination base in word address units.
    // In current cdma_load_channel this can be dst_base_q.
    input  logic [CBUF_ADDR_WIDTH-1:0] dst_base,

    // AXI stream data beat.
    input  logic [AXI_DATA_WIDTH-1:0]  stream_data,

    // Registered CBUF bank-parallel write output.
    // The flush packet is held stable for one full cycle so CBUF can sample it
    // on the following clock edge.
    output logic [BANK_NUM-1:0]        cbuf_wr_bank_en,
    output logic [(BANK_NUM*BANK_ADDR_WIDTH)-1:0]
                                        cbuf_wr_bank_addr,
    output logic [(BANK_NUM*CBUF_WORD_WIDTH)-1:0]
                                        cbuf_wr_bank_data,

    // Optional status/debug.
    output logic                       flush_pulse,
    output logic [BANK_NUM-1:0]        gather_valid
);

    localparam int ELEMENTS_PER_AXI_BEAT = AXI_DATA_WIDTH / ELEMENT_WIDTH;
    localparam int PACK_LANES            = CBUF_WORD_WIDTH / ELEMENT_WIDTH;
    localparam int PACK_LANE_WIDTH       = (PACK_LANES <= 1) ? 1 : $clog2(PACK_LANES);
    localparam int AXI_BEAT_ELEMENT_SHIFT =
        (ELEMENTS_PER_AXI_BEAT <= 1) ? 0 : $clog2(ELEMENTS_PER_AXI_BEAT);
    localparam int ROW_ELEMENT_SHIFT     = BANK_SEL_WIDTH + PACK_LANE_WIDTH;
    localparam int BYTE_VALID_WIDTH      = BANK_NUM * PACK_LANES;

    // ------------------------------------------------------------
    // Gather registers
    // ------------------------------------------------------------
    logic [BYTE_VALID_WIDTH-1:0] gather_byte_valid_q;
    logic [(BANK_NUM*BANK_ADDR_WIDTH)-1:0] gather_addr_q;
    logic [(BANK_NUM*CBUF_WORD_WIDTH)-1:0] gather_data_q;

    logic [BYTE_VALID_WIDTH-1:0] gather_byte_valid_d;
    logic [(BANK_NUM*BANK_ADDR_WIDTH)-1:0] gather_addr_d;
    logic [(BANK_NUM*CBUF_WORD_WIDTH)-1:0] gather_data_d;

    logic last_word_w;
    logic flush_pulse_d;
    logic [BANK_NUM-1:0] flush_bank_en_d;
    logic [(BANK_NUM*BANK_ADDR_WIDTH)-1:0] flush_bank_addr_d;
    logic [(BANK_NUM*CBUF_WORD_WIDTH)-1:0] flush_bank_data_d;

    // ------------------------------------------------------------
    // Address mapping
    //
    // linear CBUF element address:
    //   element_addr = dst_base + word_index * elements_per_axi_beat + lane
    //
    // bank:
    //   bank_sel = element_addr % BANK_NUM
    //
    // byte lane inside one bank word:
    //   pack_lane = (element_addr / BANK_NUM) % PACK_LANES
    //
    // bank-local address:
    //   bank_addr = element_addr / (BANK_NUM * PACK_LANES)
    //
    // This implementation assumes BANK_NUM, PACK_LANES, and
    // ELEMENTS_PER_AXI_BEAT are powers of two.
    // ------------------------------------------------------------
    function automatic logic [BANK_SEL_WIDTH-1:0] calc_bank_sel(
        input logic [CBUF_ADDR_WIDTH-1:0] element_addr
    );
        begin
            calc_bank_sel = element_addr[BANK_SEL_WIDTH-1:0];
        end
    endfunction

    function automatic logic [PACK_LANE_WIDTH-1:0] calc_pack_lane(
        input logic [CBUF_ADDR_WIDTH-1:0] element_addr
    );
        begin
            calc_pack_lane =
                PACK_LANE_WIDTH'(element_addr >> BANK_SEL_WIDTH);
        end
    endfunction

    function automatic logic [BANK_ADDR_WIDTH-1:0] calc_bank_addr(
        input logic [CBUF_ADDR_WIDTH-1:0] element_addr
    );
        begin
            calc_bank_addr = BANK_ADDR_WIDTH'(element_addr >> ROW_ELEMENT_SHIFT);
        end
    endfunction

    assign last_word_w =
        stream_fire && ((word_index + LEN_WIDTH'(1)) >= total_words);

    // ------------------------------------------------------------
    // Combinational next-state and output pulse
    // ------------------------------------------------------------
    always_comb begin
        logic [CBUF_ADDR_WIDTH-1:0] element_base;
        logic [CBUF_ADDR_WIDTH-1:0] element_addr;
        logic [BANK_SEL_WIDTH-1:0]  bank_sel;
        logic [PACK_LANE_WIDTH-1:0] pack_lane;
        logic [BANK_ADDR_WIDTH-1:0] bank_addr;
        logic                       row_full;

        gather_byte_valid_d = gather_byte_valid_q;
        gather_addr_d       = gather_addr_q;
        gather_data_d       = gather_data_q;

        flush_bank_en_d   = '0;
        flush_bank_addr_d = '0;
        flush_bank_data_d = '0;
        gather_valid      = '0;
        flush_pulse_d     = 1'b0;
        row_full          = 1'b0;
        element_base      = '0;
        element_addr      = '0;
        bank_sel          = '0;
        pack_lane         = '0;
        bank_addr         = '0;

        for (int valid_bank_idx = 0;
             valid_bank_idx < BANK_NUM;
             valid_bank_idx = valid_bank_idx + 1) begin
            gather_valid[valid_bank_idx] =
                |gather_byte_valid_q[(valid_bank_idx*PACK_LANES)+:PACK_LANES];
        end

        if (clear) begin
            gather_byte_valid_d = '0;
            gather_addr_d       = '0;
            gather_data_d       = '0;
        end else begin
            if (stream_fire) begin
                element_base =
                    dst_base +
                    (word_index[CBUF_ADDR_WIDTH-1:0] <<
                     AXI_BEAT_ELEMENT_SHIFT);

                for (int axi_lane = 0;axi_lane < ELEMENTS_PER_AXI_BEAT;
                    axi_lane = axi_lane + 1) begin
                    element_addr = element_base + CBUF_ADDR_WIDTH'(axi_lane);
                    bank_sel     = calc_bank_sel(element_addr);
                    pack_lane    = calc_pack_lane(element_addr);
                    bank_addr    = calc_bank_addr(element_addr);

                    for (int bank_idx = 0;
                         bank_idx < BANK_NUM;
                         bank_idx = bank_idx + 1) begin
                        if (bank_sel == BANK_SEL_WIDTH'(bank_idx)) begin
                            gather_addr_d[
                                (bank_idx*BANK_ADDR_WIDTH)+:BANK_ADDR_WIDTH
                            ] = bank_addr;

                            for (int pack_idx = 0;
                                 pack_idx < PACK_LANES;
                                 pack_idx = pack_idx + 1) begin
                                if (pack_lane == PACK_LANE_WIDTH'(pack_idx)) begin
                                    gather_byte_valid_d[
                                        (bank_idx*PACK_LANES)+pack_idx
                                    ] = 1'b1;

                                    gather_data_d[
                                        (bank_idx*CBUF_WORD_WIDTH) +
                                        (pack_idx*ELEMENT_WIDTH)+:ELEMENT_WIDTH
                                    ] = stream_data[
                                        (axi_lane*ELEMENT_WIDTH)+:ELEMENT_WIDTH
                                    ];
                                end
                            end
                        end
                    end
                end

                row_full    = &gather_byte_valid_d;
                flush_pulse_d = row_full || last_word_w;

                if (flush_pulse_d) begin
                    for (int flush_bank_idx = 0;
                         flush_bank_idx < BANK_NUM;
                         flush_bank_idx = flush_bank_idx + 1) begin
                        flush_bank_en_d[flush_bank_idx] =
                            |gather_byte_valid_d[(flush_bank_idx*PACK_LANES)+:PACK_LANES];
                    end

                    flush_bank_addr_d = gather_addr_d;
                    flush_bank_data_d = gather_data_d;

                    gather_byte_valid_d = '0;
                    gather_addr_d       = '0;
                    gather_data_d       = '0;
                end
            end
        end
    end

    // ------------------------------------------------------------
    // Sequential state
    // ------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            gather_byte_valid_q <= '0;
            gather_addr_q       <= '0;
            gather_data_q       <= '0;
            cbuf_wr_bank_en     <= '0;
            cbuf_wr_bank_addr   <= '0;
            cbuf_wr_bank_data   <= '0;
            flush_pulse         <= 1'b0;
        end else begin
            gather_byte_valid_q <= gather_byte_valid_d;
            gather_addr_q       <= gather_addr_d;
            gather_data_q       <= gather_data_d;
            cbuf_wr_bank_en     <= flush_bank_en_d;
            cbuf_wr_bank_addr   <= flush_bank_addr_d;
            cbuf_wr_bank_data   <= flush_bank_data_d;
            flush_pulse         <= flush_pulse_d;
        end
    end

endmodule
