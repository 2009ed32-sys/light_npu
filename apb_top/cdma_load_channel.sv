// Stream-backed CDMA load channel.
//
// The channel requests AXI read bursts through cdma_axi_transaction_ctrl and
// writes returned AXI stream words through cbuf_address_generator. The
// generator gathers 32-bit AXI beats into one bank-parallel CBUF row packet.
// On an AXI read error, the current burst is retried by the transaction
// controller, so this channel rewinds its CBUF write pointer to the start of
// that burst and clears the temporary gather row.

module cdma_load_channel #(
    parameter int ADDR_WIDTH       = 32,
    parameter int AXI_DATA_WIDTH   = 32,
    parameter int CBUF_WORD_WIDTH  = 32,
    parameter int ELEMENT_WIDTH    = 8,
    parameter int LEN_WIDTH        = 32,
    parameter int CBUF_ADDR_WIDTH = 16,
    parameter int BANK_NUM     = 8,
    parameter int BANK_SEL_WIDTH  = (BANK_NUM <= 2) ? 1 : $clog2(BANK_NUM),
    parameter int BANK_ADDR_WIDTH = 10,
    parameter int AXI_BURST_LEN   = 8
) (
    input  logic                       clk,
    input  logic                       rst_n,

    input  logic                       start,
    output logic                       busy,
    output logic                       done,
    output logic                       error,
    output logic                       fill_request,
    input  logic                       fill_done,

    input  logic [LEN_WIDTH-1:0]       cfg_matrix_width,
    input  logic [LEN_WIDTH-1:0]       cfg_matrix_height,
    input  logic [LEN_WIDTH-1:0]       cfg_channel_count,
    input  logic [CBUF_ADDR_WIDTH-1:0] cfg_dst_base,
    output logic [LEN_WIDTH-1:0]       load_total_words,
    output logic [ADDR_WIDTH-1:0]      load_last_addr,

    output logic [ADDR_WIDTH-1:0]      mem_rd_addr,

    input  logic                       stream_txn_start,
    input  logic                       stream_error,
    input  logic                       stream_valid,
    output logic                       stream_ready,
    input  logic [AXI_DATA_WIDTH-1:0]      stream_data,

    output logic [BANK_NUM-1:0] cbuf_wr_bank_en,
    output logic [(BANK_NUM*BANK_ADDR_WIDTH)-1:0] cbuf_wr_bank_addr,
    output logic [(BANK_NUM*CBUF_WORD_WIDTH)-1:0] cbuf_wr_bank_data
);

    localparam int BYTE_BITS       = 8;
    localparam int CBUF_WORD_BYTES = CBUF_WORD_WIDTH / BYTE_BITS;
    localparam int ADDR_SHIFT      = (CBUF_WORD_BYTES <= 1) ? 0 : $clog2(CBUF_WORD_BYTES);
    localparam int CHANNELS_PER_WORD = CBUF_WORD_WIDTH / ELEMENT_WIDTH;

    localparam int CHANNEL_GROUP_SHIFT = $clog2(CHANNELS_PER_WORD);
    localparam int AXI_BURST_LEN_SHIFT =
        (AXI_BURST_LEN <= 1) ? 0 : $clog2(AXI_BURST_LEN);
    localparam int CFG_DIM_WIDTH = 8;
    localparam int CFG_AREA_WIDTH = CFG_DIM_WIDTH * 2;
    localparam int CFG_CHANNEL_GROUP_WIDTH = CFG_DIM_WIDTH + 1;
    localparam int CFG_TOTAL_WORD_WIDTH =
        CFG_AREA_WIDTH + CFG_CHANNEL_GROUP_WIDTH;

    typedef enum logic [2:0] {
        ST_IDLE,
        ST_PREP,
        ST_RUN,
        ST_DRAIN,
        ST_DONE,
        ST_ERROR
    } state_e;

    state_e state_q, state_d;

    logic [LEN_WIDTH-1:0] return_count_q;
    logic [LEN_WIDTH-1:0] write_count_q;
    logic [LEN_WIDTH-1:0] total_words_q;
    logic [LEN_WIDTH-1:0] total_stream_words_q;
    logic [LEN_WIDTH-1:0] txn_start_count_q;
    logic [LEN_WIDTH-1:0] txn_start_write_count_q;
    logic [LEN_WIDTH-1:0] return_count_d;
    logic [LEN_WIDTH-1:0] write_count_d;
    logic [LEN_WIDTH-1:0] total_words_d;
    logic [LEN_WIDTH-1:0] total_stream_words_d;
    logic [LEN_WIDTH-1:0] txn_start_count_d;
    logic [LEN_WIDTH-1:0] txn_start_write_count_d;
    logic [LEN_WIDTH-1:0] return_count_after_stream;
    logic [LEN_WIDTH-1:0] write_count_after_stream;

    logic [CBUF_ADDR_WIDTH-1:0] dst_base_q;
    logic [CBUF_ADDR_WIDTH-1:0] dst_base_d;
    logic [CFG_DIM_WIDTH-1:0] cfg_matrix_width_q;
    logic [CFG_DIM_WIDTH-1:0] cfg_matrix_width_d;
    logic [CFG_DIM_WIDTH-1:0] cfg_matrix_height_q;
    logic [CFG_DIM_WIDTH-1:0] cfg_matrix_height_d;
    logic [CFG_DIM_WIDTH-1:0] cfg_channel_count_q;
    logic [CFG_DIM_WIDTH-1:0] cfg_channel_count_d;

    logic start_q;
    logic start_pulse;
    logic stream_accept;
    logic stream_write;
    logic stream_fire;
    logic cbuf_addrgen_clear;
    logic cbuf_addrgen_flush;
    logic [BANK_NUM-1:0] cbuf_addrgen_gather_valid;
    logic [LEN_WIDTH-1:0] calc_total_words_w;

    function automatic logic [CFG_CHANNEL_GROUP_WIDTH-1:0] calc_channel_groups(
        input logic [CFG_DIM_WIDTH-1:0] channel_count
    );
        logic [CFG_CHANNEL_GROUP_WIDTH-1:0] rounded_channel_count;
        begin
            rounded_channel_count =
                CFG_CHANNEL_GROUP_WIDTH'(channel_count) +
                CFG_CHANNEL_GROUP_WIDTH'(CHANNELS_PER_WORD - 1'b1);
            calc_channel_groups =
                rounded_channel_count >> CHANNEL_GROUP_SHIFT;
        end
    endfunction

    function automatic logic [LEN_WIDTH-1:0] calc_total_words(
        input logic [CFG_DIM_WIDTH-1:0] matrix_width,
        input logic [CFG_DIM_WIDTH-1:0] matrix_height,
        input logic [CFG_DIM_WIDTH-1:0] channel_count
    );
        logic [CFG_AREA_WIDTH-1:0] matrix_area;
        logic [CFG_CHANNEL_GROUP_WIDTH-1:0] channel_groups;
        logic [CFG_TOTAL_WORD_WIDTH-1:0] total_words_narrow;
        begin
            matrix_area =
                CFG_AREA_WIDTH'(matrix_width) *
                CFG_AREA_WIDTH'(matrix_height);
            channel_groups = calc_channel_groups(channel_count);
            total_words_narrow =
                CFG_TOTAL_WORD_WIDTH'(matrix_area) *
                CFG_TOTAL_WORD_WIDTH'(channel_groups);
            calc_total_words = LEN_WIDTH'(total_words_narrow);
        end
    endfunction

    function automatic logic [LEN_WIDTH-1:0] calc_total_stream_words(
        input logic [LEN_WIDTH-1:0] useful_words
    );
        logic [LEN_WIDTH-1:0] burst_count;
        begin
            if (useful_words == '0) begin
                burst_count = '0;
            end else if (AXI_BURST_LEN_SHIFT == 0) begin
                burst_count = useful_words;
            end else begin
                burst_count =
                    (useful_words + LEN_WIDTH'(AXI_BURST_LEN - 1)) >>
                    AXI_BURST_LEN_SHIFT;
            end

            calc_total_stream_words =
                burst_count << AXI_BURST_LEN_SHIFT;
        end
    endfunction

    function automatic logic [ADDR_WIDTH-1:0] calc_last_addr(
        input logic [LEN_WIDTH-1:0] total_words
    );
        begin
            if (total_words == '0) begin
                calc_last_addr = '0;
            end else begin
                calc_last_addr = ADDR_WIDTH'(total_words - 1'b1) << ADDR_SHIFT;
            end
        end
    endfunction

    assign busy               = (state_q == ST_RUN) || (state_q == ST_DRAIN);
    assign fill_request       = (state_q == ST_RUN);
    assign start_pulse        = start && !start_q;
    assign stream_ready       =
        (state_q == ST_RUN) &&
        (return_count_q < total_stream_words_q) &&
        !stream_error;
    assign stream_accept      = stream_valid && stream_ready;
    assign stream_write       =
        stream_accept && (write_count_q < total_words_q);
    assign stream_fire        = stream_write && !stream_error;
    assign cbuf_addrgen_clear = start_pulse || stream_error;
    assign calc_total_words_w =
        calc_total_words(
            cfg_matrix_width_q,
            cfg_matrix_height_q,
            cfg_channel_count_q
        );
    assign load_total_words   = total_words_q;
    assign load_last_addr     = calc_last_addr(total_words_q);

    cbuf_address_generator #(
        .AXI_DATA_WIDTH   (AXI_DATA_WIDTH),
        .CBUF_WORD_WIDTH  (CBUF_WORD_WIDTH),
        .ELEMENT_WIDTH    (ELEMENT_WIDTH),
        .CBUF_ADDR_WIDTH  (CBUF_ADDR_WIDTH),
        .LEN_WIDTH        (LEN_WIDTH),
        .BANK_NUM         (BANK_NUM),
        .BANK_SEL_WIDTH   (BANK_SEL_WIDTH),
        .BANK_ADDR_WIDTH  (BANK_ADDR_WIDTH)
    ) u_cbuf_address_generator (
        .clk              (clk),
        .rst_n            (rst_n),
        .clear            (cbuf_addrgen_clear),
        .stream_fire      (stream_fire),
        .word_index       (write_count_q),
        .total_words      (total_words_q),
        .dst_base         (dst_base_q),
        .stream_data      (stream_data),
        .cbuf_wr_bank_en  (cbuf_wr_bank_en),
        .cbuf_wr_bank_addr(cbuf_wr_bank_addr),
        .cbuf_wr_bank_data(cbuf_wr_bank_data),
        .flush_pulse      (cbuf_addrgen_flush),
        .gather_valid     (cbuf_addrgen_gather_valid)
    );

    always_comb begin
        state_d                 = state_q;
        return_count_d          = return_count_q;
        write_count_d           = write_count_q;
        total_words_d           = total_words_q;
        total_stream_words_d    = total_stream_words_q;
        txn_start_count_d       = txn_start_count_q;
        txn_start_write_count_d = txn_start_write_count_q;
        dst_base_d              = dst_base_q;
        cfg_matrix_width_d      = cfg_matrix_width_q;
        cfg_matrix_height_d     = cfg_matrix_height_q;
        cfg_channel_count_d     = cfg_channel_count_q;
        return_count_after_stream = return_count_q;
        write_count_after_stream  = write_count_q;

        mem_rd_addr             = ADDR_WIDTH'(return_count_q) << ADDR_SHIFT;
        done                    = 1'b0;
        error                   = 1'b0;

        if (stream_accept) begin
            return_count_after_stream = return_count_q + 1'b1;
        end

        if (stream_fire) begin
            write_count_after_stream = write_count_q + 1'b1;
        end

        case (state_q)
            ST_IDLE: begin
                return_count_d    = '0;
                write_count_d     = '0;
                txn_start_count_d = '0;
                txn_start_write_count_d = '0;

                if (start_pulse) begin
                    cfg_matrix_width_d  = cfg_matrix_width[CFG_DIM_WIDTH-1:0];
                    cfg_matrix_height_d = cfg_matrix_height[CFG_DIM_WIDTH-1:0];
                    cfg_channel_count_d = cfg_channel_count[CFG_DIM_WIDTH-1:0];
                    dst_base_d          = cfg_dst_base;
                    state_d             = ST_PREP;
                end
            end

            ST_PREP: begin
                if (start_pulse) begin
                    state_d = ST_ERROR;
                end else begin
                    total_words_d = calc_total_words_w;
                    total_stream_words_d =
                        calc_total_stream_words(calc_total_words_w);

                    if (calc_total_words_w == '0) begin
                        state_d = ST_DONE;
                    end else begin
                        state_d = ST_RUN;
                    end
                end
            end

            ST_RUN: begin
                return_count_d = return_count_after_stream;
                write_count_d  = write_count_after_stream;

                if (stream_txn_start) begin
                    txn_start_count_d = return_count_q;
                    txn_start_write_count_d = write_count_q;
                end

                if (start_pulse) begin
                    state_d = ST_ERROR;
                end else if (stream_error) begin
                    return_count_d = txn_start_count_q;
                    write_count_d  = txn_start_write_count_q;
                end else if (fill_done) begin
                    if ((return_count_after_stream == total_stream_words_q) &&
                        (write_count_after_stream == total_words_q)) begin
                            state_d = ST_DRAIN;
                        end else begin
                            state_d = ST_ERROR;
                        end
                end
            end

            ST_DRAIN: begin
                state_d = ST_DONE;
            end

            ST_DONE: begin
                done    = 1'b1;
                state_d = ST_IDLE;
            end

            ST_ERROR: begin
                error   = 1'b1;
                state_d = ST_IDLE;
            end

            default: begin
                state_d = ST_ERROR;
            end
        endcase
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state_q           <= ST_IDLE;
            return_count_q    <= '0;
            write_count_q     <= '0;
            total_words_q     <= '0;
            total_stream_words_q <= '0;
            txn_start_count_q <= '0;
            txn_start_write_count_q <= '0;
            dst_base_q        <= '0;
            cfg_matrix_width_q <= '0;
            cfg_matrix_height_q <= '0;
            cfg_channel_count_q <= '0;
            start_q           <= 1'b0;
        end else begin
            state_q           <= state_d;
            return_count_q    <= return_count_d;
            write_count_q     <= write_count_d;
            total_words_q     <= total_words_d;
            total_stream_words_q <= total_stream_words_d;
            txn_start_count_q <= txn_start_count_d;
            txn_start_write_count_q <= txn_start_write_count_d;
            dst_base_q        <= dst_base_d;
            cfg_matrix_width_q <= cfg_matrix_width_d;
            cfg_matrix_height_q <= cfg_matrix_height_d;
            cfg_channel_count_q <= cfg_channel_count_d;
            start_q           <= start;
        end
    end

endmodule
