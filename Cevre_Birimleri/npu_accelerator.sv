`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: Arkhe RTL Team
// Engineer: Antigravity AI
// 
// Create Date: 11.06.2026
// Design Name: npu_accelerator
// Module Name: npu_accelerator
// Description: Top Level Wrapper of the Arkhe AI Accelerator (NPU).
//              Instantiates npu_csr, npu_tcm_sram, and npu_compute_engine.
//              Provides two AXI4-Lite Slave ports:
//              1) CSR Config Port (REG_AXI)
//              2) 30 kB Local Memory Port (MEM_AXI)
//              And one Interrupt Output port (irq_o).
// 
//////////////////////////////////////////////////////////////////////////////////

module npu_accelerator (
    input  logic        clk,
    input  logic        rst_n,

    // --- AXI4-Lite Slave - CSR Config (0x4006_0000) ---
    input  logic [31:0] reg_awaddr,
    input  logic        reg_awvalid,
    output logic        reg_awready,
    input  logic [31:0] reg_wdata,
    input  logic [3:0]  reg_wstrb,
    input  logic        reg_wvalid,
    output logic        reg_wready,
    output logic [1:0]  reg_bresp,
    output logic        reg_bvalid,
    input  logic        reg_bready,
    input  logic [31:0] reg_araddr,
    input  logic        reg_arvalid,
    output logic        reg_arready,
    output logic [31:0] reg_rdata,
    output logic [1:0]  reg_rresp,
    output logic        reg_rvalid,
    input  logic        reg_rready,

    // --- AXI4-Lite Slave - 30 kB Memory (0x2001_0000) ---
    input  logic [31:0] mem_awaddr,
    input  logic        mem_awvalid,
    output logic        mem_awready,
    input  logic [31:0] mem_wdata,
    input  logic [3:0]  mem_wstrb,
    input  logic        mem_wvalid,
    output logic        mem_wready,
    output logic [1:0]  mem_bresp,
    output logic        mem_bvalid,
    input  logic        mem_bready,
    input  logic [31:0] mem_araddr,
    input  logic        mem_arvalid,
    output logic        mem_arready,
    output logic [31:0] mem_rdata,
    output logic [1:0]  mem_rresp,
    output logic        mem_rvalid,
    input  logic        mem_rready,

    // --- Kesme Çıkışı (Interrupt) ---
    output logic        irq_o
);

    // --- İç Sinyal Bağlantıları ---
    logic        start_sig;
    logic        npu_reset_sig;
    logic [12:0] in_offset_addr;
    logic [12:0] out_offset_addr;
    logic        busy_sig;
    logic        done_sig;
    logic [1:0]  class_sig;

    // SRAM Port A Kontrol Sinyalleri
    logic        ram_en_a;
    logic [3:0]  ram_we_a;
    logic [12:0] ram_addr_a;
    logic [31:0] ram_wdata_a;
    logic [31:0] ram_rdata_a;

    // SRAM Port B Kontrol Sinyalleri
    logic        ram_en_b;
    logic [3:0]  ram_we_b;
    logic [12:0] ram_addr_b;
    logic [31:0] ram_wdata_b;
    logic [31:0] ram_rdata_b;

    // Kesme Çıkışı
    assign irq_o = done_sig;

    // =========================================================================
    // NPU Kontrol ve Durum Yazmaçları (CSR)
    // =========================================================================
    npu_csr u_npu_csr (
        .clk            (clk),
        .rst_n          (rst_n),
        
        // AXI Slave (REG)
        .s_axi_awaddr   (reg_awaddr),
        .s_axi_awvalid  (reg_awvalid),
        .s_axi_awready  (reg_awready),
        .s_axi_wdata    (reg_wdata),
        .s_axi_wstrb    (reg_wstrb),
        .s_axi_wvalid   (reg_wvalid),
        .s_axi_wready   (reg_wready),
        .s_axi_bresp    (reg_bresp),
        .s_axi_bvalid   (reg_bvalid),
        .s_axi_bready   (reg_bready),
        .s_axi_araddr   (reg_araddr),
        .s_axi_arvalid  (reg_arvalid),
        .s_axi_arready  (reg_arready),
        .s_axi_rdata    (reg_rdata),
        .s_axi_rresp    (reg_rresp),
        .s_axi_rvalid   (reg_rvalid),
        .s_axi_rready   (reg_rready),
        
        // Donanımsal Kontrol
        .start_o        (start_sig),
        .npu_reset_o    (npu_reset_sig),
        .in_addr_o      (in_offset_addr),
        .out_addr_o     (out_offset_addr),
        .busy_i         (busy_sig),
        .done_i         (done_sig),
        .class_in       (class_sig)
    );

    // =========================================================================
    // NPU Hesaplama Motoru (Compute Engine)
    // =========================================================================
    npu_compute_engine u_npu_engine (
        .clk            (clk),
        .rst_n          (rst_n),
        
        // CSR Kontrol
        .start_i        (start_sig),
        .npu_reset_i    (npu_reset_sig),
        .in_addr_i      (in_offset_addr),
        .out_addr_i     (out_offset_addr),
        .busy_o         (busy_sig),
        .done_o         (done_sig),
        .class_o        (class_sig),
        
        // SRAM Port B
        .mem_en_b       (ram_en_b),
        .mem_we_b       (ram_we_b),
        .mem_addr_b     (ram_addr_b),
        .mem_wdata_b    (ram_wdata_b),
        .mem_rdata_b    (ram_rdata_b)
    );

    // =========================================================================
    // 30 kB Yerel TCM SRAM Belleği
    // =========================================================================
    npu_tcm_sram u_npu_sram (
        .clk            (clk),
        
        // Port A (AXI Slave Access)
        .en_a           (ram_en_a),
        .we_a           (ram_we_a),
        .addr_a         (ram_addr_a),
        .wdata_a        (ram_wdata_a),
        .rdata_a        (ram_rdata_a),
        
        // Port B (Compute Engine Access)
        .en_b           (ram_en_b),
        .we_b           (ram_we_b),
        .addr_b         (ram_addr_b),
        .wdata_b        (ram_wdata_b),
        .rdata_b        (ram_rdata_b)
    );

    // =========================================================================
    // TCM SRAM AXI4-Lite Slave Arayüzü (Port A)
    // =========================================================================
    logic [31:0] mem_aw_addr_lat;
    logic        mem_aw_valid_lat;
    logic [31:0] mem_w_data_lat;
    logic        mem_w_valid_lat;
    logic        mem_do_write;
    logic [31:0] mem_ar_addr_lat;
    logic        mem_ar_valid_lat;

    assign mem_do_write = mem_aw_valid_lat && mem_w_valid_lat;

    // RAM Kontrol Sinyalleri
    assign ram_en_a    = mem_do_write || (mem_ar_valid_lat && !mem_rvalid);
    assign ram_we_a    = mem_do_write ? mem_wstrb : 4'b0000;
    assign ram_wdata_a = mem_w_data_lat;

    // Adres dilimleme ve sınır güvenliği (7680 kelime üst sınır)
    logic [12:0] byte_addr_write;
    logic [12:0] byte_addr_read;
    assign byte_addr_write = mem_aw_addr_lat[14:2];
    assign byte_addr_read  = mem_ar_addr_lat[14:2];

    assign ram_addr_a  = mem_do_write ? 
                         ((byte_addr_write < 13'd7680) ? byte_addr_write : 13'd0) :
                         ((byte_addr_read  < 13'd7680) ? byte_addr_read  : 13'd0);

    // AXI Write Kanalları
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mem_awready      <= 1'b0;
            mem_wready       <= 1'b0;
            mem_bvalid       <= 1'b0;
            mem_bresp        <= 2'b00;
            mem_aw_valid_lat <= 1'b0;
            mem_w_valid_lat  <= 1'b0;
            mem_aw_addr_lat  <= '0;
            mem_w_data_lat   <= '0;
        end else begin
            // AW Handshake
            if (mem_awvalid && !mem_aw_valid_lat) begin
                mem_awready      <= 1'b1;
                mem_aw_addr_lat  <= mem_awaddr;
                mem_aw_valid_lat <= 1'b1;
            end else begin
                mem_awready      <= 1'b0;
            end

            // W Handshake
            if (mem_wvalid && !mem_w_valid_lat) begin
                mem_wready      <= 1'b1;
                mem_w_data_lat  <= mem_wdata;
                mem_w_valid_lat <= 1'b1;
            end else begin
                mem_wready      <= 1'b0;
            end

            // B Channel
            if (mem_do_write) begin
                mem_aw_valid_lat <= 1'b0;
                mem_w_valid_lat  <= 1'b0;
                mem_bvalid       <= 1'b1;
                mem_bresp        <= 2'b00;
            end

            if (mem_bvalid && mem_bready) begin
                mem_bvalid <= 1'b0;
            end
        end
    end

    // AXI Read Kanalları
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mem_arready      <= 1'b0;
            mem_rvalid       <= 1'b0;
            mem_rresp        <= 2'b00;
            mem_rdata        <= '0;
            mem_ar_valid_lat <= 1'b0;
            mem_ar_addr_lat  <= '0;
        end else begin
            // AR Handshake
            if (mem_arvalid && !mem_ar_valid_lat) begin
                mem_arready      <= 1'b1;
                mem_ar_addr_lat  <= mem_araddr;
                mem_ar_valid_lat <= 1'b1;
            end else begin
                mem_arready      <= 1'b0;
            end

            // R Channel
            if (mem_ar_valid_lat && !mem_rvalid) begin
                mem_ar_valid_lat <= 1'b0;
                mem_rvalid       <= 1'b1;
                mem_rresp        <= 2'b00;
                mem_rdata        <= ram_rdata_a;
            end

            if (mem_rvalid && mem_rready) begin
                mem_rvalid <= 1'b0;
            end
        end
    end

endmodule
