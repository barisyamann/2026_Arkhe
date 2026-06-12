`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: Arkhe RTL Team
// Engineer: Antigravity AI
// 
// Create Date: 12.06.2026
// Design Name: axil_arbiter_3to1
// Module Name: axil_arbiter_3to1
// Description: AXI4-Lite 3-to-1 Arbiter.
//              Merges CPU Data, DMA Master, and JTAG Master into a single
//              AXI4-Lite master output for the interconnect.
//              Priority: CPU (M0) > JTAG (M1) > DMA (M2)
//              Uses a simple priority-based FSM per channel.
// 
//////////////////////////////////////////////////////////////////////////////////

module axil_arbiter_3to1 (
    input  logic        clk,
    input  logic        rst_n,

    // =========================================================
    // MASTER 0 PORT - CPU Data (En yüksek öncelik)
    // =========================================================
    input  logic [31:0] m0_awaddr,  input  logic m0_awvalid, output logic m0_awready,
    input  logic [31:0] m0_wdata,   input  logic [3:0] m0_wstrb, input logic m0_wvalid, output logic m0_wready,
    output logic [1:0]  m0_bresp,   output logic m0_bvalid,  input  logic m0_bready,
    input  logic [31:0] m0_araddr,  input  logic m0_arvalid, output logic m0_arready,
    output logic [31:0] m0_rdata,   output logic [1:0] m0_rresp, output logic m0_rvalid, input logic m0_rready,

    // =========================================================
    // MASTER 1 PORT - JTAG Debug (Orta öncelik)
    // =========================================================
    input  logic [31:0] m1_awaddr,  input  logic m1_awvalid, output logic m1_awready,
    input  logic [31:0] m1_wdata,   input  logic [3:0] m1_wstrb, input logic m1_wvalid, output logic m1_wready,
    output logic [1:0]  m1_bresp,   output logic m1_bvalid,  input  logic m1_bready,
    input  logic [31:0] m1_araddr,  input  logic m1_arvalid, output logic m1_arready,
    output logic [31:0] m1_rdata,   output logic [1:0] m1_rresp, output logic m1_rvalid, input logic m1_rready,

    // =========================================================
    // MASTER 2 PORT - DMA (En düşük öncelik)
    // =========================================================
    input  logic [31:0] m2_awaddr,  input  logic m2_awvalid, output logic m2_awready,
    input  logic [31:0] m2_wdata,   input  logic [3:0] m2_wstrb, input logic m2_wvalid, output logic m2_wready,
    output logic [1:0]  m2_bresp,   output logic m2_bvalid,  input  logic m2_bready,
    input  logic [31:0] m2_araddr,  input  logic m2_arvalid, output logic m2_arready,
    output logic [31:0] m2_rdata,   output logic [1:0] m2_rresp, output logic m2_rvalid, input logic m2_rready,

    // =========================================================
    // SLAVE PORT (Interconnect girişi)
    // =========================================================
    output logic [31:0] s_awaddr,   output logic s_awvalid,  input  logic s_awready,
    output logic [31:0] s_wdata,    output logic [3:0] s_wstrb, output logic s_wvalid, input logic s_wready,
    input  logic [1:0]  s_bresp,    input  logic s_bvalid,   output logic s_bready,
    output logic [31:0] s_araddr,   output logic s_arvalid,  input  logic s_arready,
    input  logic [31:0] s_rdata,    input  logic [1:0] s_rresp, input logic s_rvalid, output logic s_rready
);

    // =========================================================================
    // WRITE CHANNEL ARBITRATION
    // =========================================================================
    typedef enum logic [2:0] {
        W_IDLE,
        W_M0_ACTIVE,
        W_M1_ACTIVE,
        W_M2_ACTIVE
    } w_state_t;

    w_state_t w_state_q, w_state_d;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            w_state_q <= W_IDLE;
        else
            w_state_q <= w_state_d;
    end

    always_comb begin
        w_state_d = w_state_q;

        // Varsayılan çıkışlar
        s_awaddr  = 32'b0; s_awvalid = 1'b0;
        s_wdata   = 32'b0; s_wstrb   = 4'b0; s_wvalid = 1'b0;
        s_bready  = 1'b0;

        m0_awready = 1'b0; m0_wready = 1'b0; m0_bresp = s_bresp; m0_bvalid = 1'b0;
        m1_awready = 1'b0; m1_wready = 1'b0; m1_bresp = s_bresp; m1_bvalid = 1'b0;
        m2_awready = 1'b0; m2_wready = 1'b0; m2_bresp = s_bresp; m2_bvalid = 1'b0;

        case (w_state_q)
            W_IDLE: begin
                // Öncelik: M0 > M1 > M2
                if (m0_awvalid || m0_wvalid) begin
                    w_state_d = W_M0_ACTIVE;
                end else if (m1_awvalid || m1_wvalid) begin
                    w_state_d = W_M1_ACTIVE;
                end else if (m2_awvalid || m2_wvalid) begin
                    w_state_d = W_M2_ACTIVE;
                end
            end

            W_M0_ACTIVE: begin
                s_awaddr   = m0_awaddr;  s_awvalid  = m0_awvalid;  m0_awready = s_awready;
                s_wdata    = m0_wdata;   s_wstrb    = m0_wstrb;    s_wvalid   = m0_wvalid;  m0_wready = s_wready;
                m0_bvalid  = s_bvalid;   s_bready   = m0_bready;
                if (s_bvalid && m0_bready) w_state_d = W_IDLE;
            end

            W_M1_ACTIVE: begin
                s_awaddr   = m1_awaddr;  s_awvalid  = m1_awvalid;  m1_awready = s_awready;
                s_wdata    = m1_wdata;   s_wstrb    = m1_wstrb;    s_wvalid   = m1_wvalid;  m1_wready = s_wready;
                m1_bvalid  = s_bvalid;   s_bready   = m1_bready;
                if (s_bvalid && m1_bready) w_state_d = W_IDLE;
            end

            W_M2_ACTIVE: begin
                s_awaddr   = m2_awaddr;  s_awvalid  = m2_awvalid;  m2_awready = s_awready;
                s_wdata    = m2_wdata;   s_wstrb    = m2_wstrb;    s_wvalid   = m2_wvalid;  m2_wready = s_wready;
                m2_bvalid  = s_bvalid;   s_bready   = m2_bready;
                if (s_bvalid && m2_bready) w_state_d = W_IDLE;
            end

            default: w_state_d = W_IDLE;
        endcase
    end

    // =========================================================================
    // READ CHANNEL ARBITRATION
    // =========================================================================
    typedef enum logic [2:0] {
        R_IDLE,
        R_M0_ADDR,
        R_M0_DATA,
        R_M1_ADDR,
        R_M1_DATA,
        R_M2_ADDR,
        R_M2_DATA
    } r_state_t;

    r_state_t r_state_q, r_state_d;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            r_state_q <= R_IDLE;
        else
            r_state_q <= r_state_d;
    end

    always_comb begin
        r_state_d = r_state_q;

        // Varsayılan çıkışlar
        s_araddr  = 32'b0; s_arvalid = 1'b0;
        s_rready  = 1'b0;

        m0_arready = 1'b0; m0_rdata = s_rdata; m0_rresp = s_rresp; m0_rvalid = 1'b0;
        m1_arready = 1'b0; m1_rdata = s_rdata; m1_rresp = s_rresp; m1_rvalid = 1'b0;
        m2_arready = 1'b0; m2_rdata = s_rdata; m2_rresp = s_rresp; m2_rvalid = 1'b0;

        case (r_state_q)
            R_IDLE: begin
                if (m0_arvalid) begin
                    s_araddr   = m0_araddr;
                    s_arvalid  = 1'b1;
                    m0_arready = s_arready;
                    if (s_arready) r_state_d = R_M0_DATA;
                    else           r_state_d = R_M0_ADDR;
                end else if (m1_arvalid) begin
                    s_araddr   = m1_araddr;
                    s_arvalid  = 1'b1;
                    m1_arready = s_arready;
                    if (s_arready) r_state_d = R_M1_DATA;
                    else           r_state_d = R_M1_ADDR;
                end else if (m2_arvalid) begin
                    s_araddr   = m2_araddr;
                    s_arvalid  = 1'b1;
                    m2_arready = s_arready;
                    if (s_arready) r_state_d = R_M2_DATA;
                    else           r_state_d = R_M2_ADDR;
                end
            end

            R_M0_ADDR: begin
                s_araddr   = m0_araddr;
                s_arvalid  = m0_arvalid;
                m0_arready = s_arready;
                if (s_arready && s_arvalid) r_state_d = R_M0_DATA;
            end

            R_M0_DATA: begin
                s_rready  = m0_rready;
                m0_rvalid = s_rvalid;
                if (s_rvalid && m0_rready) r_state_d = R_IDLE;
            end

            R_M1_ADDR: begin
                s_araddr   = m1_araddr;
                s_arvalid  = m1_arvalid;
                m1_arready = s_arready;
                if (s_arready && s_arvalid) r_state_d = R_M1_DATA;
            end

            R_M1_DATA: begin
                s_rready  = m1_rready;
                m1_rvalid = s_rvalid;
                if (s_rvalid && m1_rready) r_state_d = R_IDLE;
            end

            R_M2_ADDR: begin
                s_araddr   = m2_araddr;
                s_arvalid  = m2_arvalid;
                m2_arready = s_arready;
                if (s_arready && s_arvalid) r_state_d = R_M2_DATA;
            end

            R_M2_DATA: begin
                s_rready  = m2_rready;
                m2_rvalid = s_rvalid;
                if (s_rvalid && m2_rready) r_state_d = R_IDLE;
            end

            default: r_state_d = R_IDLE;
        endcase
    end

endmodule
