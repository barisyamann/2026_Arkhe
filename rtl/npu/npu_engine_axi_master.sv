`timescale 1ns / 1ps

// ============================================================================
// NPU Compute Engine -> AXI4-Lite Master Bridge
//
// Bu modul Compute Engine'in basit bellek isteklerini
// AXI4-Lite transaction'larina cevirir.
//
// Asama 1:
//   Sadece READ yolu aktiftir.
//
// TCM adresleri Compute Engine tarafinda WORD adresidir.
// AXI'de BYTE adresi kullanildigi icin:
//   AXI_ADDR = TCM_BASE_ADDR + (word_addr * 4)
// ============================================================================

module npu_engine_axi_master #(
    parameter logic [31:0] TCM_BASE_ADDR = 32'h2001_0000
)(
    input  logic        clk,
    input  logic        rst_n,

    // ------------------------------------------------------------------------
    // Compute Engine tarafi
    // ------------------------------------------------------------------------
    input  logic        req_valid_i,
    input  logic        req_write_i,
    input  logic [12:0] req_addr_i,      // TCM word address
    input  logic [31:0] req_wdata_i,
    input  logic [3:0]  req_wstrb_i,

    output logic        req_ready_o,

    output logic        rsp_valid_o,
    output logic [31:0] rsp_rdata_o,
    output logic [1:0]  rsp_resp_o,

    // ------------------------------------------------------------------------
    // AXI4-Lite Master
    // ------------------------------------------------------------------------

    // Write Address
    output logic [31:0] m_axi_awaddr,
    output logic        m_axi_awvalid,
    input  logic        m_axi_awready,

    // Write Data
    output logic [31:0] m_axi_wdata,
    output logic [3:0]  m_axi_wstrb,
    output logic        m_axi_wvalid,
    input  logic        m_axi_wready,

    // Write Response
    input  logic [1:0]  m_axi_bresp,
    input  logic        m_axi_bvalid,
    output logic        m_axi_bready,

    // Read Address
    output logic [31:0] m_axi_araddr,
    output logic        m_axi_arvalid,
    input  logic        m_axi_arready,

    // Read Data
    input  logic [31:0] m_axi_rdata,
    input  logic [1:0]  m_axi_rresp,
    input  logic        m_axi_rvalid,
    output logic        m_axi_rready
);

    // ========================================================================
    // READ FSM
    // ========================================================================

    typedef enum logic [1:0] {
        IDLE,
        READ_ADDR,
        READ_DATA
    } state_t;

    state_t state;

    // Compute Engine'den gelen adres burada tutulur.
    logic [12:0] req_addr_q;

    // ========================================================================
    // Sequential logic
    // ========================================================================

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= IDLE;
            req_addr_q  <= '0;

            rsp_valid_o <= 1'b0;
            rsp_rdata_o <= '0;
            rsp_resp_o  <= 2'b00;

        end else begin

            // Response normalde tek clock pulse.
            rsp_valid_o <= 1'b0;

            case (state)

                // ------------------------------------------------------------
                // Yeni Compute Engine istegini bekle
                // ------------------------------------------------------------
                IDLE: begin
                    if (req_valid_i && !req_write_i) begin
                        req_addr_q <= req_addr_i;
                        state      <= READ_ADDR;
                    end
                end

                // ------------------------------------------------------------
                // AXI read-address handshake
                // ------------------------------------------------------------
                READ_ADDR: begin
                    if (m_axi_arready) begin
                        state <= READ_DATA;
                    end
                end

                // ------------------------------------------------------------
                // AXI read-data handshake
                // ------------------------------------------------------------
                READ_DATA: begin
                    if (m_axi_rvalid) begin
                        rsp_rdata_o <= m_axi_rdata;
                        rsp_resp_o  <= m_axi_rresp;
                        rsp_valid_o <= 1'b1;

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
    // Combinational AXI outputs
    // ========================================================================

    always_comb begin

        // --------------------------------------------------------------------
        // Compute Engine request kabul sinyali
        // Su an yalniz READ kabul ediyoruz.
        // --------------------------------------------------------------------
        req_ready_o = (state == IDLE) && !req_write_i;

        // --------------------------------------------------------------------
        // WRITE kanallari henuz kullanilmiyor.
        // --------------------------------------------------------------------
        m_axi_awaddr  = 32'b0;
        m_axi_awvalid = 1'b0;

        m_axi_wdata   = 32'b0;
        m_axi_wstrb   = 4'b0000;
        m_axi_wvalid  = 1'b0;

        m_axi_bready  = 1'b0;

        // --------------------------------------------------------------------
        // READ ADDRESS
        //
        // Compute Engine WORD adresi kullanir.
        // AXI BYTE adresi kullandigi icin adres 2 bit sola kaydirilir.
        //
        // Ornek:
        // req_addr_q = 0
        // AXI = 0x20010000
        //
        // req_addr_q = 3584
        // AXI = 0x20013800
        // --------------------------------------------------------------------
        m_axi_araddr =
            TCM_BASE_ADDR + {17'b0, req_addr_q, 2'b00};

        m_axi_arvalid = (state == READ_ADDR);

        // --------------------------------------------------------------------
        // READ DATA
        // --------------------------------------------------------------------
        m_axi_rready = (state == READ_DATA);

    end

endmodule
