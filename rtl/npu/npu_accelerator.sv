`timescale 1ns / 1ps
// Description: Top Level Wrapper of the Arkhe AI Accelerator (NPU).
//              Instantiates npu_csr, npu_axi_controller, npu_tcm_sram, and npu_compute_engine.
//              Provides two AXI4-Lite Slave ports:
//              1) CSR Config Port (REG_AXI)
//              2) 30 kB Local Memory Port (MEM_AXI)
//              And one Interrupt Output port (irq_o).

module npu_accelerator #(
    parameter int unsigned TCM_WORDS = 7680
)(
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
    logic        irq_sig;

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

    // Kesme Çıkışı bağlantısı
    assign irq_o = irq_sig;

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
        .class_in       (class_sig),
        .irq_o          (irq_sig)
    );

    // =========================================================================
    // NPU TCM AXI Denetleyicisi (AXI Controller)
    // =========================================================================
    npu_axi_controller u_npu_axi_ctrl (
        .clk            (clk),
        .rst_n          (rst_n),
        
        // AXI Slave (MEM)
        .mem_awaddr     (mem_awaddr),
        .mem_awvalid    (mem_awvalid),
        .mem_awready    (mem_awready),
        .mem_wdata      (mem_wdata),
        .mem_wstrb      (mem_wstrb),
        .mem_wvalid     (mem_wvalid),
        .mem_wready     (mem_wready),
        .mem_bresp      (mem_bresp),
        .mem_bvalid     (mem_bvalid),
        .mem_bready     (mem_bready),
        .mem_araddr     (mem_araddr),
        .mem_arvalid    (mem_arvalid),
        .mem_arready    (mem_arready),
        .mem_rdata      (mem_rdata),
        .mem_rresp      (mem_rresp),
        .mem_rvalid     (mem_rvalid),
        .mem_rready     (mem_rready),
        
        // SRAM Port A
        .ram_en_o       (ram_en_a),
        .ram_we_o       (ram_we_a),
        .ram_addr_o     (ram_addr_a),
        .ram_wdata_o    (ram_wdata_a),
        .ram_rdata_i    (ram_rdata_a)
    );

    // =========================================================================
    // NPU Yerel Belleği (TCM SRAM)
    // =========================================================================
    npu_tcm_sram #(
        .TCM_WORDS (TCM_WORDS)
    ) u_npu_sram (
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

endmodule
