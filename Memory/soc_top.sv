`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: Arkhe RTL Team
// Engineer: Antigravity AI
// 
// Create Date: 25.04.2026
// Update Date: 12.06.2026
// Design Name: soc_top
// Module Name: soc_top
// Description: Top Level Module of the Arkhe RISC-V SoC.
//              Instantiates the CORE-V CV32E40P CPU, OBI-to-AXI Bridges,
//              3-to-1 AXI4-Lite Master Arbiter (CPU/JTAG/DMA),
//              AXI4-Lite Interconnect (1M→13S), Boot ROM, I-RAM, D-RAM,
//              Peripherals (GPIO, Timer, UART1, UART2 Stream, I2C Master,
//              QSPI Master, NPU Accelerator, DMA Controller, JTAG Debug).
// 
//////////////////////////////////////////////////////////////////////////////////

`include "memory_map_pck.sv"

module soc_top (
    input  logic        clk_i,
    input  logic        rst_ni,

    // --- GPIO Arayüzü ---
    input  logic [15:0] gpio_i,
    output logic [15:0] gpio_o,
    output logic [15:0] gpio_tx_en_o,

    // --- UART 1 (General) Arayüzü ---
    input  logic        uart1_rxd,
    output logic        uart1_txd,

    // --- UART 2 (Stream) Arayüzü ---
    input  logic        uart2_rxd,
    output logic        uart2_txd,

    // --- I2C Master Arayüzü ---
    inout  wire         i2c_sda,
    inout  wire         i2c_scl,

    // --- QSPI Master Arayüzü ---
    output logic        qspi_sck,
    output logic        qspi_cs_n,
    inout  wire         qspi_io0,
    inout  wire         qspi_io1,
    inout  wire         qspi_io2,
    inout  wire         qspi_io3,

    // --- JTAG Debug Arayüzü ---
    input  logic        jtag_tms,
    input  logic        jtag_tck,
    input  logic        jtag_tdi,
    output logic        jtag_tdo,
    input  logic        jtag_trst_n
);

    import memory_map_pck::*;

    // =========================================================
    // İÇ SİNYALLER (OBI BUS)
    // =========================================================
    
    // Instruction OBI Sinyalleri
    logic        instr_req;
    logic        instr_gnt;
    logic        instr_rvalid;
    logic [31:0] instr_addr;
    logic [31:0] instr_rdata;

    // Data OBI Sinyalleri
    logic        data_req;
    logic        data_gnt;
    logic        data_rvalid;
    logic        data_we;
    logic [3:0]  data_be;
    logic [31:0] data_addr;
    logic [31:0] data_wdata;
    logic [31:0] data_rdata;

    // Kesme Sinyalleri
    logic [31:0] irq_vector;
    logic        gpio_irq;
    logic        timer_irq;
    logic        uart1_irq;
    logic        uart2_irq;
    logic        qspi_irq;
    logic        npu_irq;
    logic        dma_irq;
    logic        i2c_irq;
    logic        core_sleep;
    logic        debug_req;

    assign irq_vector = {
        7'b0,
        dma_irq,
        i2c_irq,
        npu_irq,
        qspi_irq,
        1'b0,
        uart2_irq,
        uart1_irq,
        timer_irq,
        gpio_irq,
        16'b0
    };

    // =========================================================
    // CV32E40P RISC-V ÇEKİRDEĞİ
    // =========================================================
    cv32e40p_core #(
        .COREV_PULP      (0),
        .COREV_CLUSTER   (0),
        .FPU             (0),
        .NUM_MHPMCOUNTERS(1)
    ) u_core (
        .clk_i                  (clk_i),
        .rst_ni                 (rst_ni),
        .pulp_clock_en_i        (1'b0),
        .scan_cg_en_i           (1'b0),
        .boot_addr_i            (BOOT_ROM_BASE),
        .mtvec_addr_i           (32'h0000_0000),
        .dm_halt_addr_i         (32'h0000_0000),
        .hart_id_i              (32'h0000_0000),
        .dm_exception_addr_i    (32'h0000_0000),

        // Instruction OBI Portları
        .instr_req_o            (instr_req),
        .instr_gnt_i            (instr_gnt),
        .instr_rvalid_i         (instr_rvalid),
        .instr_addr_o           (instr_addr),
        .instr_rdata_i          (instr_rdata),
        
        // Data OBI Portları
        .data_req_o             (data_req),
        .data_gnt_i             (data_gnt),
        .data_rvalid_i          (data_rvalid),
        .data_we_o              (data_we),
        .data_be_o              (data_be),
        .data_addr_o            (data_addr),
        .data_wdata_o           (data_wdata),
        .data_rdata_i           (data_rdata),

        // APU Arayüzü (Tied-off)
        .apu_busy_o             (),
        .apu_req_o              (),
        .apu_gnt_i              (1'b0),
        .apu_operands_o         (),
        .apu_op_o               (),
        .apu_flags_o            (),
        .apu_rvalid_i           (1'b0),
        .apu_result_i           (32'h0),
        .apu_flags_i            ('0),

        // Kesme ve Kontrol
        .irq_i                  (irq_vector),
        .irq_ack_o              (),
        .irq_id_o               (),
        .debug_req_i            (debug_req),
        .debug_havereset_o      (),
        .debug_running_o        (),
        .debug_halted_o         (),
        .fetch_enable_i         (1'b1),
        .core_sleep_o           (core_sleep)
    );

    // =========================================================
    // AXI-LITE MASTER VERİYOLU ARAYÜZLERİ (KÖPRÜLER)
    // =========================================================
    
    // Instruction AXI-Lite Hattı
    logic [31:0] instr_axil_araddr;
    logic        instr_axil_arvalid;
    logic        instr_axil_arready;
    logic [31:0] instr_axil_rdata;
    logic [1:0]  instr_axil_rresp;
    logic        instr_axil_rvalid;
    logic        instr_axil_rready;

    obi_to_axi_simple u_instr_bridge (
        .clk_i          (clk_i),
        .rst_ni         (rst_ni),
        // OBI
        .obi_req_i      (instr_req),
        .obi_gnt_o      (instr_gnt),
        .obi_addr_i     (instr_addr),
        .obi_we_i       (1'b0), // Kod okurken yazma olmaz
        .obi_be_i       (4'hf),
        .obi_wdata_i    (32'b0),
        .obi_rdata_o    (instr_rdata),
        .obi_rvalid_o   (instr_rvalid),
        // AXI4-Lite Master
        .axil_awaddr_o  (),
        .axil_awvalid_o (),
        .axil_awready_i (1'b0),
        .axil_wdata_o   (),
        .axil_wstrb_o   (),
        .axil_wvalid_o  (),
        .axil_wready_i  (1'b0),
        .axil_bresp_i   (2'b00),
        .axil_bvalid_i  (1'b0),
        .axil_bready_o  (),
        .axil_araddr_o  (instr_axil_araddr),
        .axil_arvalid_o (instr_axil_arvalid),
        .axil_arready_i (instr_axil_arready),
        .axil_rdata_i   (instr_axil_rdata),
        .axil_rresp_i   (instr_axil_rresp),
        .axil_rvalid_i  (instr_axil_rvalid),
        .axil_rready_o  (instr_axil_rready)
    );

    // Data AXI-Lite Hattı (CPU → Arbiter'a gider)
    logic [31:0] data_axil_awaddr;
    logic        data_axil_awvalid;
    logic        data_axil_awready;
    logic [31:0] data_axil_wdata;
    logic [3:0]  data_axil_wstrb;
    logic        data_axil_wvalid;
    logic        data_axil_wready;
    logic [1:0]  data_axil_bresp;
    logic        data_axil_bvalid;
    logic        data_axil_bready;
    logic [31:0] data_axil_araddr;
    logic        data_axil_arvalid;
    logic        data_axil_arready;
    logic [31:0] data_axil_rdata;
    logic [1:0]  data_axil_rresp;
    logic        data_axil_rvalid;
    logic        data_axil_rready;

    obi_to_axi_simple u_data_bridge (
        .clk_i          (clk_i),
        .rst_ni         (rst_ni),
        // OBI
        .obi_req_i      (data_req),
        .obi_gnt_o      (data_gnt),
        .obi_addr_i     (data_addr),
        .obi_we_i       (data_we),
        .obi_be_i       (data_be),
        .obi_wdata_i    (data_wdata),
        .obi_rdata_o    (data_rdata),
        .obi_rvalid_o   (data_rvalid),
        // AXI4-Lite Master
        .axil_awaddr_o  (data_axil_awaddr),
        .axil_awvalid_o (data_axil_awvalid),
        .axil_awready_i (data_axil_awready),
        .axil_wdata_o   (data_axil_wdata),
        .axil_wstrb_o   (data_axil_wstrb),
        .axil_wvalid_o  (data_axil_wvalid),
        .axil_wready_i  (data_axil_wready),
        .axil_bresp_i   (data_axil_bresp),
        .axil_bvalid_i  (data_axil_bvalid),
        .axil_bready_o  (data_axil_bready),
        .axil_araddr_o  (data_axil_araddr),
        .axil_arvalid_o (data_axil_arvalid),
        .axil_arready_i (data_axil_arready),
        .axil_rdata_i   (data_axil_rdata),
        .axil_rresp_i   (data_axil_rresp),
        .axil_rvalid_i  (data_axil_rvalid),
        .axil_rready_o  (data_axil_rready)
    );

    // =========================================================
    // DMA ve JTAG MASTER SİNYALLERİ
    // =========================================================
    
    // DMA Master AXI-Lite sinyalleri
    logic [31:0] dma_m_awaddr;  logic dma_m_awvalid;  logic dma_m_awready;
    logic [31:0] dma_m_wdata;   logic [3:0] dma_m_wstrb; logic dma_m_wvalid; logic dma_m_wready;
    logic [1:0]  dma_m_bresp;   logic dma_m_bvalid;   logic dma_m_bready;
    logic [31:0] dma_m_araddr;  logic dma_m_arvalid;  logic dma_m_arready;
    logic [31:0] dma_m_rdata;   logic [1:0] dma_m_rresp; logic dma_m_rvalid; logic dma_m_rready;

    // JTAG Master AXI-Lite sinyalleri
    logic [31:0] jtag_m_awaddr;  logic jtag_m_awvalid;  logic jtag_m_awready;
    logic [31:0] jtag_m_wdata;   logic [3:0] jtag_m_wstrb; logic jtag_m_wvalid; logic jtag_m_wready;
    logic [1:0]  jtag_m_bresp;   logic jtag_m_bvalid;   logic jtag_m_bready;
    logic [31:0] jtag_m_araddr;  logic jtag_m_arvalid;  logic jtag_m_arready;
    logic [31:0] jtag_m_rdata;   logic [1:0] jtag_m_rresp; logic jtag_m_rvalid; logic jtag_m_rready;

    // Arbiter → Interconnect arası birleştirilmiş master sinyal
    logic [31:0] merged_m_awaddr;  logic merged_m_awvalid;  logic merged_m_awready;
    logic [31:0] merged_m_wdata;   logic [3:0] merged_m_wstrb; logic merged_m_wvalid; logic merged_m_wready;
    logic [1:0]  merged_m_bresp;   logic merged_m_bvalid;   logic merged_m_bready;
    logic [31:0] merged_m_araddr;  logic merged_m_arvalid;  logic merged_m_arready;
    logic [31:0] merged_m_rdata;   logic [1:0] merged_m_rresp; logic merged_m_rvalid; logic merged_m_rready;

    // =========================================================
    // 3-TO-1 AXI-LITE MASTER ARBITER
    // (CPU Data > JTAG > DMA → Birleştirilmiş Master)
    // =========================================================
    axil_arbiter_3to1 u_master_arbiter (
        .clk        (clk_i),
        .rst_n      (rst_ni),
        // M0: CPU Data (en yüksek öncelik)
        .m0_awaddr  (data_axil_awaddr),  .m0_awvalid (data_axil_awvalid),  .m0_awready (data_axil_awready),
        .m0_wdata   (data_axil_wdata),   .m0_wstrb   (data_axil_wstrb),   .m0_wvalid  (data_axil_wvalid),  .m0_wready  (data_axil_wready),
        .m0_bresp   (data_axil_bresp),   .m0_bvalid  (data_axil_bvalid),  .m0_bready  (data_axil_bready),
        .m0_araddr  (data_axil_araddr),  .m0_arvalid (data_axil_arvalid),  .m0_arready (data_axil_arready),
        .m0_rdata   (data_axil_rdata),   .m0_rresp   (data_axil_rresp),   .m0_rvalid  (data_axil_rvalid),  .m0_rready  (data_axil_rready),
        // M1: JTAG Debug (orta öncelik)
        .m1_awaddr  (jtag_m_awaddr),  .m1_awvalid (jtag_m_awvalid),  .m1_awready (jtag_m_awready),
        .m1_wdata   (jtag_m_wdata),   .m1_wstrb   (jtag_m_wstrb),   .m1_wvalid  (jtag_m_wvalid),  .m1_wready  (jtag_m_wready),
        .m1_bresp   (jtag_m_bresp),   .m1_bvalid  (jtag_m_bvalid),  .m1_bready  (jtag_m_bready),
        .m1_araddr  (jtag_m_araddr),  .m1_arvalid (jtag_m_arvalid),  .m1_arready (jtag_m_arready),
        .m1_rdata   (jtag_m_rdata),   .m1_rresp   (jtag_m_rresp),   .m1_rvalid  (jtag_m_rvalid),  .m1_rready  (jtag_m_rready),
        // M2: DMA (en düşük öncelik)
        .m2_awaddr  (dma_m_awaddr),  .m2_awvalid (dma_m_awvalid),  .m2_awready (dma_m_awready),
        .m2_wdata   (dma_m_wdata),   .m2_wstrb   (dma_m_wstrb),   .m2_wvalid  (dma_m_wvalid),  .m2_wready  (dma_m_wready),
        .m2_bresp   (dma_m_bresp),   .m2_bvalid  (dma_m_bvalid),  .m2_bready  (dma_m_bready),
        .m2_araddr  (dma_m_araddr),  .m2_arvalid (dma_m_arvalid),  .m2_arready (dma_m_arready),
        .m2_rdata   (dma_m_rdata),   .m2_rresp   (dma_m_rresp),   .m2_rvalid  (dma_m_rvalid),  .m2_rready  (dma_m_rready),
        // Slave: Birleştirilmiş çıkış
        .s_awaddr   (merged_m_awaddr),  .s_awvalid  (merged_m_awvalid),  .s_awready  (merged_m_awready),
        .s_wdata    (merged_m_wdata),   .s_wstrb    (merged_m_wstrb),   .s_wvalid   (merged_m_wvalid),  .s_wready   (merged_m_wready),
        .s_bresp    (merged_m_bresp),   .s_bvalid   (merged_m_bvalid),  .s_bready   (merged_m_bready),
        .s_araddr   (merged_m_araddr),  .s_arvalid  (merged_m_arvalid),  .s_arready  (merged_m_arready),
        .s_rdata    (merged_m_rdata),   .s_rresp    (merged_m_rresp),   .s_rvalid   (merged_m_rvalid),  .s_rready   (merged_m_rready)
    );

    // =========================================================
    // SLAVE PORT SİNYAL TANIMLAMALARI (INTERCONNECT ÇIKIŞLARI)
    // =========================================================
    
    // Slave 0: Boot ROM Data
    logic [31:0] s0_awaddr; logic s0_awvalid; logic s0_awready;
    logic [31:0] s0_wdata; logic [3:0] s0_wstrb; logic s0_wvalid; logic s0_wready;
    logic [1:0] s0_bresp; logic s0_bvalid; logic s0_bready;
    logic [31:0] s0_araddr; logic s0_arvalid; logic s0_arready;
    logic [31:0] s0_rdata; logic [1:0] s0_rresp; logic s0_rvalid; logic s0_rready;

    // Slave 1: Instruction RAM Data
    logic [31:0] s1_awaddr; logic s1_awvalid; logic s1_awready;
    logic [31:0] s1_wdata; logic [3:0] s1_wstrb; logic s1_wvalid; logic s1_wready;
    logic [1:0] s1_bresp; logic s1_bvalid; logic s1_bready;
    logic [31:0] s1_araddr; logic s1_arvalid; logic s1_arready;
    logic [31:0] s1_rdata; logic [1:0] s1_rresp; logic s1_rvalid; logic s1_rready;

    // Slave 2: Data RAM
    logic [31:0] s2_awaddr; logic s2_awvalid; logic s2_awready;
    logic [31:0] s2_wdata; logic [3:0] s2_wstrb; logic s2_wvalid; logic s2_wready;
    logic [1:0] s2_bresp; logic s2_bvalid; logic s2_bready;
    logic [31:0] s2_araddr; logic s2_arvalid; logic s2_arready;
    logic [31:0] s2_rdata; logic [1:0] s2_rresp; logic s2_rvalid; logic s2_rready;

    // Slave 3: GPIO
    logic [31:0] s3_awaddr; logic s3_awvalid; logic s3_awready;
    logic [31:0] s3_wdata; logic [3:0] s3_wstrb; logic s3_wvalid; logic s3_wready;
    logic [1:0] s3_bresp; logic s3_bvalid; logic s3_bready;
    logic [31:0] s3_araddr; logic s3_arvalid; logic s3_arready;
    logic [31:0] s3_rdata; logic [1:0] s3_rresp; logic s3_rvalid; logic s3_rready;

    // Slave 4: Timer
    logic [31:0] s4_awaddr; logic s4_awvalid; logic s4_awready;
    logic [31:0] s4_wdata; logic [3:0] s4_wstrb; logic s4_wvalid; logic s4_wready;
    logic [1:0] s4_bresp; logic s4_bvalid; logic s4_bready;
    logic [31:0] s4_araddr; logic s4_arvalid; logic s4_arready;
    logic [31:0] s4_rdata; logic [1:0] s4_rresp; logic s4_rvalid; logic s4_rready;

    // Slave 5: UART General
    logic [31:0] s5_awaddr; logic s5_awvalid; logic s5_awready;
    logic [31:0] s5_wdata; logic [3:0] s5_wstrb; logic s5_wvalid; logic s5_wready;
    logic [1:0] s5_bresp; logic s5_bvalid; logic s5_bready;
    logic [31:0] s5_araddr; logic s5_arvalid; logic s5_arready;
    logic [31:0] s5_rdata; logic [1:0] s5_rresp; logic s5_rvalid; logic s5_rready;

    // Slave 6: UART Stream
    logic [31:0] s6_awaddr; logic s6_awvalid; logic s6_awready;
    logic [31:0] s6_wdata; logic [3:0] s6_wstrb; logic s6_wvalid; logic s6_wready;
    logic [1:0] s6_bresp; logic s6_bvalid; logic s6_bready;
    logic [31:0] s6_araddr; logic s6_arvalid; logic s6_arready;
    logic [31:0] s6_rdata; logic [1:0] s6_rresp; logic s6_rvalid; logic s6_rready;

    // Slave 7: I2C Master
    logic [31:0] s7_awaddr; logic s7_awvalid; logic s7_awready;
    logic [31:0] s7_wdata; logic [3:0] s7_wstrb; logic s7_wvalid; logic s7_wready;
    logic [1:0] s7_bresp; logic s7_bvalid; logic s7_bready;
    logic [31:0] s7_araddr; logic s7_arvalid; logic s7_arready;
    logic [31:0] s7_rdata; logic [1:0] s7_rresp; logic s7_rvalid; logic s7_rready;

    // Slave 8: QSPI Master
    logic [31:0] s8_awaddr; logic s8_awvalid; logic s8_awready;
    logic [31:0] s8_wdata; logic [3:0] s8_wstrb; logic s8_wvalid; logic s8_wready;
    logic [1:0] s8_bresp; logic s8_bvalid; logic s8_bready;
    logic [31:0] s8_araddr; logic s8_arvalid; logic s8_arready;
    logic [31:0] s8_rdata; logic [1:0] s8_rresp; logic s8_rvalid; logic s8_rready;

    // Slave 9: NPU CSR
    logic [31:0] s9_awaddr; logic s9_awvalid; logic s9_awready;
    logic [31:0] s9_wdata; logic [3:0] s9_wstrb; logic s9_wvalid; logic s9_wready;
    logic [1:0] s9_bresp; logic s9_bvalid; logic s9_bready;
    logic [31:0] s9_araddr; logic s9_arvalid; logic s9_arready;
    logic [31:0] s9_rdata; logic [1:0] s9_rresp; logic s9_rvalid; logic s9_rready;

    // Slave 10: NPU Memory (30 kB)
    logic [31:0] s10_awaddr; logic s10_awvalid; logic s10_awready;
    logic [31:0] s10_wdata; logic [3:0] s10_wstrb; logic s10_wvalid; logic s10_wready;
    logic [1:0] s10_bresp; logic s10_bvalid; logic s10_bready;
    logic [31:0] s10_araddr; logic s10_arvalid; logic s10_arready;
    logic [31:0] s10_rdata; logic [1:0] s10_rresp; logic s10_rvalid; logic s10_rready;

    // Slave 11: DMA CSR
    logic [31:0] s11_awaddr; logic s11_awvalid; logic s11_awready;
    logic [31:0] s11_wdata; logic [3:0] s11_wstrb; logic s11_wvalid; logic s11_wready;
    logic [1:0] s11_bresp; logic s11_bvalid; logic s11_bready;
    logic [31:0] s11_araddr; logic s11_arvalid; logic s11_arready;
    logic [31:0] s11_rdata; logic [1:0] s11_rresp; logic s11_rvalid; logic s11_rready;

    // Slave 12: JTAG CSR
    logic [31:0] s12_awaddr; logic s12_awvalid; logic s12_awready;
    logic [31:0] s12_wdata; logic [3:0] s12_wstrb; logic s12_wvalid; logic s12_wready;
    logic [1:0] s12_bresp; logic s12_bvalid; logic s12_bready;
    logic [31:0] s12_araddr; logic s12_arvalid; logic s12_arready;
    logic [31:0] s12_rdata; logic [1:0] s12_rresp; logic s12_rvalid; logic s12_rready;

    // =========================================================
    // AXI4-LITE INTERCONNECT (KAVŞAK) INSTANTIATION
    // =========================================================
    axi_lite_interconnect u_interconnect (
        .clk        (clk_i),
        .rst_n      (rst_ni),
        // Birleştirilmiş Master (Arbiter çıkışı)
        .m_awaddr   (merged_m_awaddr),
        .m_awvalid  (merged_m_awvalid),
        .m_awready  (merged_m_awready),
        .m_wdata    (merged_m_wdata),
        .m_wstrb    (merged_m_wstrb),
        .m_wvalid   (merged_m_wvalid),
        .m_wready   (merged_m_wready),
        .m_bresp    (merged_m_bresp),
        .m_bvalid   (merged_m_bvalid),
        .m_bready   (merged_m_bready),
        .m_araddr   (merged_m_araddr),
        .m_arvalid  (merged_m_arvalid),
        .m_arready  (merged_m_arready),
        .m_rdata    (merged_m_rdata),
        .m_rresp    (merged_m_rresp),
        .m_rvalid   (merged_m_rvalid),
        .m_rready   (merged_m_rready),
        // Slaves 0-12
        .s0_awaddr  (s0_awaddr),  .s0_awvalid  (s0_awvalid),  .s0_awready  (s0_awready),
        .s0_wdata   (s0_wdata),   .s0_wstrb   (s0_wstrb),   .s0_wvalid   (s0_wvalid),   .s0_wready   (s0_wready),
        .s0_bresp   (s0_bresp),   .s0_bvalid   (s0_bvalid),   .s0_bready   (s0_bready),
        .s0_araddr  (s0_araddr),  .s0_arvalid  (s0_arvalid),  .s0_arready  (s0_arready),
        .s0_rdata   (s0_rdata),   .s0_rresp    (s0_rresp),    .s0_rvalid   (s0_rvalid),   .s0_rready   (s0_rready),

        .s1_awaddr  (s1_awaddr),  .s1_awvalid  (s1_awvalid),  .s1_awready  (s1_awready),
        .s1_wdata   (s1_wdata),   .s1_wstrb   (s1_wstrb),   .s1_wvalid   (s1_wvalid),   .s1_wready   (s1_wready),
        .s1_bresp   (s1_bresp),   .s1_bvalid   (s1_bvalid),   .s1_bready   (s1_bready),
        .s1_araddr  (s1_araddr),  .s1_arvalid  (s1_arvalid),  .s1_arready  (s1_arready),
        .s1_rdata   (s1_rdata),   .s1_rresp    (s1_rresp),    .s1_rvalid   (s1_rvalid),   .s1_rready   (s1_rready),

        .s2_awaddr  (s2_awaddr),  .s2_awvalid  (s2_awvalid),  .s2_awready  (s2_awready),
        .s2_wdata   (s2_wdata),   .s2_wstrb   (s2_wstrb),   .s2_wvalid   (s2_wvalid),   .s2_wready   (s2_wready),
        .s2_bresp   (s2_bresp),   .s2_bvalid   (s2_bvalid),   .s2_bready   (s2_bready),
        .s2_araddr  (s2_araddr),  .s2_arvalid  (s2_arvalid),  .s2_arready  (s2_arready),
        .s2_rdata   (s2_rdata),   .s2_rresp    (s2_rresp),    .s2_rvalid   (s2_rvalid),   .s2_rready   (s2_rready),

        .s3_awaddr  (s3_awaddr),  .s3_awvalid  (s3_awvalid),  .s3_awready  (s3_awready),
        .s3_wdata   (s3_wdata),   .s3_wstrb   (s3_wstrb),   .s3_wvalid   (s3_wvalid),   .s3_wready   (s3_wready),
        .s3_bresp   (s3_bresp),   .s3_bvalid   (s3_bvalid),   .s3_bready   (s3_bready),
        .s3_araddr  (s3_araddr),  .s3_arvalid  (s3_arvalid),  .s3_arready  (s3_arready),
        .s3_rdata   (s3_rdata),   .s3_rresp    (s3_rresp),    .s3_rvalid   (s3_rvalid),   .s3_rready   (s3_rready),

        .s4_awaddr  (s4_awaddr),  .s4_awvalid  (s4_awvalid),  .s4_awready  (s4_awready),
        .s4_wdata   (s4_wdata),   .s4_wstrb   (s4_wstrb),   .s4_wvalid   (s4_wvalid),   .s4_wready   (s4_wready),
        .s4_bresp   (s4_bresp),   .s4_bvalid   (s4_bvalid),   .s4_bready   (s4_bready),
        .s4_araddr  (s4_araddr),  .s4_arvalid  (s4_arvalid),  .s4_arready  (s4_arready),
        .s4_rdata   (s4_rdata),   .s4_rresp    (s4_rresp),    .s4_rvalid   (s4_rvalid),   .s4_rready   (s4_rready),

        .s5_awaddr  (s5_awaddr),  .s5_awvalid  (s5_awvalid),  .s5_awready  (s5_awready),
        .s5_wdata   (s5_wdata),   .s5_wstrb   (s5_wstrb),   .s5_wvalid   (s5_wvalid),   .s5_wready   (s5_wready),
        .s5_bresp   (s5_bresp),   .s5_bvalid   (s5_bvalid),   .s5_bready   (s5_bready),
        .s5_araddr  (s5_araddr),  .s5_arvalid  (s5_arvalid),  .s5_arready  (s5_arready),
        .s5_rdata   (s5_rdata),   .s5_rresp    (s5_rresp),    .s5_rvalid   (s5_rvalid),   .s5_rready   (s5_rready),

        .s6_awaddr  (s6_awaddr),  .s6_awvalid  (s6_awvalid),  .s6_awready  (s6_awready),
        .s6_wdata   (s6_wdata),   .s6_wstrb   (s6_wstrb),   .s6_wvalid   (s6_wvalid),   .s6_wready   (s6_wready),
        .s6_bresp   (s6_bresp),   .s6_bvalid   (s6_bvalid),   .s6_bready   (s6_bready),
        .s6_araddr  (s6_araddr),  .s6_arvalid  (s6_arvalid),  .s6_arready  (s6_arready),
        .s6_rdata   (s6_rdata),   .s6_rresp    (s6_rresp),    .s6_rvalid   (s6_rvalid),   .s6_rready   (s6_rready),

        .s7_awaddr  (s7_awaddr),  .s7_awvalid  (s7_awvalid),  .s7_awready  (s7_awready),
        .s7_wdata   (s7_wdata),   .s7_wstrb   (s7_wstrb),   .s7_wvalid   (s7_wvalid),   .s7_wready   (s7_wready),
        .s7_bresp   (s7_bresp),   .s7_bvalid   (s7_bvalid),   .s7_bready   (s7_bready),
        .s7_araddr  (s7_araddr),  .s7_arvalid  (s7_arvalid),  .s7_arready  (s7_arready),
        .s7_rdata   (s7_rdata),   .s7_rresp    (s7_rresp),    .s7_rvalid   (s7_rvalid),   .s7_rready   (s7_rready),

        .s8_awaddr  (s8_awaddr),  .s8_awvalid  (s8_awvalid),  .s8_awready  (s8_awready),
        .s8_wdata   (s8_wdata),   .s8_wstrb   (s8_wstrb),   .s8_wvalid   (s8_wvalid),   .s8_wready   (s8_wready),
        .s8_bresp   (s8_bresp),   .s8_bvalid   (s8_bvalid),   .s8_bready   (s8_bready),
        .s8_araddr  (s8_araddr),  .s8_arvalid  (s8_arvalid),  .s8_arready  (s8_arready),
        .s8_rdata   (s8_rdata),   .s8_rresp    (s8_rresp),    .s8_rvalid   (s8_rvalid),   .s8_rready   (s8_rready),

        .s9_awaddr  (s9_awaddr),  .s9_awvalid  (s9_awvalid),  .s9_awready  (s9_awready),
        .s9_wdata   (s9_wdata),   .s9_wstrb   (s9_wstrb),   .s9_wvalid   (s9_wvalid),   .s9_wready   (s9_wready),
        .s9_bresp   (s9_bresp),   .s9_bvalid   (s9_bvalid),   .s9_bready   (s9_bready),
        .s9_araddr  (s9_araddr),  .s9_arvalid  (s9_arvalid),  .s9_arready  (s9_arready),
        .s9_rdata   (s9_rdata),   .s9_rresp    (s9_rresp),    .s9_rvalid   (s9_rvalid),   .s9_rready   (s9_rready),

        .s10_awaddr (s10_awaddr), .s10_awvalid (s10_awvalid), .s10_awready (s10_awready),
        .s10_wdata  (s10_wdata),  .s10_wstrb   (s10_wstrb),   .s10_wvalid  (s10_wvalid),  .s10_wready  (s10_wready),
        .s10_bresp  (s10_bresp),  .s10_bvalid  (s10_bvalid),  .s10_bready  (s10_bready),
        .s10_araddr (s10_araddr), .s10_arvalid (s10_arvalid), .s10_arready (s10_arready),
        .s10_rdata  (s10_rdata),  .s10_rresp   (s10_rresp),   .s10_rvalid  (s10_rvalid),  .s10_rready  (s10_rready),

        .s11_awaddr (s11_awaddr), .s11_awvalid (s11_awvalid), .s11_awready (s11_awready),
        .s11_wdata  (s11_wdata),  .s11_wstrb   (s11_wstrb),   .s11_wvalid  (s11_wvalid),  .s11_wready  (s11_wready),
        .s11_bresp  (s11_bresp),  .s11_bvalid  (s11_bvalid),  .s11_bready  (s11_bready),
        .s11_araddr (s11_araddr), .s11_arvalid (s11_arvalid), .s11_arready (s11_arready),
        .s11_rdata  (s11_rdata),  .s11_rresp   (s11_rresp),   .s11_rvalid  (s11_rvalid),  .s11_rready  (s11_rready),

        .s12_awaddr (s12_awaddr), .s12_awvalid (s12_awvalid), .s12_awready (s12_awready),
        .s12_wdata  (s12_wdata),  .s12_wstrb   (s12_wstrb),   .s12_wvalid  (s12_wvalid),  .s12_wready  (s12_wready),
        .s12_bresp  (s12_bresp),  .s12_bvalid  (s12_bvalid),  .s12_bready  (s12_bready),
        .s12_araddr (s12_araddr), .s12_arvalid (s12_arvalid), .s12_arready (s12_arready),
        .s12_rdata  (s12_rdata),  .s12_rresp   (s12_rresp),   .s12_rvalid  (s12_rvalid),  .s12_rready  (s12_rready)
    );

    // =========================================================
    // INSTRUCTION SIDE ADDRESS DECODER/ROUTER
    // =========================================================
    logic instr_to_rom;
    assign instr_to_rom = (instr_axil_araddr[31:24] == 8'h00);

    // ROM Arbiter Master 0
    logic [31:0] rom_m0_araddr; logic rom_m0_arvalid; logic rom_m0_arready;
    logic [31:0] rom_m0_rdata; logic [1:0] rom_m0_rresp; logic rom_m0_rvalid; logic rom_m0_rready;

    assign rom_m0_araddr  = instr_axil_araddr;
    assign rom_m0_arvalid = instr_axil_arvalid && instr_to_rom;
    assign rom_m0_rready  = instr_axil_rready;

    // Instruction RAM (I-RAM) Arbiter Master 0
    logic [31:0] iram_m0_araddr; logic iram_m0_arvalid; logic iram_m0_arready;
    logic [31:0] iram_m0_rdata; logic [1:0] iram_m0_rresp; logic iram_m0_rvalid; logic iram_m0_rready;

    assign iram_m0_araddr  = instr_axil_araddr;
    assign iram_m0_arvalid = instr_axil_arvalid && !instr_to_rom;
    assign iram_m0_rready  = instr_axil_rready;

    // Demux read response back to Instruction Bridge
    assign instr_axil_arready = instr_to_rom ? rom_m0_arready : iram_m0_arready;
    assign instr_axil_rdata   = instr_to_rom ? rom_m0_rdata   : iram_m0_rdata;
    assign instr_axil_rresp   = instr_to_rom ? rom_m0_rresp   : iram_m0_rresp;
    assign instr_axil_rvalid  = instr_to_rom ? rom_m0_rvalid  : iram_m0_rvalid;

    // =========================================================
    // ARBITERS FOR SHARED MEMORY SPACES (ROM & I-RAM)
    // =========================================================
    
    // ROM Arbiter (Shared between Instruction Fetch and Data Bus)
    logic [31:0] rom_s_awaddr; logic rom_s_awvalid; logic rom_s_awready;
    logic [31:0] rom_s_wdata; logic [3:0] rom_s_wstrb; logic rom_s_wvalid; logic rom_s_wready;
    logic [1:0] rom_s_bresp; logic rom_s_bvalid; logic rom_s_bready;
    logic [31:0] rom_s_araddr; logic rom_s_arvalid; logic rom_s_arready;
    logic [31:0] rom_s_rdata; logic [1:0] rom_s_rresp; logic rom_s_rvalid; logic rom_s_rready;

    axil_arbiter_2to1 u_rom_arbiter (
        .clk        (clk_i),
        .rst_n      (rst_ni),
        .m0_araddr  (rom_m0_araddr),  .m0_arvalid (rom_m0_arvalid),  .m0_arready (rom_m0_arready),
        .m0_rdata   (rom_m0_rdata),   .m0_rresp   (rom_m0_rresp),    .m0_rvalid  (rom_m0_rvalid),  .m0_rready  (rom_m0_rready),
        .m1_awaddr  (s0_awaddr),  .m1_awvalid (s0_awvalid),  .m1_awready (s0_awready),
        .m1_wdata   (s0_wdata),   .m1_wstrb   (s0_wstrb),   .m1_wvalid  (s0_wvalid),  .m1_wready  (s0_wready),
        .m1_bresp   (s0_bresp),   .m1_bvalid  (s0_bvalid),  .m1_bready  (s0_bready),
        .m1_araddr  (s0_araddr),  .m1_arvalid (s0_arvalid),  .m1_arready (s0_arready),
        .m1_rdata   (s0_rdata),   .m1_rresp   (s0_rresp),   .m1_rvalid  (s0_rvalid),  .m1_rready  (s0_rready),
        .s_awaddr   (rom_s_awaddr),  .s_awvalid  (rom_s_awvalid),  .s_awready  (rom_s_awready),
        .s_wdata    (rom_s_wdata),   .s_wstrb    (rom_s_wstrb),   .s_wvalid   (rom_s_wvalid),  .s_wready   (rom_s_wready),
        .s_bresp    (rom_s_bresp),   .s_bvalid   (rom_s_bvalid),  .s_bready   (rom_s_bready),
        .s_araddr   (rom_s_araddr),  .s_arvalid  (rom_s_arvalid),  .s_arready  (rom_s_arready),
        .s_rdata    (rom_s_rdata),   .s_rresp    (rom_s_rresp),   .s_rvalid   (rom_s_rvalid),  .s_rready   (rom_s_rready)
    );

    // I-RAM Arbiter (Shared between Instruction Fetch and Data Bus for shadowing)
    logic [31:0] iram_s_awaddr; logic iram_s_awvalid; logic iram_s_awready;
    logic [31:0] iram_s_wdata; logic [3:0] iram_s_wstrb; logic iram_s_wvalid; logic iram_s_wready;
    logic [1:0] iram_s_bresp; logic iram_s_bvalid; logic iram_s_bready;
    logic [31:0] iram_s_araddr; logic iram_s_arvalid; logic iram_s_arready;
    logic [31:0] iram_s_rdata; logic [1:0] iram_s_rresp; logic iram_s_rvalid; logic iram_s_rready;

    axil_arbiter_2to1 u_iram_arbiter (
        .clk        (clk_i),
        .rst_n      (rst_ni),
        .m0_araddr  (iram_m0_araddr),  .m0_arvalid (iram_m0_arvalid),  .m0_arready (iram_m0_arready),
        .m0_rdata   (iram_m0_rdata),   .m0_rresp   (iram_m0_rresp),    .m0_rvalid  (iram_m0_rvalid),  .m0_rready  (iram_m0_rready),
        .m1_awaddr  (s1_awaddr),  .m1_awvalid (s1_awvalid),  .m1_awready (s1_awready),
        .m1_wdata   (s1_wdata),   .m1_wstrb   (s1_wstrb),   .m1_wvalid  (s1_wvalid),  .m1_wready  (s1_wready),
        .m1_bresp   (s1_bresp),   .m1_bvalid  (s1_bvalid),  .m1_bready  (s1_bready),
        .m1_araddr  (s1_araddr),  .m1_arvalid (s1_arvalid),  .m1_arready (s1_arready),
        .m1_rdata   (s1_rdata),   .m1_rresp   (s1_rresp),   .m1_rvalid  (s1_rvalid),  .m1_rready  (s1_rready),
        .s_awaddr   (iram_s_awaddr),  .s_awvalid  (iram_s_awvalid),  .s_awready  (iram_s_awready),
        .s_wdata    (iram_s_wdata),   .s_wstrb    (iram_s_wstrb),   .s_wvalid   (iram_s_wvalid),  .s_wready   (iram_s_wready),
        .s_bresp    (iram_s_bresp),   .s_bvalid   (iram_s_bvalid),  .s_bready   (iram_s_bready),
        .s_araddr   (iram_s_araddr),  .s_arvalid  (iram_s_arvalid),  .s_arready  (iram_s_arready),
        .s_rdata    (iram_s_rdata),   .s_rresp    (iram_s_rresp),   .s_rvalid   (iram_s_rvalid),  .s_rready   (iram_s_rready)
    );

    // =========================================================
    // BELLEKLER (BOOT ROM, I-RAM, D-RAM) INSTANTIATION
    // =========================================================
    
    // Boot ROM (1 kB)
    logic [31:0] rom_addr_i;
    logic        rom_req_i;
    logic [31:0] rom_rdata_o;
    logic        rom_rvalid_o;

    boot_rom u_boot_rom (
        .clk_i        (clk_i),
        .rst_ni       (rst_ni),
        .rom_addr_i   (rom_addr_i),
        .rom_req_i    (rom_req_i),
        .rom_rdata_o  (rom_rdata_o),
        .rom_rvalid_o (rom_rvalid_o)
    );

    // AXI-Lite to OBI conversion for Boot ROM
    assign rom_addr_i      = rom_s_araddr;
    assign rom_req_i       = rom_s_arvalid;
    assign rom_s_arready   = 1'b1;
    assign rom_s_rdata     = rom_rdata_o;
    assign rom_s_rresp     = 2'b00;
    assign rom_s_rvalid    = rom_rvalid_o;

    // AXI-Lite Write responder for Boot ROM (Read-only)
    assign rom_s_awready   = 1'b1;
    assign rom_s_wready    = 1'b1;
    assign rom_s_bresp     = 2'b00;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            rom_s_bvalid <= 1'b0;
        end else begin
            if (rom_s_awvalid && rom_s_wvalid && !rom_s_bvalid) begin
                rom_s_bvalid <= 1'b1;
            end else if (rom_s_bvalid && rom_s_bready) begin
                rom_s_bvalid <= 1'b0;
            end
        end
    end

    // Instruction RAM (8 kB SRAM)
    sram_module #(
        .AXI_ADDR_W (32),
        .AXI_DATA_W (32),
        .RAM_DEPTH  (2048)
    ) u_instruction_ram (
        .clk            (clk_i),
        .rst_n          (rst_ni),
        .s_axil_awaddr  (iram_s_awaddr),  .s_axil_awvalid (iram_s_awvalid),  .s_axil_awready (iram_s_awready),
        .s_axil_wdata   (iram_s_wdata),   .s_axil_wstrb   (iram_s_wstrb),   .s_axil_wvalid  (iram_s_wvalid),  .s_axil_wready  (iram_s_wready),
        .s_axil_bresp   (iram_s_bresp),   .s_axil_bvalid  (iram_s_bvalid),  .s_axil_bready  (iram_s_bready),
        .s_axil_araddr  (iram_s_araddr),  .s_axil_arvalid (iram_s_arvalid),  .s_axil_arready (iram_s_arready),
        .s_axil_rdata   (iram_s_rdata),   .s_axil_rresp   (iram_s_rresp),   .s_axil_rvalid  (iram_s_rvalid),  .s_axil_rready  (iram_s_rready)
    );

    // Data RAM (8 kB SRAM)
    sram_module #(
        .AXI_ADDR_W (32),
        .AXI_DATA_W (32),
        .RAM_DEPTH  (2048)
    ) u_data_ram (
        .clk            (clk_i),
        .rst_n          (rst_ni),
        .s_axil_awaddr  (s2_awaddr),  .s_axil_awvalid (s2_awvalid),  .s_axil_awready (s2_awready),
        .s_axil_wdata   (s2_wdata),   .s_axil_wstrb   (s2_wstrb),   .s_axil_wvalid  (s2_wvalid),  .s_axil_wready  (s2_wready),
        .s_axil_bresp   (s2_bresp),   .s_axil_bvalid  (s2_bvalid),  .s_axil_bready  (s2_bready),
        .s_axil_araddr  (s2_araddr),  .s_axil_arvalid (s2_arvalid),  .s_axil_arready (s2_arready),
        .s_axil_rdata   (s2_rdata),   .s_axil_rresp   (s2_rresp),   .s_axil_rvalid  (s2_rvalid),  .s_axil_rready  (s2_rready)
    );

    // =========================================================
    // ÇEVRE BİRİMLERİ (PERIPHERALS) INSTANTIATION
    // =========================================================
    
    // GPIO (16 Inputs / 16 Outputs)
    gpio_peripheral #(
        .AXI_ADDR_W (32),
        .AXI_DATA_W (32)
    ) u_gpio (
        .clk                (clk_i),
        .rst_n              (rst_ni),
        .gpio_i             (gpio_i),
        .gpio_o             (gpio_o),
        .gpio_tx_en_o       (gpio_tx_en_o),
        .global_interrupt_o (gpio_irq),
        .s_axil_awaddr      (s3_awaddr),  .s_axil_awvalid (s3_awvalid),  .s_axil_awready (s3_awready),
        .s_axil_wdata       (s3_wdata),   .s_axil_wstrb   (s3_wstrb),   .s_axil_wvalid  (s3_wvalid),  .s_axil_wready  (s3_wready),
        .s_axil_bresp       (s3_bresp),   .s_axil_bvalid  (s3_bvalid),  .s_axil_bready  (s3_bready),
        .s_axil_araddr      (s3_araddr),  .s_axil_arvalid (s3_arvalid),  .s_axil_arready (s3_arready),
        .s_axil_rdata       (s3_rdata),   .s_axil_rresp   (s3_rresp),   .s_axil_rvalid  (s3_rvalid),  .s_axil_rready  (s3_rready)
    );

    // Timer (32-bit Prescaled Counter)
    timer_peripheral #(
        .S_AXI_ADDR_WIDTH   (32),
        .S_AXI_DATA_WIDTH   (32)
    ) u_timer (
        .s_axi_aclk     (clk_i),
        .s_axi_aresetn  (rst_ni),
        .s_axi_awaddr   (s4_awaddr),  .s_axi_awprot (3'b000),  .s_axi_awvalid (s4_awvalid),  .s_axi_awready (s4_awready),
        .s_axi_wdata    (s4_wdata),   .s_axi_wstrb  (s4_wstrb),  .s_axi_wvalid (s4_wvalid),  .s_axi_wready (s4_wready),
        .s_axi_bresp    (s4_bresp),   .s_axi_bvalid (s4_bvalid),  .s_axi_bready (s4_bready),
        .s_axi_araddr   (s4_araddr),  .s_axi_arprot (3'b000),  .s_axi_arvalid (s4_arvalid),  .s_axi_arready (s4_arready),
        .s_axi_rdata    (s4_rdata),   .s_axi_rresp  (s4_rresp),  .s_axi_rvalid (s4_rvalid),  .s_axi_rready (s4_rready),
        .timer_irq      (timer_irq)
    );

    // UART 1 (General Purpose UART)
    uart_peripheral #(
        .SYS_CLK_HZ     (50_000_000),
        .DEFAULT_BAUD   (115_200)
    ) u_uart1 (
        .clk            (clk_i),
        .rst_n          (rst_ni),
        .uart_rxd       (uart1_rxd),
        .uart_txd       (uart1_txd),
        .uart_irq       (uart1_irq),
        .s_axil_awaddr  (s5_awaddr[7:0]),  .s_axil_awvalid (s5_awvalid),  .s_axil_awready (s5_awready),
        .s_axil_wdata   (s5_wdata),   .s_axil_wstrb   (s5_wstrb),   .s_axil_wvalid  (s5_wvalid),  .s_axil_wready  (s5_wready),
        .s_axil_bresp   (s5_bresp),   .s_axil_bvalid  (s5_bvalid),  .s_axil_bready  (s5_bready),
        .s_axil_araddr  (s5_araddr[7:0]),  .s_axil_arvalid (s5_arvalid),  .s_axil_arready (s5_arready),
        .s_axil_rdata   (s5_rdata),   .s_axil_rresp   (s5_rresp),   .s_axil_rvalid  (s5_rvalid),  .s_axil_rready  (s5_rready)
    );

    // UART 2 (UART Stream)
    uart_stream_peripheral #(
        .SYS_CLK_HZ     (50_000_000),
        .DEFAULT_BAUD   (115_200)
    ) u_uart2 (
        .clk            (clk_i),
        .rst_n          (rst_ni),
        .uart_rxd       (uart2_rxd),
        .uart_txd       (uart2_txd),
        .uart_stream_irq(uart2_irq),
        .fifo_empty     (),
        .fifo_full      (),
        .s_axil_awaddr  (s6_awaddr[7:0]),  .s_axil_awvalid (s6_awvalid),  .s_axil_awready (s6_awready),
        .s_axil_wdata   (s6_wdata),   .s_axil_wstrb   (s6_wstrb),   .s_axil_wvalid  (s6_wvalid),  .s_axil_wready  (s6_wready),
        .s_axil_bresp   (s6_bresp),   .s_axil_bvalid  (s6_bvalid),  .s_axil_bready  (s6_bready),
        .s_axil_araddr  (s6_araddr[7:0]),  .s_axil_arvalid (s6_arvalid),  .s_axil_arready (s6_arready),
        .s_axil_rdata   (s6_rdata),   .s_axil_rresp   (s6_rresp),   .s_axil_rvalid  (s6_rvalid),  .s_axil_rready  (s6_rready)
    );

    // I2C Master (400 kHz Fast Mode)
    i2c_peripheral #(
        .SYS_CLK_FREQ   (50_000_000),
        .I2C_FREQ       (400_000)
    ) u_i2c (
        .clk            (clk_i),
        .rst_n          (rst_ni),
        .sda            (i2c_sda),
        .scl            (i2c_scl),
        .i2c_irq        (i2c_irq),
        .s_axi_awaddr   (s7_awaddr[7:0]),  .s_axi_awprot (3'b000),  .s_axi_awvalid (s7_awvalid),  .s_axi_awready (s7_awready),
        .s_axi_wdata    (s7_wdata),   .s_axi_wstrb  (s7_wstrb),  .s_axi_wvalid (s7_wvalid),  .s_axi_wready (s7_wready),
        .s_axi_bresp    (s7_bresp),   .s_axi_bvalid (s7_bvalid),  .s_axi_bready (s7_bready),
        .s_axi_araddr   (s7_araddr[7:0]),  .s_axi_arprot (3'b000),  .s_axi_arvalid (s7_arvalid),  .s_axi_arready (s7_arready),
        .s_axi_rdata    (s7_rdata),   .s_axi_rresp  (s7_rresp),  .s_axi_rvalid (s7_rvalid),  .s_axi_rready (s7_rready)
    );

    // QSPI Master (Supports NOR Flash Interface)
    qspi_master #(
        .FIFO_DEPTH     (64),
        .AXI_AW         (32),
        .AXI_DW         (32)
    ) u_qspi (
        .clk            (clk_i),
        .rst_n          (rst_ni),
        .qspi_sck       (qspi_sck),
        .qspi_cs_n      (qspi_cs_n),
        .qspi_io0       (qspi_io0),
        .qspi_io1       (qspi_io1),
        .qspi_io2       (qspi_io2),
        .qspi_io3       (qspi_io3),
        .irq            (qspi_irq),
        .s_axi_awaddr   (s8_awaddr),  .s_axi_awvalid (s8_awvalid),  .s_axi_awready (s8_awready),
        .s_axi_wdata    (s8_wdata),   .s_axi_wstrb   (s8_wstrb),   .s_axi_wvalid  (s8_wvalid),  .s_axi_wready  (s8_wready),
        .s_axi_bresp    (s8_bresp),   .s_axi_bvalid  (s8_bvalid),  .s_axi_bready  (s8_bready),
        .s_axi_araddr   (s8_araddr),  .s_axi_arvalid (s8_arvalid),  .s_axi_arready (s8_arready),
        .s_axi_rdata    (s8_rdata),   .s_axi_rresp   (s8_rresp),   .s_axi_rvalid  (s8_rvalid),  .s_axi_rready  (s8_rready)
    );

    // =========================================================================
    // YAPAY ZEKA HIZLANDIRICI (NPU) ENTEGRASYONU
    // =========================================================================
    npu_accelerator u_npu (
        .clk         (clk_i),
        .rst_n       (rst_ni),
        // AXI Slave - CSR (s9)
        .reg_awaddr  (s9_awaddr),  .reg_awvalid (s9_awvalid),  .reg_awready (s9_awready),
        .reg_wdata   (s9_wdata),   .reg_wstrb   (s9_wstrb),   .reg_wvalid  (s9_wvalid),  .reg_wready  (s9_wready),
        .reg_bresp   (s9_bresp),   .reg_bvalid  (s9_bvalid),  .reg_bready  (s9_bready),
        .reg_araddr  (s9_araddr),  .reg_arvalid (s9_arvalid),  .reg_arready (s9_arready),
        .reg_rdata   (s9_rdata),   .reg_rresp   (s9_rresp),   .reg_rvalid  (s9_rvalid),  .reg_rready  (s9_rready),
        // AXI Slave - Memory (s10)
        .mem_awaddr  (s10_awaddr),  .mem_awvalid (s10_awvalid),  .mem_awready (s10_awready),
        .mem_wdata   (s10_wdata),   .mem_wstrb   (s10_wstrb),   .mem_wvalid  (s10_wvalid),  .mem_wready  (s10_wready),
        .mem_bresp   (s10_bresp),   .mem_bvalid  (s10_bvalid),  .mem_bready  (s10_bready),
        .mem_araddr  (s10_araddr),  .mem_arvalid (s10_arvalid),  .mem_arready (s10_arready),
        .mem_rdata   (s10_rdata),   .mem_rresp   (s10_rresp),   .mem_rvalid  (s10_rvalid),  .mem_rready  (s10_rready),
        // Kesme Çıkışı
        .irq_o       (npu_irq)
    );

    // =========================================================================
    // DMA KONTROLCÜSÜ ENTEGRASYONU
    // =========================================================================
    dma_controller u_dma (
        .clk            (clk_i),
        .rst_n          (rst_ni),
        // AXI Slave - CSR (s11)
        .s_axi_awaddr   (s11_awaddr),  .s_axi_awvalid (s11_awvalid),  .s_axi_awready (s11_awready),
        .s_axi_wdata    (s11_wdata),   .s_axi_wstrb   (s11_wstrb),   .s_axi_wvalid  (s11_wvalid),  .s_axi_wready  (s11_wready),
        .s_axi_bresp    (s11_bresp),   .s_axi_bvalid  (s11_bvalid),  .s_axi_bready  (s11_bready),
        .s_axi_araddr   (s11_araddr),  .s_axi_arvalid (s11_arvalid),  .s_axi_arready (s11_arready),
        .s_axi_rdata    (s11_rdata),   .s_axi_rresp   (s11_rresp),   .s_axi_rvalid  (s11_rvalid),  .s_axi_rready  (s11_rready),
        // AXI Master - Veri Transfer Portu
        .m_axi_awaddr   (dma_m_awaddr),  .m_axi_awvalid (dma_m_awvalid),  .m_axi_awready (dma_m_awready),
        .m_axi_wdata    (dma_m_wdata),   .m_axi_wstrb   (dma_m_wstrb),   .m_axi_wvalid  (dma_m_wvalid),  .m_axi_wready  (dma_m_wready),
        .m_axi_bresp    (dma_m_bresp),   .m_axi_bvalid  (dma_m_bvalid),  .m_axi_bready  (dma_m_bready),
        .m_axi_araddr   (dma_m_araddr),  .m_axi_arvalid (dma_m_arvalid),  .m_axi_arready (dma_m_arready),
        .m_axi_rdata    (dma_m_rdata),   .m_axi_rresp   (dma_m_rresp),   .m_axi_rvalid  (dma_m_rvalid),  .m_axi_rready  (dma_m_rready),
        // Kesme
        .irq_o          (dma_irq)
    );

    // =========================================================================
    // JTAG/DEBUG MODÜLÜ ENTEGRASYONU
    // =========================================================================
    jtag_debug u_jtag (
        .clk            (clk_i),
        .rst_n          (rst_ni),
        // JTAG Fiziksel Pinler
        .jtag_tms       (jtag_tms),
        .jtag_tck       (jtag_tck),
        .jtag_tdi       (jtag_tdi),
        .jtag_tdo       (jtag_tdo),
        .jtag_trst_n    (jtag_trst_n),
        // CPU Debug Kontrol
        .debug_req_o    (debug_req),
        // AXI Slave - CSR (s12)
        .s_axi_awaddr   (s12_awaddr),  .s_axi_awvalid (s12_awvalid),  .s_axi_awready (s12_awready),
        .s_axi_wdata    (s12_wdata),   .s_axi_wstrb   (s12_wstrb),   .s_axi_wvalid  (s12_wvalid),  .s_axi_wready  (s12_wready),
        .s_axi_bresp    (s12_bresp),   .s_axi_bvalid  (s12_bvalid),  .s_axi_bready  (s12_bready),
        .s_axi_araddr   (s12_araddr),  .s_axi_arvalid (s12_arvalid),  .s_axi_arready (s12_arready),
        .s_axi_rdata    (s12_rdata),   .s_axi_rresp   (s12_rresp),   .s_axi_rvalid  (s12_rvalid),  .s_axi_rready  (s12_rready),
        // AXI Master - Bellek Erişim Portu
        .m_axi_awaddr   (jtag_m_awaddr),  .m_axi_awvalid (jtag_m_awvalid),  .m_axi_awready (jtag_m_awready),
        .m_axi_wdata    (jtag_m_wdata),   .m_axi_wstrb   (jtag_m_wstrb),   .m_axi_wvalid  (jtag_m_wvalid),  .m_axi_wready  (jtag_m_wready),
        .m_axi_bresp    (jtag_m_bresp),   .m_axi_bvalid  (jtag_m_bvalid),  .m_axi_bready  (jtag_m_bready),
        .m_axi_araddr   (jtag_m_araddr),  .m_axi_arvalid (jtag_m_arvalid),  .m_axi_arready (jtag_m_arready),
        .m_axi_rdata    (jtag_m_rdata),   .m_axi_rresp   (jtag_m_rresp),   .m_axi_rvalid  (jtag_m_rvalid),  .m_axi_rready  (jtag_m_rready)
    );

endmodule
