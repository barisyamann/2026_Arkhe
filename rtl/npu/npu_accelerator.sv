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

    // SRAM Port B (salt-okunur) fiziksel sinyalleri
    logic        eng_tcm_rd_en;
    logic [12:0] eng_tcm_rd_addr;
    logic [31:0] ram_rdata_b;

    // Compute Engine <-> AXI master basit request/response arayuzu
    logic        eng_req_valid;
    logic        eng_req_write;
    logic [12:0] eng_req_addr;
    logic [31:0] eng_req_wdata;
    logic [3:0]  eng_req_wstrb;
    logic        eng_req_ready;
    logic        eng_rsp_valid;
    logic [31:0] eng_rsp_rdata;
    logic [1:0]  eng_rsp_resp;

    // Yerel Engine AXI4-Lite baglantisi
    logic [31:0] eng_axi_awaddr;
    logic        eng_axi_awvalid;
    logic        eng_axi_awready;
    logic [31:0] eng_axi_wdata;
    logic [3:0]  eng_axi_wstrb;
    logic        eng_axi_wvalid;
    logic        eng_axi_wready;
    logic [1:0]  eng_axi_bresp;
    logic        eng_axi_bvalid;
    logic        eng_axi_bready;
    logic [31:0] eng_axi_araddr;
    logic        eng_axi_arvalid;
    logic        eng_axi_arready;
    logic [31:0] eng_axi_rdata;
    logic [1:0]  eng_axi_rresp;
    logic        eng_axi_rvalid;
    logic        eng_axi_rready;

    // Engine AXI TCM adapter -> Port A write istegi
    logic        eng_wr_req;
    logic [12:0] eng_wr_addr;
    logic [31:0] eng_wr_data;
    logic [3:0]  eng_wr_strb;
    logic        eng_wr_grant;

    // =========================================================================
    // TCM Port A cokluyucusu - B2 (ASIC SRAM makro uyumlulugu)
    //
    // sky130 SRAM makrolari 1RW + 1R yapisindadir: yalnizca BIR port yazabilir.
    // Onceki tasarimda iki port da yaziyordu (Port A: AXI, Port B: hesaplama
    // motorunun softmax sonuclari) ve bu yapi ASIC'te dogrudan makroya
    // eslenemezdi.
    //
    // Cozum: motorun sonuc yazimlari da Port A'ya yonlendirildi. Motor yalnizca
    // WRITE_OUT_0..3 durumlarinda, toplam DORT kelime yaziyor; geri kalan tum
    // erisimi okuma. Port B artik salt-okunur.
    //
    // Cakisma: oncelik motordadir (sonucun kaybolmasi sessiz bir hesap hatasi
    // olurdu), AXI tarafi ise stall_i ile geri bastirilir - erisim dusurulmez,
    // yalnizca dort cevrim ertelenir.
    //
    // "NPU mesgulken CPU zaten wfi'da bekliyor" argumanina DAYANILMADI: bu bir
    // yazilim davranisidir ve donanim garantisi yerine gecmez.
    // =========================================================================
    logic        tcm_en_a;
    logic [3:0]  tcm_we_a;
    logic [12:0] tcm_addr_a;
    logic [31:0] tcm_wdata_a;

    // Engine yazmalari Port A'da onceliklidir. Aynı sinyal external MEM_AXI
    // controller'i stall ederek transaction kaybini engeller.
    assign tcm_en_a    = eng_wr_req ? 1'b1        : ram_en_a;
    assign tcm_we_a    = eng_wr_req ? eng_wr_strb : ram_we_a;
    assign tcm_addr_a  = eng_wr_req ? eng_wr_addr : ram_addr_a;
    assign tcm_wdata_a = eng_wr_req ? eng_wr_data : ram_wdata_a;

    // Port A mux motor istegine kesin oncelik verdigi icin grant her zaman
    // verilebilir; external controller ayni anda stall edilir.
    assign eng_wr_grant = 1'b1;


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
        .ram_rdata_i    (ram_rdata_a),

        // Motor sonuc yazarken Port A onundur; AXI tarafi geri bastirilir
        .stall_i        (eng_wr_req)
    );

    // =========================================================================
    // NPU Yerel Belleği (TCM SRAM)
    // =========================================================================
    npu_tcm_sram #(
        .TCM_WORDS (TCM_WORDS)
    ) u_npu_sram (
        .clk            (clk),

        // Port A - TEK YAZAN PORT (AXI erisimleri + motor sonuc yazimlari)
        .en_a           (tcm_en_a),
        .we_a           (tcm_we_a),
        .addr_a         (tcm_addr_a),
        .wdata_a        (tcm_wdata_a),
        .rdata_a        (ram_rdata_a),

        // Port B - SALT OKUNUR (motorun veri/agirlik okumalari)
        .en_b           (eng_tcm_rd_en),
        .addr_b         (eng_tcm_rd_addr),
        .rdata_b        (ram_rdata_b)
    );

    // =========================================================================
    // Compute Engine request -> AXI4-Lite master
    // =========================================================================
    npu_engine_axi_master #(.TCM_BASE_ADDR(32'h2001_0000)) u_engine_axi_master (
        .clk            (clk),
        .rst_n          (rst_n),
        .req_valid_i    (eng_req_valid),
        .req_write_i    (eng_req_write),
        .req_addr_i     (eng_req_addr),
        .req_wdata_i    (eng_req_wdata),
        .req_wstrb_i    (eng_req_wstrb),
        .req_ready_o    (eng_req_ready),
        .rsp_valid_o    (eng_rsp_valid),
        .rsp_rdata_o    (eng_rsp_rdata),
        .rsp_resp_o     (eng_rsp_resp),
        .m_axi_awaddr   (eng_axi_awaddr),
        .m_axi_awvalid  (eng_axi_awvalid),
        .m_axi_awready  (eng_axi_awready),
        .m_axi_wdata    (eng_axi_wdata),
        .m_axi_wstrb    (eng_axi_wstrb),
        .m_axi_wvalid   (eng_axi_wvalid),
        .m_axi_wready   (eng_axi_wready),
        .m_axi_bresp    (eng_axi_bresp),
        .m_axi_bvalid   (eng_axi_bvalid),
        .m_axi_bready   (eng_axi_bready),
        .m_axi_araddr   (eng_axi_araddr),
        .m_axi_arvalid  (eng_axi_arvalid),
        .m_axi_arready  (eng_axi_arready),
        .m_axi_rdata    (eng_axi_rdata),
        .m_axi_rresp    (eng_axi_rresp),
        .m_axi_rvalid   (eng_axi_rvalid),
        .m_axi_rready   (eng_axi_rready)
    );

    // =========================================================================
    // Yerel AXI4-Lite -> fiziksel TCM portlari
    // =========================================================================
    npu_engine_axi_tcm_slave #(
        .TCM_BASE_ADDR(32'h2001_0000),
        .TCM_WORDS    (TCM_WORDS)
    ) u_engine_axi_tcm (
        .clk            (clk),
        .rst_n          (rst_n),
        .s_axi_awaddr   (eng_axi_awaddr),
        .s_axi_awvalid  (eng_axi_awvalid),
        .s_axi_awready  (eng_axi_awready),
        .s_axi_wdata    (eng_axi_wdata),
        .s_axi_wstrb    (eng_axi_wstrb),
        .s_axi_wvalid   (eng_axi_wvalid),
        .s_axi_wready   (eng_axi_wready),
        .s_axi_bresp    (eng_axi_bresp),
        .s_axi_bvalid   (eng_axi_bvalid),
        .s_axi_bready   (eng_axi_bready),
        .s_axi_araddr   (eng_axi_araddr),
        .s_axi_arvalid  (eng_axi_arvalid),
        .s_axi_arready  (eng_axi_arready),
        .s_axi_rdata    (eng_axi_rdata),
        .s_axi_rresp    (eng_axi_rresp),
        .s_axi_rvalid   (eng_axi_rvalid),
        .s_axi_rready   (eng_axi_rready),
        .tcm_rd_en_o    (eng_tcm_rd_en),
        .tcm_rd_addr_o  (eng_tcm_rd_addr),
        .tcm_rd_data_i  (ram_rdata_b),
        .tcm_wr_req_o   (eng_wr_req),
        .tcm_wr_addr_o  (eng_wr_addr),
        .tcm_wr_data_o  (eng_wr_data),
        .tcm_wr_strb_o  (eng_wr_strb),
        .tcm_wr_grant_i (eng_wr_grant)
    );

    // =========================================================================
    // NPU Hesaplama Motoru (Compute Engine)
    // =========================================================================
    npu_compute_engine u_npu_engine (
        .clk            (clk),
        .rst_n          (rst_n),
        .start_i        (start_sig),
        .npu_reset_i    (npu_reset_sig),
        .in_addr_i      (in_offset_addr),
        .out_addr_i     (out_offset_addr),
        .busy_o         (busy_sig),
        .done_o         (done_sig),
        .class_o        (class_sig),
        .mem_req_valid_o(eng_req_valid),
        .mem_req_write_o(eng_req_write),
        .mem_req_addr_o (eng_req_addr),
        .mem_req_wdata_o(eng_req_wdata),
        .mem_req_wstrb_o(eng_req_wstrb),
        .mem_req_ready_i(eng_req_ready),
        .mem_rsp_valid_i(eng_rsp_valid),
        .mem_rsp_rdata_i(eng_rsp_rdata),
        .mem_rsp_resp_i (eng_rsp_resp)
    );

endmodule
