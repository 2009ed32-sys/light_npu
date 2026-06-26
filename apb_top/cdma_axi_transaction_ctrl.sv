// Shared AXI read-burst controller for the data and weight CDMA channels.
//
// Each transaction uses the fixed AXI burst length. The controller advances
// the address only after a successful transaction and retries the same address
// after an AXI error.

module cdma_axi_transaction_ctrl #(
    parameter int ADDR_WIDTH       = 32,
    parameter int AXI_DATA_WIDTH   = 32,
    parameter int CBUF_WORD_WIDTH  = 32,
    parameter int LEN_WIDTH        = 32,
    parameter int AXI_BURST_LEN    = 8
) (
    input  logic                  clk,
    input  logic                  rst_n,

    input  logic                  data_fill_request,
    input  logic [ADDR_WIDTH-1:0] data_src_base_addr,
    input  logic [LEN_WIDTH-1:0]  data_load_total_words,
    output logic                  data_fill_done,

    input  logic                  weight_fill_request,
    input  logic [ADDR_WIDTH-1:0] weight_src_base_addr,
    input  logic [LEN_WIDTH-1:0]  weight_load_total_words,
    output logic                  weight_fill_done,

    output logic                  axi_load_start,
    output logic [ADDR_WIDTH-1:0] axi_txn_addr,
    output logic                  axi_init_txn,
    output logic                  axi_stream_sel,
    input  logic                  axi_txn_done,
    input  logic                  axi_error
);

    localparam int BYTE_BITS      = 8;
    localparam int AXI_BEAT_BYTES = AXI_DATA_WIDTH / BYTE_BITS;
    localparam int CBUF_WORD_BYTES = CBUF_WORD_WIDTH / BYTE_BITS;
    localparam int WORDS_PER_AXI_BEAT = AXI_DATA_WIDTH / CBUF_WORD_WIDTH;
    localparam int WORDS_PER_AXI_BEAT_SHIFT =
        (WORDS_PER_AXI_BEAT <= 1) ? 0 : $clog2(WORDS_PER_AXI_BEAT);
    localparam int AXI_BURST_LEN_SHIFT =
        (AXI_BURST_LEN <= 1) ? 0 : $clog2(AXI_BURST_LEN);
    localparam int BURST_BYTES     = AXI_BURST_LEN * AXI_BEAT_BYTES;

    typedef enum logic [2:0] {
        ST_IDLE,
        ST_LOAD_START,
        ST_ISSUE,
        ST_WAIT_CLEAR,
        ST_WAIT_RESULT,
        ST_COMPLETE
    } state_e;

    state_e state_q, state_d;

    logic [ADDR_WIDTH-1:0] current_addr_q;
    logic [ADDR_WIDTH-1:0] current_addr_d;
    logic [LEN_WIDTH-1:0]  remaining_bursts_q;
    logic [LEN_WIDTH-1:0]  remaining_bursts_d;
    logic                  stream_sel_q;
    logic                  stream_sel_d;

    function automatic logic [LEN_WIDTH-1:0] ceil_div_words_per_axi_beat(
        input logic [LEN_WIDTH-1:0] value
    );
        begin
            if (value == '0) begin
                ceil_div_words_per_axi_beat = '0;
            end else if (WORDS_PER_AXI_BEAT_SHIFT == 0) begin
                ceil_div_words_per_axi_beat = value;
            end else begin
                ceil_div_words_per_axi_beat =
                    (value + LEN_WIDTH'(WORDS_PER_AXI_BEAT - 1)) >>
                    WORDS_PER_AXI_BEAT_SHIFT;
            end
        end
    endfunction

    function automatic logic [LEN_WIDTH-1:0] ceil_div_axi_burst_len(
        input logic [LEN_WIDTH-1:0] value
    );
        begin
            if (value == '0) begin
                ceil_div_axi_burst_len = '0;
            end else if (AXI_BURST_LEN_SHIFT == 0) begin
                ceil_div_axi_burst_len = value;
            end else begin
                ceil_div_axi_burst_len =
                    (value + LEN_WIDTH'(AXI_BURST_LEN - 1)) >>
                    AXI_BURST_LEN_SHIFT;
            end
        end
    endfunction
    
    function automatic logic [LEN_WIDTH-1:0] calc_total_bursts(
        input logic [LEN_WIDTH-1:0] total_cbuf_words
    );
        logic [LEN_WIDTH-1:0] total_axi_beats;
        begin
            total_axi_beats =
                ceil_div_words_per_axi_beat(total_cbuf_words);

            calc_total_bursts =
                ceil_div_axi_burst_len(total_axi_beats);
        end
    endfunction

    assign axi_txn_addr     = current_addr_q;
    assign axi_stream_sel   = stream_sel_q;

    always_comb begin
        state_d              = state_q;
        current_addr_d       = current_addr_q;
        remaining_bursts_d   = remaining_bursts_q;
        stream_sel_d         = stream_sel_q;

        data_fill_done       = 1'b0;
        weight_fill_done     = 1'b0;
        axi_load_start       = 1'b0;
        axi_init_txn         = 1'b0;

        case (state_q)
            ST_IDLE: begin
                current_addr_d = '0;

                if (data_fill_request) begin
                    current_addr_d =
                        data_src_base_addr;
                    remaining_bursts_d =
                        calc_total_bursts(data_load_total_words);
                    stream_sel_d = 1'b0;
                    state_d       = ST_LOAD_START;
                end else if (weight_fill_request) begin
                    current_addr_d =
                        weight_src_base_addr;
                    remaining_bursts_d =
                        calc_total_bursts(weight_load_total_words);
                    stream_sel_d = 1'b1;
                    state_d       = ST_LOAD_START;
                end
            end

            ST_LOAD_START: begin
                axi_load_start = 1'b1;

                if (remaining_bursts_q == '0) begin
                    state_d = ST_COMPLETE;
                end else begin
                    state_d = ST_ISSUE;
                end
            end

            ST_ISSUE: begin
                axi_init_txn = 1'b1;
                state_d      = ST_WAIT_CLEAR;
            end

            ST_WAIT_CLEAR: begin
                if (!axi_txn_done && !axi_error) begin
                    state_d = ST_WAIT_RESULT;
                end
            end

            ST_WAIT_RESULT: begin
                if (axi_error) begin
                    state_d = ST_ISSUE;
                end else if (axi_txn_done) begin
                    if (remaining_bursts_q == LEN_WIDTH'(1)) begin
                        remaining_bursts_d = '0;
                        state_d            = ST_COMPLETE;
                    end else begin
                        current_addr_d =
                            current_addr_q + ADDR_WIDTH'(BURST_BYTES);
                        remaining_bursts_d =
                            remaining_bursts_q - 1'b1;
                        state_d = ST_ISSUE;
                    end
                end
            end

            ST_COMPLETE: begin
                if (stream_sel_q == 1'b0) begin
                    data_fill_done = 1'b1;
                end else begin
                    weight_fill_done = 1'b1;
                end

                state_d = ST_IDLE;
            end

            default: begin
                state_d = ST_IDLE;
            end
        endcase
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state_q            <= ST_IDLE;
            current_addr_q     <= '0;
            remaining_bursts_q <= '0;
            stream_sel_q       <= 1'b0;
        end else begin
            state_q            <= state_d;
            current_addr_q     <= current_addr_d;
            remaining_bursts_q <= remaining_bursts_d;
            stream_sel_q       <= stream_sel_d;
        end
    end

endmodule
