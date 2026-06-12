`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: Arkhe RTL Team
// Engineer: Antigravity AI
// 
// Create Date: 26.04.2026
// Update Date: 11.06.2026
// Design Name: obi_to_axi_simple
// Module Name: obi_to_axi_simple
// Description: Robust OBI (Open Bus Interface) to AXI4-Lite Master bridge.
//              Correctly manages independent write address/data handshakes and 
//              translates responses back to the OBI protocol.
// 
//////////////////////////////////////////////////////////////////////////////////

module obi_to_axi_simple (
    input  logic        clk_i,
    input  logic        rst_ni,

    // OBI Tarafı (İşlemciye bağlanır)
    input  logic        obi_req_i,
    output logic        obi_gnt_o,
    input  logic [31:0] obi_addr_i,
    input  logic        obi_we_i,
    input  logic [3:0]  obi_be_i,
    input  logic [31:0] obi_wdata_i,
    output logic [31:0] obi_rdata_o,
    output logic        obi_rvalid_o,

    // AXI4-Lite Master Tarafı
    // Yazma Adresi Kanalı
    output logic [31:0] axil_awaddr_o,
    output logic        axil_awvalid_o,
    input  logic        axil_awready_i,
    // Yazma Verisi Kanalı
    output logic [31:0] axil_wdata_o,
    output logic [3:0]  axil_wstrb_o,
    output logic        axil_wvalid_o,
    input  logic        axil_wready_i,
    // Yazma Yanıt Kanalı
    input  logic [1:0]  axil_bresp_i,
    input  logic        axil_bvalid_i,
    output logic        axil_bready_o,
    // Okuma Adresi Kanalı
    output logic [31:0] axil_araddr_o,
    output logic        axil_arvalid_o,
    input  logic        axil_arready_i,
    // Okuma Verisi Kanalı
    input  logic [31:0] axil_rdata_i,
    input  logic [1:0]  axil_rresp_i,
    input  logic        axil_rvalid_i,
    output logic        axil_rready_o
);

    // FSM Durumları
    typedef enum logic [2:0] {
        ST_IDLE,
        ST_WRITE_ADDR_DATA,
        ST_WRITE_RESP,
        ST_READ_ADDR,
        ST_READ_DATA
    } state_t;

    state_t state_q, state_d;

    // Giriş Latch Yazmaçları
    logic [31:0] addr_q, addr_d;
    logic [31:0] wdata_q, wdata_d;
    logic [3:0]  be_q, be_d;
    logic        aw_accepted_q, aw_accepted_d;
    logic        w_accepted_q, w_accepted_d;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            state_q       <= ST_IDLE;
            addr_q        <= '0;
            wdata_q       <= '0;
            be_q          <= '0;
            aw_accepted_q <= 1'b0;
            w_accepted_q  <= 1'b0;
        end else begin
            state_q       <= state_d;
            addr_q        <= addr_d;
            wdata_q       <= wdata_d;
            be_q          <= be_d;
            aw_accepted_q <= aw_accepted_d;
            w_accepted_q  <= w_accepted_d;
        end
    end

    always_comb begin
        state_d       = state_q;
        addr_d        = addr_q;
        wdata_d       = wdata_q;
        be_d          = be_q;
        aw_accepted_d = aw_accepted_q;
        w_accepted_d  = w_accepted_q;

        // Varsayılan AXI Çıkışları
        axil_awaddr_o  = addr_q;
        axil_awvalid_o = 1'b0;
        axil_wdata_o   = wdata_q;
        axil_wstrb_o   = be_q;
        axil_wvalid_o  = 1'b0;
        axil_bready_o  = 1'b0;
        axil_araddr_o  = addr_q;
        axil_arvalid_o = 1'b0;
        axil_rready_o  = 1'b0;

        // Varsayılan OBI Çıkışları
        obi_gnt_o    = 1'b0;
        obi_rvalid_o = 1'b0;
        obi_rdata_o  = '0;

        case (state_q)
            ST_IDLE: begin
                aw_accepted_d = 1'b0;
                w_accepted_d  = 1'b0;
                if (obi_req_i) begin
                    addr_d  = obi_addr_i;
                    wdata_d = obi_wdata_i;
                    be_d    = obi_be_i;
                    if (obi_we_i) begin
                        state_d = ST_WRITE_ADDR_DATA;
                    end else begin
                        state_d = ST_READ_ADDR;
                    end
                end
            end

            ST_WRITE_ADDR_DATA: begin
                axil_awvalid_o = ~aw_accepted_q;
                axil_wvalid_o  = ~w_accepted_q;

                if (axil_awvalid_o && axil_awready_i) begin
                    aw_accepted_d = 1'b1;
                end
                if (axil_wvalid_o && axil_wready_i) begin
                    w_accepted_d = 1'b1;
                end

                // awready ve wready kabul edildiğinde OBI adres fazı onaylanır
                if ((aw_accepted_q || (axil_awvalid_o && axil_awready_i)) && 
                    (w_accepted_q  || (axil_wvalid_o  && axil_wready_i))) begin
                    obi_gnt_o = 1'b1;
                    state_d   = ST_WRITE_RESP;
                end
            end

            ST_WRITE_RESP: begin
                axil_bready_o = 1'b1;
                if (axil_bvalid_i) begin
                    obi_rvalid_o = 1'b1;
                    state_d      = ST_IDLE;
                end
            end

            ST_READ_ADDR: begin
                axil_arvalid_o = 1'b1;
                if (axil_arready_i) begin
                    obi_gnt_o = 1'b1;
                    state_d   = ST_READ_DATA;
                end
            end

            ST_READ_DATA: begin
                axil_rready_o = 1'b1;
                if (axil_rvalid_i) begin
                    obi_rdata_o  = axil_rdata_i;
                    obi_rvalid_o = 1'b1;
                    state_d      = ST_IDLE;
                end
            end
            
            default: state_d = ST_IDLE;
        endcase
    end

endmodule