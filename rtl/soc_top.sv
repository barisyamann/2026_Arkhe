`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 25.04.2026 17:55:46
// Design Name: 
// Module Name: soc_top
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////
// Include satırı Vivado'nun dosyayı hiyerarşide doğru bağlamasını sağlar
`include "memory_map_pck.sv"

module soc_top (
    input  logic clk_i,
    input  logic rst_ni
);

    // Paketi modülün içinde import ediyoruz
    import memory_map_pck::*;

    // =========================================================
    // İÇ SİNYALLER (OBI BUS)
    // =========================================================
    
    // Instruction OBI Sinyalleri (İşlemcinin kod okuduğu hat)
    logic        instr_req;    // Komut okuma isteği (CPU'dan hafızaya: "Veri okumak istiyorum")
    logic        instr_gnt;    // İstek onayı (Hafızadan CPU'ya: "Adresi aldım, meşgul değilim")
    logic        instr_rvalid; // Okunan veri geçerli (Hafızadan CPU'ya: "Kod kapıda, alabilirsin")
    logic [31:0] instr_addr;   // Okunacak komutun adresi (CPU'dan hafızaya: "Hangi satırı okuyayım?")
    logic [31:0] instr_rdata;  // Gelen komut verisi (Hafızadan CPU'ya: "İstediğin 32-bitlik komut bu")

    // Data OBI Sinyalleri (İşlemcinin veri okuyup yazdığı hat)
    logic        data_req;     // Veri işlem isteği (CPU'dan hafızaya: "Veri okumak veya yazmak istiyorum")
    logic        data_gnt;     // İşlem onayı (Hafızadan CPU'ya: "İsteği aldım, işleme koyuyorum")
    logic        data_rvalid;  // Veri/İşlem geçerli (Hafızadan CPU'ya: "Okunan veri geldi veya yazma bitti")
    logic        data_we;      // Yazma izni (1: Hafızaya veri yazılır, 0: Hafızadan veri okunur)
    logic [3:0]  data_be;      // Bayt seçici (32-bitin hangi 8-bitlik kısımları yazılacak/okunacak?)
    logic [31:0] data_addr;    // İşlem yapılacak adres (CPU'dan hafızaya: "Hangi adrese erişeyim?")
    logic [31:0] data_wdata;   // Yazılacak veri (CPU'dan hafızaya: "Bu sayıyı adrese kaydet")
    logic [31:0] data_rdata;   // Okunan veri (Hafızadan CPU'ya: "Adresten okuduğum sayı bu")

    // =========================================================
    // CV32E40P RISC-V ÇEKİRDEĞİ
    // =========================================================
    
    cv32e40p_core u_core (
        .clk_i          (clk_i),
        .rst_ni         (rst_ni),
        
        // Instruction OBI Portları
        .instr_req_o    (instr_req),
        .instr_gnt_i    (instr_gnt),
        .instr_rvalid_i (instr_rvalid),
        .instr_addr_o   (instr_addr),
        .instr_rdata_i  (instr_rdata),
        
        // Data OBI Portları
        .data_req_o     (data_req),
        .data_gnt_i     (data_gnt),
        .data_rvalid_i  (data_rvalid),
        .data_we_o      (data_we),
        .data_be_o      (data_be),
        .data_addr_o    (data_addr),
        .data_wdata_o   (data_wdata),
        .data_rdata_i   (data_rdata),

        // --- İşlemci Kontrol ve Yönetim Sinyalleri ---
        .fetch_enable_i (1'b1),            // İşlemci Başlatıcı: 1 olduğu sürece CPU sürekli kod çalıştırır
        .irq_i          (32'b0),           // Kesme Girişleri: Dışarıdan gelen acil uyarılar (Şimdilik susturduk)
        .core_sleep_o   ()                 // Uyku Bildirimi: CPU uykuya geçerse buradan sinyal verir (Kullanmıyoruz)
    );

    // =========================================================
    // AXI BUS SİNYALLERİ (Köprüden Sonraki Dil)
    // =========================================================
    
    // Instruction AXI Hattı (Sadece Okuma Yapacak)
    logic        instr_axi_arvalid;
    logic        instr_axi_arready;
    logic [31:0] instr_axi_araddr;
    logic        instr_axi_rvalid;
    logic        instr_axi_rready;
    logic [31:0] instr_axi_rdata;

    // Data AXI Hattı (Hem Okuma Hem Yazma Yapacak)
    logic        data_axi_awvalid, data_axi_awready;
    logic [31:0] data_axi_awaddr;
    logic        data_axi_wvalid,  data_axi_wready;
    logic [31:0] data_axi_wdata;
    logic [3:0]  data_axi_wstrb;
    logic        data_axi_bvalid,  data_axi_bready;
    logic        data_axi_arvalid, data_axi_arready;
    logic [31:0] data_axi_araddr;
    logic        data_axi_rvalid,  data_axi_rready;
    logic [31:0] data_axi_rdata;
    
    // Instruction Köprüsü (En sade haliyle)
    obi_to_axi_simple u_instr_bridge (
        .clk_i        (clk_i),
        .rst_ni       (rst_ni),
        // OBI Tarafı
        .obi_req_i    (instr_req),
        .obi_gnt_o    (instr_gnt),
        .obi_addr_i   (instr_addr),
        .obi_we_i     (1'b0), // Kod okurken yazma olmaz
        .obi_be_i     (4'hf),
        .obi_wdata_i  (32'b0),
        .obi_rdata_o  (instr_rdata),
        .obi_rvalid_o (instr_rvalid),
        // AXI-Lite Tarafı (Sinyalleri şimdilik basitçe bağlayacağız)
        .axi_req_o    (instr_axi_arvalid), // AXI sinyalleriyle eşleşiyor
        .axi_gnt_i    (instr_axi_arready),
        .axi_addr_o   (instr_axi_araddr),
        .axi_we_o     (), 
        .axi_be_o     (),
        .axi_wdata_o  (),
        .axi_rdata_i  (instr_axi_rdata),
        .axi_rvalid_i (instr_axi_rvalid)
    );
    
    // Data Köprüsü (Veri Okuma/Yazma için)
    obi_to_axi_simple u_data_bridge (
        .clk_i        (clk_i),
        .rst_ni       (rst_ni),
        // OBI Tarafı (İşlemcinin Data bacakları)
        .obi_req_i    (data_req),
        .obi_gnt_o    (data_gnt),
        .obi_addr_i   (data_addr),
        .obi_we_i     (data_we),
        .obi_be_i     (data_be),
        .obi_wdata_i  (data_wdata),
        .obi_rdata_o  (data_rdata),
        .obi_rvalid_o (data_rvalid),
        
        // AXI-Lite Tarafı
        .axi_req_o    (data_axi_arvalid), // Hem AR hem AW valid için temel tetikleyici
        .axi_gnt_i    (data_axi_arready),
        .axi_addr_o   (data_axi_araddr),
        .axi_we_o     (data_axi_awvalid), // Yazma isteği
        .axi_be_o     (data_axi_wstrb),
        .axi_wdata_o  (data_axi_wdata),
        .axi_rdata_i  (data_axi_rdata),
        .axi_rvalid_i (data_axi_rvalid)
    );
    
    // =========================================================
    // SLAVE BİRİM SİNYALLERİ (Kavşaktan Sonraki Duraklar)
    // =========================================================
    logic rom_req, rom_gnt;
    logic ram_req, ram_gnt;
    logic gpio_req, gpio_gnt;
    
    // Veri Hattı Kavşağı (Trafik Polisi)
    axi_lite_interconnect u_interconnect (
        .m_addr_i (data_axi_araddr), // İşlemciden gelen adres
        .m_req_i  (data_axi_arvalid),// İşlemciden gelen istek
        .m_gnt_o  (data_axi_arready),// İşlemciye giden onay
        
        .s0_req_o (rom_req),  // ROM'a giden yol
        .s0_gnt_i (rom_gnt),
        
        .s1_req_o (ram_req),  // RAM'a giden yol
        .s1_gnt_i (ram_gnt),
        
        .s2_req_o (gpio_req), // GPIO'ya giden yol
        .s2_gnt_i (gpio_gnt)
    );

endmodule
