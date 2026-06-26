`timescale 1ns/1ps

// Lightweight protocol checkers for the APB3 control path and the single-
// outstanding AXI read/write masters used by this project.

module apb3_protocol_checker #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32,
    parameter bit ZERO_WAIT  = 1'b1
) (
    input logic                  PCLK,
    input logic                  PRESETn,
    input logic                  PSEL,
    input logic                  PENABLE,
    input logic                  PWRITE,
    input logic [ADDR_WIDTH-1:0] PADDR,
    input logic [DATA_WIDTH-1:0] PWDATA,
    input logic [DATA_WIDTH-1:0] PRDATA,
    input logic                  PREADY,
    input logic                  PSLVERR
);

    logic setup_q;
    logic wait_q;
    logic wait_write_q;
    logic [ADDR_WIDTH-1:0] wait_addr_q;
    logic [DATA_WIDTH-1:0] wait_wdata_q;

    always_ff @(posedge PCLK) begin
        if (!PRESETn) begin
            setup_q      <= 1'b0;
            wait_q       <= 1'b0;
            wait_write_q <= 1'b0;
            wait_addr_q  <= '0;
            wait_wdata_q <= '0;
        end else begin
            assert (!PENABLE || PSEL)
                else $fatal(1, "APB PENABLE asserted without PSEL");

            if (setup_q) begin
                assert (PSEL && PENABLE)
                    else $fatal(1, "APB SETUP was not followed by ACCESS");
            end

            if (wait_q) begin
                assert (PSEL && PENABLE)
                    else $fatal(1, "APB ACCESS ended while PREADY was low");
                assert (PADDR == wait_addr_q && PWRITE == wait_write_q)
                    else $fatal(1, "APB address/control changed during wait state");
                if (wait_write_q) begin
                    assert (PWDATA == wait_wdata_q)
                        else $fatal(1, "APB write data changed during wait state");
                end
            end

            if (PSLVERR) begin
                assert (PSEL && PENABLE && PREADY)
                    else $fatal(1, "APB PSLVERR asserted outside completion cycle");
            end

            if (ZERO_WAIT && PSEL && PENABLE) begin
                assert (PREADY)
                    else $fatal(1, "Zero-wait APB slave deasserted PREADY");
            end

            setup_q <= PSEL && !PENABLE;
            wait_q  <= PSEL && PENABLE && !PREADY;
            if (PSEL && PENABLE && !PREADY) begin
                wait_addr_q  <= PADDR;
                wait_write_q <= PWRITE;
                wait_wdata_q <= PWDATA;
            end

            // PRDATA is intentionally sampled only by the testbench on a
            // completed read transfer. Its value is don't-care otherwise.
        end
    end

endmodule


module axi_read_protocol_checker #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32
) (
    input logic                  ACLK,
    input logic                  ARESETn,
    input logic [ADDR_WIDTH-1:0] ARADDR,
    input logic [7:0]            ARLEN,
    input logic [2:0]            ARSIZE,
    input logic [1:0]            ARBURST,
    input logic                  ARVALID,
    input logic                  ARREADY,
    input logic [DATA_WIDTH-1:0] RDATA,
    input logic [1:0]            RRESP,
    input logic                  RLAST,
    input logic                  RVALID,
    input logic                  RREADY
);

    logic reset_seen_q;
    logic ar_stall_q;
    logic [ADDR_WIDTH-1:0] araddr_hold_q;
    logic [7:0] arlen_hold_q;
    logic [2:0] arsize_hold_q;
    logic [1:0] arburst_hold_q;

    logic r_stall_q;
    logic [DATA_WIDTH-1:0] rdata_hold_q;
    logic [1:0] rresp_hold_q;
    logic rlast_hold_q;

    logic read_active_q;
    logic [7:0] active_arlen_q;
    logic [8:0] read_beat_q;

    function automatic logic crosses_4k(
        input logic [ADDR_WIDTH-1:0] addr,
        input logic [7:0] len,
        input logic [2:0] size
    );
        longint unsigned burst_bytes;
        longint unsigned end_offset;
        begin
            burst_bytes = (longint'(len) + 1) << size;
            end_offset = longint'(addr[11:0]) + burst_bytes;
            crosses_4k = end_offset > 4096;
        end
    endfunction

    always_ff @(posedge ACLK) begin
        if (!ARESETn) begin
            reset_seen_q    <= 1'b1;
            ar_stall_q      <= 1'b0;
            r_stall_q       <= 1'b0;
            read_active_q   <= 1'b0;
            active_arlen_q  <= '0;
            read_beat_q     <= '0;
            araddr_hold_q   <= '0;
            arlen_hold_q    <= '0;
            arsize_hold_q   <= '0;
            arburst_hold_q  <= '0;
            rdata_hold_q    <= '0;
            rresp_hold_q    <= '0;
            rlast_hold_q    <= 1'b0;
        end else begin
            if (reset_seen_q) begin
                assert (!ARVALID)
                    else $fatal(1, "AXI ARVALID remained asserted after reset");
                reset_seen_q <= 1'b0;
            end

            if (ar_stall_q) begin
                assert (ARVALID)
                    else $fatal(1, "AXI ARVALID dropped before AR handshake");
                assert (ARADDR == araddr_hold_q &&
                        ARLEN == arlen_hold_q &&
                        ARSIZE == arsize_hold_q &&
                        ARBURST == arburst_hold_q)
                    else $fatal(1, "AXI AR payload changed under backpressure");
            end

            if (r_stall_q) begin
                assert (RVALID)
                    else $fatal(1, "AXI RVALID dropped before R handshake");
                assert (RDATA == rdata_hold_q &&
                        RRESP == rresp_hold_q &&
                        RLAST == rlast_hold_q)
                    else $fatal(1, "AXI R payload changed under backpressure");
            end

            ar_stall_q <= ARVALID && !ARREADY;
            if (ARVALID && !ARREADY) begin
                araddr_hold_q  <= ARADDR;
                arlen_hold_q   <= ARLEN;
                arsize_hold_q  <= ARSIZE;
                arburst_hold_q <= ARBURST;
            end

            r_stall_q <= RVALID && !RREADY;
            if (RVALID && !RREADY) begin
                rdata_hold_q <= RDATA;
                rresp_hold_q <= RRESP;
                rlast_hold_q <= RLAST;
            end

            if (ARVALID && ARREADY) begin
                assert (!read_active_q)
                    else $fatal(1, "AXI checker supports one outstanding read");
                assert (!crosses_4k(ARADDR, ARLEN, ARSIZE))
                    else $fatal(1, "AXI read burst crosses a 4KB boundary");
                read_active_q  <= 1'b1;
                active_arlen_q <= ARLEN;
                read_beat_q    <= '0;
            end

            if (RVALID && RREADY) begin
                assert (read_active_q)
                    else $fatal(1, "AXI read data accepted without an active request");
                assert (RLAST == (read_beat_q == {1'b0, active_arlen_q}))
                    else $fatal(1, "AXI RLAST does not match ARLEN");

                if (RLAST) begin
                    read_active_q <= 1'b0;
                    read_beat_q   <= '0;
                end else begin
                    read_beat_q <= read_beat_q + 1'b1;
                end
            end
        end
    end

endmodule


module axi_write_protocol_checker #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32
) (
    input logic                       ACLK,
    input logic                       ARESETn,
    input logic [ADDR_WIDTH-1:0]      AWADDR,
    input logic [7:0]                 AWLEN,
    input logic [2:0]                 AWSIZE,
    input logic [1:0]                 AWBURST,
    input logic                       AWVALID,
    input logic                       AWREADY,
    input logic [DATA_WIDTH-1:0]      WDATA,
    input logic [(DATA_WIDTH/8)-1:0]  WSTRB,
    input logic                       WLAST,
    input logic                       WVALID,
    input logic                       WREADY,
    input logic [1:0]                 BRESP,
    input logic                       BVALID,
    input logic                       BREADY
);

    logic reset_seen_q;
    logic aw_stall_q;
    logic [ADDR_WIDTH-1:0] awaddr_hold_q;
    logic [7:0] awlen_hold_q;
    logic [2:0] awsize_hold_q;
    logic [1:0] awburst_hold_q;

    logic w_stall_q;
    logic [DATA_WIDTH-1:0] wdata_hold_q;
    logic [(DATA_WIDTH/8)-1:0] wstrb_hold_q;
    logic wlast_hold_q;

    logic b_stall_q;
    logic [1:0] bresp_hold_q;

    logic aw_seen_q;
    logic [7:0] active_awlen_q;
    logic wlast_seen_q;
    logic [8:0] w_beat_count_q;
    logic [8:0] w_total_count_q;

    function automatic logic crosses_4k(
        input logic [ADDR_WIDTH-1:0] addr,
        input logic [7:0] len,
        input logic [2:0] size
    );
        longint unsigned burst_bytes;
        longint unsigned end_offset;
        begin
            burst_bytes = (longint'(len) + 1) << size;
            end_offset = longint'(addr[11:0]) + burst_bytes;
            crosses_4k = end_offset > 4096;
        end
    endfunction

    always_ff @(posedge ACLK) begin
        if (!ARESETn) begin
            reset_seen_q    <= 1'b1;
            aw_stall_q      <= 1'b0;
            w_stall_q       <= 1'b0;
            b_stall_q       <= 1'b0;
            aw_seen_q       <= 1'b0;
            active_awlen_q  <= '0;
            wlast_seen_q    <= 1'b0;
            w_beat_count_q  <= '0;
            w_total_count_q <= '0;
            awaddr_hold_q   <= '0;
            awlen_hold_q    <= '0;
            awsize_hold_q   <= '0;
            awburst_hold_q  <= '0;
            wdata_hold_q    <= '0;
            wstrb_hold_q    <= '0;
            wlast_hold_q    <= 1'b0;
            bresp_hold_q    <= '0;
        end else begin
            if (reset_seen_q) begin
                assert (!AWVALID && !WVALID)
                    else $fatal(1, "AXI write VALID remained asserted after reset");
                reset_seen_q <= 1'b0;
            end

            if (aw_stall_q) begin
                assert (AWVALID)
                    else $fatal(1, "AXI AWVALID dropped before AW handshake");
                assert (AWADDR == awaddr_hold_q &&
                        AWLEN == awlen_hold_q &&
                        AWSIZE == awsize_hold_q &&
                        AWBURST == awburst_hold_q)
                    else $fatal(1, "AXI AW payload changed under backpressure");
            end

            if (w_stall_q) begin
                assert (WVALID)
                    else $fatal(1, "AXI WVALID dropped before W handshake");
                assert (WDATA == wdata_hold_q &&
                        WSTRB == wstrb_hold_q &&
                        WLAST == wlast_hold_q)
                    else $fatal(1, "AXI W payload changed under backpressure");
            end

            if (b_stall_q) begin
                assert (BVALID)
                    else $fatal(1, "AXI BVALID dropped before B handshake");
                assert (BRESP == bresp_hold_q)
                    else $fatal(1, "AXI BRESP changed under backpressure");
            end

            aw_stall_q <= AWVALID && !AWREADY;
            if (AWVALID && !AWREADY) begin
                awaddr_hold_q  <= AWADDR;
                awlen_hold_q   <= AWLEN;
                awsize_hold_q  <= AWSIZE;
                awburst_hold_q <= AWBURST;
            end

            w_stall_q <= WVALID && !WREADY;
            if (WVALID && !WREADY) begin
                wdata_hold_q <= WDATA;
                wstrb_hold_q <= WSTRB;
                wlast_hold_q <= WLAST;
            end

            b_stall_q <= BVALID && !BREADY;
            if (BVALID && !BREADY) begin
                bresp_hold_q <= BRESP;
            end

            if (AWVALID && AWREADY) begin
                assert (!aw_seen_q)
                    else $fatal(1, "AXI checker supports one outstanding write");
                assert (!crosses_4k(AWADDR, AWLEN, AWSIZE))
                    else $fatal(1, "AXI write burst crosses a 4KB boundary");
                aw_seen_q      <= 1'b1;
                active_awlen_q <= AWLEN;
                if (wlast_seen_q) begin
                    assert (w_total_count_q == ({1'b0, AWLEN} + 1'b1))
                        else $fatal(1, "AXI WLAST position does not match AWLEN");
                end
            end

            if (WVALID && WREADY) begin
                if (WLAST) begin
                    wlast_seen_q    <= 1'b1;
                    w_total_count_q <= w_beat_count_q + 1'b1;
                    if (aw_seen_q) begin
                        assert ((w_beat_count_q + 1'b1) ==
                                ({1'b0, active_awlen_q} + 1'b1))
                            else $fatal(1, "AXI WLAST position does not match AWLEN");
                    end
                end else begin
                    w_beat_count_q <= w_beat_count_q + 1'b1;
                end
            end

            if (BVALID) begin
                assert (aw_seen_q && wlast_seen_q)
                    else $fatal(1, "AXI BVALID asserted before AW and final W acceptance");
            end

            if (BVALID && BREADY) begin
                aw_seen_q       <= 1'b0;
                active_awlen_q  <= '0;
                wlast_seen_q    <= 1'b0;
                w_beat_count_q  <= '0;
                w_total_count_q <= '0;
            end
        end
    end

endmodule
