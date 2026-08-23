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

    // Motorun BASIT bellek portu (artik dogrudan TCM'ye degil, AXI
    // master'ina baglanir - bkz. u_eng_axi_master)
    logic        ram_en_b;
    logic [3:0]  ram_we_b;
    logic [12:0] ram_addr_b;
    logic [31:0] ram_wdata_b;
    logic [31:0] ram_rdata_b;      // AXI master'dan motora donen veri

    // TCM Port B'nin HAM cikisi - AXI slave'i bunu okur
    logic [31:0] ram_rdata_b_raw;

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
    logic        eng_wr_req;     // motor sonuc yazmak istiyor
    logic        tcm_en_a;
    logic [3:0]  tcm_we_a;
    logic [12:0] tcm_addr_a;
    logic [31:0] tcm_wdata_a;

    // =========================================================================
    // MOTOR <-> TCM ARASI AXI4-LITE HATTI  (23 Agustos 2026)
    //
    // Sartname s.549-554: veri bellekten AXI arayuzu uzerinden hizlandirici
    // uzerine cekilmeli, sonuc yine AXI uzerinden bellege geri yazilmalidir.
    //
    // Onceden motor TCM'ye dogrudan SRAM sinyalleriyle bagliydi. Artik
    // arada GERCEK AXI4-Lite hatlari var: dalga formunda gorulur, SVA
    // protokol denetleyicisi baglanabilir, islemler sayilabilir.
    //
    // Bekleme cevrimi yoktur (arready/awready/wready hep 1), bu yuzden
    // okuma gecikmesi senkron SRAM ile AYNI kalir - CONV boru hattina
    // yeni asama eklemek gerekmedi.
    // =========================================================================
    logic [31:0] eng_awaddr, eng_wdata_axi, eng_araddr, eng_rdata_axi;
    logic [3:0]  eng_wstrb;
    logic        eng_awvalid, eng_awready, eng_wvalid, eng_wready;
    logic [1:0]  eng_bresp,  eng_rresp;
    logic        eng_bvalid, eng_bready, eng_arvalid, eng_arready;
    logic        eng_rvalid, eng_rready;
    logic        eng_bresp_err, eng_rresp_err;

    // Slave tarafindan gelen TCM sinyalleri
    logic        axi_ram_en_b;
    logic [12:0] axi_ram_addr_b;
    logic        axi_ram_wr_req;
    logic [3:0]  axi_ram_we_a;
    logic [12:0] axi_ram_addr_a;
    logic [31:0] axi_ram_wdata_a;

    npu_engine_axi_master #(
        .ADDR_W (13)
    ) u_eng_axi_master (
        .clk           (clk),
        .rst_n         (rst_n),
        .eng_en        (ram_en_b),
        .eng_we        (ram_we_b),
        .eng_addr      (ram_addr_b),
        .eng_wdata     (ram_wdata_b),
        .eng_rdata     (ram_rdata_b),
        .m_axi_awaddr  (eng_awaddr),
        .m_axi_awvalid (eng_awvalid),
        .m_axi_awready (eng_awready),
        .m_axi_wdata   (eng_wdata_axi),
        .m_axi_wstrb   (eng_wstrb),
        .m_axi_wvalid  (eng_wvalid),
        .m_axi_wready  (eng_wready),
        .m_axi_bresp   (eng_bresp),
        .m_axi_bvalid  (eng_bvalid),
        .m_axi_bready  (eng_bready),
        .m_axi_araddr  (eng_araddr),
        .m_axi_arvalid (eng_arvalid),
        .m_axi_arready (eng_arready),
        .m_axi_rdata   (eng_rdata_axi),
        .m_axi_rresp   (eng_rresp),
        .m_axi_rvalid  (eng_rvalid),
        .m_axi_rready  (eng_rready),
        .bresp_err_o   (eng_bresp_err),
        .rresp_err_o   (eng_rresp_err)
    );

    npu_tcm_axi_slave #(
        .TCM_WORDS (TCM_WORDS),
        .ADDR_W    (13)
    ) u_eng_axi_slave (
        .clk           (clk),
        .rst_n         (rst_n),
        .s_axi_awaddr  (eng_awaddr),
        .s_axi_awvalid (eng_awvalid),
        .s_axi_awready (eng_awready),
        .s_axi_wdata   (eng_wdata_axi),
        .s_axi_wstrb   (eng_wstrb),
        .s_axi_wvalid  (eng_wvalid),
        .s_axi_wready  (eng_wready),
        .s_axi_bresp   (eng_bresp),
        .s_axi_bvalid  (eng_bvalid),
        .s_axi_bready  (eng_bready),
        .s_axi_araddr  (eng_araddr),
        .s_axi_arvalid (eng_arvalid),
        .s_axi_arready (eng_arready),
        .s_axi_rdata   (eng_rdata_axi),
        .s_axi_rresp   (eng_rresp),
        .s_axi_rvalid  (eng_rvalid),
        .s_axi_rready  (eng_rready),
        .ram_en_b      (axi_ram_en_b),
        .ram_addr_b    (axi_ram_addr_b),
        .ram_rdata_b   (ram_rdata_b_raw),
        .ram_wr_req    (axi_ram_wr_req),
        .ram_we_a      (axi_ram_we_a),
        .ram_addr_a    (axi_ram_addr_a),
        .ram_wdata_a   (axi_ram_wdata_a)
    );

    // Yazma istegi artik AXI slave'inden geliyor
    assign eng_wr_req = axi_ram_wr_req;

    assign tcm_en_a    = eng_wr_req ? 1'b1            : ram_en_a;
    assign tcm_we_a    = eng_wr_req ? axi_ram_we_a    : ram_we_a;
    assign tcm_addr_a  = eng_wr_req ? axi_ram_addr_a  : ram_addr_a;
    assign tcm_wdata_a = eng_wr_req ? axi_ram_wdata_a : ram_wdata_a;


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

        // Port B - SALT OKUNUR
        // Artik motora DEGIL, AXI slave'ine bagli (u_eng_axi_slave).
        .en_b           (axi_ram_en_b),
        .addr_b         (axi_ram_addr_b),
        .rdata_b        (ram_rdata_b_raw)
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
