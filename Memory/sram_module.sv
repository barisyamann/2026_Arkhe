`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: Arkhe RTL Team
// Engineer: Antigravity AI
// 
// Create Date: 11.06.2026
// Design Name: sram_module
// Module Name: sram_module
// Description: Parametric 8 kB SRAM module with a standard AXI4-Lite Slave Interface.
//              Supports 4-bit write strobes (byte write enable) for BRAM inference in Vivado.
// 
//////////////////////////////////////////////////////////////////////////////////

module sram_module #(
    parameter int AXI_ADDR_W = 32,
    parameter int AXI_DATA_W = 32,
    parameter int RAM_DEPTH  = 2048 // 2048 words * 4 bytes = 8 kB
)(
    input  logic                    clk,
    input  logic                    rst_n,

    // --- AXI4-Lite Slave Arayüzü ---
    // Yazma Adresi
    input  logic [AXI_ADDR_W-1:0]   s_axil_awaddr,
    input  logic                    s_axil_awvalid,
    output logic                    s_axil_awready,
    // Yazma Verisi
    input  logic [AXI_DATA_W-1:0]   s_axil_wdata,
    input  logic [3:0]              s_axil_wstrb,
    input  logic                    s_axil_wvalid,
    output logic                    s_axil_wready,
    // Yazma Yanıtı
    output logic [1:0]              s_axil_bresp,
    output logic                    s_axil_bvalid,
    input  logic                    s_axil_bready,
    // Okuma Adresi
    input  logic [AXI_ADDR_W-1:0]   s_axil_araddr,
    input  logic                    s_axil_arvalid,
    output logic                    s_axil_arready,
    // Okuma Verisi
    output logic [AXI_DATA_W-1:0]   s_axil_rdata,
    output logic [1:0]              s_axil_rresp,
    output logic                    s_axil_rvalid,
    input  logic                    s_axil_rready
);

    // RAM Tanımı (2048 satır x 32-bit = 8 kB)
    logic [31:0] ram [0:RAM_DEPTH-1];

    // AXI El Sıkışma Durum Kontrolleri
    logic aw_active;
    logic w_active;
    logic [AXI_ADDR_W-1:0] aw_addr_reg;
    logic [AXI_ADDR_W-1:0] ar_addr_reg;

    localparam logic [1:0] RESP_OKAY = 2'b00;

    // --- AXI Yazma Kontrolü ---
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            aw_active      <= 1'b0;
            w_active       <= 1'b0;
            aw_addr_reg    <= '0;
            s_axil_awready <= 1'b0;
            s_axil_wready  <= 1'b0;
            s_axil_bvalid  <= 1'b0;
            s_axil_bresp   <= RESP_OKAY;
        end else begin
            // Adres handshake
            if (s_axil_awvalid && s_axil_awready) begin
                aw_active      <= 1'b1;
                aw_addr_reg    <= s_axil_awaddr;
                s_axil_awready <= 1'b0;
            end else if (!aw_active) begin
                s_axil_awready <= s_axil_awvalid;
            end

            // Veri handshake
            if (s_axil_wvalid && s_axil_wready) begin
                w_active      <= 1'b1;
                s_axil_wready <= 1'b0;
            end else if (!w_active) begin
                s_axil_wready  <= s_axil_wvalid;
            end

            // Yazma işleminin RAM'e uygulanması
            if (aw_active && w_active && !s_axil_bvalid) begin
                aw_active     <= 1'b0;
                w_active      <= 1'b0;
                s_axil_bvalid <= 1'b1;
                s_axil_bresp  <= RESP_OKAY;

                // Adres kelime hizalaması (word alignment): [12:2] bitlerini kullanıyoruz (2048 satır için)
                // (aw_addr_reg - BASE) işleminin üst modülde veya interconnect'te yapıldığı varsayılır,
                // buraya doğrudan RAM içi offset gelir veya adresin ilgili bitleri filtrelenir.
                // RAM_DEPTH 2048 ise $clog2(RAM_DEPTH)+1 bit gereklidir. [12:2] bitleri 2048 kelimeyi adresler.
                if (aw_addr_reg[$clog2(RAM_DEPTH)+1 : 2] < RAM_DEPTH) begin
                    if (s_axil_wstrb[0]) ram[aw_addr_reg[$clog2(RAM_DEPTH)+1 : 2]][7:0]   <= s_axil_wdata[7:0];
                    if (s_axil_wstrb[1]) ram[aw_addr_reg[$clog2(RAM_DEPTH)+1 : 2]][15:8]  <= s_axil_wdata[15:8];
                    if (s_axil_wstrb[2]) ram[aw_addr_reg[$clog2(RAM_DEPTH)+1 : 2]][23:16] <= s_axil_wdata[23:16];
                    if (s_axil_wstrb[3]) ram[aw_addr_reg[$clog2(RAM_DEPTH)+1 : 2]][31:24] <= s_axil_wdata[31:24];
                end
            end

            // Yanıt tamamlama
            if (s_axil_bvalid && s_axil_bready) begin
                s_axil_bvalid <= 1'b0;
            end
        end
    end

    // --- AXI Okuma Kontrolü ---
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_axil_arready <= 1'b0;
            s_axil_rvalid  <= 1'b0;
            s_axil_rdata   <= '0;
            s_axil_rresp   <= RESP_OKAY;
        end else begin
            if (s_axil_arvalid && !s_axil_rvalid) begin
                s_axil_arready <= 1'b1;
                s_axil_rvalid  <= 1'b1;
                s_axil_rresp   <= RESP_OKAY;
                
                // RAM'den veri okuma (Bir çevrim gecikmeli)
                if (s_axil_araddr[$clog2(RAM_DEPTH)+1 : 2] < RAM_DEPTH) begin
                    s_axil_rdata <= ram[s_axil_araddr[$clog2(RAM_DEPTH)+1 : 2]];
                end else begin
                    s_axil_rdata <= 32'hDEADBEEF; // Geçersiz adres okuması
                end
            end else begin
                s_axil_arready <= 1'b0;
            end

            // Okuma kanalı el sıkışması
            if (s_axil_rvalid && s_axil_rready) begin
                s_axil_rvalid <= 1'b0;
            end
        end
    end

endmodule
