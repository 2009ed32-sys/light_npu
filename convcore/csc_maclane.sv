`timescale 1ns/1ps
// CBUF read-data formatter for CSC.
//
// CDMA stores elements by rotating through CBUF banks and pack lanes.  This
// module reverses that placement for the current scheduler packet and builds
// the MACCell lane vectors.

module csc_maclane #(
    parameter int ELEMENT_WIDTH     = 8,
    parameter int BANK_NUM          = 8,
    parameter int MACCELL_NUM       = 8,
    parameter int MACLANE_NUM       = 4,
    parameter int BANK_SEL_WIDTH    = (BANK_NUM <= 2) ? 1 : $clog2(BANK_NUM),
    parameter int PACK_LANE_WIDTH   = (MACLANE_NUM <= 2) ? 1 : $clog2(MACLANE_NUM)
) (
    input  logic [BANK_SEL_WIDTH-1:0] data_bank_start,
    input  logic [PACK_LANE_WIDTH-1:0] data_pack_lane,
    input  logic [BANK_SEL_WIDTH-1:0] weight_bank_start,
    input  logic [PACK_LANE_WIDTH-1:0] weight_pack_lane,

    input  logic [(BANK_NUM*MACLANE_NUM*ELEMENT_WIDTH)-1:0] data_cbuf_rd_data,
    input  logic [(BANK_NUM*MACLANE_NUM*ELEMENT_WIDTH)-1:0] weight_cbuf_rd_data,

    output logic [(MACCELL_NUM*MACLANE_NUM*ELEMENT_WIDTH)-1:0] maccell_data,
    output logic [(MACCELL_NUM*MACLANE_NUM*ELEMENT_WIDTH)-1:0] maccell_weight
);

    localparam int MAC_VEC_WIDTH = MACCELL_NUM * MACLANE_NUM * ELEMENT_WIDTH;

    logic [MACLANE_NUM*ELEMENT_WIDTH-1:0] data_lanes_w;

    function automatic logic [BANK_SEL_WIDTH-1:0] packet_bank(
        input logic [BANK_SEL_WIDTH-1:0] bank_start,
        input int unsigned elem_offset
    );
        int unsigned bank_linear;
        begin
            bank_linear = int'(bank_start) + elem_offset;
            packet_bank = BANK_SEL_WIDTH'(bank_linear % BANK_NUM);
        end
    endfunction

    function automatic logic [PACK_LANE_WIDTH-1:0] packet_pack_lane(
        input logic [BANK_SEL_WIDTH-1:0] bank_start,
        input logic [PACK_LANE_WIDTH-1:0] pack_start,
        input int unsigned elem_offset
    );
        int unsigned bank_linear;
        int unsigned pack_linear;
        begin
            bank_linear = int'(bank_start) + elem_offset;
            pack_linear = int'(pack_start) + (bank_linear / BANK_NUM);
            packet_pack_lane = PACK_LANE_WIDTH'(pack_linear % MACLANE_NUM);
        end
    endfunction

    always_comb begin
        logic [BANK_SEL_WIDTH-1:0] src_bank;
        logic [PACK_LANE_WIDTH-1:0] src_pack;

        data_lanes_w = '0;
        maccell_data = '0;
        maccell_weight = '0;
        src_bank = '0;
        src_pack = '0;

        for (int lane_idx = 0; lane_idx < MACLANE_NUM; lane_idx = lane_idx + 1) begin
            src_bank = packet_bank(data_bank_start, lane_idx);
            src_pack = packet_pack_lane(data_bank_start, data_pack_lane, lane_idx);

            for (int bank_idx = 0; bank_idx < BANK_NUM; bank_idx = bank_idx + 1) begin
                for (int pack_idx = 0; pack_idx < MACLANE_NUM; pack_idx = pack_idx + 1) begin
                    if ((src_bank == BANK_SEL_WIDTH'(bank_idx)) &&
                        (src_pack == PACK_LANE_WIDTH'(pack_idx))) begin
                        data_lanes_w[
                            (lane_idx*ELEMENT_WIDTH)+:ELEMENT_WIDTH
                        ] = data_cbuf_rd_data[
                            ((bank_idx*MACLANE_NUM + pack_idx)*ELEMENT_WIDTH)
                            +:ELEMENT_WIDTH
                        ];
                    end
                end
            end
        end

        for (int cell_idx = 0; cell_idx < MACCELL_NUM; cell_idx = cell_idx + 1) begin
            for (int lane_idx = 0; lane_idx < MACLANE_NUM; lane_idx = lane_idx + 1) begin
                maccell_data[
                    ((cell_idx*MACLANE_NUM + lane_idx)*ELEMENT_WIDTH)
                    +:ELEMENT_WIDTH
                ] = data_lanes_w[(lane_idx*ELEMENT_WIDTH)+:ELEMENT_WIDTH];

                src_bank =
                    packet_bank(
                        weight_bank_start,
                        (cell_idx*MACLANE_NUM) + lane_idx
                    );
                src_pack =
                    packet_pack_lane(
                        weight_bank_start,
                        weight_pack_lane,
                        (cell_idx*MACLANE_NUM) + lane_idx
                    );

                for (int bank_idx = 0; bank_idx < BANK_NUM; bank_idx = bank_idx + 1) begin
                    for (int pack_idx = 0; pack_idx < MACLANE_NUM; pack_idx = pack_idx + 1) begin
                        if ((src_bank == BANK_SEL_WIDTH'(bank_idx)) &&
                            (src_pack == PACK_LANE_WIDTH'(pack_idx))) begin
                            maccell_weight[
                                ((cell_idx*MACLANE_NUM + lane_idx)*ELEMENT_WIDTH)
                                +:ELEMENT_WIDTH
                            ] = weight_cbuf_rd_data[
                                ((bank_idx*MACLANE_NUM + pack_idx)*ELEMENT_WIDTH)
                                +:ELEMENT_WIDTH
                            ];
                        end
                    end
                end
            end
        end
    end

endmodule
