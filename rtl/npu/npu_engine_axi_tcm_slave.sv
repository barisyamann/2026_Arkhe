`timescale 1ns / 1ps

// ============================================================================
// NPU Engine AXI4-Lite -> TCM Adapter
//
// Engine tarafindan uretilen AXI4-Lite transaction'larini
// NPU TCM'nin fiziksel portlarina cevirir.
//
// READ:
//   AXI AR/R -> TCM Port B (salt-okunur)
//
// WRITE:
//   AXI AW/W/B -> TCM Port A icin write request
//
// Port A fiziksel arbitrasyonu npu_accelerator seviyesinde yapilacaktir.
// ============================================================================

module npu_engine_axi_tcm_slave #(
    parameter logic [31:0] TCM_BASE_ADDR = 32'h2001_0000,
    parameter int unsigned TCM_WORDS     = 7680
)(
    input  logic        clk,
    input  logic        rst_n,

    // ------------------------------------------------------------------------
    // AXI4-Lite Slave
    // ------------------------------------------------------------------------

    // Write Address
    input  logic [31:0] s_axi_awaddr,
    input  logic        s_axi_awvalid,
    output logic        s_axi_awready,

    // Write Data
    input  logic [31:0] s_axi_wdata,
    input  logic [3:0]  s_axi_wstrb,
    input  logic        s_axi_wvalid,
    output logic        s_axi_wready,

    // Write Response
    output logic [1:0]  s_axi_bresp,
    output logic        s_axi_bvalid,
    input  logic        s_axi_bready,

    // Read Address
    input  logic [31:0] s_axi_araddr,
    input  logic        s_axi_arvalid,
    output logic        s_axi_arready,

    // Read Data
    output logic [31:0] s_axi_rdata,
    output logic [1:0]  s_axi_rresp,
    output logic        s_axi_rvalid,
    input  logic        s_axi_rready,

    // ------------------------------------------------------------------------
    // TCM Port B - READ ONLY
    // ------------------------------------------------------------------------
    output logic        tcm_rd_en_o,
    output logic [12:0] tcm_rd_addr_o,
    input  logic [31:0] tcm_rd_data_i,

    // ------------------------------------------------------------------------
    // TCM Port A icin WRITE REQUEST
    //
    // Daha sonra npu_accelerator'da mevcut Port-A mux'una baglanacak.
    // ------------------------------------------------------------------------
    output logic        tcm_wr_req_o,
    output logic [12:0] tcm_wr_addr_o,
    output logic [31:0] tcm_wr_data_o,
    output logic [3:0]  tcm_wr_strb_o,

    input  logic        tcm_wr_grant_i
);

    // ========================================================================
    // STATE
    // ========================================================================

    typedef enum logic [2:0] {
        IDLE,
        READ_REQ,
        READ_WAIT,
        READ_RESP,
        WRITE_REQ,
        WRITE_RESP
    } state_t;

    state_t state;

    // ========================================================================
    // Registers
    // ========================================================================

    logic [12:0] rd_word_addr_q;
    logic [31:0] rd_data_q;
    logic [1:0]  rd_resp_q;

    logic [12:0] wr_word_addr_q;
    logic [31:0] wr_data_q;
    logic [3:0]  wr_strb_q;
    logic [1:0]  wr_resp_q;

    logic        aw_captured;
    logic        w_captured;

    logic [31:0] awaddr_q;

    // ========================================================================
    // Address helpers
    // ========================================================================

    function automatic logic addr_valid(
        input logic [31:0] addr
    );
        logic [31:0] offset;
        begin
            if (addr < TCM_BASE_ADDR) begin
                addr_valid = 1'b0;
            end else begin
                offset = addr - TCM_BASE_ADDR;

                addr_valid =
                    (offset[1:0] == 2'b00) &&
                    ((offset >> 2) < TCM_WORDS);
            end
        end
    endfunction

    function automatic logic [12:0] addr_to_word(
        input logic [31:0] addr
    );
        logic [31:0] offset;
        begin
            offset       = addr - TCM_BASE_ADDR;
            addr_to_word = offset[14:2];
        end
    endfunction

    // ========================================================================
    // Sequential
    // ========================================================================

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin

            state          <= IDLE;

            rd_word_addr_q <= '0;
            rd_data_q      <= '0;
            rd_resp_q      <= 2'b00;

            wr_word_addr_q <= '0;
            wr_data_q      <= '0;
            wr_strb_q      <= '0;
            wr_resp_q      <= 2'b00;

            aw_captured    <= 1'b0;
            w_captured     <= 1'b0;
            awaddr_q       <= '0;

        end else begin

            case (state)

                // ============================================================
                // IDLE
                // ============================================================

                IDLE: begin

                    // --------------------------------------------------------
                    // READ
                    //
                    // Engine master ayni anda read ve write uretmeyecek.
                    // Read'e burada oncelik veriyoruz.
                    // --------------------------------------------------------
                    if (s_axi_arvalid) begin

                        if (addr_valid(s_axi_araddr)) begin
                            rd_word_addr_q <=
                                addr_to_word(s_axi_araddr);

                            rd_resp_q <= 2'b00; // OKAY
                            state     <= READ_REQ;

                        end else begin
                            rd_data_q <= 32'b0;
                            rd_resp_q <= 2'b11; // DECERR
                            state     <= READ_RESP;
                        end

                    end else begin

                        // ----------------------------------------------------
                        // WRITE ADDRESS
                        // ----------------------------------------------------
                        if (s_axi_awvalid && !aw_captured) begin
                            awaddr_q    <= s_axi_awaddr;
                            aw_captured <= 1'b1;
                        end

                        // ----------------------------------------------------
                        // WRITE DATA
                        // ----------------------------------------------------
                        if (s_axi_wvalid && !w_captured) begin
                            wr_data_q   <= s_axi_wdata;
                            wr_strb_q   <= s_axi_wstrb;
                            w_captured  <= 1'b1;
                        end

                        // AW ve W ayni veya farkli cycle'da gelebilir.
                        if ((aw_captured || s_axi_awvalid) &&
                            (w_captured  || s_axi_wvalid)) begin

                            if (addr_valid(
                                aw_captured
                                    ? awaddr_q
                                    : s_axi_awaddr
                            )) begin

                                wr_word_addr_q <= addr_to_word(
                                    aw_captured
                                        ? awaddr_q
                                        : s_axi_awaddr
                                );

                                wr_resp_q <= 2'b00;
                                state     <= WRITE_REQ;

                            end else begin

                                wr_resp_q <= 2'b11;
                                state     <= WRITE_RESP;
                            end
                        end
                    end
                end

                // ============================================================
                // READ
                // ============================================================

                // TCM Port B'ye adres/en ver.
                READ_REQ: begin
                    state <= READ_WAIT;
                end

                // TCM senkron SRAM:
                // READ_REQ clock'undan sonra veri gecerli hale gelir.
                READ_WAIT: begin
                    rd_data_q <= tcm_rd_data_i;
                    state     <= READ_RESP;
                end

                // AXI RVALID, RREADY handshake
                READ_RESP: begin
                    if (s_axi_rready) begin
                        state <= IDLE;
                    end
                end

                // ============================================================
                // WRITE
                // ============================================================

                // Port A arbitratorunden grant bekle.
                WRITE_REQ: begin
                    if (tcm_wr_grant_i) begin
                        state <= WRITE_RESP;
                    end
                end

                // AXI BVALID, BREADY handshake
                WRITE_RESP: begin
                    if (s_axi_bready) begin

                        aw_captured <= 1'b0;
                        w_captured  <= 1'b0;

                        state <= IDLE;
                    end
                end

                default: begin
                    state <= IDLE;
                end

            endcase
        end
    end

    // ========================================================================
    // Combinational outputs
    // ========================================================================

    always_comb begin

        // Defaults
        s_axi_awready = 1'b0;
        s_axi_wready  = 1'b0;

        s_axi_bvalid  = 1'b0;
        s_axi_bresp   = wr_resp_q;

        s_axi_arready = 1'b0;

        s_axi_rvalid  = 1'b0;
        s_axi_rdata   = rd_data_q;
        s_axi_rresp   = rd_resp_q;

        tcm_rd_en_o   = 1'b0;
        tcm_rd_addr_o = rd_word_addr_q;

        tcm_wr_req_o  = 1'b0;
        tcm_wr_addr_o = wr_word_addr_q;
        tcm_wr_data_o = wr_data_q;
        tcm_wr_strb_o = wr_strb_q;

        case (state)

            // ---------------------------------------------------------------
            IDLE: begin

                s_axi_arready = 1'b1;

                // Read transaction yoksa write kanallarini kabul et.
                if (!s_axi_arvalid) begin
                    s_axi_awready = !aw_captured;
                    s_axi_wready  = !w_captured;
                end
            end

            // ---------------------------------------------------------------
            READ_REQ: begin
                tcm_rd_en_o   = 1'b1;
                tcm_rd_addr_o = rd_word_addr_q;
            end

            READ_RESP: begin
                s_axi_rvalid = 1'b1;
                s_axi_rdata  = rd_data_q;
                s_axi_rresp  = rd_resp_q;
            end

            // ---------------------------------------------------------------
            WRITE_REQ: begin
                tcm_wr_req_o  = 1'b1;
                tcm_wr_addr_o = wr_word_addr_q;
                tcm_wr_data_o = wr_data_q;
                tcm_wr_strb_o = wr_strb_q;
            end

            WRITE_RESP: begin
                s_axi_bvalid = 1'b1;
                s_axi_bresp  = wr_resp_q;
            end

            default: ;

        endcase
    end

endmodule
