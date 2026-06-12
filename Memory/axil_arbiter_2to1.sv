`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: Arkhe RTL Team
// Engineer: Antigravity AI
// 
// Create Date: 11.06.2026
// Design Name: axil_arbiter_2to1
// Module Name: axil_arbiter_2to1
// Description: AXI4-Lite 2-to-1 Arbiter/Multiplexer. Allows Master 0 (read-only)
//              and Master 1 (read/write) to share a single AXI4-Lite slave.
// 
//////////////////////////////////////////////////////////////////////////////////

module axil_arbiter_2to1 (
    input  logic        clk,
    input  logic        rst_n,

    // =========================================================
    // MASTER 0 PORT (e.g., Instruction Fetch - Read Only)
    // =========================================================
    input  logic [31:0] m0_araddr,
    input  logic        m0_arvalid,
    output logic        m0_arready,
    output logic [31:0] m0_rdata,
    output logic [1:0]  m0_rresp,
    output logic        m0_rvalid,
    input  logic        m0_rready,

    // =========================================================
    // MASTER 1 PORT (e.g., Data Access - Read/Write)
    // =========================================================
    input  logic [31:0] m1_awaddr,
    input  logic        m1_awvalid,
    output logic        m1_awready,
    input  logic [31:0] m1_wdata,
    input  logic [3:0]  m1_wstrb,
    input  logic        m1_wvalid,
    output logic        m1_wready,
    output logic [1:0]  m1_bresp,
    output logic        m1_bvalid,
    input  logic        m1_bready,
    input  logic [31:0] m1_araddr,
    input  logic        m1_arvalid,
    output logic        m1_arready,
    output logic [31:0] m1_rdata,
    output logic [1:0]  m1_rresp,
    output logic        m1_rvalid,
    input  logic        m1_rready,

    // =========================================================
    // SLAVE PORT (Shared Memory)
    // =========================================================
    output logic [31:0] s_awaddr,
    output logic        s_awvalid,
    input  logic        s_awready,
    output logic [31:0] s_wdata,
    output logic [3:0]  s_wstrb,
    output logic        s_wvalid,
    input  logic        s_wready,
    input  logic [1:0]  s_bresp,
    input  logic        s_bvalid,
    output logic        s_bready,
    output logic [31:0] s_araddr,
    output logic        s_arvalid,
    input  logic        s_arready,
    input  logic [31:0] s_rdata,
    input  logic [1:0]  s_rresp,
    input  logic        s_rvalid,
    output logic        s_rready
);

    // --- READ ARBITRATION ---
    typedef enum logic [1:0] {
        R_IDLE,
        R_BUSY0,
        R_BUSY1
    } r_state_t;

    r_state_t r_state_q, r_state_d;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_state_q <= R_IDLE;
        end else begin
            r_state_q <= r_state_d;
        end
    end

    always_comb begin
        r_state_d = r_state_q;

        // Default Slave Read Outputs
        s_araddr  = 32'b0;
        s_arvalid = 1'b0;
        s_rready  = 1'b0;

        // Default Master Read Outputs
        m0_arready = 1'b0;
        m0_rdata   = s_rdata;
        m0_rresp   = s_rresp;
        m0_rvalid  = 1'b0;

        m1_arready = 1'b0;
        m1_rdata   = s_rdata;
        m1_rresp   = s_rresp;
        m1_rvalid  = 1'b0;

        case (r_state_q)
            R_IDLE: begin
                if (m1_arvalid) begin
                    // Priority to Data (Master 1)
                    s_araddr   = m1_araddr;
                    s_arvalid  = m1_arvalid;
                    m1_arready = s_arready;
                    if (s_arvalid && s_arready) begin
                        r_state_d = R_BUSY1;
                    end
                end else if (m0_arvalid) begin
                    s_araddr   = m0_araddr;
                    s_arvalid  = m0_arvalid;
                    m0_arready = s_arready;
                    if (s_arvalid && s_arready) begin
                        r_state_d = R_BUSY0;
                    end
                end
            end

            R_BUSY0: begin
                s_rready   = m0_rready;
                m0_rvalid  = s_rvalid;
                if (s_rvalid && s_rready) begin
                    r_state_d = R_IDLE;
                end
            end

            R_BUSY1: begin
                s_rready   = m1_rready;
                m1_rvalid  = s_rvalid;
                if (s_rvalid && s_rready) begin
                    r_state_d = R_IDLE;
                end
            end
        endcase
    end

    // --- WRITE ARBITRATION ---
    // Since Master 0 (Instruction) is Read-Only, Master 1 has exclusive write access.
    assign s_awaddr   = m1_awaddr;
    assign s_awvalid  = m1_awvalid;
    assign m1_awready = s_awready;

    assign s_wdata    = m1_wdata;
    assign s_wstrb    = m1_wstrb;
    assign s_wvalid   = m1_wvalid;
    assign m1_wready  = s_wready;

    assign m1_bresp   = s_bresp;
    assign m1_bvalid  = s_bvalid;
    assign s_bready   = m1_bready;

endmodule
