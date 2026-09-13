// =============================================================================
//  tb_jtag_yanit_kodu.sv
//
//  NEDEN VAR
//    12 Eylul 2026 port taramasi sunu buldu:
//
//      jtag_debug : m_axi_rresp  (sadece port tanimi - HIC OKUNMUYOR)
//      jtag_debug : m_axi_bresp  (sadece port tanimi - HIC OKUNMUYOR)
//
//    JTAG debug master interconnect uzerinden TUM slave'lere erisir.
//    Tanimsiz bir adres okunursa interconnect DECERR (2'b11) ve
//    0xDEADBEEF dondurur. Yanit kodu kontrol edilmediginde JTAG bu
//    COP VERIYI GECERLI SANIR - debug oturumunda sessiz yanlis okuma.
//
//  DUZELTME (rtl/Cevre_Birimleri/jtag_debug.sv)
//    Yanit kodu yakalanir ve iki yoldan bildirilir:
//      1. REG_DBG_STATUS[3]   = hata bayragi
//         REG_DBG_STATUS[5:4] = son AXI yanit kodu
//      2. IR_MEM_READ DR'sinin alt 32 biti
//         0x00000000 = OKAY,  ust bitler 0x39101B9 = hata imzasi
//
//  BU TEST NE DOGRULAR
//    1. OKAY yanitinda hata bayragi DUSUK kalir
//    2. SLVERR yanitinda bayrak YUKSELIR ve kod dogru yakalanir
//    3. DECERR yanitinda bayrak YUKSELIR
//    4. Yeni islem baslayinca bayrak TEMIZLENIR
//    5. Yazma yolunda (bresp) de ayni davranis
// =============================================================================
`timescale 1ns/1ps

module tb_jtag_yanit_kodu;

    localparam int AW = 32;
    localparam int DW = 32;

    logic clk = 1'b0, rst_n = 1'b0;
    always #10 clk = ~clk;

    logic jtag_tms = 1'b1, jtag_tck = 1'b0, jtag_tdi = 1'b0, jtag_trst_n = 1'b1;
    logic jtag_tdo, debug_req_o, bus_fault_irq_o;

    // AXI slave (CSR) - durum yazmacini okumak icin KULLANILIR
    logic [AW-1:0] s_awaddr = '0;  logic s_awvalid = 1'b0; logic s_awready;
    logic [DW-1:0] s_wdata = '0;   logic [3:0] s_wstrb = '0;
    logic s_wvalid = 1'b0;         logic s_wready;
    logic [1:0] s_bresp;           logic s_bvalid; logic s_bready = 1'b1;
    logic [AW-1:0] s_araddr = '0;  logic s_arvalid = 1'b0; logic s_arready;
    logic [DW-1:0] s_rdata;        logic [1:0] s_rresp; logic s_rvalid;
    logic s_rready = 1'b1;

    // AXI master (JTAG -> bellek) - YANIT KODU BURADAN ZORLANIR
    logic [AW-1:0] m_awaddr;  logic m_awvalid; logic m_awready;
    logic [DW-1:0] m_wdata;   logic [3:0] m_wstrb; logic m_wvalid; logic m_wready;
    logic [1:0] m_bresp;      logic m_bvalid;  logic m_bready;
    logic [AW-1:0] m_araddr;  logic m_arvalid; logic m_arready;
    logic [DW-1:0] m_rdata;   logic [1:0] m_rresp; logic m_rvalid; logic m_rready;

    int pass_count = 0, fail_count = 0;

    jtag_debug dut (
        .clk(clk), .rst_n(rst_n),
        .jtag_tms(jtag_tms), .jtag_tck(jtag_tck), .jtag_tdi(jtag_tdi),
        .jtag_tdo(jtag_tdo), .jtag_trst_n(jtag_trst_n),
        .debug_req_o(debug_req_o),
        .instr_bus_err_i(1'b0), .instr_bus_err_addr_i(32'h0),
        .data_bus_err_i(1'b0),  .data_bus_err_addr_i(32'h0),
        .bus_fault_irq_o(bus_fault_irq_o),
        .s_axi_awaddr(s_awaddr), .s_axi_awvalid(s_awvalid), .s_axi_awready(s_awready),
        .s_axi_wdata(s_wdata), .s_axi_wstrb(s_wstrb), .s_axi_wvalid(s_wvalid),
        .s_axi_wready(s_wready),
        .s_axi_bresp(s_bresp), .s_axi_bvalid(s_bvalid), .s_axi_bready(s_bready),
        .s_axi_araddr(s_araddr), .s_axi_arvalid(s_arvalid), .s_axi_arready(s_arready),
        .s_axi_rdata(s_rdata), .s_axi_rresp(s_rresp), .s_axi_rvalid(s_rvalid),
        .s_axi_rready(s_rready),
        .m_axi_awaddr(m_awaddr), .m_axi_awvalid(m_awvalid), .m_axi_awready(m_awready),
        .m_axi_wdata(m_wdata), .m_axi_wstrb(m_wstrb), .m_axi_wvalid(m_wvalid),
        .m_axi_wready(m_wready),
        .m_axi_bresp(m_bresp), .m_axi_bvalid(m_bvalid), .m_axi_bready(m_bready),
        .m_axi_araddr(m_araddr), .m_axi_arvalid(m_arvalid), .m_axi_arready(m_arready),
        .m_axi_rdata(m_rdata), .m_axi_rresp(m_rresp), .m_axi_rvalid(m_rvalid),
        .m_axi_rready(m_rready)
    );

    // -------------------------------------------------------------------
    //  SAHTE SLAVE - yanit kodu TEST TARAFINDAN belirlenir
    // -------------------------------------------------------------------
    logic [1:0] zorlanan_yanit = 2'b00;
    logic [31:0] zorlanan_veri = 32'hA5A5_1234;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_awready <= 1'b0; m_wready <= 1'b0;
            m_bvalid  <= 1'b0; m_bresp  <= 2'b00;
            m_arready <= 1'b0; m_rvalid <= 1'b0;
            m_rdata   <= 32'h0; m_rresp <= 2'b00;
        end else begin
            m_awready <= m_awvalid && !m_bvalid;
            m_wready  <= m_wvalid  && !m_bvalid;
            if (m_awvalid && m_awready && m_wvalid && m_wready) begin
                m_bvalid <= 1'b1;
                m_bresp  <= zorlanan_yanit;      // ZORLANAN yanit
            end
            if (m_bvalid && m_bready) m_bvalid <= 1'b0;

            m_arready <= m_arvalid && !m_rvalid;
            if (m_arvalid && m_arready) begin
                m_rvalid <= 1'b1;
                m_rdata  <= zorlanan_veri;
                m_rresp  <= zorlanan_yanit;      // ZORLANAN yanit
            end
            if (m_rvalid && m_rready) m_rvalid <= 1'b0;
        end
    end

    task automatic kontrol(input bit kosul, input string mesaj);
        if (kosul) begin pass_count++; $display("  [OK] %s", mesaj); end
        else       begin fail_count++; $display("  [HATA] %s", mesaj); end
    endtask

    // -------------------------------------------------------------------
    //  JTAG TAP surme
    // -------------------------------------------------------------------
    task automatic jtag_clock();
        jtag_tck = 1'b0; #50;
        jtag_tck = 1'b1; #50;
        jtag_tck = 1'b0;
    endtask

    task automatic jtag_reset();
        jtag_trst_n = 1'b0; #50;
        jtag_trst_n = 1'b1;
        jtag_tms = 1'b1;
        repeat (5) jtag_clock();
        jtag_tms = 1'b0;
        jtag_clock();
    endtask

    task automatic jtag_shift_ir(input logic [3:0] ir_in);
        jtag_tms = 1'b1; jtag_clock();
        jtag_tms = 1'b1; jtag_clock();
        jtag_tms = 1'b0; jtag_clock();
        jtag_tms = 1'b0; jtag_clock();
        for (int i = 0; i < 4; i++) begin
            jtag_tdi = ir_in[i];
            jtag_tms = (i == 3) ? 1'b1 : 1'b0;
            jtag_clock();
        end
        jtag_tms = 1'b1; jtag_clock();
        jtag_tms = 1'b0; jtag_clock();
    endtask

    task automatic jtag_shift_dr64(input logic [63:0] dr_in);
        jtag_tms = 1'b1; jtag_clock();
        jtag_tms = 1'b0; jtag_clock();
        jtag_tms = 1'b0; jtag_clock();
        for (int i = 0; i < 64; i++) begin
            jtag_tdi = dr_in[i];
            jtag_tms = (i == 63) ? 1'b1 : 1'b0;
            jtag_clock();
        end
        jtag_tms = 1'b1; jtag_clock();
        jtag_tms = 1'b0; jtag_clock();
    endtask

    // CSR uzerinden durum yazmacini oku
    task automatic csr_oku(input [AW-1:0] adr, output logic [DW-1:0] veri);
        int g;
        begin
            @(negedge clk); s_araddr = adr; s_arvalid = 1'b1; s_rready = 1'b1;
            @(negedge clk);
            g = 0;
            while (!s_arready && g < 40) begin @(negedge clk); g++; end
            @(negedge clk); s_arvalid = 1'b0;
            g = 0;
            while (!s_rvalid && g < 40) begin @(negedge clk); g++; end
            veri = s_rdata;
            @(negedge clk); s_rready = 1'b0;
            @(negedge clk);
        end
    endtask

    // Bir JTAG okuma islemi yap
    task automatic jtag_oku(input [31:0] adr);
        begin
            jtag_shift_ir(4'h2);            // IR_MEM_READ
            jtag_shift_dr64({32'h0, adr});
            repeat (40) @(posedge clk);
        end
    endtask

    task automatic jtag_yaz(input [31:0] adr, input [31:0] veri);
        begin
            jtag_shift_ir(4'h3);            // IR_MEM_WRITE
            jtag_shift_dr64({veri, adr});
            repeat (40) @(posedge clk);
        end
    endtask

    logic [31:0] durum;

    initial begin
        $display("================================================================");
        $display(" JTAG AXI YANIT KODU DENETIMI");
        $display("================================================================");
        $display("");
        $display("m_axi_rresp ve m_axi_bresp portlari 12 Eylul 2026'ya kadar");
        $display("HIC OKUNMUYORDU. DECERR donen bir okuma cop veriyle");
        $display("gecerli sanilirdi. Bu test duzeltmeyi dogrular.");
        $display("");

        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (5) @(posedge clk);
        jtag_reset();

        // ---------------------------------------------------------------
        //  1. OKAY: hata bayragi DUSUK kalmali
        // ---------------------------------------------------------------
        $display("1. OKAY yaniti (2'b00)");
        zorlanan_yanit = 2'b00;
        jtag_oku(32'h0000_0010);
        csr_oku(32'h04, durum);          // REG_DBG_STATUS
        $display("    STATUS = 0x%08h  (bit3=hata, bit5:4=kod)", durum);
        kontrol(durum[3] === 1'b0,
                $sformatf("OKAY'da hata bayragi dusuk (bit3=%0b)", durum[3]));
        kontrol(durum[5:4] === 2'b00,
                $sformatf("OKAY'da yanit kodu 00 (bit5:4=%02b)", durum[5:4]));

        // ---------------------------------------------------------------
        //  2. SLVERR: bayrak YUKSELMELI
        // ---------------------------------------------------------------
        $display("");
        $display("2. SLVERR yaniti (2'b10)");
        zorlanan_yanit = 2'b10;
        jtag_oku(32'h0000_0020);
        csr_oku(32'h04, durum);
        $display("    STATUS = 0x%08h", durum);
        kontrol(durum[3] === 1'b1,
                $sformatf("SLVERR'de hata bayragi YUKSELDI (bit3=%0b)", durum[3]));
        kontrol(durum[5:4] === 2'b10,
                $sformatf("SLVERR kodu dogru yakalandi (bit5:4=%02b)", durum[5:4]));

        // ---------------------------------------------------------------
        //  3. DECERR: bayrak YUKSELMELI
        //
        //  Gercek senaryo: interconnect tanimsiz adreste DECERR +
        //  0xDEADBEEF dondurur.
        // ---------------------------------------------------------------
        $display("");
        $display("3. DECERR yaniti (2'b11) - tanimsiz adres senaryosu");
        zorlanan_yanit = 2'b11;
        zorlanan_veri  = 32'hDEAD_BEEF;
        jtag_oku(32'h3000_0000);
        csr_oku(32'h04, durum);
        $display("    STATUS = 0x%08h", durum);
        kontrol(durum[3] === 1'b1,
                $sformatf("DECERR'de hata bayragi YUKSELDI (bit3=%0b)", durum[3]));
        kontrol(durum[5:4] === 2'b11,
                $sformatf("DECERR kodu dogru yakalandi (bit5:4=%02b)", durum[5:4]));

        // ---------------------------------------------------------------
        //  4. Yeni islem bayragi TEMIZLEMELI
        // ---------------------------------------------------------------
        $display("");
        $display("4. Yeni OKAY islemi bayragi temizliyor mu");
        zorlanan_yanit = 2'b00;
        zorlanan_veri  = 32'hA5A5_1234;
        jtag_oku(32'h0000_0030);
        csr_oku(32'h04, durum);
        $display("    STATUS = 0x%08h", durum);
        kontrol(durum[3] === 1'b0,
                $sformatf("yeni OKAY islemi bayragi TEMIZLEDI (bit3=%0b)", durum[3]));

        // ---------------------------------------------------------------
        //  5. YAZMA yolunda da ayni davranis (bresp)
        // ---------------------------------------------------------------
        $display("");
        $display("5. Yazma yolu (bresp)");
        zorlanan_yanit = 2'b10;          // SLVERR
        jtag_yaz(32'h0000_0040, 32'hCAFE_0001);
        csr_oku(32'h04, durum);
        $display("    STATUS = 0x%08h", durum);
        kontrol(durum[3] === 1'b1,
                $sformatf("yazmada SLVERR bayragi YUKSELDI (bit3=%0b)", durum[3]));

        zorlanan_yanit = 2'b00;
        jtag_yaz(32'h0000_0050, 32'hCAFE_0002);
        csr_oku(32'h04, durum);
        kontrol(durum[3] === 1'b0,
                $sformatf("yazmada OKAY bayragi temizledi (bit3=%0b)", durum[3]));

        $display("");
        $display("================================================================");
        if (fail_count == 0)
            $display(" TB SONUC: GECTI  (%0d denetim)", pass_count);
        else
            $display(" TB SONUC: KALDI  (%0d gecti, %0d kaldi)", pass_count, fail_count);
        $display("================================================================");
        $finish;
    end

    initial begin
        #10_000_000;
        $display("  [HATA] gozcu: test 10 ms icinde bitmedi");
        $display(" TB SONUC: KALDI (asili kaldi)");
        $finish;
    end

endmodule
