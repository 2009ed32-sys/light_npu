`timescale 1ns/1ps
// APB3 CSB register block for convcore.
//
// Register map matches axi_slave_csb_v1_0:
//   0x00 CDMA_CONTROL
//   0x04 CDMA_STATUS                 read-only from hardware
//   0x08 DATA_MATRIX_WIDTH
//   0x0c DATA_MATRIX_HEIGHT
//   0x10 DATA_CHANNEL_COUNT
//   0x14 DATA_DST_BASE
//   0x18 WEIGHT_MATRIX_WIDTH
//   0x1c WEIGHT_MATRIX_HEIGHT
//   0x20 WEIGHT_CHANNEL_COUNT
//   0x24 WEIGHT_DST_BASE
//   0x28 CSC_CONTROL                  bit 0 auto-clears after write
//   0x2c CSC_STATUS                   read-only from hardware
//   0x30 CSC_ATOMICS
//   0x34 CSC_DATA_BASE
//   0x38 CSC_WEIGHT_BASE
//   0x3c CSC_INPUT_WIDTH_HEIGHT       [15:0] width, [31:16] height
//   0x40 CSC_INPUT_CHANNELS
//   0x44 CSC_KERNEL_WIDTH_HEIGHT      [15:0] width, [31:16] height
//   0x48 CSC_STRIDE_XY                [15:0] stride_x, [31:16] stride_y
//   0x4c CSC_OUTPUT_WIDTH_HEIGHT      [15:0] width, [31:16] height
//   0x50 CSC_OUTPUT_CHANNELS
//
// Status flag extension:
//   CDMA_STATUS/CSC_STATUS[31]         sticky APB invalid-address access
//   CDMA_STATUS/CSC_STATUS[30]         sticky APB write blocked while locked
// Write 1 to either status register bit to clear the corresponding flag.

module apb3_slave #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32,
    parameter int SLVREG_NUM = 21
) (
    input  logic                  PCLK,
    input  logic                  PRESETn,

    input  logic                  PSEL,
    input  logic                  PENABLE,
    input  logic                  PWRITE,
    input  logic [ADDR_WIDTH-1:0] PADDR,
    input  logic [DATA_WIDTH-1:0] PWDATA,

    output logic [DATA_WIDTH-1:0] PRDATA,
    output logic                  PREADY,
    output logic                  PSLVERR,

    output logic [DATA_WIDTH-1:0] CDMA_CONTROL,
    input  logic [DATA_WIDTH-1:0] CDMA_STATUS,
    output logic [DATA_WIDTH-1:0] DATA_MATRIX_WIDTH,
    output logic [DATA_WIDTH-1:0] DATA_MATRIX_HEIGHT,
    output logic [DATA_WIDTH-1:0] DATA_CHANNEL_COUNT,
    output logic [DATA_WIDTH-1:0] DATA_DST_BASE,
    output logic [DATA_WIDTH-1:0] WEIGHT_MATRIX_WIDTH,
    output logic [DATA_WIDTH-1:0] WEIGHT_MATRIX_HEIGHT,
    output logic [DATA_WIDTH-1:0] WEIGHT_CHANNEL_COUNT,
    output logic [DATA_WIDTH-1:0] WEIGHT_DST_BASE,
    output logic [DATA_WIDTH-1:0] CSC_CONTROL,
    input  logic [DATA_WIDTH-1:0] CSC_STATUS,
    output logic [DATA_WIDTH-1:0] CSC_ATOMICS,
    output logic [DATA_WIDTH-1:0] CSC_DATA_BASE,
    output logic [DATA_WIDTH-1:0] CSC_WEIGHT_BASE,
    output logic [DATA_WIDTH-1:0] CSC_INPUT_WIDTH_HEIGHT,
    output logic [DATA_WIDTH-1:0] CSC_INPUT_CHANNELS,
    output logic [DATA_WIDTH-1:0] CSC_KERNEL_WIDTH_HEIGHT,
    output logic [DATA_WIDTH-1:0] CSC_STRIDE_XY,
    output logic [DATA_WIDTH-1:0] CSC_OUTPUT_WIDTH_HEIGHT,
    output logic [DATA_WIDTH-1:0] CSC_OUTPUT_CHANNELS
);

    localparam int ADDR_LSB = $clog2(DATA_WIDTH / 8);
    localparam int REG_IDX_WIDTH =
        (SLVREG_NUM <= 2) ? 1 : $clog2(SLVREG_NUM);

    logic [DATA_WIDTH-1:0] slv_reg [0:SLVREG_NUM-1];

    logic [REG_IDX_WIDTH-1:0] reg_idx;
    logic aligned_addr;
    logic valid_addr;
    logic access_phase;
    logic do_access;
    logic do_write;
    logic write_to_status;
    logic write_to_control;
    logic write_sets_new_control_bit;
    logic clear_control_write;
    logic csc_start_write;
    logic control_write_allowed_while_locked;
    logic cdma_active;
    logic csc_active;
    logic npu_locked;
    logic busy_write_blocked;
    logic invalid_access;
    logic clear_invalid_access_flag;
    logic clear_busy_write_flag;
    logic apb_invalid_access_q;
    logic apb_busy_write_q;

    function automatic logic [DATA_WIDTH-1:0] status_with_apb_flags(
        input logic [DATA_WIDTH-1:0] hw_status
    );
        begin
            status_with_apb_flags = hw_status;
            status_with_apb_flags[DATA_WIDTH-1] = apb_invalid_access_q;
            status_with_apb_flags[DATA_WIDTH-2] = apb_busy_write_q;
        end
    endfunction

    assign access_phase = PSEL && PENABLE;
    assign do_access    = access_phase && PREADY;

    assign reg_idx =
        PADDR[ADDR_LSB + REG_IDX_WIDTH - 1 : ADDR_LSB];
    assign aligned_addr = (PADDR[ADDR_LSB-1:0] == '0);
    assign valid_addr   = aligned_addr && (reg_idx < REG_IDX_WIDTH'(SLVREG_NUM));

    assign PREADY  = 1'b1;
    assign PSLVERR = invalid_access || busy_write_blocked;

    assign invalid_access =
        do_access && !valid_addr;

    assign write_to_status =
        valid_addr &&
        ((reg_idx == REG_IDX_WIDTH'(1)) ||
         (reg_idx == REG_IDX_WIDTH'(11)));

    assign write_to_control =
        valid_addr &&
        ((reg_idx == REG_IDX_WIDTH'(0)) ||
         (reg_idx == REG_IDX_WIDTH'(10)));

    assign cdma_active =
        CDMA_STATUS[0] || CDMA_STATUS[3] ||
        slv_reg[0][0] || slv_reg[0][1];
    assign csc_active =
        CSC_STATUS[1] || slv_reg[10][1];
    assign npu_locked = cdma_active || csc_active;

    assign write_sets_new_control_bit =
        write_to_control &&
        (((reg_idx == REG_IDX_WIDTH'(0)) &&
          (((PWDATA[1:0] & ~slv_reg[0][1:0]) != 2'b00))) ||
         ((reg_idx == REG_IDX_WIDTH'(10)) &&
          (((PWDATA[1:0] & ~slv_reg[10][1:0]) != 2'b00))));

    assign clear_control_write =
        write_to_control && !write_sets_new_control_bit;

    assign csc_start_write =
        (reg_idx == REG_IDX_WIDTH'(10)) &&
        slv_reg[10][1] &&
        PWDATA[0] &&
        CSC_STATUS[0];

    assign control_write_allowed_while_locked =
        clear_control_write || csc_start_write;

    assign busy_write_blocked =
        do_access && PWRITE && valid_addr && npu_locked &&
        !write_to_status && !control_write_allowed_while_locked;

    assign do_write =
        do_access && PWRITE && valid_addr && !busy_write_blocked;

    assign clear_invalid_access_flag =
        do_write && write_to_status && PWDATA[DATA_WIDTH-1];
    assign clear_busy_write_flag =
        do_write && write_to_status && PWDATA[DATA_WIDTH-2];

    always_comb begin
        PRDATA = '0;

        if (valid_addr) begin
            PRDATA = slv_reg[reg_idx];
        end
    end

    always_ff @(posedge PCLK) begin
        if (!PRESETn) begin
            for (int i = 0; i < SLVREG_NUM; i = i + 1) begin
                slv_reg[i] <= '0;
            end
            apb_invalid_access_q <= 1'b0;
            apb_busy_write_q     <= 1'b0;
        end else begin
            slv_reg[1]  <= status_with_apb_flags(CDMA_STATUS);
            slv_reg[11] <= status_with_apb_flags(CSC_STATUS);

            if (invalid_access) begin
                apb_invalid_access_q <= 1'b1;
            end else if (clear_invalid_access_flag) begin
                apb_invalid_access_q <= 1'b0;
            end

            if (busy_write_blocked) begin
                apb_busy_write_q <= 1'b1;
            end else if (clear_busy_write_flag) begin
                apb_busy_write_q <= 1'b0;
            end

            // CSC_CONTROL[0] is op_start and is treated as a one-cycle pulse.
            slv_reg[10][0] <= 1'b0;

            if (do_write) begin
                unique case (reg_idx)
                    REG_IDX_WIDTH'(1),
                    REG_IDX_WIDTH'(11): begin
                        // Hardware status is read-only. APB sticky flags above
                        // are write-one-to-clear through these addresses.
                    end

                    default: begin
                        slv_reg[reg_idx] <= PWDATA;
                    end
                endcase
            end
        end
    end

    assign CDMA_CONTROL            = slv_reg[0];
    assign DATA_MATRIX_WIDTH       = slv_reg[2];
    assign DATA_MATRIX_HEIGHT      = slv_reg[3];
    assign DATA_CHANNEL_COUNT      = slv_reg[4];
    assign DATA_DST_BASE           = slv_reg[5];
    assign WEIGHT_MATRIX_WIDTH     = slv_reg[6];
    assign WEIGHT_MATRIX_HEIGHT    = slv_reg[7];
    assign WEIGHT_CHANNEL_COUNT    = slv_reg[8];
    assign WEIGHT_DST_BASE         = slv_reg[9];
    assign CSC_CONTROL             = slv_reg[10];
    assign CSC_ATOMICS             = slv_reg[12];
    assign CSC_DATA_BASE           = slv_reg[13];
    assign CSC_WEIGHT_BASE         = slv_reg[14];
    assign CSC_INPUT_WIDTH_HEIGHT  = slv_reg[15];
    assign CSC_INPUT_CHANNELS      = slv_reg[16];
    assign CSC_KERNEL_WIDTH_HEIGHT = slv_reg[17];
    assign CSC_STRIDE_XY           = slv_reg[18];
    assign CSC_OUTPUT_WIDTH_HEIGHT = slv_reg[19];
    assign CSC_OUTPUT_CHANNELS     = slv_reg[20];

endmodule
