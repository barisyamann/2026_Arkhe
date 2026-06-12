`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: Arkhe RTL Team
// Engineer: Antigravity AI
// 
// Create Date: 11.06.2026
// Design Name: npu_tcm_sram
// Module Name: npu_tcm_sram
// Description: Dual-Port Tightly Coupled Memory (TCM) for NPU.
//              Size: Exactly 30 kB (7680 words x 32-bit).
//              Port A is for external AXI Bus access.
//              Port B is for internal Compute Engine access.
// 
//////////////////////////////////////////////////////////////////////////////////

module npu_tcm_sram (
    input  logic        clk,
    
    // --- Port A (AXI Slave Access) ---
    input  logic        en_a,
    input  logic [3:0]  we_a,
    input  logic [12:0] addr_a, // 2^13 = 8192 (Needs to index 7680)
    input  logic [31:0] wdata_a,
    output logic [31:0] rdata_a,
    
    // --- Port B (Internal Compute Engine) ---
    input  logic        en_b,
    input  logic [3:0]  we_b,
    input  logic [12:0] addr_b,
    input  logic [31:0] wdata_b,
    output logic [31:0] rdata_b
);

    // 7680 words * 4 bytes = 30720 bytes = 30 kB
    logic [31:0] ram [0:7679];

    // Simülasyonda tanımsız (X) değerlerin önlenmesi için yerel bellek sıfırlaması
    initial begin
        for (int i = 0; i < 7680; i = i + 1) begin
            ram[i] = 32'h0;
        end
    end

    // Port A Read/Write
    always_ff @(posedge clk) begin
        if (en_a) begin
            if (we_a[0]) ram[addr_a][7:0]   <= wdata_a[7:0];
            if (we_a[1]) ram[addr_a][15:8]  <= wdata_a[15:8];
            if (we_a[2]) ram[addr_a][23:16] <= wdata_a[23:16];
            if (we_a[3]) ram[addr_a][31:24] <= wdata_a[31:24];
            rdata_a <= ram[addr_a];
        end
    end

    // Port B Read/Write
    always_ff @(posedge clk) begin
        if (en_b) begin
            if (we_b[0]) ram[addr_b][7:0]   <= wdata_b[7:0];
            if (we_b[1]) ram[addr_b][15:8]  <= wdata_b[15:8];
            if (we_b[2]) ram[addr_b][23:16] <= wdata_b[23:16];
            if (we_b[3]) ram[addr_b][31:24] <= wdata_b[31:24];
            rdata_b <= ram[addr_b];
        end
    end

endmodule
