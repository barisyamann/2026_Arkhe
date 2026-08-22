`timescale 1ns/1ps
// =============================================================================
//  tb_dma_controller.sv - DMA blok seviyesi self-checking testbench
//  TEKNOFEST 2026 - Takim Arkhe
//
//  NEDEN YAZILDI (22 Agustos 2026)
//
//    DMA'nin HIC blok testi yoktu. Yalnizca sistem testinde dolayli
//    calisiyordu ve kapsama olcumunde %41,1 statement ile en dusuk
//    modulumuzdu.
//
//  EN ONEMLI TEST: AW / W KANAL AYRIMI
//
//    Veriyolu incelemesinde bulgu V1 su idi: DMA, AW ve W'nin AYNI
//    cevrimde kabul edilmesini sart kosuyordu. AXI4-Lite'ta bu kanallar
//    BAGIMSIZDIR; bir slave adresi N. cevrimde, veriyi N+1'de kabul
//    edebilir. Duzeltildi (aw_done_q / w_done_q bayraklari) ama
//    DOGRULANMAMISTI - sistemdeki tum slave'ler iki ready'yi birlikte
//    yukselttigi icin hata zaten gorunmuyordu.
//
//    Buradaki bellek modeli AW ve W'yi KASITLI OLARAK farkli cevrimlerde
//    kabul eder. Duzeltme olmasaydi DMA ikinci bir AW islemi baslatir ve
//    veri bozulurdu.
//
//  KAPSAM
//    - CSR yazmaclarinin geri okunmasi
//    - Bellek-bellek transferi (artan adres)
//    - SRC_FIXED / DST_FIXED kipleri (cevre birimi FIFO senaryosu)
//    - AW/W ayri cevrimde kabul  <-- V1 dogrulamasi
//    - Hata yanitinin (SLVERR) yakalanmasi
//    - Kesme cikisi ve dma_reset
// =============================================================================

module tb_dma_controller;

    localparam logic [4:0] R_CTRL   = 5'h00;
    localparam logic [4:0] R_STATUS = 5'h04;
    localparam logic [4:0] R_SRC    = 5'h08;
    localparam logic [4:0] R_DST    = 5'h0C;
    localparam logic [4:0] R_LEN    = 5'h10;

    localparam logic [31:0] CTRL_START     = 32'h1;
    localparam logic [31:0] CTRL_RESET     = 32'h2;
    localparam logic [31:0] CTRL_SRC_FIXED = 32'h4;
    localparam logic [31:0] CTRL_DST_FIXED = 32'h8;

    localparam int MEM_WORDS = 256;

    logic clk = 0;
    always #10 clk = ~clk;

    logic rst_n;

    // --- CSR (slave) ---
    logic [31:0] s_awaddr, s_wdata, s_araddr, s_rdata;
    logic [3:0]  s_wstrb;
    logic        s_awvalid, s_awready, s_wvalid, s_wready;
    logic [1:0]  s_bresp, s_rresp;
    logic        s_bvalid, s_bready, s_arvalid, s_arready, s_rvalid, s_rready;

    // --- Master (veri yolu) ---
    logic [31:0] m_awaddr, m_wdata, m_araddr, m_rdata;
    logic [3:0]  m_wstrb;
    logic        m_awvalid, m_awready, m_wvalid, m_wready;
    logic [1:0]  m_bresp, m_rresp;
    logic        m_bvalid, m_bready, m_arvalid, m_arready, m_rvalid, m_rready;

    logic irq;

    dma_controller dut (
        .clk(clk), .rst_n(rst_n),
        .s_axi_awaddr(s_awaddr), .s_axi_awvalid(s_awvalid), .s_axi_awready(s_awready),
        .s_axi_wdata(s_wdata), .s_axi_wstrb(s_wstrb),
        .s_axi_wvalid(s_wvalid), .s_axi_wready(s_wready),
        .s_axi_bresp(s_bresp), .s_axi_bvalid(s_bvalid), .s_axi_bready(s_bready),
        .s_axi_araddr(s_araddr), .s_axi_arvalid(s_arvalid), .s_axi_arready(s_arready),
        .s_axi_rdata(s_rdata), .s_axi_rresp(s_rresp),
        .s_axi_rvalid(s_rvalid), .s_axi_rready(s_rready),
        .m_axi_awaddr(m_awaddr), .m_axi_awvalid(m_awvalid), .m_axi_awready(m_awready),
        .m_axi_wdata(m_wdata), .m_axi_wstrb(m_wstrb),
        .m_axi_wvalid(m_wvalid), .m_axi_wready(m_wready),
        .m_axi_bresp(m_bresp), .m_axi_bvalid(m_bvalid), .m_axi_bready(m_bready),
        .m_axi_araddr(m_araddr), .m_axi_arvalid(m_arvalid), .m_axi_arready(m_arready),
        .m_axi_rdata(m_rdata), .m_axi_rresp(m_rresp),
        .m_axi_rvalid(m_rvalid), .m_axi_rready(m_rready),
        .irq_o(irq)
    );

    // =========================================================================
    // AXI4-Lite BELLEK MODELI (DMA'nin master portuna baglanir)
    //
    // Davranis anahtarlari:
    //   ayrik_aw_w : 1 ise AW ve W AYRI cevrimlerde kabul edilir.
    //                Bulgu V1'in dogrulanmasi icin kritik.
    //   hata_adres : bu adrese erisimde SLVERR doner (0 = kapali)
    // =========================================================================
    logic [31:0] mem [0:MEM_WORDS-1];
    bit          ayrik_aw_w  = 1'b0;
    logic [31:0] hata_adres  = 32'hFFFF_FFFF;
    // Yalnizca always_ff tarafindan surulur; test once/sonra farkini alir.
    // (Hem initial hem always_ff'ten surmek karma surucu hatasi verir.)
    int          aw_kabul_sayisi;

    // --- Yazma kanali ---
    typedef enum logic [1:0] { W_BEKLE, W_AW_ALDI, W_W_ALDI, W_YANIT } wst_t;
    wst_t wst;
    logic [31:0] w_addr_lat;
    logic [31:0] w_data_lat;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wst             <= W_BEKLE;
            aw_kabul_sayisi <= 0;
            m_awready  <= 1'b0;
            m_wready   <= 1'b0;
            m_bvalid   <= 1'b0;
            m_bresp    <= 2'b00;
            w_addr_lat <= '0;
            w_data_lat <= '0;
        end else begin
            m_awready <= 1'b0;
            m_wready  <= 1'b0;

            unique case (wst)
                W_BEKLE: begin
                    m_bvalid <= 1'b0;
                    if (ayrik_aw_w) begin
                        // ONCE yalnizca AW kabul et - W'yi bir cevrim beklet
                        if (m_awvalid) begin
                            m_awready       <= 1'b1;
                            w_addr_lat      <= m_awaddr;
                            aw_kabul_sayisi <= aw_kabul_sayisi + 1;
                            wst             <= W_AW_ALDI;
                        end
                    end else begin
                        // Sistemdeki gercek slave'ler gibi: ikisi birlikte
                        if (m_awvalid && m_wvalid) begin
                            m_awready       <= 1'b1;
                            m_wready        <= 1'b1;
                            w_addr_lat      <= m_awaddr;
                            w_data_lat      <= m_wdata;
                            aw_kabul_sayisi <= aw_kabul_sayisi + 1;
                            wst             <= W_YANIT;
                        end
                    end
                end

                W_AW_ALDI: begin
                    // Bir cevrim bekle, sonra W'yi kabul et
                    if (m_wvalid) begin
                        m_wready   <= 1'b1;
                        w_data_lat <= m_wdata;
                        wst        <= W_YANIT;
                    end
                    // Duzeltme olmasaydi burada m_awvalid HALA yuksek olur
                    // ve W_BEKLE'ye donunce ikinci bir AW sayilirdi.
                end

                W_YANIT: begin
                    if (w_addr_lat == hata_adres) begin
                        m_bresp <= 2'b10;                 // SLVERR
                    end else begin
                        m_bresp <= 2'b00;
                        if ((w_addr_lat >> 2) < MEM_WORDS)
                            mem[w_addr_lat >> 2] <= w_data_lat;
                    end
                    m_bvalid <= 1'b1;
                    if (m_bvalid && m_bready) begin
                        m_bvalid <= 1'b0;
                        wst      <= W_BEKLE;
                    end
                end

                default: wst <= W_BEKLE;
            endcase
        end
    end

    // --- Okuma kanali ---
    typedef enum logic [1:0] { R_BEKLE, R_VERI } rst_t;
    rst_t rst_st;
    logic [31:0] r_addr_lat;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rst_st    <= R_BEKLE;
            m_arready <= 1'b0;
            m_rvalid  <= 1'b0;
            m_rdata   <= '0;
            m_rresp   <= 2'b00;
        end else begin
            m_arready <= 1'b0;
            unique case (rst_st)
                R_BEKLE: begin
                    m_rvalid <= 1'b0;
                    if (m_arvalid) begin
                        m_arready  <= 1'b1;
                        r_addr_lat <= m_araddr;
                        rst_st     <= R_VERI;
                    end
                end
                R_VERI: begin
                    if (r_addr_lat == hata_adres) begin
                        m_rresp <= 2'b10;
                        m_rdata <= 32'hDEAD_DEAD;
                    end else begin
                        m_rresp <= 2'b00;
                        m_rdata <= ((r_addr_lat >> 2) < MEM_WORDS)
                                   ? mem[r_addr_lat >> 2] : 32'h0;
                    end
                    m_rvalid <= 1'b1;
                    if (m_rvalid && m_rready) begin
                        m_rvalid <= 1'b0;
                        rst_st   <= R_BEKLE;
                    end
                end
                default: rst_st <= R_BEKLE;
            endcase
        end
    end

    // =========================================================================
    // Self-checking
    // =========================================================================
    int hata = 0, denetim = 0;

    task automatic denetle(input string ad, input logic [31:0] g, input logic [31:0] b);
        denetim++;
        if (g === b) $display("      [OK]   %-38s = 0x%08h", ad, g);
        else begin
            hata++;
            $display("      [HATA] %-38s beklenen=0x%08h gercek=0x%08h", ad, b, g);
        end
    endtask

    initial begin
        #20_000_000;
        $display(" DMA TESTI BASARISIZ - zaman asimi");
        $fatal(1, "tb_dma_controller zaman asimi");
    end

    // =========================================================================
    // CSR erisim gorevleri
    // =========================================================================
    // -------------------------------------------------------------------------
    // DIKKAT - VALID SINYALLERI EL SIKISMADA GERI CEKILMELI
    //
    // dma_controller CSR arayuzu istegi bir mandalda tutuyor:
    //     if (s_axi_arvalid && !ar_valid_lat) begin ... ar_valid_lat <= 1; end
    // Mandal, rvalid kurulunca temizleniyor. Eger arvalid rvalid'e kadar
    // yuksek tutulursa, mandal temizlendigi cevrimde IKINCI bir okuma
    // baslar ve rvalid yuksek kalir. Bir sonraki csr_read o bekleyen
    // yaniti okur - yani her okuma BIR ISLEM GERIDEN gelir.
    //
    // Ilk yazimda tam olarak bu oldu: read(DST) SRC'nin degerini donduruyordu.
    // Ayni tuzak yazma kanalinda da var (aw_valid_lat / w_valid_lat).
    // Cozum: valid'i READY gorulur gorulmez geri cek.
    // -------------------------------------------------------------------------
    task automatic csr_write(input logic [4:0] adr, input logic [31:0] dat);
        @(posedge clk);
        s_awaddr <= {27'b0, adr}; s_awvalid <= 1'b1;
        s_wdata  <= dat; s_wvalid <= 1'b1; s_wstrb <= 4'hF;
        s_bready <= 1'b1;
        forever begin
            @(posedge clk);
            if (s_awready && s_wready) begin
                s_awvalid <= 1'b0; s_wvalid <= 1'b0;
                break;
            end
        end
        forever begin @(posedge clk); if (s_bvalid) break; end
        @(posedge clk);
        s_bready <= 1'b0;
        @(posedge clk);
    endtask

    task automatic csr_read(input logic [4:0] adr, output logic [31:0] dat);
        @(posedge clk);
        s_araddr <= {27'b0, adr}; s_arvalid <= 1'b1; s_rready <= 1'b1;
        forever begin
            @(posedge clk);
            if (s_arready) begin s_arvalid <= 1'b0; break; end
        end
        forever begin
            @(posedge clk);
            if (s_rvalid) begin dat = s_rdata; break; end
        end
        @(posedge clk);
        s_rready <= 1'b0;
        @(posedge clk);
    endtask

    // Transfer bitene kadar bekle (STATUS[1] = done)
    task automatic transfer_bekle(input int azami);
        logic [31:0] st;
        int n; n = 0;
        forever begin
            csr_read(R_STATUS, st);
            if (st[1]) break;
            if (n++ > azami) begin
                $display("      [HATA] transfer tamamlanmadi (zaman asimi)");
                hata++;
                break;
            end
        end
    endtask

    task automatic dma_sifirla();
        csr_write(R_CTRL, CTRL_RESET);
        repeat (3) @(posedge clk);
        csr_write(R_CTRL, 32'h0);
        repeat (3) @(posedge clk);
    endtask

    logic [31:0] v;
    int          i;
    int          aw_once;

    initial begin
        s_awvalid = 0; s_wvalid = 0; s_bready = 0; s_arvalid = 0; s_rready = 0;
        s_awaddr = 0; s_araddr = 0; s_wdata = 0; s_wstrb = 4'hF;
        rst_n = 0;

        for (i = 0; i < MEM_WORDS; i++) mem[i] = 32'h0;
        // Kaynak alan: 0x00..0x3F (16 kelime), bilinen desen
        for (i = 0; i < 16; i++) mem[i] = 32'hC0DE_0000 + i;

        repeat (5) @(posedge clk);
        rst_n = 1;
        repeat (5) @(posedge clk);

        $display("================================================================");
        $display(" DMA BLOK TESTI");
        $display("================================================================");

        // ---------------------------------------------------------------------
        $display("  -- 1. CSR yazmaclari");
        csr_read(R_CTRL,   v); denetle("reset CTRL", v, 32'h0);
        csr_read(R_STATUS, v); denetle("reset STATUS", v, 32'h0);
        denetle("reset IRQ", {31'b0, irq}, 32'h0);

        csr_write(R_SRC, 32'h1234_5678);
        csr_read(R_SRC, v); denetle("SRC geri okuma", v, 32'h1234_5678);
        csr_write(R_DST, 32'h8765_4321);
        csr_read(R_DST, v); denetle("DST geri okuma", v, 32'h8765_4321);
        csr_write(R_LEN, 32'd64);
        csr_read(R_LEN, v); denetle("LEN geri okuma", v, 32'd64);

        // ---------------------------------------------------------------------
        // 2. Bellek-bellek transferi (AW/W birlikte kabul - normal kip)
        // ---------------------------------------------------------------------
        $display("  -- 2. Bellek-bellek transferi (8 kelime)");
        ayrik_aw_w = 1'b0;
        dma_sifirla();
        csr_write(R_SRC, 32'h0000_0000);        // kelime 0
        csr_write(R_DST, 32'h0000_0100);        // kelime 64
        csr_write(R_LEN, 32'd8);
        csr_write(R_CTRL, CTRL_START);
        transfer_bekle(2000);

        csr_read(R_STATUS, v);
        denetle("transfer sonrasi DONE", {31'b0, v[1]}, 32'h1);
        denetle("transfer sonrasi ERROR yok", {31'b0, v[2]}, 32'h0);
        denetle("transfer sonrasi BUSY dustu", {31'b0, v[0]}, 32'h0);
        denetle("transfer IRQ uretti", {31'b0, irq}, 32'h1);

        for (i = 0; i < 8; i++)
            denetle($sformatf("hedef kelime %0d", i), mem[64 + i], 32'hC0DE_0000 + i);
        denetle("hedef disina tasma yok", mem[72], 32'h0);

        // ---------------------------------------------------------------------
        // 3. AW ve W AYRI CEVRIMLERDE  -  bulgu V1 dogrulamasi
        //
        // Bellek modeli once yalnizca AW kabul eder, W'yi bir cevrim
        // bekletir. Duzeltme oncesi DMA awvalid'i yuksek tutmaya devam
        // eder, slave ikinci bir AW islemi sayardi.
        // ---------------------------------------------------------------------
        $display("  -- 3. AW/W ayri cevrimde (bulgu V1)");
        ayrik_aw_w = 1'b1;
        dma_sifirla();
        for (i = 0; i < MEM_WORDS; i++) mem[i] = 32'h0;
        for (i = 0; i < 8; i++) mem[i] = 32'hBEEF_0000 + i;
        aw_once = aw_kabul_sayisi;

        csr_write(R_SRC, 32'h0000_0000);
        csr_write(R_DST, 32'h0000_0100);
        csr_write(R_LEN, 32'd8);
        csr_write(R_CTRL, CTRL_START);
        transfer_bekle(4000);

        for (i = 0; i < 8; i++)
            denetle($sformatf("ayrik kip kelime %0d", i), mem[64 + i], 32'hBEEF_0000 + i);

        // 8 kelime -> TAM 8 adres islemi olmali. Fazlasi, AW'nin ikinci kez
        // kabul edildigi anlamina gelir - eski hatanin imzasi.
        denetle("AW islem sayisi tam 8 (fazla yok)",
                aw_kabul_sayisi - aw_once, 32'd8);

        // ---------------------------------------------------------------------
        // 4. SRC_FIXED  (cevre birimi FIFO'sundan okuma senaryosu)
        // ---------------------------------------------------------------------
        $display("  -- 4. SRC_FIXED");
        ayrik_aw_w = 1'b0;
        dma_sifirla();
        for (i = 0; i < MEM_WORDS; i++) mem[i] = 32'h0;
        mem[0] = 32'hAAAA_5555;                 // tek kaynak adresi

        csr_write(R_SRC, 32'h0000_0000);
        csr_write(R_DST, 32'h0000_0100);
        csr_write(R_LEN, 32'd4);
        csr_write(R_CTRL, CTRL_START | CTRL_SRC_FIXED);
        transfer_bekle(2000);

        for (i = 0; i < 4; i++)
            denetle($sformatf("SRC_FIXED hedef %0d", i), mem[64 + i], 32'hAAAA_5555);

        // ---------------------------------------------------------------------
        // 5. DST_FIXED  (cevre birimi FIFO'suna yazma senaryosu)
        // ---------------------------------------------------------------------
        $display("  -- 5. DST_FIXED");
        dma_sifirla();
        for (i = 0; i < MEM_WORDS; i++) mem[i] = 32'h0;
        for (i = 0; i < 4; i++) mem[i] = 32'h1111_0000 + i;

        csr_write(R_SRC, 32'h0000_0000);
        csr_write(R_DST, 32'h0000_0100);
        csr_write(R_LEN, 32'd4);
        csr_write(R_CTRL, CTRL_START | CTRL_DST_FIXED);
        transfer_bekle(2000);

        // Hepsi ayni adrese yazildi -> son deger kalir
        denetle("DST_FIXED son deger", mem[64], 32'h1111_0003);
        denetle("DST_FIXED sonraki adres bos", mem[65], 32'h0);

        // ---------------------------------------------------------------------
        // 6. Hata yanitinin yakalanmasi
        // ---------------------------------------------------------------------
        $display("  -- 6. SLVERR yakalanmasi");
        dma_sifirla();
        for (i = 0; i < MEM_WORDS; i++) mem[i] = 32'h0;
        hata_adres = 32'h0000_0104;             // hedefin ikinci kelimesi

        csr_write(R_SRC, 32'h0000_0000);
        csr_write(R_DST, 32'h0000_0100);
        csr_write(R_LEN, 32'd4);
        csr_write(R_CTRL, CTRL_START);
        transfer_bekle(2000);

        csr_read(R_STATUS, v);
        denetle("hata biti kuruldu", {31'b0, v[2]}, 32'h1);
        denetle("hataya ragmen transfer bitti", {31'b0, v[1]}, 32'h1);
        hata_adres = 32'hFFFF_FFFF;

        // ---------------------------------------------------------------------
        // 7. dma_reset durumu temizler
        // ---------------------------------------------------------------------
        $display("  -- 7. CTRL[1] reset");
        csr_write(R_CTRL, CTRL_RESET);
        repeat (5) @(posedge clk);
        csr_read(R_STATUS, v);
        denetle("reset sonrasi STATUS temiz", v, 32'h0);
        denetle("reset sonrasi IRQ dustu", {31'b0, irq}, 32'h0);
        csr_write(R_CTRL, 32'h0);

        // ---------------------------------------------------------------------
        // 8. START biti donanimda kendini temizler
        // ---------------------------------------------------------------------
        $display("  -- 8. START kendini temizler");
        csr_write(R_SRC, 32'h0);
        csr_write(R_DST, 32'h0000_0100);
        csr_write(R_LEN, 32'd2);
        csr_write(R_CTRL, CTRL_START);
        transfer_bekle(2000);
        csr_read(R_CTRL, v);
        denetle("START biti otomatik temizlendi", {31'b0, v[0]}, 32'h0);

        // ---------------------------------------------------------------------
        $display("================================================================");
        if (hata != 0) begin
            $display(" DMA TESTI BASARISIZ - %0d hata / %0d denetim", hata, denetim);
            $display("================================================================");
            $fatal(1, "DMA dogrulamasi basarisiz");
        end
        $display(" DMA TESTI GECTI - %0d denetim, 0 hata", denetim);
        $display("================================================================");
        $finish;
    end

endmodule
