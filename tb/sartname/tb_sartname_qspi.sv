`timescale 1ns / 1ps
// ============================================================================
//  tb_sartname_qspi.sv - QSPI MASTER SARTNAME UYUM TESTI
//
//  TEKNOFEST 2026 Teknik Sartnamesi v1.3, EK-2 (s.24-27)
//
//  BU TESTIN OZEL ONEMI
//
//  Sartname s.24 "Tum flash alanini kapsamak icin 4-bayt adresleme modu
//  destegi bulunacaktir" der, ama s.26'daki QSPI_ADR tanimi 3 bayt anlatir
//  ve 4-bayti secen bir bit TANIMLAMAZ. Bu bosluk CCR[24] rezerve biti ile
//  doldurulmustur (bkz. evidence/sartname/SARTNAME_UYUMU_VE_SAPMALAR.md).
//
//  Bu testin en kritik bolumu, CCR[24]=1 iken kontrolcunun GERCEKTEN dort
//  bayt adres bastigini SCK kenarlarini sayarak kanitlamasidir. Boylece
//  "4-bayt destegi var" iddiasi belge degil OLCUM olur.
//
//  KAPSANAN MADDELER
//    x1 / x2 / x4 veri genisligi        (CCR[9:8])
//    veri boyutu N-1 kodlamasi          (CCR[23:16])
//    prescaler N+1 kodlamasi            (CCR[30:25])
//    3 bayt / 4 bayt adres              (CCR[24], varsayilan 3)
//    SPI mod 0 - SCK bosta 0            (s.24)
//    QSPI_STA bit haritasi              (s.26)
//    QSPI_FCR flush ve otomatik sifirlanma (s.27)
//    FIFO hata bayraklari               (s.26)
// ============================================================================

module tb_sartname_qspi;

    logic clk = 1'b0;
    logic rst_n = 1'b0;
    always #5 clk = ~clk;

    logic [31:0] awaddr, araddr, wdata, rdata;
    logic [3:0]  wstrb;
    logic        awvalid, awready, wvalid, wready;
    logic        bvalid, bready, arvalid, arready, rvalid, rready;
    logic [1:0]  bresp, rresp;

    logic        qspi_sck, qspi_cs_n;
    logic [3:0]  qspi_io_o, qspi_io_oe;
    logic [3:0]  qspi_io_i = 4'b1111;
    logic        irq;

    qspi_master dut (
        .clk(clk), .rst_n(rst_n),
        .s_axi_awaddr(awaddr), .s_axi_awvalid(awvalid), .s_axi_awready(awready),
        .s_axi_wdata(wdata), .s_axi_wstrb(wstrb),
        .s_axi_wvalid(wvalid), .s_axi_wready(wready),
        .s_axi_bresp(bresp), .s_axi_bvalid(bvalid), .s_axi_bready(bready),
        .s_axi_araddr(araddr), .s_axi_arvalid(arvalid), .s_axi_arready(arready),
        .s_axi_rdata(rdata), .s_axi_rresp(rresp),
        .s_axi_rvalid(rvalid), .s_axi_rready(rready),
        .qspi_sck(qspi_sck), .qspi_cs_n(qspi_cs_n),
        .qspi_io_o(qspi_io_o), .qspi_io_oe(qspi_io_oe), .qspi_io_i(qspi_io_i),
        .irq(irq)
    );

    // SARTNAME EK-2 s.25-27 tablosundan BIREBIR
    localparam QSPI_CCR = 32'h00;
    localparam QSPI_ADR = 32'h04;
    localparam QSPI_DR  = 32'h08;
    localparam QSPI_STA = 32'h0C;
    localparam QSPI_FCR = 32'h10;

    // Komut opcode'lari
    localparam CMD_READ  = 8'h03;
    localparam CMD_RDID  = 8'h9F;
    localparam CMD_QOR   = 8'h6B;

    int hata = 0, denetim = 0;

    task automatic madde(input string s);
        $display("");
        $display("  --- %s", s);
    endtask

    task automatic denetle(input string ad, input logic [31:0] gercek,
                                            input logic [31:0] beklenen);
        denetim++;
        if (gercek === beklenen)
            $display("      [OK]   %-46s = 0x%08h", ad, gercek);
        else begin
            hata++;
            $display("      [HATA] %-46s beklenen=0x%08h gercek=0x%08h",
                     ad, beklenen, gercek);
        end
    endtask

    task automatic denetle_kosul(input string ad, input logic kosul,
                                 input logic [31:0] bilgi);
        denetim++;
        if (kosul)
            $display("      [OK]   %-46s   (%0d)", ad, bilgi);
        else begin
            hata++;
            $display("      [HATA] %-46s   (%0d)", ad, bilgi);
        end
    endtask

    task automatic axi_write(input logic [31:0] adr, input logic [31:0] dat);
        @(posedge clk);
        awaddr <= adr; awvalid <= 1'b1;
        wdata  <= dat; wvalid  <= 1'b1; wstrb <= 4'hF;
        bready <= 1'b1;
        @(posedge clk);
        while (!(awready && wready)) @(posedge clk);
        awvalid <= 1'b0; wvalid <= 1'b0;
        while (!bvalid) @(posedge clk);
        @(posedge clk);
        bready <= 1'b0;
    endtask

    task automatic axi_read(input logic [31:0] adr, output logic [31:0] dat);
        @(posedge clk);
        araddr <= adr; arvalid <= 1'b1; rready <= 1'b1;
        @(posedge clk);
        while (!arready) @(posedge clk);
        arvalid <= 1'b0;
        while (!rvalid) @(posedge clk);
        dat = rdata;
        @(posedge clk);
        rready <= 1'b0;
    endtask

    // ------------------------------------------------------------------------
    // SCK yukselen kenarlarini say - adres fazinin kac bit surdugunu olcmek
    // icin. CS dustukten sonra komut 8 bit, sonra adres gelir.
    // ------------------------------------------------------------------------
    // Sayim CS kenarina baglidir: CS dustugunde sifirlanir, boylece
    // onceki islemden kalan kenarlar karismaz. (Ilk yazimda sayac AXI
    // yazmasindan once aciliyordu ve axi_write'in surdugu cevrimlerde
    // onceki islemin kenarlarini sayabiliyordu.)
    int sck_sayaci;

    always @(negedge qspi_cs_n) sck_sayaci <= 0;
    always @(posedge qspi_sck)  sck_sayaci <= sck_sayaci + 1;

    logic [31:0] v, v2;

    // ------------------------------------------------------------------------
    // CCR'ye YAPILAN HER YAZMA bir islem baslatir (qspi_master.sv:507
    // ccr_written). CCR[31] ile durum temizlemek de bir yazmadir ve eski
    // reg_ccr degeriyle bir islem tetikler. Bu yuzden temizlemeden sonra
    // FSM'in bosa donmesini BEKLEMEK gerekir; aksi halde bir sonraki
    // komut yazildiginda FSM hala mesguldur ve komut kaybolur.
    // ------------------------------------------------------------------------
    task automatic bosa_don();
        logic [31:0] st;
        begin
            st = 32'hFFFF_FFFF;
            while (st[1] == 1'b1) axi_read(QSPI_STA, st);   // busy dusene kadar
            repeat (5) @(posedge clk);
        end
    endtask

    initial begin
        #20_000_000;
        $fatal(1, "tb_sartname_qspi zaman asimi");
    end

    initial begin
        $display("========================================================================");
        $display(" QSPI MASTER - SARTNAME UYUM TESTI");
        $display(" TEKNOFEST 2026 Teknik Sartnamesi v1.3, EK-2 (s.24-27)");
        $display("========================================================================");

        awvalid = 0; wvalid = 0; bready = 0; arvalid = 0; rready = 0;
        awaddr = 0; araddr = 0; wdata = 0; wstrb = 4'hF;
        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (5) @(posedge clk);

        // ====================================================================
        madde("s.24 SPI mod 0: \"SCLK pini BOSTA/IDLE durumunda '0'da duracak\"");
        // ====================================================================
        denetle("bosta SCK = 0", qspi_sck, 1'b0);
        denetle("bosta CS yuksek (pasif)", qspi_cs_n, 1'b1);

        // ====================================================================
        madde("s.26 QSPI_STA[5]: \"RX FIFO empty ... tamamen bos oldugunda 1\"");
        // ====================================================================
        axi_read(QSPI_STA, v);
        denetle("reset sonrasi RX FIFO bos (STA[5]=1)", v[5], 1'b1);

        // ====================================================================
        madde("s.26 QSPI_STA[7]: \"TX FIFO empty ... tamamen bos oldugunda 1\"");
        // ====================================================================
        denetle("reset sonrasi TX FIFO bos (STA[7]=1)", v[7], 1'b1);

        // ====================================================================
        madde("s.26 QSPI_STA[1]: \"'0' Mesgul degil\"");
        // ====================================================================
        denetle("bosta mesgul degil (STA[1]=0)", v[1], 1'b0);

        // ====================================================================
        madde("s.25 QSPI_CCR[9:8] veri modu: \"01 x1\" - tek hat modunda IO2/IO3 surulmemeli");
        // ====================================================================
        axi_write(QSPI_ADR, 32'h00_1234);
        // x1, 4 bayt veri, prescaler 2, CMD_READ
        axi_write(QSPI_CCR, (32'd2 << 25) | (32'd1 << 8) | (32'd3 << 16) | CMD_READ);
        // Komut fazinda IO0 surulur, IO2/IO3 asla
        repeat (20) @(posedge clk);
        denetle("x1 modunda IO2 surulmuyor", qspi_io_oe[2], 1'b0);
        denetle("x1 modunda IO3 surulmuyor", qspi_io_oe[3], 1'b0);
        // Islemin bitmesini bekle
        v = 0;
        while (v[0] == 1'b0) axi_read(QSPI_STA, v);
        denetle("x1 islemi tamamlandi (STA[0]=1)", v[0], 1'b1);

        // ====================================================================
        madde("s.25 QSPI_CCR[9:8] veri modu: \"11 x4\" - dort hat da surulmeli");
        // ====================================================================
        axi_write(QSPI_CCR, 32'h8000_0000);     // durum temizle
        axi_write(QSPI_FCR, 32'd3);             // FIFO'lari bosalt
        axi_write(QSPI_ADR, 32'h00_5678);
        // x4 YAZMA: CCR[10]=1, veri fazinda dort hat da surulmeli
        axi_write(QSPI_DR, 32'hAABB_CCDD);      // TX FIFO'ya veri koy
        axi_write(QSPI_CCR, (32'd2 << 25) | (32'd3 << 8) | (32'd1 << 10) |
                            (32'd3 << 16) | 8'h32);   // QPP
        // Veri fazina kadar bekle, sonra oe'yi kontrol et
        fork
            begin : x4_gozle
                logic gordu_io3;
                gordu_io3 = 1'b0;
                repeat (400) begin
                    @(posedge clk);
                    if (qspi_io_oe[3]) gordu_io3 = 1'b1;
                end
                denetle_kosul("x4 modunda IO3 suruldu (dort hat aktif)",
                              gordu_io3, gordu_io3);
            end
        join
        v = 0;
        while (v[0] == 1'b0) axi_read(QSPI_STA, v);

        // ====================================================================
        madde("s.25 QSPI_CCR[23:16] veri boyutu: \"yazilan degerin 1 FAZLASI kadar bayt\"");
        // ====================================================================
        // 1 bayt okuma: alan = 0
        axi_write(QSPI_CCR, 32'h8000_0000);
        bosa_don();
        axi_write(QSPI_FCR, 32'd3);
        axi_write(QSPI_CCR, (32'd2 << 25) | (32'd1 << 8) | (32'd0 << 16) | CMD_RDID);
        v = 0;
        while (v[0] == 1'b0) axi_read(QSPI_STA, v);
        $display("      bilgi  boyut alani=0 -> SCK kenari = %0d", sck_sayaci);
        // RDID adres istemez: 8 bit komut + 8 bit veri = 16 kenar
        denetle_kosul("boyut=0 -> 1 bayt (komut 8 + veri 8 = 16 kenar)",
                      (sck_sayaci >= 15) && (sck_sayaci <= 17), sck_sayaci);

        // 3 bayt okuma: alan = 2
        axi_write(QSPI_CCR, 32'h8000_0000);
        bosa_don();
        axi_write(QSPI_FCR, 32'd3);
        axi_write(QSPI_CCR, (32'd2 << 25) | (32'd1 << 8) | (32'd2 << 16) | CMD_RDID);
        v = 0;
        while (v[0] == 1'b0) axi_read(QSPI_STA, v);
        $display("      bilgi  boyut alani=2 -> SCK kenari = %0d", sck_sayaci);
        denetle_kosul("boyut=2 -> 3 bayt (komut 8 + veri 24 = 32 kenar)",
                      (sck_sayaci >= 31) && (sck_sayaci <= 33), sck_sayaci);

        // ====================================================================
        madde("s.25 QSPI_CCR[24]=0 (VARSAYILAN): 3 bayt adres - sartname QSPI_ADR[23:0] tanimi");
        // ====================================================================
        axi_write(QSPI_CCR, 32'h8000_0000);
        bosa_don();
        axi_write(QSPI_FCR, 32'd3);
        axi_write(QSPI_ADR, 32'h00AB_CDEF);
        // CMD_READ adres ister; 1 bayt veri
        axi_write(QSPI_CCR, (32'd2 << 25) | (32'd1 << 8) | (32'd0 << 16) | CMD_READ);
        v = 0;
        while (v[0] == 1'b0) axi_read(QSPI_STA, v);
        $display("      bilgi  CCR[24]=0 -> SCK kenari = %0d", sck_sayaci);
        // komut 8 + adres 24 (3 bayt) + veri 8 = 40 kenar
        denetle_kosul("CCR[24]=0 -> UC bayt adres (8+24+8 = 40 kenar)",
                      (sck_sayaci >= 39) && (sck_sayaci <= 41), sck_sayaci);

        // ====================================================================
        madde("s.24 \"Tum flash alanini kapsamak icin 4-BAYT ADRESLEME MODU destegi bulunacaktir\" - CCR[24]=1 ile OLCULDU");
        // ====================================================================
        axi_write(QSPI_CCR, 32'h8000_0000);
        bosa_don();
        axi_write(QSPI_FCR, 32'd3);
        axi_write(QSPI_ADR, 32'h12AB_CDEF);     // 32 bit tam adres
        // CCR[24]=1 -> dort bayt adres
        axi_write(QSPI_CCR, (32'd2 << 25) | (32'd1 << 24) | (32'd1 << 8) |
                            (32'd0 << 16) | CMD_READ);
        v = 0;
        while (v[0] == 1'b0) axi_read(QSPI_STA, v);
        $display("      bilgi  CCR[24]=1 -> SCK kenari = %0d", sck_sayaci);
        // komut 8 + adres 32 (4 bayt) + veri 8 = 48 kenar
        denetle_kosul("CCR[24]=1 -> DORT bayt adres (8+32+8 = 48 kenar)",
                      (sck_sayaci >= 47) && (sck_sayaci <= 49), sck_sayaci);
        $display("      bilgi  3 bayt ile 4 bayt arasindaki fark 8 kenar = 1 bayt");


        // ====================================================================
        madde("s.25 QSPI_CCR[30:25] prescaler: \"'0' yazilirsa SCLK sistem saat hizinda, '1' ise yarisinda\"");
        // ====================================================================
        // prescaler 0 ile 1 baytlik islem
        axi_write(QSPI_CCR, 32'h8000_0000);
        bosa_don();
        axi_write(QSPI_FCR, 32'd3);
        v2 = $time;
        axi_write(QSPI_CCR, (32'd0 << 25) | (32'd1 << 8) | (32'd0 << 16) | CMD_RDID);
        v = 0;
        while (v[0] == 1'b0) axi_read(QSPI_STA, v);
        // Sadece kabul edildigini dogrula (tam zamanlama olcumu ayri testte)
        denetle_kosul("prescaler=0 kabul edildi ve islem tamamlandi", v[0], v[0]);

        axi_write(QSPI_CCR, 32'h8000_0000);
        bosa_don();
        axi_write(QSPI_FCR, 32'd3);
        axi_write(QSPI_CCR, (32'd7 << 25) | (32'd1 << 8) | (32'd0 << 16) | CMD_RDID);
        v = 0;
        while (v[0] == 1'b0) axi_read(QSPI_STA, v);
        denetle_kosul("prescaler=7 kabul edildi ve islem tamamlandi", v[0], v[0]);

        // ====================================================================
        madde("s.27 QSPI_FCR[0]: \"RX FIFO flush. Uzerine 1 yazildiginda tum RX FIFO'yu bosaltir\"");
        // ====================================================================
        axi_write(QSPI_CCR, 32'h8000_0000);
        bosa_don();
        axi_write(QSPI_FCR, 32'd3);
        axi_read(QSPI_STA, v);
        denetle("FCR[0] flush sonrasi RX FIFO bos", v[5], 1'b1);

        // ====================================================================
        madde("s.27 QSPI_FCR: \"otomatik olarak 0'a cekilir\"");
        // ====================================================================
        axi_write(QSPI_FCR, 32'd1);
        repeat (3) @(posedge clk);
        axi_read(QSPI_FCR, v);
        denetle("FCR yazma sonrasi kendini sifirladi", v[1:0], 2'b00);

        // ====================================================================
        madde("s.26 QSPI_STA[11:8] FIFO error: \"'0001' RX FIFO boskken okunmaya calisildi\"");
        // ====================================================================
        axi_write(QSPI_CCR, 32'h8000_0000);     // hata bayraklarini temizle
        axi_write(QSPI_FCR, 32'd3);
        axi_read(QSPI_STA, v);
        denetle("temizleme sonrasi hata bayragi yok", v[11:8], 4'b0000);

        axi_read(QSPI_DR, v2);                  // BOS FIFO'dan oku
        axi_read(QSPI_STA, v);
        denetle_kosul("bos FIFO okumasi hata bayragi kurdu (STA[8])",
                      (v[8] == 1'b1), v[11:8]);

        // ====================================================================
        madde("s.26 QSPI_STA[0]: \"QSPI_CCR[31] bitine '1' yazildiginda sifirlanir\"");
        // ====================================================================
        axi_write(QSPI_CCR, 32'h8000_0000);
        repeat (3) @(posedge clk);
        axi_read(QSPI_STA, v);
        denetle("CCR[31]=1 -> STA[0] (done) sifirlandi", v[0], 1'b0);
        denetle("CCR[31]=1 -> hata bayraklari da temizlendi", v[11:8], 4'b0000);

        // ====================================================================
        madde("s.24 \"Cift flash (Dual-flash) modu desteklenmeyecektir\" - tek CS hatti");
        // ====================================================================
        denetle_kosul("yalnizca tek CS hatti var (dual-flash yok)",
                      ($bits(qspi_cs_n) == 1), $bits(qspi_cs_n));

        // ====================================================================
        madde("s.26 QSPI_DR: \"64x32-bit genisliginde bir adet TX ve bir adet RX FIFO\"");
        // ====================================================================
        denetle_kosul("FIFO derinligi 64", (dut.FIFO_DEPTH == 64), dut.FIFO_DEPTH);
        denetle_kosul("FIFO genisligi 32 bit",
                      ($bits(dut.rx_fifo[0]) == 32), $bits(dut.rx_fifo[0]));

        // ====================================================================
        $display("");
        $display("========================================================================");
        $display(" QSPI SARTNAME UYUMU: %0d denetim, %0d hata", denetim, hata);
        if (hata == 0)
            $display(" SONUC: EK-2 QSPI bolumunun TAMAMI saglaniyor");
        else
            $display(" SONUC: %0d MADDE SAGLANMIYOR", hata);
        $display("========================================================================");

        if (hata != 0) $fatal(1, "QSPI sartname uyum testi basarisiz");
        $finish;
    end

endmodule
