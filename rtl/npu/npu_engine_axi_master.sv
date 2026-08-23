`timescale 1ns / 1ps

// ============================================================================
// NPU Compute Engine -> AXI4-Lite Master Bridge
//
// Compute Engine'in basit bellek read/write isteklerini
// AXI4-Lite transaction'larina cevirir.
//
// Compute Engine WORD adresi kullanir.
// AXI BYTE adresi kullandigi icin:
//
//   AXI_ADDR = TCM_BASE_ADDR + (word_addr * 4)
//
// READ:
//   req -> AR -> R -> response
//
// WRITE:
//   req -> AW + W -> B -> response
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
    input  logic [12:0] req_addr_i,
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
    // FSM
    // ========================================================================

    typedef enum logic [2:0] {
        IDLE,
        READ_ADDR,
        READ_DATA,
        WRITE_SEND,
        WRITE_RESP
    } state_t;

    state_t state;

    // Request bilgilerini transaction boyunca sakla.
    logic [12:0] req_addr_q;
    logic [31:0] req_wdata_q;
    logic [3:0]  req_wstrb_q;

    // AXI write address ve write data kanallari birbirinden bagimsizdir.
    // Hangisinin kabul edildigini ayri ayri tutuyoruz.
    logic aw_done;
    logic w_done;

    // ========================================================================
    // Sequential logic
    // ========================================================================

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= IDLE;

            req_addr_q  <= '0;
            req_wdata_q <= '0;
            req_wstrb_q <= '0;

            aw_done     <= 1'b0;
            w_done      <= 1'b0;

            rsp_valid_o <= 1'b0;
            rsp_rdata_o <= '0;
            rsp_resp_o  <= 2'b00;

        end else begin

            // Response normalde bir clock pulse.
            rsp_valid_o <= 1'b0;

            case (state)

                // ============================================================
                // Yeni Compute Engine istegi
                // ============================================================
                IDLE: begin
                    aw_done <= 1'b0;
                    w_done  <= 1'b0;

                    if (req_valid_i) begin
                        req_addr_q <= req_addr_i;

                        if (req_write_i) begin
                            req_wdata_q <= req_wdata_i;
                            req_wstrb_q <= req_wstrb_i;
                            state       <= WRITE_SEND;
                        end else begin
                            state <= READ_ADDR;
                        end
                    end
                end

                // ============================================================
                // AXI READ
                // ============================================================

                // Read address handshake
                READ_ADDR: begin
                    if (m_axi_arready) begin
                        state <= READ_DATA;
                    end
                end

                // Read data handshake
                READ_DATA: begin
                    if (m_axi_rvalid) begin
                        rsp_rdata_o <= m_axi_rdata;
                        rsp_resp_o  <= m_axi_rresp;
                        rsp_valid_o <= 1'b1;

                        state <= IDLE;
                    end
                end

                // ============================================================
                // AXI WRITE
                // ============================================================

                // AXI4-Lite'ta AW ve W kanallari bagimsizdir.
                // Ikisi de kabul edilene kadar VALID'ler tutulur.
                WRITE_SEND: begin

                    if (m_axi_awready && !aw_done) begin
                        aw_done <= 1'b1;
                    end

                    if (m_axi_wready && !w_done) begin
                        w_done <= 1'b1;
                    end

                    // Ikisi ayni clock'ta veya farkli clock'larda
                    // kabul edilmis olabilir.
                    if ((aw_done || m_axi_awready) &&
                        (w_done  || m_axi_wready)) begin

                        state <= WRITE_RESP;
                    end
                end

                // Slave'in write response'unu bekle.
                WRITE_RESP: begin
                    if (m_axi_bvalid) begin
                        rsp_rdata_o <= 32'b0;
                        rsp_resp_o  <= m_axi_bresp;
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
    // Combinational outputs
    // ========================================================================

    always_comb begin

        // --------------------------------------------------------------------
        // Compute Engine yeni istegi yalniz IDLE durumunda verebilir.
        // --------------------------------------------------------------------
        req_ready_o = (state == IDLE);

        // --------------------------------------------------------------------
        // AXI WRITE ADDRESS
        // --------------------------------------------------------------------
        m_axi_awaddr =
            TCM_BASE_ADDR + {17'b0, req_addr_q, 2'b00};

        m_axi_awvalid =
            (state == WRITE_SEND) && !aw_done;

        // --------------------------------------------------------------------
        // AXI WRITE DATA
        // --------------------------------------------------------------------
        m_axi_wdata  = req_wdata_q;
        m_axi_wstrb  = req_wstrb_q;

        m_axi_wvalid =
            (state == WRITE_SEND) && !w_done;

        // --------------------------------------------------------------------
        // AXI WRITE RESPONSE
        // --------------------------------------------------------------------
        m_axi_bready = (state == WRITE_RESP);

        // --------------------------------------------------------------------
        // AXI READ ADDRESS
        // --------------------------------------------------------------------
        m_axi_araddr =
            TCM_BASE_ADDR + {17'b0, req_addr_q, 2'b00};

        m_axi_arvalid = (state == READ_ADDR);

        // --------------------------------------------------------------------
        // AXI READ DATA
        // --------------------------------------------------------------------
        m_axi_rready = (state == READ_DATA);

    end

endmodule
