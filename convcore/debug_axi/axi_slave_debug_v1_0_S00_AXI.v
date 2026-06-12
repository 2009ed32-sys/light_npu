    `timescale 1 ns / 1 ps

    // AXI-Lite register block for MACLane debug packets.
    //
    // Suggested external base address: 0x4001_0000
    //
    // Internal register map:
    //   0x00 CONTROL
    //        bit 0 enable
    //        bit 1 clear_status pulse, write-one
    //        bit 2 irq_enable
    //        bit 3 hold_enable
    //        bit 4 compare_enable
    //        bit 5 continue pulse, write-one
    //        bit 6 compare_strobe pulse, write-one
    //   0x04 EXPECTED_WORD0, packet bits [31:0]
    //   0x08 EXPECTED_WORD1, packet bits [63:32]
    //   0x0C EXPECTED_WORD2, packet bits [95:64]
    //   0x10 EXPECTED_WORD3, packet bits [127:96]
    //   0x14 ID            read-only 0x44424731 ("DBG1")
    //   0x18 BASEADDR      read-only suggested base address
    //   0x20 STATUS_WORD0, debug_status_packet bits [31:0]
    //   0x24 STATUS_WORD1, debug_status_packet bits [63:32]
    //   0x28 STATUS_WORD2, debug_status_packet bits [95:64]
    //   0x2C STATUS_WORD3, debug_status_packet bits [127:96]
    //   0x30 STATUS_WORD4, debug_status_packet bits [159:128]
    //   0x34 STATUS_WORD5, debug_status_packet bits [191:160]
    //   0x38 STATUS_WORD6, debug_status_packet bits [223:192]
    //   0x3C STATUS_WORD7, debug_status_packet bits [255:224]
    //   0x40 STATUS_WORD8, debug_status_packet bits [287:256]

    module axi_slave_debug_v1_0_S00_AXI #(
        parameter integer C_S_AXI_DATA_WIDTH = 32,
        parameter integer C_S_AXI_ADDR_WIDTH = 7,
        parameter integer MACCELL_NUM = 8,
        parameter integer DEBUG_TAG_WIDTH = 32,
        parameter integer DEBUG_SELECT_WIDTH = 3,
        parameter integer DEBUG_LANE_WIDTH = 32,
        parameter integer DEBUG_CONTROL_WIDTH = 8,
        parameter integer DEBUG_EXPECTED_PACKET_WIDTH =
            (2 * DEBUG_LANE_WIDTH) + DEBUG_TAG_WIDTH + DEBUG_SELECT_WIDTH + 4,
        parameter integer DEBUG_STATUS_PACKET_BASE_WIDTH =
            129 + DEBUG_TAG_WIDTH + (2 * MACCELL_NUM) + (2 * DEBUG_LANE_WIDTH),
        parameter integer DEBUG_STATUS_PACKET_WIDTH =
            (((DEBUG_STATUS_PACKET_BASE_WIDTH + 31) / 32) * 32) + 32,
        parameter integer C_DEBUG_BASEADDR = 32'h4001_0000
    ) (
        output wire [DEBUG_CONTROL_WIDTH-1:0] DEBUG_CONTROL_PACKET,
        output wire [DEBUG_EXPECTED_PACKET_WIDTH-1:0] DEBUG_EXPECTED_PACKET,
        input  wire [DEBUG_STATUS_PACKET_WIDTH-1:0] DEBUG_STATUS_PACKET,

        input  wire S_AXI_ACLK,
        input  wire S_AXI_ARESETN,
        input  wire [C_S_AXI_ADDR_WIDTH-1:0] S_AXI_AWADDR,
        input  wire [2:0] S_AXI_AWPROT,
        input  wire S_AXI_AWVALID,
        output wire S_AXI_AWREADY,
        input  wire [C_S_AXI_DATA_WIDTH-1:0] S_AXI_WDATA,
        input  wire [(C_S_AXI_DATA_WIDTH/8)-1:0] S_AXI_WSTRB,
        input  wire S_AXI_WVALID,
        output wire S_AXI_WREADY,
        output wire [1:0] S_AXI_BRESP,
        output wire S_AXI_BVALID,
        input  wire S_AXI_BREADY,
        input  wire [C_S_AXI_ADDR_WIDTH-1:0] S_AXI_ARADDR,
        input  wire [2:0] S_AXI_ARPROT,
        input  wire S_AXI_ARVALID,
        output wire S_AXI_ARREADY,
        output wire [C_S_AXI_DATA_WIDTH-1:0] S_AXI_RDATA,
        output wire [1:0] S_AXI_RRESP,
        output wire S_AXI_RVALID,
        input  wire S_AXI_RREADY
    );

        localparam integer ADDR_LSB = 2;
        localparam integer REG_ADDR_WIDTH = 5;
        localparam integer STATUS_STORAGE_WIDTH =
            (DEBUG_STATUS_PACKET_WIDTH > 288) ?
            (((DEBUG_STATUS_PACKET_WIDTH + 31) / 32) * 32) : 288;
        localparam [31:0] DEBUG_ID = 32'h4442_4731;

        reg [C_S_AXI_ADDR_WIDTH-1:0] axi_awaddr;
        reg axi_awready;
        reg axi_wready;
        reg [1:0] axi_bresp;
        reg axi_bvalid;
        reg [C_S_AXI_ADDR_WIDTH-1:0] axi_araddr;
        reg axi_arready;
        reg [C_S_AXI_DATA_WIDTH-1:0] axi_rdata;
        reg [1:0] axi_rresp;
        reg axi_rvalid;
        reg aw_en;

        wire slv_reg_wren;
        wire slv_reg_rden;
        wire [REG_ADDR_WIDTH-1:0] wr_addr;
        wire [REG_ADDR_WIDTH-1:0] rd_addr;

        reg [31:0] control_reg;
        reg [31:0] expected_word0_reg;
        reg [31:0] expected_word1_reg;
        reg [31:0] expected_word2_reg;
        reg [31:0] expected_word3_reg;
        reg clear_status_pulse_q;
        reg continue_pulse_q;
        reg compare_strobe_pulse_q;
        reg [31:0] reg_data_out;

        wire [127:0] expected_packet_storage;
        wire [STATUS_STORAGE_WIDTH-1:0] status_packet_storage;

        assign S_AXI_AWREADY = axi_awready;
        assign S_AXI_WREADY = axi_wready;
        assign S_AXI_BRESP = axi_bresp;
        assign S_AXI_BVALID = axi_bvalid;
        assign S_AXI_ARREADY = axi_arready;
        assign S_AXI_RDATA = axi_rdata;
        assign S_AXI_RRESP = axi_rresp;
        assign S_AXI_RVALID = axi_rvalid;

        assign slv_reg_wren =
            axi_wready && S_AXI_WVALID && axi_awready && S_AXI_AWVALID;
        assign slv_reg_rden =
            axi_arready && S_AXI_ARVALID && !axi_rvalid;

        assign wr_addr =
            axi_awaddr[ADDR_LSB + REG_ADDR_WIDTH - 1:ADDR_LSB];
        assign rd_addr =
            axi_araddr[ADDR_LSB + REG_ADDR_WIDTH - 1:ADDR_LSB];

        assign expected_packet_storage = {
            expected_word3_reg,
            expected_word2_reg,
            expected_word1_reg,
            expected_word0_reg
        };

        assign DEBUG_EXPECTED_PACKET =
            expected_packet_storage[DEBUG_EXPECTED_PACKET_WIDTH-1:0];

        assign status_packet_storage =
            {{(STATUS_STORAGE_WIDTH - DEBUG_STATUS_PACKET_WIDTH){1'b0}},
             DEBUG_STATUS_PACKET};

        assign DEBUG_CONTROL_PACKET[0] = control_reg[0];
        assign DEBUG_CONTROL_PACKET[1] = clear_status_pulse_q;
        assign DEBUG_CONTROL_PACKET[2] = control_reg[2];
        assign DEBUG_CONTROL_PACKET[3] = control_reg[3];
        assign DEBUG_CONTROL_PACKET[4] = control_reg[4];
        assign DEBUG_CONTROL_PACKET[5] = continue_pulse_q;
        assign DEBUG_CONTROL_PACKET[6] = compare_strobe_pulse_q;
        assign DEBUG_CONTROL_PACKET[DEBUG_CONTROL_WIDTH-1:7] =
            {(DEBUG_CONTROL_WIDTH > 7 ? DEBUG_CONTROL_WIDTH - 7 : 1){1'b0}};

        function [31:0] apply_wstrb;
            input [31:0] old_value;
            input [31:0] new_value;
            input [3:0] strobe;
            integer byte_index;
            begin
                apply_wstrb = old_value;
                for (byte_index = 0; byte_index < 4; byte_index = byte_index + 1) begin
                    if (strobe[byte_index]) begin
                        apply_wstrb[(byte_index*8)+:8] =
                            new_value[(byte_index*8)+:8];
                    end
                end
            end
        endfunction

        always @(posedge S_AXI_ACLK) begin
            if (S_AXI_ARESETN == 1'b0) begin
                axi_awready <= 1'b0;
                aw_en <= 1'b1;
            end else begin
                if (!axi_awready && S_AXI_AWVALID && S_AXI_WVALID && aw_en) begin
                    axi_awready <= 1'b1;
                    aw_en <= 1'b0;
                end else if (S_AXI_BREADY && axi_bvalid) begin
                    aw_en <= 1'b1;
                    axi_awready <= 1'b0;
                end else begin
                    axi_awready <= 1'b0;
                end
            end
        end

        always @(posedge S_AXI_ACLK) begin
            if (S_AXI_ARESETN == 1'b0) begin
                axi_awaddr <= {C_S_AXI_ADDR_WIDTH{1'b0}};
            end else if (!axi_awready && S_AXI_AWVALID && S_AXI_WVALID && aw_en) begin
                axi_awaddr <= S_AXI_AWADDR;
            end
        end

        always @(posedge S_AXI_ACLK) begin
            if (S_AXI_ARESETN == 1'b0) begin
                axi_wready <= 1'b0;
            end else begin
                if (!axi_wready && S_AXI_WVALID && S_AXI_AWVALID && aw_en) begin
                    axi_wready <= 1'b1;
                end else begin
                    axi_wready <= 1'b0;
                end
            end
        end

        always @(posedge S_AXI_ACLK) begin
            if (S_AXI_ARESETN == 1'b0) begin
                control_reg <= 32'b0;
                expected_word0_reg <= 32'b0;
                expected_word1_reg <= 32'b0;
                expected_word2_reg <= 32'b0;
                expected_word3_reg <= 32'b0;
                clear_status_pulse_q <= 1'b0;
                continue_pulse_q <= 1'b0;
                compare_strobe_pulse_q <= 1'b0;
            end else begin
                clear_status_pulse_q <= 1'b0;
                continue_pulse_q <= 1'b0;
                compare_strobe_pulse_q <= 1'b0;

                if (slv_reg_wren) begin
                    case (wr_addr)
                        5'h00: begin
                            control_reg <= apply_wstrb(
                                control_reg,
                                S_AXI_WDATA,
                                S_AXI_WSTRB
                            ) & 32'h0000_001d;

                            if (S_AXI_WSTRB[0]) begin
                                clear_status_pulse_q <= S_AXI_WDATA[1];
                                continue_pulse_q <= S_AXI_WDATA[5];
                                compare_strobe_pulse_q <= S_AXI_WDATA[6];
                            end
                        end

                        5'h01: begin
                            expected_word0_reg <= apply_wstrb(
                                expected_word0_reg,
                                S_AXI_WDATA,
                                S_AXI_WSTRB
                            );
                        end

                        5'h02: begin
                            expected_word1_reg <= apply_wstrb(
                                expected_word1_reg,
                                S_AXI_WDATA,
                                S_AXI_WSTRB
                            );
                        end

                        5'h03: begin
                            expected_word2_reg <= apply_wstrb(
                                expected_word2_reg,
                                S_AXI_WDATA,
                                S_AXI_WSTRB
                            );
                        end

                        5'h04: begin
                            expected_word3_reg <= apply_wstrb(
                                expected_word3_reg,
                                S_AXI_WDATA,
                                S_AXI_WSTRB
                            );
                        end

                        default: begin
                        end
                    endcase
                end
            end
        end

        always @(posedge S_AXI_ACLK) begin
            if (S_AXI_ARESETN == 1'b0) begin
                axi_bvalid <= 1'b0;
                axi_bresp <= 2'b00;
            end else begin
                if (axi_awready && S_AXI_AWVALID && !axi_bvalid &&
                    axi_wready && S_AXI_WVALID) begin
                    axi_bvalid <= 1'b1;
                    axi_bresp <= 2'b00;
                end else if (S_AXI_BREADY && axi_bvalid) begin
                    axi_bvalid <= 1'b0;
                end
            end
        end

        always @(posedge S_AXI_ACLK) begin
            if (S_AXI_ARESETN == 1'b0) begin
                axi_arready <= 1'b0;
                axi_araddr <= {C_S_AXI_ADDR_WIDTH{1'b0}};
            end else begin
                if (!axi_arready && S_AXI_ARVALID) begin
                    axi_arready <= 1'b1;
                    axi_araddr <= S_AXI_ARADDR;
                end else begin
                    axi_arready <= 1'b0;
                end
            end
        end

        always @(*) begin
            reg_data_out = 32'b0;

            case (rd_addr)
                5'h00: reg_data_out = control_reg;
                5'h01: reg_data_out = expected_word0_reg;
                5'h02: reg_data_out = expected_word1_reg;
                5'h03: reg_data_out = expected_word2_reg;
                5'h04: reg_data_out = expected_word3_reg;
                5'h05: reg_data_out = DEBUG_ID;
                5'h06: reg_data_out = C_DEBUG_BASEADDR;
                5'h08: reg_data_out = status_packet_storage[31:0];
                5'h09: reg_data_out = status_packet_storage[63:32];
                5'h0a: reg_data_out = status_packet_storage[95:64];
                5'h0b: reg_data_out = status_packet_storage[127:96];
                5'h0c: reg_data_out = status_packet_storage[159:128];
                5'h0d: reg_data_out = status_packet_storage[191:160];
                5'h0e: reg_data_out = status_packet_storage[223:192];
                5'h0f: reg_data_out = status_packet_storage[255:224];
                5'h10: reg_data_out = status_packet_storage[287:256];
                default: reg_data_out = 32'b0;
            endcase
        end

        always @(posedge S_AXI_ACLK) begin
            if (S_AXI_ARESETN == 1'b0) begin
                axi_rvalid <= 1'b0;
                axi_rresp <= 2'b00;
            end else begin
                if (slv_reg_rden) begin
                    axi_rvalid <= 1'b1;
                    axi_rresp <= 2'b00;
                end else if (axi_rvalid && S_AXI_RREADY) begin
                    axi_rvalid <= 1'b0;
                end
            end
        end

        always @(posedge S_AXI_ACLK) begin
            if (S_AXI_ARESETN == 1'b0) begin
                axi_rdata <= 32'b0;
            end else if (slv_reg_rden) begin
                axi_rdata <= reg_data_out;
            end
        end

    endmodule
