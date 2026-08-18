`timescale 1ns / 1ps
// Description: Dual-Port Tightly Coupled Memory (TCM) for NPU.
//              Size: Exactly 30 kB (7680 words x 32-bit).
//              Port A is for external AXI Bus access.
//              Port B is for internal Compute Engine access.
//              Includes boundary protection logic.

module npu_tcm_sram #(
    // Kelime sayisi. FPGA: 7680 (30 kB). ASIC'te SRAM makro
    // boyutuna gore kucultulebilir. Adres portu 13 bit oldugu
    // icin ust sinir 8192'dir.
    parameter int unsigned TCM_WORDS = 7680
)(
    input  logic        clk,
    
    // --- Port A (AXI Slave Access) ---
    input  logic        en_a,
    input  logic [3:0]  we_a,
    input  logic [12:0] addr_a, // 2^13 = 8192 (Needs to index 7680)
    input  logic [31:0] wdata_a,
    output logic [31:0] rdata_a,
    
    // -------------------------------------------------------------------------
    // Port B (Internal Compute Engine) - SALT OKUNUR
    //
    // sky130 SRAM makrolari 1RW + 1R yapisindadir; yalnizca bir port yazabilir.
    // Bu yuzden Port B'nin yazma yolu kaldirildi ve motorun sonuc yazimlari
    // npu_accelerator icinde Port A'ya yonlendirildi (bkz. tcm_en_a coklayici).
    //
    // Boylece modul dogrudan bir 1RW+1R makroya eslenebiliyor: Port A -> RW,
    // Port B -> R.
    // -------------------------------------------------------------------------
    input  logic        en_b,
    input  logic [12:0] addr_b,
    output logic [31:0] rdata_b
);

    // 7680 words * 4 bytes = 30720 bytes = 30 kB
     logic [31:0] ram [0:TCM_WORDS-1];

    // Simülasyonda tanımsız (X) değerlerin önlenmesi için yerel bellek sıfırlaması
    initial begin
                for (int i = 0; i < TCM_WORDS; i = i + 1) begin
            ram[i] = 32'h0;
        end
    end

    // Port A Read/Write with boundary checks
    always_ff @(posedge clk) begin
        if (en_a) begin
            if (addr_a < TCM_WORDS) begin
                if (we_a[0]) ram[addr_a][7:0]   <= wdata_a[7:0];
                if (we_a[1]) ram[addr_a][15:8]  <= wdata_a[15:8];
                if (we_a[2]) ram[addr_a][23:16] <= wdata_a[23:16];
                if (we_a[3]) ram[addr_a][31:24] <= wdata_a[31:24];
                rdata_a <= ram[addr_a];
            end else begin
                rdata_a <= 32'h0; // Sınır dışı okuma durumunda güvenli sıfır dön
            end
        end
    end

    // Port B - yalnizca okuma (1RW+1R makronun R portu)
    always_ff @(posedge clk) begin
        if (en_b) begin
            if (addr_b < TCM_WORDS) begin
                rdata_b <= ram[addr_b];
            end else begin
                rdata_b <= 32'h0; // Sınır dışı okuma durumunda güvenli sıfır dön
            end
        end
    end

endmodule
