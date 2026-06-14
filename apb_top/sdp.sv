`timescale 1ns/1ps

// SDP delivery writeback scheduler.
//
// This first SDP version does not implement post-processing. It drains CACC
// delivery FIFO vectors in order and emits one 32-bit write request per valid
// MACCell lane. Address generation is intentionally sequential:
//
//   write_addr = (output_base_addr + write_count) << OUTPUT_ADDR_SHIFT
//
// This keeps SDP independent from CACC's internal output-coordinate generator.

module sdp #(
    parameter int MACCELL_NUM = 8,
    parameter int PSUM_WIDTH  = 32,
    parameter int ADDR_WIDTH  = 32,
    parameter int OUTPUT_ADDR_SHIFT = 2
) (
    input  logic clk,
    input  logic rst_n,

    input  logic op_enable,
    input  logic op_start,
    output logic op_ready,
    output logic op_busy,
    output logic op_done,
    output logic op_error,

    input  logic [ADDR_WIDTH-1:0] output_base_addr,

    input  logic                       cacc_valid,
    output logic                       cacc_ready,
    input  logic [MACCELL_NUM-1:0]     cacc_mask,
    input  logic [(MACCELL_NUM*PSUM_WIDTH)-1:0] cacc_data,
    input  logic                       cacc_last,

    output logic                       write_req_valid,
    input  logic                       write_req_ready,
    output logic [ADDR_WIDTH-1:0]      write_req_addr,
    output logic [PSUM_WIDTH-1:0]      write_req_data,
    output logic [(PSUM_WIDTH/8)-1:0]  write_req_strb,
    output logic                       write_req_last,
    input  logic                       write_done,
    input  logic                       write_error
);

    localparam int PSUM_BYTES = PSUM_WIDTH / 8;
    localparam int LANE_IDX_WIDTH =
        (MACCELL_NUM <= 2) ? 1 : $clog2(MACCELL_NUM);

    typedef enum logic [2:0] {
        ST_IDLE,
        ST_WAIT_CACC,
        ST_SELECT_LANE,
        ST_SEND_REQ,
        ST_WAIT_WRITE_DONE
    } state_t;

    state_t state_q;

    logic [ADDR_WIDTH-1:0] output_base_addr_q;
    logic [ADDR_WIDTH-1:0] write_count_q;
    logic [MACCELL_NUM-1:0] cacc_mask_q;
    logic [(MACCELL_NUM*PSUM_WIDTH)-1:0] cacc_data_q;
    logic cacc_last_q;
    logic [LANE_IDX_WIDTH-1:0] lane_idx_q;

    logic write_req_valid_q;
    logic [ADDR_WIDTH-1:0] write_req_addr_q;
    logic [PSUM_WIDTH-1:0] write_req_data_q;
    logic write_req_last_q;
    logic req_vector_last_q;
    logic op_done_q;
    logic op_error_q;

    logic cacc_accept_w;
    logic selected_lane_valid_w;
    logic selected_lane_vector_last_w;
    logic selected_lane_op_last_w;
    logic write_req_fire_w;
    logic has_later_valid_lane_w;

    assign cacc_ready =
        op_enable &&
        (state_q == ST_WAIT_CACC);
    assign cacc_accept_w = cacc_valid && cacc_ready;

    assign selected_lane_valid_w = cacc_mask_q[lane_idx_q];

    always_comb begin
        has_later_valid_lane_w = 1'b0;
        for (int lane_idx = 0; lane_idx < MACCELL_NUM; lane_idx = lane_idx + 1) begin
            if ((lane_idx > int'(lane_idx_q)) && cacc_mask_q[lane_idx]) begin
                has_later_valid_lane_w = 1'b1;
            end
        end
    end

    assign selected_lane_vector_last_w = !has_later_valid_lane_w;
    assign selected_lane_op_last_w =
        cacc_last_q && selected_lane_vector_last_w;
    assign write_req_fire_w = write_req_valid && write_req_ready;

    assign op_ready =
        op_enable &&
        ((state_q == ST_IDLE) || (state_q == ST_WAIT_CACC));
    assign op_busy = op_enable && (state_q != ST_IDLE);
    assign op_done = op_done_q;
    assign op_error = op_error_q;

    assign write_req_valid = write_req_valid_q;
    assign write_req_addr = write_req_addr_q;
    assign write_req_data = write_req_data_q;
    assign write_req_last = write_req_last_q;

    always_comb begin
        write_req_strb = '0;
        for (int byte_idx = 0; byte_idx < PSUM_BYTES; byte_idx = byte_idx + 1) begin
            write_req_strb[byte_idx] = 1'b1;
        end
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state_q <= ST_IDLE;
            output_base_addr_q <= '0;
            write_count_q <= '0;
            cacc_mask_q <= '0;
            cacc_data_q <= '0;
            cacc_last_q <= 1'b0;
            lane_idx_q <= '0;
            write_req_valid_q <= 1'b0;
            write_req_addr_q <= '0;
            write_req_data_q <= '0;
            write_req_last_q <= 1'b0;
            req_vector_last_q <= 1'b0;
            op_done_q <= 1'b0;
            op_error_q <= 1'b0;
        end else if (!op_enable) begin
            state_q <= ST_IDLE;
            output_base_addr_q <= '0;
            write_count_q <= '0;
            cacc_mask_q <= '0;
            cacc_data_q <= '0;
            cacc_last_q <= 1'b0;
            lane_idx_q <= '0;
            write_req_valid_q <= 1'b0;
            write_req_addr_q <= '0;
            write_req_data_q <= '0;
            write_req_last_q <= 1'b0;
            req_vector_last_q <= 1'b0;
            op_done_q <= 1'b0;
            op_error_q <= 1'b0;
        end else begin
            if (write_error) begin
                op_error_q <= 1'b1;
            end

            case (state_q)
                ST_IDLE: begin
                    write_req_valid_q <= 1'b0;
                    write_req_last_q <= 1'b0;
                    req_vector_last_q <= 1'b0;

                    if (op_start) begin
                        output_base_addr_q <= output_base_addr;
                        write_count_q <= '0;
                        lane_idx_q <= '0;
                        cacc_mask_q <= '0;
                        cacc_data_q <= '0;
                        cacc_last_q <= 1'b0;
                        op_done_q <= 1'b0;
                        op_error_q <= 1'b0;
                        state_q <= ST_WAIT_CACC;
                    end
                end

                ST_WAIT_CACC: begin
                    write_req_valid_q <= 1'b0;
                    write_req_last_q <= 1'b0;
                    req_vector_last_q <= 1'b0;

                    if (op_start) begin
                        output_base_addr_q <= output_base_addr;
                        write_count_q <= '0;
                        lane_idx_q <= '0;
                        op_done_q <= 1'b0;
                        op_error_q <= 1'b0;
                    end

                    if (cacc_accept_w) begin
                        cacc_mask_q <= cacc_mask;
                        cacc_data_q <= cacc_data;
                        cacc_last_q <= cacc_last;
                        lane_idx_q <= '0;
                        state_q <= ST_SELECT_LANE;
                    end
                end

                ST_SELECT_LANE: begin
                    write_req_valid_q <= 1'b0;
                    write_req_last_q <= 1'b0;

                    if (selected_lane_valid_w) begin
                        write_req_addr_q <=
                            (output_base_addr_q + write_count_q) <<
                            OUTPUT_ADDR_SHIFT;
                        write_req_data_q <=
                            cacc_data_q[(lane_idx_q*PSUM_WIDTH) +: PSUM_WIDTH];
                        write_req_last_q <= selected_lane_op_last_w;
                        req_vector_last_q <= selected_lane_vector_last_w;
                        write_req_valid_q <= 1'b1;
                        state_q <= ST_SEND_REQ;
                    end else if (selected_lane_vector_last_w) begin
                        if (cacc_last_q) begin
                            op_done_q <= 1'b1;
                            state_q <= ST_IDLE;
                        end else begin
                            state_q <= ST_WAIT_CACC;
                        end
                    end else begin
                        lane_idx_q <= lane_idx_q + 1'b1;
                    end
                end

                ST_SEND_REQ: begin
                    if (write_req_fire_w) begin
                        write_req_valid_q <= 1'b0;
                        write_count_q <= write_count_q + 1'b1;

                        if (write_req_last_q) begin
                            state_q <= ST_WAIT_WRITE_DONE;
                        end else if (req_vector_last_q) begin
                            state_q <= ST_WAIT_CACC;
                        end else begin
                            lane_idx_q <= lane_idx_q + 1'b1;
                            state_q <= ST_SELECT_LANE;
                        end
                    end
                end

                ST_WAIT_WRITE_DONE: begin
                    write_req_valid_q <= 1'b0;

                    if (write_done) begin
                        op_done_q <= 1'b1;
                        state_q <= ST_IDLE;
                    end else if (write_error) begin
                        state_q <= ST_IDLE;
                    end
                end

                default: begin
                    state_q <= ST_IDLE;
                    write_req_valid_q <= 1'b0;
                    write_req_last_q <= 1'b0;
                    req_vector_last_q <= 1'b0;
                end
            endcase
        end
    end

endmodule
