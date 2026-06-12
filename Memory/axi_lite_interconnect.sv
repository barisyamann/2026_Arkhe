`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: Arkhe RTL Team
// Engineer: Antigravity AI
// 
// Create Date: 26.04.2026
// Update Date: 11.06.2026
// Design Name: axi_lite_interconnect
// Module Name: axi_lite_interconnect
// Description: Expanded AXI4-Lite Interconnect (1 Master to 13 Slaves).
//              Routes Write Address, Write Data, Write Response, Read Address,
//              and Read Data channels. Includes default error responder.
// 
//////////////////////////////////////////////////////////////////////////////////

module axi_lite_interconnect (
    input  logic        clk,
    input  logic        rst_n,

    // =========================================================
    // MASTER PORT (From CPU/Bridge)
    // =========================================================
    input  logic [31:0] m_awaddr,
    input  logic        m_awvalid,
    output logic        m_awready,
    input  logic [31:0] m_wdata,
    input  logic [3:0]  m_wstrb,
    input  logic        m_wvalid,
    output logic        m_wready,
    output logic [1:0]  m_bresp,
    output logic        m_bvalid,
    input  logic        m_bready,
    input  logic [31:0] m_araddr,
    input  logic        m_arvalid,
    output logic        m_arready,
    output logic [31:0] m_rdata,
    output logic [1:0]  m_rresp,
    output logic        m_rvalid,
    input  logic        m_rready,

    // =========================================================
    // SLAVE 0: Boot ROM (0x0000_0000 - 0x0000_03FF)
    // =========================================================
    output logic [31:0] s0_awaddr,
    output logic        s0_awvalid,
    input  logic        s0_awready,
    output logic [31:0] s0_wdata,
    output logic [3:0]  s0_wstrb,
    output logic        s0_wvalid,
    input  logic        s0_wready,
    input  logic [1:0]  s0_bresp,
    input  logic        s0_bvalid,
    output logic        s0_bready,
    output logic [31:0] s0_araddr,
    output logic        s0_arvalid,
    input  logic        s0_arready,
    input  logic [31:0] s0_rdata,
    input  logic [1:0]  s0_rresp,
    input  logic        s0_rvalid,
    output logic        s0_rready,

    // =========================================================
    // SLAVE 1: Instruction RAM (0x0100_0000 - 0x0100_1FFF)
    // =========================================================
    output logic [31:0] s1_awaddr,
    output logic        s1_awvalid,
    input  logic        s1_awready,
    output logic [31:0] s1_wdata,
    output logic [3:0]  s1_wstrb,
    output logic        s1_wvalid,
    input  logic        s1_wready,
    input  logic [1:0]  s1_bresp,
    input  logic        s1_bvalid,
    output logic        s1_bready,
    output logic [31:0] s1_araddr,
    output logic        s1_arvalid,
    input  logic        s1_arready,
    input  logic [31:0] s1_rdata,
    input  logic [1:0]  s1_rresp,
    input  logic        s1_rvalid,
    output logic        s1_rready,

    // =========================================================
    // SLAVE 2: Data RAM (0x2000_0000 - 0x2000_1FFF)
    // =========================================================
    output logic [31:0] s2_awaddr,
    output logic        s2_awvalid,
    input  logic        s2_awready,
    output logic [31:0] s2_wdata,
    output logic [3:0]  s2_wstrb,
    output logic        s2_wvalid,
    input  logic        s2_wready,
    input  logic [1:0]  s2_bresp,
    input  logic        s2_bvalid,
    output logic        s2_bready,
    output logic [31:0] s2_araddr,
    output logic        s2_arvalid,
    input  logic        s2_arready,
    input  logic [31:0] s2_rdata,
    input  logic [1:0]  s2_rresp,
    input  logic        s2_rvalid,
    output logic        s2_rready,

    // =========================================================
    // SLAVE 3: GPIO (0x4000_0000 - 0x4000_0FFF)
    // =========================================================
    output logic [31:0] s3_awaddr,
    output logic        s3_awvalid,
    input  logic        s3_awready,
    output logic [31:0] s3_wdata,
    output logic [3:0]  s3_wstrb,
    output logic        s3_wvalid,
    input  logic        s3_wready,
    input  logic [1:0]  s3_bresp,
    input  logic        s3_bvalid,
    output logic        s3_bready,
    output logic [31:0] s3_araddr,
    output logic        s3_arvalid,
    input  logic        s3_arready,
    input  logic [31:0] s3_rdata,
    input  logic [1:0]  s3_rresp,
    input  logic        s3_rvalid,
    output logic        s3_rready,

    // =========================================================
    // SLAVE 4: Timer (0x4001_0000 - 0x4001_0FFF)
    // =========================================================
    output logic [31:0] s4_awaddr,
    output logic        s4_awvalid,
    input  logic        s4_awready,
    output logic [31:0] s4_wdata,
    output logic [3:0]  s4_wstrb,
    output logic        s4_wvalid,
    input  logic        s4_wready,
    input  logic [1:0]  s4_bresp,
    input  logic        s4_bvalid,
    output logic        s4_bready,
    output logic [31:0] s4_araddr,
    output logic        s4_arvalid,
    input  logic        s4_arready,
    input  logic [31:0] s4_rdata,
    input  logic [1:0]  s4_rresp,
    input  logic        s4_rvalid,
    output logic        s4_rready,

    // =========================================================
    // SLAVE 5: UART General / UART1 (0x4002_0000 - 0x4002_0FFF)
    // =========================================================
    output logic [31:0] s5_awaddr,
    output logic        s5_awvalid,
    input  logic        s5_awready,
    output logic [31:0] s5_wdata,
    output logic [3:0]  s5_wstrb,
    output logic        s5_wvalid,
    input  logic        s5_wready,
    input  logic [1:0]  s5_bresp,
    input  logic        s5_bvalid,
    output logic        s5_bready,
    output logic [31:0] s5_araddr,
    output logic        s5_arvalid,
    input  logic        s5_arready,
    input  logic [31:0] s5_rdata,
    input  logic [1:0]  s5_rresp,
    input  logic        s5_rvalid,
    output logic        s5_rready,

    // =========================================================
    // SLAVE 6: UART Stream / UART2 (0x4003_0000 - 0x4003_0FFF)
    // =========================================================
    output logic [31:0] s6_awaddr,
    output logic        s6_awvalid,
    input  logic        s6_awready,
    output logic [31:0] s6_wdata,
    output logic [3:0]  s6_wstrb,
    output logic        s6_wvalid,
    input  logic        s6_wready,
    input  logic [1:0]  s6_bresp,
    input  logic        s6_bvalid,
    output logic        s6_bready,
    output logic [31:0] s6_araddr,
    output logic        s6_arvalid,
    input  logic        s6_arready,
    input  logic [31:0] s6_rdata,
    input  logic [1:0]  s6_rresp,
    input  logic        s6_rvalid,
    output logic        s6_rready,

    // =========================================================
    // SLAVE 7: I2C Master (0x4004_0000 - 0x4004_0FFF)
    // =========================================================
    output logic [31:0] s7_awaddr,
    output logic        s7_awvalid,
    input  logic        s7_awready,
    output logic [31:0] s7_wdata,
    output logic [3:0]  s7_wstrb,
    output logic        s7_wvalid,
    input  logic        s7_wready,
    input  logic [1:0]  s7_bresp,
    input  logic        s7_bvalid,
    output logic        s7_bready,
    output logic [31:0] s7_araddr,
    output logic        s7_arvalid,
    input  logic        s7_arready,
    input  logic [31:0] s7_rdata,
    input  logic [1:0]  s7_rresp,
    input  logic        s7_rvalid,
    output logic        s7_rready,

    // =========================================================
    // SLAVE 8: QSPI Master (0x4005_0000 - 0x4005_0FFF)
    // =========================================================
    output logic [31:0] s8_awaddr,
    output logic        s8_awvalid,
    input  logic        s8_awready,
    output logic [31:0] s8_wdata,
    output logic [3:0]  s8_wstrb,
    output logic        s8_wvalid,
    input  logic        s8_wready,
    input  logic [1:0]  s8_bresp,
    input  logic        s8_bvalid,
    output logic        s8_bready,
    output logic [31:0] s8_araddr,
    output logic        s8_arvalid,
    input  logic        s8_arready,
    input  logic [31:0] s8_rdata,
    input  logic [1:0]  s8_rresp,
    input  logic        s8_rvalid,
    output logic        s8_rready,

    // =========================================================
    // SLAVE 9: YZ Kontrol CSR / NPU CSR (0x4006_0000 - 0x4006_0FFF)
    // =========================================================
    output logic [31:0] s9_awaddr,
    output logic        s9_awvalid,
    input  logic        s9_awready,
    output logic [31:0] s9_wdata,
    output logic [3:0]  s9_wstrb,
    output logic        s9_wvalid,
    input  logic        s9_wready,
    input  logic [1:0]  s9_bresp,
    input  logic        s9_bvalid,
    output logic        s9_bready,
    output logic [31:0] s9_araddr,
    output logic        s9_arvalid,
    input  logic        s9_arready,
    input  logic [31:0] s9_rdata,
    input  logic [1:0]  s9_rresp,
    input  logic        s9_rvalid,
    output logic        s9_rready,

    // =========================================================
    // SLAVE 10: YZ Belleği / NPU Memory (0x2001_0000 - 0x2001_77FF -> 30 kB)
    // =========================================================
    output logic [31:0] s10_awaddr,
    output logic        s10_awvalid,
    input  logic        s10_awready,
    output logic [31:0] s10_wdata,
    output logic [3:0]  s10_wstrb,
    output logic        s10_wvalid,
    input  logic        s10_wready,
    input  logic [1:0]  s10_bresp,
    input  logic        s10_bvalid,
    output logic        s10_bready,
    output logic [31:0] s10_araddr,
    output logic        s10_arvalid,
    input  logic        s10_arready,
    input  logic [31:0] s10_rdata,
    input  logic [1:0]  s10_rresp,
    input  logic        s10_rvalid,
    output logic        s10_rready,

    // =========================================================
    // SLAVE 11: DMA CSR (0x4007_0000 - 0x4007_0FFF)
    // =========================================================
    output logic [31:0] s11_awaddr,
    output logic        s11_awvalid,
    input  logic        s11_awready,
    output logic [31:0] s11_wdata,
    output logic [3:0]  s11_wstrb,
    output logic        s11_wvalid,
    input  logic        s11_wready,
    input  logic [1:0]  s11_bresp,
    input  logic        s11_bvalid,
    output logic        s11_bready,
    output logic [31:0] s11_araddr,
    output logic        s11_arvalid,
    input  logic        s11_arready,
    input  logic [31:0] s11_rdata,
    input  logic [1:0]  s11_rresp,
    input  logic        s11_rvalid,
    output logic        s11_rready,

    // =========================================================
    // SLAVE 12: JTAG CSR (0x4008_0000 - 0x4008_0FFF)
    // =========================================================
    output logic [31:0] s12_awaddr,
    output logic        s12_awvalid,
    input  logic        s12_awready,
    output logic [31:0] s12_wdata,
    output logic [3:0]  s12_wstrb,
    output logic        s12_wvalid,
    input  logic        s12_wready,
    input  logic [1:0]  s12_bresp,
    input  logic        s12_bvalid,
    output logic        s12_bready,
    output logic [31:0] s12_araddr,
    output logic        s12_arvalid,
    input  logic        s12_arready,
    input  logic [31:0] s12_rdata,
    input  logic [1:0]  s12_rresp,
    input  logic        s12_rvalid,
    output logic        s12_rready
);

    // Slave ID çözme fonksiyonu
    function automatic int get_slave_id(input logic [31:0] addr);
        if (addr >= 32'h0000_0000 && addr <= 32'h0000_03FF) return 0;  // Boot ROM
        if (addr >= 32'h0100_0000 && addr <= 32'h0100_1FFF) return 1;  // Instruction RAM
        if (addr >= 32'h2000_0000 && addr <= 32'h2000_1FFF) return 2;  // Data RAM
        if (addr >= 32'h4000_0000 && addr <= 32'h4000_0FFF) return 3;  // GPIO
        if (addr >= 32'h4001_0000 && addr <= 32'h4001_0FFF) return 4;  // Timer
        if (addr >= 32'h4002_0000 && addr <= 32'h4002_0FFF) return 5;  // UART General
        if (addr >= 32'h4003_0000 && addr <= 32'h4003_0FFF) return 6;  // UART Stream
        if (addr >= 32'h4004_0000 && addr <= 32'h4004_0FFF) return 7;  // I2C Master
        if (addr >= 32'h4005_0000 && addr <= 32'h4005_0FFF) return 8;  // QSPI Master
        if (addr >= 32'h4006_0000 && addr <= 32'h4006_0FFF) return 9;  // NPU CSR
        if (addr >= 32'h2001_0000 && addr <= 32'h2001_77FF) return 10; // NPU Memory (30 kB)
        if (addr >= 32'h4007_0000 && addr <= 32'h4007_0FFF) return 11; // DMA CSR
        if (addr >= 32'h4008_0000 && addr <= 32'h4008_0FFF) return 12; // JTAG CSR
        return 13; // Hatalı Adres (Default Slave)
    endfunction

    // Seçilen Slave Yazmaçları (Outstanding istekleri takip etmek için)
    logic [3:0] write_sel_q, write_sel_d;
    logic [3:0] read_sel_q, read_sel_d;
    // NOT: 4-bit yeterli çünkü 0..13 aralığında (13 = default slave)

    // Default Slave Hata Sinyalleri
    logic        err_awready, err_wready;
    logic        err_bvalid;
    logic        err_arready;
    logic        err_rvalid;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            write_sel_q <= 4'd13;
            read_sel_q  <= 4'd13;
        end else begin
            write_sel_q <= write_sel_d;
            read_sel_q  <= read_sel_d;
        end
    end

    // =========================================================
    // YAZMA KANALI YÖNLENDİRME (AW, W, B)
    // =========================================================
    always_comb begin
        write_sel_d = write_sel_q;

        // Varsayılan bağlantılar
        m_awready  = 1'b0;
        m_wready   = 1'b0;
        m_bresp    = 2'b00;
        m_bvalid   = 1'b0;

        s0_awaddr  = m_awaddr; s0_awvalid = 1'b0; s0_wdata = m_wdata; s0_wstrb = m_wstrb; s0_wvalid = 1'b0; s0_bready = 1'b0;
        s1_awaddr  = m_awaddr; s1_awvalid = 1'b0; s1_wdata = m_wdata; s1_wstrb = m_wstrb; s1_wvalid = 1'b0; s1_bready = 1'b0;
        s2_awaddr  = m_awaddr; s2_awvalid = 1'b0; s2_wdata = m_wdata; s2_wstrb = m_wstrb; s2_wvalid = 1'b0; s2_bready = 1'b0;
        s3_awaddr  = m_awaddr; s3_awvalid = 1'b0; s3_wdata = m_wdata; s3_wstrb = m_wstrb; s3_wvalid = 1'b0; s3_bready = 1'b0;
        s4_awaddr  = m_awaddr; s4_awvalid = 1'b0; s4_wdata = m_wdata; s4_wstrb = m_wstrb; s4_wvalid = 1'b0; s4_bready = 1'b0;
        s5_awaddr  = m_awaddr; s5_awvalid = 1'b0; s5_wdata = m_wdata; s5_wstrb = m_wstrb; s5_wvalid = 1'b0; s5_bready = 1'b0;
        s6_awaddr  = m_awaddr; s6_awvalid = 1'b0; s6_wdata = m_wdata; s6_wstrb = m_wstrb; s6_wvalid = 1'b0; s6_bready = 1'b0;
        s7_awaddr  = m_awaddr; s7_awvalid = 1'b0; s7_wdata = m_wdata; s7_wstrb = m_wstrb; s7_wvalid = 1'b0; s7_bready = 1'b0;
        s8_awaddr  = m_awaddr; s8_awvalid = 1'b0; s8_wdata = m_wdata; s8_wstrb = m_wstrb; s8_wvalid = 1'b0; s8_bready = 1'b0;
        s9_awaddr  = m_awaddr; s9_awvalid = 1'b0; s9_wdata = m_wdata; s9_wstrb = m_wstrb; s9_wvalid = 1'b0; s9_bready = 1'b0;
        s10_awaddr = m_awaddr; s10_awvalid = 1'b0; s10_wdata = m_wdata; s10_wstrb = m_wstrb; s10_wvalid = 1'b0; s10_bready = 1'b0;
        s11_awaddr = m_awaddr; s11_awvalid = 1'b0; s11_wdata = m_wdata; s11_wstrb = m_wstrb; s11_wvalid = 1'b0; s11_bready = 1'b0;
        s12_awaddr = m_awaddr; s12_awvalid = 1'b0; s12_wdata = m_wdata; s12_wstrb = m_wstrb; s12_wvalid = 1'b0; s12_bready = 1'b0;

        if (write_sel_q == 4'd13) begin
            // İstek geldiğinde slave adresini çözüyoruz
            if (m_awvalid) begin
                write_sel_d = get_slave_id(m_awaddr);
            end
        end

        case (write_sel_q)
            4'd0: begin
                s0_awvalid = m_awvalid; s0_wvalid = m_wvalid; s0_bready = m_bready;
                m_awready  = s0_awready; m_wready = s0_wready; m_bresp = s0_bresp; m_bvalid = s0_bvalid;
                if (m_bvalid && m_bready) write_sel_d = 4'd13;
            end
            4'd1: begin
                s1_awvalid = m_awvalid; s1_wvalid = m_wvalid; s1_bready = m_bready;
                m_awready  = s1_awready; m_wready = s1_wready; m_bresp = s1_bresp; m_bvalid = s1_bvalid;
                if (m_bvalid && m_bready) write_sel_d = 4'd13;
            end
            4'd2: begin
                s2_awvalid = m_awvalid; s2_wvalid = m_wvalid; s2_bready = m_bready;
                m_awready  = s2_awready; m_wready = s2_wready; m_bresp = s2_bresp; m_bvalid = s2_bvalid;
                if (m_bvalid && m_bready) write_sel_d = 4'd13;
            end
            4'd3: begin
                s3_awvalid = m_awvalid; s3_wvalid = m_wvalid; s3_bready = m_bready;
                m_awready  = s3_awready; m_wready = s3_wready; m_bresp = s3_bresp; m_bvalid = s3_bvalid;
                if (m_bvalid && m_bready) write_sel_d = 4'd13;
            end
            4'd4: begin
                s4_awvalid = m_awvalid; s4_wvalid = m_wvalid; s4_bready = m_bready;
                m_awready  = s4_awready; m_wready = s4_wready; m_bresp = s4_bresp; m_bvalid = s4_bvalid;
                if (m_bvalid && m_bready) write_sel_d = 4'd13;
            end
            4'd5: begin
                s5_awvalid = m_awvalid; s5_wvalid = m_wvalid; s5_bready = m_bready;
                m_awready  = s5_awready; m_wready = s5_wready; m_bresp = s5_bresp; m_bvalid = s5_bvalid;
                if (m_bvalid && m_bready) write_sel_d = 4'd13;
            end
            4'd6: begin
                s6_awvalid = m_awvalid; s6_wvalid = m_wvalid; s6_bready = m_bready;
                m_awready  = s6_awready; m_wready = s6_wready; m_bresp = s6_bresp; m_bvalid = s6_bvalid;
                if (m_bvalid && m_bready) write_sel_d = 4'd13;
            end
            4'd7: begin
                s7_awvalid = m_awvalid; s7_wvalid = m_wvalid; s7_bready = m_bready;
                m_awready  = s7_awready; m_wready = s7_wready; m_bresp = s7_bresp; m_bvalid = s7_bvalid;
                if (m_bvalid && m_bready) write_sel_d = 4'd13;
            end
            4'd8: begin
                s8_awvalid = m_awvalid; s8_wvalid = m_wvalid; s8_bready = m_bready;
                m_awready  = s8_awready; m_wready = s8_wready; m_bresp = s8_bresp; m_bvalid = s8_bvalid;
                if (m_bvalid && m_bready) write_sel_d = 4'd13;
            end
            4'd9: begin
                s9_awvalid = m_awvalid; s9_wvalid = m_wvalid; s9_bready = m_bready;
                m_awready  = s9_awready; m_wready = s9_wready; m_bresp = s9_bresp; m_bvalid = s9_bvalid;
                if (m_bvalid && m_bready) write_sel_d = 4'd13;
            end
            4'd10: begin
                s10_awvalid = m_awvalid; s10_wvalid = m_wvalid; s10_bready = m_bready;
                m_awready  = s10_awready; m_wready = s10_wready; m_bresp = s10_bresp; m_bvalid = s10_bvalid;
                if (m_bvalid && m_bready) write_sel_d = 4'd13;
            end
            4'd11: begin
                s11_awvalid = m_awvalid; s11_wvalid = m_wvalid; s11_bready = m_bready;
                m_awready  = s11_awready; m_wready = s11_wready; m_bresp = s11_bresp; m_bvalid = s11_bvalid;
                if (m_bvalid && m_bready) write_sel_d = 4'd13;
            end
            4'd12: begin
                s12_awvalid = m_awvalid; s12_wvalid = m_wvalid; s12_bready = m_bready;
                m_awready  = s12_awready; m_wready = s12_wready; m_bresp = s12_bresp; m_bvalid = s12_bvalid;
                if (m_bvalid && m_bready) write_sel_d = 4'd13;
            end
            default: begin // Hatalı adres yönlendirmesi (Default Slave)
                m_awready = err_awready;
                m_wready  = err_wready;
                m_bresp   = 2'b10; // SLVERR
                m_bvalid  = err_bvalid;
                if (m_bvalid && m_bready) write_sel_d = 4'd13;
            end
        endcase
    end

    // Default Slave Yazma Yanıt Üreteci
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            err_awready <= 1'b0;
            err_wready  <= 1'b0;
            err_bvalid  <= 1'b0;
        end else begin
            if (write_sel_q == 4'd13 && m_awvalid && get_slave_id(m_awaddr) == 13) begin
                err_awready <= 1'b1;
                err_wready  <= 1'b1;
            end else begin
                err_awready <= 1'b0;
                err_wready  <= 1'b0;
            end

            if (err_awready && m_awvalid && err_wready && m_wvalid) begin
                err_bvalid <= 1'b1;
            end

            if (err_bvalid && m_bready) begin
                err_bvalid <= 1'b0;
            end
        end
    end

    // =========================================================
    // OKUMA KANALI YÖNLENDİRME (AR, R)
    // =========================================================
    always_comb begin
        read_sel_d = read_sel_q;

        // Varsayılan bağlantılar
        m_arready  = 1'b0;
        m_rdata    = 32'h0;
        m_rresp    = 2'b00;
        m_rvalid   = 1'b0;

        s0_araddr  = m_araddr; s0_arvalid = 1'b0; s0_rready = 1'b0;
        s1_araddr  = m_araddr; s1_arvalid = 1'b0; s1_rready = 1'b0;
        s2_araddr  = m_araddr; s2_arvalid = 1'b0; s2_rready = 1'b0;
        s3_araddr  = m_araddr; s3_arvalid = 1'b0; s3_rready = 1'b0;
        s4_araddr  = m_araddr; s4_arvalid = 1'b0; s4_rready = 1'b0;
        s5_araddr  = m_araddr; s5_arvalid = 1'b0; s5_rready = 1'b0;
        s6_araddr  = m_araddr; s6_arvalid = 1'b0; s6_rready = 1'b0;
        s7_araddr  = m_araddr; s7_arvalid = 1'b0; s7_rready = 1'b0;
        s8_araddr  = m_araddr; s8_arvalid = 1'b0; s8_rready = 1'b0;
        s9_araddr  = m_araddr; s9_arvalid = 1'b0; s9_rready = 1'b0;
        s10_araddr = m_araddr; s10_arvalid = 1'b0; s10_rready = 1'b0;
        s11_araddr = m_araddr; s11_arvalid = 1'b0; s11_rready = 1'b0;
        s12_araddr = m_araddr; s12_arvalid = 1'b0; s12_rready = 1'b0;

        if (read_sel_q == 4'd13) begin
            if (m_arvalid) begin
                read_sel_d = get_slave_id(m_araddr);
            end
        end

        case (read_sel_q)
            4'd0: begin
                s0_arvalid = m_arvalid; s0_rready = m_rready;
                m_arready  = s0_arready; m_rdata = s0_rdata; m_rresp = s0_rresp; m_rvalid = s0_rvalid;
                if (m_rvalid && m_rready) read_sel_d = 4'd13;
            end
            4'd1: begin
                s1_arvalid = m_arvalid; s1_rready = m_rready;
                m_arready  = s1_arready; m_rdata = s1_rdata; m_rresp = s1_rresp; m_rvalid = s1_rvalid;
                if (m_rvalid && m_rready) read_sel_d = 4'd13;
            end
            4'd2: begin
                s2_arvalid = m_arvalid; s2_rready = m_rready;
                m_arready  = s2_arready; m_rdata = s2_rdata; m_rresp = s2_rresp; m_rvalid = s2_rvalid;
                if (m_rvalid && m_rready) read_sel_d = 4'd13;
            end
            4'd3: begin
                s3_arvalid = m_arvalid; s3_rready = m_rready;
                m_arready  = s3_arready; m_rdata = s3_rdata; m_rresp = s3_rresp; m_rvalid = s3_rvalid;
                if (m_rvalid && m_rready) read_sel_d = 4'd13;
            end
            4'd4: begin
                s4_arvalid = m_arvalid; s4_rready = m_rready;
                m_arready  = s4_arready; m_rdata = s4_rdata; m_rresp = s4_rresp; m_rvalid = s4_rvalid;
                if (m_rvalid && m_rready) read_sel_d = 4'd13;
            end
            4'd5: begin
                s5_arvalid = m_arvalid; s5_rready = m_rready;
                m_arready  = s5_arready; m_rdata = s5_rdata; m_rresp = s5_rresp; m_rvalid = s5_rvalid;
                if (m_rvalid && m_rready) read_sel_d = 4'd13;
            end
            4'd6: begin
                s6_arvalid = m_arvalid; s6_rready = m_rready;
                m_arready  = s6_arready; m_rdata = s6_rdata; m_rresp = s6_rresp; m_rvalid = s6_rvalid;
                if (m_rvalid && m_rready) read_sel_d = 4'd13;
            end
            4'd7: begin
                s7_arvalid = m_arvalid; s7_rready = m_rready;
                m_arready  = s7_arready; m_rdata = s7_rdata; m_rresp = s7_rresp; m_rvalid = s7_rvalid;
                if (m_rvalid && m_rready) read_sel_d = 4'd13;
            end
            4'd8: begin
                s8_arvalid = m_arvalid; s8_rready = m_rready;
                m_arready  = s8_arready; m_rdata = s8_rdata; m_rresp = s8_rresp; m_rvalid = s8_rvalid;
                if (m_rvalid && m_rready) read_sel_d = 4'd13;
            end
            4'd9: begin
                s9_arvalid = m_arvalid; s9_rready = m_rready;
                m_arready  = s9_arready; m_rdata = s9_rdata; m_rresp = s9_rresp; m_rvalid = s9_rvalid;
                if (m_rvalid && m_rready) read_sel_d = 4'd13;
            end
            4'd10: begin
                s10_arvalid = m_arvalid; s10_rready = m_rready;
                m_arready  = s10_arready; m_rdata = s10_rdata; m_rresp = s10_rresp; m_rvalid = s10_rvalid;
                if (m_rvalid && m_rready) read_sel_d = 4'd13;
            end
            4'd11: begin
                s11_arvalid = m_arvalid; s11_rready = m_rready;
                m_arready  = s11_arready; m_rdata = s11_rdata; m_rresp = s11_rresp; m_rvalid = s11_rvalid;
                if (m_rvalid && m_rready) read_sel_d = 4'd13;
            end
            4'd12: begin
                s12_arvalid = m_arvalid; s12_rready = m_rready;
                m_arready  = s12_arready; m_rdata = s12_rdata; m_rresp = s12_rresp; m_rvalid = s12_rvalid;
                if (m_rvalid && m_rready) read_sel_d = 4'd13;
            end
            default: begin // Hatalı adres (Default Slave)
                m_arready = err_arready;
                m_rdata   = 32'hDEADBEEF;
                m_rresp   = 2'b10; // SLVERR
                m_rvalid  = err_rvalid;
                if (m_rvalid && m_rready) read_sel_d = 4'd13;
            end
        endcase
    end

    // Default Slave Okuma Yanıt Üreteci
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            err_arready <= 1'b0;
            err_rvalid  <= 1'b0;
        end else begin
            if (read_sel_q == 4'd13 && m_arvalid && get_slave_id(m_araddr) == 13) begin
                err_arready <= 1'b1;
            end else begin
                err_arready <= 1'b0;
            end

            if (err_arready && m_arvalid) begin
                err_rvalid <= 1'b1;
            end

            if (err_rvalid && m_rready) begin
                err_rvalid <= 1'b0;
            end
        end
    end

endmodule