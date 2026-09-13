// =============================================================================
//  tb_wstrb_kismi_yazma.sv
//
//  NEDEN VAR
//    12 Eylul 2026'da UVM kapsam genisletmesi bir ACIK ortaya cikardi:
//
//        [OK] yazmalar tek genislikte (tam=16 bayt=0 yarim=0)
//
//    162.064 AXI islemi iceren sistem regresyonunda TEK BIR kismi yazma
//    yok. Yani sram_module.sv:319-322'deki bayt-secmeli yazma mantigi
//    HIC dogrulanmamisti:
//
//        if (w_strb_reg[0]) ram[waddr][7:0]   <= w_data_reg[7:0];
//        if (w_strb_reg[1]) ram[waddr][15:8]  <= w_data_reg[15:8];
//        ...
//
//    Bu kod yanlis olsaydi (ornegin strb biti yanlis dilime baglansaydi)
//    mevcut testlerin HICBIRI yakalamazdi.
//
//  NE DOGRULAR
//    1. Her bayt seridi tek basina yazilabiliyor mu
//    2. Yazilmayan baytlar KORUNUYOR mu (asil risk bu)
//    3. Yarim kelime (16 bit) yazmalar
//    4. WSTRB=0 hicbir seyi degistirmiyor mu
//    5. Ardisik kismi yazmalar birikimli dogru sonuc veriyor mu
//    6. Kismi yazma komsu adresi bozmuyor mu
// =============================================================================
`timescale 1ns/1ps

module tb_wstrb_kismi_yazma;

    localparam int AW = 32;
    localparam int DW = 32;
    localparam int DEPTH = 2048;

    logic clk = 1'b0, rst_n = 1'b0;
    always #5ns clk = ~clk;

    logic [AW-1:0] awaddr;  logic awvalid; logic awready;
    logic [DW-1:0] wdata;   logic [3:0] wstrb; logic wvalid; logic wready;
    logic [1:0]    bresp;   logic bvalid;  logic bready;
    logic [AW-1:0] araddr;  logic arvalid; logic arready;
    logic [DW-1:0] rdata;   logic [1:0] rresp; logic rvalid; logic rready;

    int pass_count = 0, fail_count = 0;

    sram_module #(.AXI_ADDR_W(AW), .AXI_DATA_W(DW), .RAM_DEPTH(DEPTH)) dut (
        .clk(clk), .rst_n(rst_n),
        .s_axil_awaddr(awaddr), .s_axil_awvalid(awvalid), .s_axil_awready(awready),
        .s_axil_wdata(wdata),   .s_axil_wstrb(wstrb),     .s_axil_wvalid(wvalid),
        .s_axil_wready(wready),
        .s_axil_bresp(bresp),   .s_axil_bvalid(bvalid),   .s_axil_bready(bready),
        .s_axil_araddr(araddr), .s_axil_arvalid(arvalid), .s_axil_arready(arready),
        .s_axil_rdata(rdata),   .s_axil_rresp(rresp),     .s_axil_rvalid(rvalid),
        .s_axil_rready(rready)
    );

    task automatic kontrol(input bit kosul, input string mesaj);
        if (kosul) begin pass_count++; $display("  [OK] %s", mesaj); end
        else       begin fail_count++; $display("  [HATA] %s", mesaj); end
    endtask

    // -------------------------------------------------------------------
    //  AXI4-Lite yazma - WSTRB ile
    //
    //  ZAMANLAMA NOTU
    //    RTL READY'yi bir cevrim GEC yukseltir ve el sikisma posedge'inde
    //    dusurur. Bu yuzden VALID, TAKIP EDEN negedge'e kadar yuksek
    //    kalmalidir. Kalip tb_sram_w_yakalama.sv'den alinmistir (o test
    //    calisan referanstir):
    //        negedge'de sur -> negedge'de READY yokla -> bir negedge daha
    //
    //    AW ve W kanallari BAGIMSIZ el sikisir; ikisi de fork icinde
    //    surulur. sram_module her iki kanal tamamlanmadan yazmaz
    //    (aw_active && w_active).
    // -------------------------------------------------------------------
    task automatic axi_yaz(input [AW-1:0] adr, input [DW-1:0] veri,
                           input [3:0] strb);
        int g;
        begin
            bready = 1'b1;
            fork
                begin : aw_kanali
                    @(negedge clk); awaddr = adr; awvalid = 1'b1;
                    @(negedge clk);
                    g = 0;
                    while (!awready && g < 40) begin @(negedge clk); g++; end
                    @(negedge clk);
                    awvalid = 1'b0;
                end
                begin : w_kanali
                    @(negedge clk); wdata = veri; wstrb = strb; wvalid = 1'b1;
                    @(negedge clk);
                    g = 0;
                    while (!wready && g < 40) begin @(negedge clk); g++; end
                    @(negedge clk);
                    wvalid = 1'b0;
                end
            join

            // B yanitini bekle
            g = 0;
            while (!bvalid && g < 40) begin @(negedge clk); g++; end
            @(negedge clk);
            bready = 1'b0;
        end
    endtask

    task automatic axi_oku(input [AW-1:0] adr, output logic [DW-1:0] veri);
        int g;
        begin
            @(negedge clk); araddr = adr; arvalid = 1'b1; rready = 1'b1;
            @(negedge clk);
            g = 0;
            while (!arready && g < 40) begin @(negedge clk); g++; end
            @(negedge clk);
            arvalid = 1'b0;
            g = 0;
            while (!rvalid && g < 40) begin @(negedge clk); g++; end
            veri = rdata;
            @(negedge clk);
            rready = 1'b0;
        end
    endtask

    logic [DW-1:0] okunan;

    initial begin
        awaddr = 32'h0; awvalid = 1'b0;
        wdata  = 32'h0; wstrb = 4'b0000; wvalid = 1'b0;
        bready = 1'b0;
        araddr = 32'h0; arvalid = 1'b0; rready = 1'b0;

        $display("================================================================");
        $display(" WSTRB KISMI YAZMA DOGRULAMASI");
        $display("================================================================");

        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (3) @(posedge clk);

        // ===============================================================
        //  1. Her bayt seridi ayri ayri - KORUMA asil risk
        // ===============================================================
        $display("");
        $display("1. Bayt seridi yazma ve KORUMA testi");

        axi_yaz(32'h0000_0000, 32'hAABB_CCDD, 4'b1111);
        axi_oku(32'h0000_0000, okunan);
        kontrol(okunan === 32'hAABB_CCDD,
                $sformatf("tam kelime yazildi: 0x%08h", okunan));

        axi_yaz(32'h0000_0000, 32'h0000_0011, 4'b0001);
        axi_oku(32'h0000_0000, okunan);
        kontrol(okunan === 32'hAABB_CC11,
                $sformatf("strb=0001 yalniz bayt0: 0x%08h (beklenen AABBCC11)", okunan));

        axi_yaz(32'h0000_0000, 32'h0000_2200, 4'b0010);
        axi_oku(32'h0000_0000, okunan);
        kontrol(okunan === 32'hAABB_2211,
                $sformatf("strb=0010 yalniz bayt1: 0x%08h (beklenen AABB2211)", okunan));

        axi_yaz(32'h0000_0000, 32'h0033_0000, 4'b0100);
        axi_oku(32'h0000_0000, okunan);
        kontrol(okunan === 32'hAA33_2211,
                $sformatf("strb=0100 yalniz bayt2: 0x%08h (beklenen AA332211)", okunan));

        axi_yaz(32'h0000_0000, 32'h4400_0000, 4'b1000);
        axi_oku(32'h0000_0000, okunan);
        kontrol(okunan === 32'h4433_2211,
                $sformatf("strb=1000 yalniz bayt3: 0x%08h (beklenen 44332211)", okunan));

        // ===============================================================
        //  2. Yarim kelime
        // ===============================================================
        $display("");
        $display("2. Yarim kelime (16 bit) yazma");

        axi_yaz(32'h0000_0004, 32'hFFFF_FFFF, 4'b1111);
        axi_yaz(32'h0000_0004, 32'h0000_5A5A, 4'b0011);
        axi_oku(32'h0000_0004, okunan);
        kontrol(okunan === 32'hFFFF_5A5A,
                $sformatf("strb=0011 alt yarim: 0x%08h (beklenen FFFF5A5A)", okunan));

        axi_yaz(32'h0000_0004, 32'hA5A5_0000, 4'b1100);
        axi_oku(32'h0000_0004, okunan);
        kontrol(okunan === 32'hA5A5_5A5A,
                $sformatf("strb=1100 ust yarim: 0x%08h (beklenen A5A55A5A)", okunan));

        // ===============================================================
        //  3. WSTRB = 0 : hicbir sey degismemeli
        // ===============================================================
        $display("");
        $display("3. WSTRB=0000 koruma testi");

        axi_yaz(32'h0000_0008, 32'h1234_5678, 4'b1111);
        axi_yaz(32'h0000_0008, 32'hDEAD_BEEF, 4'b0000);
        axi_oku(32'h0000_0008, okunan);
        kontrol(okunan === 32'h1234_5678,
                $sformatf("strb=0000 icerik korundu: 0x%08h (beklenen 12345678)", okunan));

        // ===============================================================
        //  4. Birikimli: sifirdan bayt bayt kelime kur
        // ===============================================================
        $display("");
        $display("4. Birikimli kismi yazma");

        axi_yaz(32'h0000_000C, 32'h0000_0000, 4'b1111);
        axi_yaz(32'h0000_000C, 32'h0000_00DE, 4'b0001);
        axi_yaz(32'h0000_000C, 32'h0000_AD00, 4'b0010);
        axi_yaz(32'h0000_000C, 32'h00BE_0000, 4'b0100);
        axi_yaz(32'h0000_000C, 32'hEF00_0000, 4'b1000);
        axi_oku(32'h0000_000C, okunan);
        kontrol(okunan === 32'hEFBE_ADDE,
                $sformatf("dort bayt yazmasi birlesti: 0x%08h (beklenen EFBEADDE)", okunan));

        // ===============================================================
        //  5. Komsu adres bozulmamali
        // ===============================================================
        $display("");
        $display("5. Komsu adres bozulmama testi");

        axi_yaz(32'h0000_0010, 32'h1111_1111, 4'b1111);
        axi_yaz(32'h0000_0014, 32'h2222_2222, 4'b1111);
        axi_yaz(32'h0000_0010, 32'h0000_00FF, 4'b0001);

        axi_oku(32'h0000_0010, okunan);
        kontrol(okunan === 32'h1111_11FF,
                $sformatf("hedef adres dogru: 0x%08h (beklenen 111111FF)", okunan));

        axi_oku(32'h0000_0014, okunan);
        kontrol(okunan === 32'h2222_2222,
                $sformatf("komsu adres BOZULMADI: 0x%08h (beklenen 22222222)", okunan));

        // ===============================================================
        $display("");
        $display("================================================================");
        if (fail_count == 0)
            $display(" TB SONUC: GECTI  (%0d denetim)", pass_count);
        else
            $display(" TB SONUC: KALDI  (%0d gecti, %0d kaldi)", pass_count, fail_count);
        $display("================================================================");
        $finish;
    end

    // Gozcu - sartname s.615: test manuel inceleme gerektirmeden bitmelidir
    initial begin
        #500_000;
        $display("  [HATA] gozcu: test 500 us icinde bitmedi");
        $display(" TB SONUC: KALDI (asili kaldi)");
        $finish;
    end

endmodule
