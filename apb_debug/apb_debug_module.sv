`timescale 1ns/1ps

module apb_debug_module #(
    parameter int ADDR_WIDTH          = 32,
    parameter int DATA_WIDTH          = 32,
    parameter int DEBUG_DATA_WIDTH    = 256,
    parameter int DEBUG_BUFFER_DEPTH  = 16
) (
    input  logic                        PCLK,
    input  logic                        PRESETn,

    input  logic                        PSEL,
    input  logic                        PENABLE,
    input  logic                        PWRITE,
    input  logic [ADDR_WIDTH-1:0]       PADDR,
    input  logic [DATA_WIDTH-1:0]       PWDATA,

    output logic [DATA_WIDTH-1:0]       PRDATA,
    output logic                        PREADY,
    output logic                        PSLVERR,

    input  logic [DEBUG_DATA_WIDTH-1:0] debug_port,
    input  logic                        debug_valid
);

    localparam int ADDR_LSB = $clog2(DATA_WIDTH / 8);
    localparam int DEBUG_WORDS = DEBUG_DATA_WIDTH / DATA_WIDTH;
    localparam int BUFFER_IDX_WIDTH =
        (DEBUG_BUFFER_DEPTH <= 2) ? 1 : $clog2(DEBUG_BUFFER_DEPTH);
    localparam int BUFFER_COUNT_WIDTH =
        (DEBUG_BUFFER_DEPTH <= 1) ? 1 : $clog2(DEBUG_BUFFER_DEPTH + 1);
    localparam int REG_NUM = DEBUG_WORDS + 4;
    localparam int REG_IDX_WIDTH = (REG_NUM <= 2) ? 1 : $clog2(REG_NUM);

    localparam logic [REG_IDX_WIDTH-1:0] REG_CONTROL    = REG_IDX_WIDTH'(0);
    localparam logic [REG_IDX_WIDTH-1:0] REG_STATUS     = REG_IDX_WIDTH'(1);
    localparam logic [REG_IDX_WIDTH-1:0] REG_READ_INDEX = REG_IDX_WIDTH'(2);
    localparam logic [REG_IDX_WIDTH-1:0] REG_COUNT      = REG_IDX_WIDTH'(3);
    localparam logic [REG_IDX_WIDTH-1:0] REG_DATA0      = REG_IDX_WIDTH'(4);

    logic [REG_IDX_WIDTH-1:0]     reg_idx;
    logic                         aligned_addr;
    logic                         valid_addr;
    logic                         access_phase;
    logic                         do_access;
    logic                         do_write;
    logic                         clear_buffer_w;
    logic                         buffer_non_empty_w;
    logic                         buffer_full_w;
    logic                         capture_seen_w;
    logic                         capture_accept_w;
    logic                         capture_drop_w;
    logic [REG_IDX_WIDTH-1:0]     data_word_idx_w;
    logic [DATA_WIDTH-1:0]        count_ext_w;
    logic [DATA_WIDTH-1:0]        wr_ptr_ext_w;
    logic [DATA_WIDTH-1:0]        read_index_ext_w;

    logic                         capture_enable_q;
    logic                         freeze_q;
    logic                         overwrite_enable_q;
    logic                         irq_enable_q;
    logic                         overflow_q;
    logic [BUFFER_IDX_WIDTH-1:0]  wr_ptr_q;
    logic [BUFFER_IDX_WIDTH-1:0]  read_index_q;
    logic [BUFFER_COUNT_WIDTH-1:0] stored_count_q;
    logic [DATA_WIDTH-1:0]        capture_count_q;

    (* ram_style = "registers" *)
    logic [DATA_WIDTH-1:0] snapshot_mem [0:DEBUG_BUFFER_DEPTH-1][0:DEBUG_WORDS-1];

    function automatic logic [BUFFER_IDX_WIDTH-1:0] buffer_ptr_inc(
        input logic [BUFFER_IDX_WIDTH-1:0] ptr
    );
        begin
            if (ptr == BUFFER_IDX_WIDTH'(DEBUG_BUFFER_DEPTH - 1)) begin
                buffer_ptr_inc = '0;
            end else begin
                buffer_ptr_inc = ptr + 1'b1;
            end
        end
    endfunction

    function automatic logic [BUFFER_IDX_WIDTH-1:0] sanitize_index(
        input logic [DATA_WIDTH-1:0] value
    );
        begin
            if (value >= DATA_WIDTH'(DEBUG_BUFFER_DEPTH)) begin
                sanitize_index = '0;
            end else begin
                sanitize_index = value[BUFFER_IDX_WIDTH-1:0];
            end
        end
    endfunction

    assign access_phase = PSEL && PENABLE;
    assign do_access    = access_phase && PREADY;

    assign reg_idx =
        PADDR[ADDR_LSB + REG_IDX_WIDTH - 1 : ADDR_LSB];
    assign aligned_addr = (PADDR[ADDR_LSB-1:0] == '0);
    assign valid_addr   = aligned_addr && (reg_idx < REG_IDX_WIDTH'(REG_NUM));

    assign PREADY  = 1'b1;
    assign PSLVERR = do_access && !valid_addr;

    assign do_write = do_access && PWRITE && valid_addr;
    assign clear_buffer_w =
        do_write && (reg_idx == REG_CONTROL) && PWDATA[0];

    assign buffer_non_empty_w = (stored_count_q != '0);
    assign buffer_full_w =
        (stored_count_q == BUFFER_COUNT_WIDTH'(DEBUG_BUFFER_DEPTH));

    assign capture_seen_w =
        debug_valid && capture_enable_q && !freeze_q;
    assign capture_accept_w =
        capture_seen_w &&
        (!buffer_full_w || overwrite_enable_q);
    assign capture_drop_w =
        capture_seen_w && buffer_full_w && !overwrite_enable_q;

    assign data_word_idx_w = reg_idx - REG_DATA0;
    assign count_ext_w = DATA_WIDTH'(stored_count_q);
    assign wr_ptr_ext_w = DATA_WIDTH'(wr_ptr_q);
    assign read_index_ext_w = DATA_WIDTH'(read_index_q);

    assign debug_irq = irq_enable_q && buffer_non_empty_w;

    always_comb begin
        PRDATA = '0;

        if (valid_addr) begin
            unique case (reg_idx)
                REG_CONTROL: begin
                    PRDATA[1] = capture_enable_q;
                    PRDATA[2] = freeze_q;
                    PRDATA[3] = overwrite_enable_q;
                    PRDATA[4] = irq_enable_q;
                end

                REG_STATUS: begin
                    PRDATA[0]     = buffer_non_empty_w;
                    PRDATA[1]     = buffer_full_w;
                    PRDATA[2]     = overflow_q;
                    PRDATA[3]     = capture_enable_q;
                    PRDATA[4]     = freeze_q;
                    PRDATA[5]     = debug_irq;
                    PRDATA[15:8]  = count_ext_w[7:0];
                    PRDATA[23:16] = wr_ptr_ext_w[7:0];
                    PRDATA[31:24] = read_index_ext_w[7:0];
                end

                REG_READ_INDEX: begin
                    PRDATA = read_index_ext_w;
                end

                REG_COUNT: begin
                    PRDATA = capture_count_q;
                end

                default: begin
                    if ((reg_idx >= REG_DATA0) &&
                        (reg_idx < REG_IDX_WIDTH'(REG_NUM))) begin
                        PRDATA = snapshot_mem[read_index_q][data_word_idx_w];
                    end
                end
            endcase
        end
    end

    always_ff @(posedge PCLK) begin
        if (!PRESETn) begin
            capture_enable_q <= 1'b0;
            freeze_q <= 1'b0;
            overwrite_enable_q <= 1'b0;
            irq_enable_q <= 1'b0;
            overflow_q <= 1'b0;
            wr_ptr_q <= '0;
            read_index_q <= '0;
            stored_count_q <= '0;
            capture_count_q <= '0;

            for (int slot_idx = 0; slot_idx < DEBUG_BUFFER_DEPTH; slot_idx = slot_idx + 1) begin
                for (int word_idx = 0; word_idx < DEBUG_WORDS; word_idx = word_idx + 1) begin
                    snapshot_mem[slot_idx][word_idx] <= '0;
                end
            end
        end else begin
            if (do_write && (reg_idx == REG_CONTROL)) begin
                capture_enable_q <= PWDATA[1];
                freeze_q <= PWDATA[2];
                overwrite_enable_q <= PWDATA[3];
                irq_enable_q <= PWDATA[4];
            end

            if (do_write && (reg_idx == REG_READ_INDEX)) begin
                read_index_q <= sanitize_index(PWDATA);
            end

            if (clear_buffer_w) begin
                overflow_q <= 1'b0;
                wr_ptr_q <= '0;
                read_index_q <= '0;
                stored_count_q <= '0;
                capture_count_q <= '0;
            end else begin
                if (capture_seen_w) begin
                    capture_count_q <= capture_count_q + DATA_WIDTH'(1);
                end

                if (capture_accept_w) begin
                    for (int word_idx = 0; word_idx < DEBUG_WORDS; word_idx = word_idx + 1) begin
                        snapshot_mem[wr_ptr_q][word_idx] <=
                            debug_port[(word_idx * DATA_WIDTH) +: DATA_WIDTH];
                    end

                    wr_ptr_q <= buffer_ptr_inc(wr_ptr_q);

                    if (!buffer_full_w) begin
                        stored_count_q <= stored_count_q + 1'b1;
                    end else begin
                        overflow_q <= 1'b1;
                    end
                end else if (capture_drop_w) begin
                    overflow_q <= 1'b1;
                end
            end
        end
    end

endmodule
