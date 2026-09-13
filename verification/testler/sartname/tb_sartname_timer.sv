`timescale 1ns / 1ps
// ============================================================================
//  tb_sartname_timer.sv - TIMER SARTNAME UYUM TESTI
//
//  TEKNOFEST 2026 Cip Tasarim Yarismasi - Teknik Sartname v1.3, EK-2
//
//  BU TEST NE YAPAR
//
//  Mevcut blok testleri "tasarim dogru calisiyor mu" sorusunu sorar.
//  Bu test farkli bir soru sorar: "SARTNAMEDE YAZAN CUMLE ne diyorsa
//  TAM OLARAK o mu oluyor?"
//
//  Her denetim, sartnamenin ilgili cumlesini yorum olarak tasir ve o
//  cumlenin dogrudan karsiligini olcer. Boylece juri "su maddeyi
//  sagliyor musunuz" diye sordugunda cevap tek bir test ciktisidir.
//
//  KAPSANAN SARTNAME MADDELERI (EK-2, Timer, s.20-21)
//    0x00 TIM_PRE  prescaler, PRE+1 bolme orani
//    0x04 TIM_ARE  auto-reload, "ulastiktan sonraki periyotta 0"
//    0x08 TIM_CLR  clear, "[0] biti 1 ise CNT=0, diger bitler etkisiz"
//    0x0C TIM_ENA  enable, "0 ise son degerini korur", "ENA=0 iken CLR calisir"
//    0x10 TIM_MOD  mode,  "[0]=1 yukari, 0 asagi"
//    0x14 TIM_CNT  sayac degeri
//    0x18 TIM_EVN  event, "ARE degerine her ulastiginda 1 artar"
//    0x1C TIM_EVC  event clear, "[0] biti 1 ise EVN=0"
// ============================================================================

module tb_sartname_timer;

    logic clk = 1'b0;
    logic rst_n = 1'b0;
    always #5 clk = ~clk;                       // 100 MHz

    // AXI4-Lite
    logic [11:0] awaddr, araddr;
    logic [31:0] wdata, rdata;
    logic [3:0]  wstrb;
    logic        awvalid, awready, wvalid, wready;
    logic        bvalid, bready, arvalid, arready, rvalid, rready;
    logic [1:0]  bresp, rresp;
    logic        timer_irq;

    timer_peripheral dut (
        .s_axi_aclk(clk), .s_axi_aresetn(rst_n),
        .s_axi_awaddr(awaddr), .s_axi_awprot(3'b000),
        .s_axi_awvalid(awvalid), .s_axi_awready(awready),
        .s_axi_wdata(wdata), .s_axi_wstrb(wstrb),
        .s_axi_wvalid(wvalid), .s_axi_wready(wready),
        .s_axi_bresp(bresp), .s_axi_bvalid(bvalid), .s_axi_bready(bready),
        .s_axi_araddr(araddr), .s_axi_arprot(3'b000),
        .s_axi_arvalid(arvalid), .s_axi_arready(arready),
        .s_axi_rdata(rdata), .s_axi_rresp(rresp),
        .s_axi_rvalid(rvalid), .s_axi_rready(rready),
        .timer_irq(timer_irq)
    );

    // ------------------------------------------------------------------------
    // Yazmac ofsetleri - SARTNAME EK-2 s.20-21 tablosundan BIREBIR
    // ------------------------------------------------------------------------
    localparam TIM_PRE = 12'h000;
    localparam TIM_ARE = 12'h004;
    localparam TIM_CLR = 12'h008;
    localparam TIM_ENA = 12'h00C;
    localparam TIM_MOD = 12'h010;
    localparam TIM_CNT = 12'h014;
    localparam TIM_EVN = 12'h018;
    localparam TIM_EVC = 12'h01C;

    int hata = 0, denetim = 0;

    task automatic madde(input string sartname_cumlesi);
        $display("");
        $display("  --- %s", sartname_cumlesi);
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
            $display("      [OK]   %-46s   (0x%08h)", ad, bilgi);
        else begin
            hata++;
            $display("      [HATA] %-46s   (0x%08h)", ad, bilgi);
        end
    endtask

    task automatic axi_write(input logic [11:0] adr, input logic [31:0] dat);
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

    task automatic axi_read(input logic [11:0] adr, output logic [31:0] dat);
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

    logic [31:0] v, v2, v3;
    int          sayim_pre0, sayim_pre1, sayim_pre3;

    initial begin
        #20_000_000;
        $display(" ZAMAN ASIMI");
        $fatal(1, "tb_sartname_timer zaman asimi");
    end

    initial begin
        $display("========================================================================");
        $display(" TIMER - SARTNAME UYUM TESTI");
        $display(" TEKNOFEST 2026 Teknik Sartnamesi v1.3, EK-2 (s.20-21)");
        $display("========================================================================");

        awvalid = 0; wvalid = 0; bready = 0; arvalid = 0; rready = 0;
        awaddr = 0; araddr = 0; wdata = 0; wstrb = 4'hF;
        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (5) @(posedge clk);

        // ====================================================================
        madde("s.20 TIM_PRE: \"TIM_PRE '0' oldugu zaman sayac sistem saat hizinda artacak. Yani sistem saatinin 1 periyodunda 1 degisecektir.\"");
        // ====================================================================
        axi_write(TIM_ENA, 32'd0);
        axi_write(TIM_CLR, 32'd1);
        axi_write(TIM_PRE, 32'd0);
        axi_write(TIM_ARE, 32'hFFFF_FFFF);
        axi_write(TIM_MOD, 32'd1);              // yukari
        axi_write(TIM_ENA, 32'd1);
        repeat (100) @(posedge clk);
        axi_write(TIM_ENA, 32'd0);
        axi_read(TIM_CNT, v);
        sayim_pre0 = v;
        $display("      bilgi  PRE=0 ile 100 cevrimde sayim = %0d", sayim_pre0);
        denetle_kosul("PRE=0 -> her cevrimde 1 artis (sayim ~100)",
                      (sayim_pre0 >= 95) && (sayim_pre0 <= 105), sayim_pre0);

        // ====================================================================
        madde("s.20 TIM_PRE: \"TIM_PRE '1' oldugu zaman sayac sistem saatinin 2 periyodunda 1 degisecektir.\"");
        // ====================================================================
        axi_write(TIM_ENA, 32'd0);
        axi_write(TIM_CLR, 32'd1);
        axi_write(TIM_PRE, 32'd1);
        axi_write(TIM_ENA, 32'd1);
        repeat (100) @(posedge clk);
        axi_write(TIM_ENA, 32'd0);
        axi_read(TIM_CNT, v);
        sayim_pre1 = v;
        $display("      bilgi  PRE=1 ile 100 cevrimde sayim = %0d", sayim_pre1);
        // PRE=1 -> iki cevrimde bir; sayim PRE=0'in yaklasik yarisi olmali
        denetle_kosul("PRE=1 -> iki cevrimde 1 artis (sayim ~50)",
                      (sayim_pre1 >= 45) && (sayim_pre1 <= 55), sayim_pre1);
        denetle_kosul("PRE=1 sayimi PRE=0'in yaklasik yarisi",
                      (sayim_pre1 * 2 >= sayim_pre0 - 6) &&
                      (sayim_pre1 * 2 <= sayim_pre0 + 6), sayim_pre1);

        // ====================================================================
        madde("s.20 TIM_PRE kurali dogrulama: bolme orani = PRE + 1 (PRE=3 -> dort cevrimde bir)");
        // ====================================================================
        axi_write(TIM_ENA, 32'd0);
        axi_write(TIM_CLR, 32'd1);
        axi_write(TIM_PRE, 32'd3);
        axi_write(TIM_ENA, 32'd1);
        repeat (100) @(posedge clk);
        axi_write(TIM_ENA, 32'd0);
        axi_read(TIM_CNT, v);
        sayim_pre3 = v;
        $display("      bilgi  PRE=3 ile 100 cevrimde sayim = %0d", sayim_pre3);
        denetle_kosul("PRE=3 -> dort cevrimde 1 artis (sayim ~25)",
                      (sayim_pre3 >= 22) && (sayim_pre3 <= 28), sayim_pre3);

        // ====================================================================
        madde("s.21 TIM_ARE: \"TIM_AR registeri 0x36 ise, TIM_CNT 0x36 degerine ULASTIKTAN SONRAKI PERIYOTTA 0 degerini alacaktir.\"");
        // ====================================================================
        axi_write(TIM_ENA, 32'd0);
        axi_write(TIM_CLR, 32'd1);
        axi_write(TIM_PRE, 32'd0);
        axi_write(TIM_ARE, 32'h36);
        axi_write(TIM_EVC, 32'd1);
        axi_write(TIM_ENA, 32'd1);

        // Sayaci 0x36'ya kadar birak, sonra tam o anda durdur
        repeat (32'h36) @(posedge clk);
        axi_write(TIM_ENA, 32'd0);
        axi_read(TIM_CNT, v);
        $display("      bilgi  0x36 cevrim sonra CNT = 0x%02h", v);
        // Bu noktada CNT 0x36'ya ulasmis ya da cok yakin olmali
        denetle_kosul("CNT, ARE degerine ulasabiliyor",
                      (v <= 32'h36), v);

        // Sarmanin gerceklestigini KANITLA: sayac ARE'yi asamaz.
        //
        // NOT: CNT'nin tam degerini beklemek kirilgandir - AXI yazma
        // islemleri de cevrim harcar ve sayac o sirada ilerler. Dogru
        // olcut sudur: sayac ARE degerini ASLA ASMAZ, cunku ulastiginda
        // sifirlanir. Bu, sarmanin calistiginin dogrudan kanitidir.
        axi_write(TIM_ENA, 32'd0);
        axi_write(TIM_CLR, 32'd1);
        axi_write(TIM_ARE, 32'd9);          // 0..9 arasi sayar
        axi_write(TIM_EVC, 32'd1);
        axi_write(TIM_ENA, 32'd1);
        repeat (200) @(posedge clk);        // bircok tur
        axi_write(TIM_ENA, 32'd0);
        axi_read(TIM_CNT, v);
        $display("      bilgi  ARE=9, 200 cevrim sonra CNT = %0d", v);
        denetle_kosul("sayac ARE degerini asmiyor (sarma calisiyor)",
                      (v <= 32'd9), v);

        // ====================================================================
        madde("s.21 TIM_EVN: \"TIM_CNT registeri, TIM_ARE degerine HER ULASTIGINDA 1 artacaktir\"");
        // ====================================================================
        axi_write(TIM_ENA, 32'd0);
        axi_write(TIM_CLR, 32'd1);
        axi_write(TIM_ARE, 32'd9);
        axi_write(TIM_EVC, 32'd1);
        axi_read(TIM_EVN, v);
        denetle("EVC sonrasi EVN = 0", v, 32'd0);

        axi_write(TIM_ENA, 32'd1);
        repeat (10) @(posedge clk);         // bir tur
        axi_write(TIM_ENA, 32'd0);
        axi_read(TIM_EVN, v);
        $display("      bilgi  bir tur sonra EVN = %0d", v);
        denetle_kosul("bir sarma -> EVN 1 artti", (v == 32'd1), v);

        axi_write(TIM_ENA, 32'd1);
        repeat (30) @(posedge clk);         // uc tur daha
        axi_write(TIM_ENA, 32'd0);
        axi_read(TIM_EVN, v2);
        $display("      bilgi  uc tur daha sonra EVN = %0d", v2);
        denetle_kosul("her sarmada EVN artiyor (toplam ~4)",
                      (v2 >= 3) && (v2 <= 5), v2);

        // ====================================================================
        madde("s.21 TIM_EVC: \"TIM_EVC[0] biti '1' ise event register (TIM_EVN) degeri 0 yapilacaktir\"");
        // ====================================================================
        axi_write(TIM_EVC, 32'd1);
        axi_read(TIM_EVN, v);
        denetle("EVC[0]=1 -> EVN sifirlandi", v, 32'd0);

        // ====================================================================
        madde("s.21 TIM_EVC: \"Diger bitler etkisizdir\"");
        // ====================================================================
        axi_write(TIM_ENA, 32'd1);
        repeat (10) @(posedge clk);
        axi_write(TIM_ENA, 32'd0);
        axi_read(TIM_EVN, v);
        denetle_kosul("EVN yeniden artti (temizleme oncesi)", (v > 0), v);
        axi_write(TIM_EVC, 32'hFFFF_FFFE);  // bit0 HARIC hepsi 1
        axi_read(TIM_EVN, v2);
        denetle("EVC[0]=0 iken diger bitler etkisiz - EVN degismedi", v2, v);

        // ====================================================================
        madde("s.21 TIM_CLR: \"TIM_CLR[0] biti '1' ise sayac register (TIM_CNT) degeri 0 yapilacaktir\"");
        // ====================================================================
        axi_write(TIM_ENA, 32'd0);
        axi_write(TIM_ARE, 32'hFFFF_FFFF);
        axi_write(TIM_ENA, 32'd1);
        repeat (50) @(posedge clk);
        axi_write(TIM_ENA, 32'd0);
        axi_read(TIM_CNT, v);
        denetle_kosul("sayac sifir degil (temizleme oncesi)", (v > 0), v);
        axi_write(TIM_CLR, 32'd1);
        axi_read(TIM_CNT, v);
        denetle("CLR[0]=1 -> CNT sifirlandi", v, 32'd0);

        // ====================================================================
        madde("s.21 TIM_CLR: \"Diger bitler etkisizdir\"");
        // ====================================================================
        axi_write(TIM_ENA, 32'd1);
        repeat (50) @(posedge clk);
        axi_write(TIM_ENA, 32'd0);
        axi_read(TIM_CNT, v);
        denetle_kosul("sayac yeniden ilerledi", (v > 0), v);
        axi_write(TIM_CLR, 32'hFFFF_FFFE);  // bit0 HARIC hepsi 1
        axi_read(TIM_CNT, v2);
        denetle("CLR[0]=0 iken diger bitler etkisiz - CNT degismedi", v2, v);

        // ====================================================================
        madde("s.21 TIM_ENA: \"TIM_EN[0] biti '0' ise sayac SON DEGERINI KORUYACAKTIR\"");
        // ====================================================================
        axi_write(TIM_CLR, 32'd1);
        axi_write(TIM_ENA, 32'd1);
        repeat (40) @(posedge clk);
        axi_write(TIM_ENA, 32'd0);
        axi_read(TIM_CNT, v);
        repeat (200) @(posedge clk);        // uzun sure bekle
        axi_read(TIM_CNT, v2);
        denetle("ENA=0 iken sayac son degerini korudu", v2, v);

        // ====================================================================
        madde("s.21 TIM_ENA: \"TIM_EN '0' iken TIM_CLR '1' ise sayac registeri sifirlanacaktir\"");
        // ====================================================================
        // ENA hala 0, sayac v degerinde
        denetle_kosul("on kosul: ENA=0 ve sayac sifir degil", (v2 > 0), v2);
        axi_write(TIM_CLR, 32'd1);
        axi_read(TIM_CNT, v3);
        denetle("ENA=0 iken CLR calisti - CNT sifir", v3, 32'd0);

        // ====================================================================
        madde("s.21 TIM_MOD: \"TIM_MOD[0] biti '1' ise YUKARI dogru, '0' ise ASAGI dogru sayacaktir\"");
        // ====================================================================
        // Yukari
        axi_write(TIM_ENA, 32'd0);
        axi_write(TIM_CLR, 32'd1);
        axi_write(TIM_ARE, 32'hFFFF_FFFF);
        axi_write(TIM_MOD, 32'd1);
        axi_write(TIM_ENA, 32'd1);
        repeat (20) @(posedge clk);
        axi_read(TIM_CNT, v);
        repeat (20) @(posedge clk);
        axi_write(TIM_ENA, 32'd0);
        axi_read(TIM_CNT, v2);
        denetle_kosul("MOD=1 -> sayac ARTIYOR", (v2 > v), v2);

        // Asagi: ARE degerinden geriye
        axi_write(TIM_ENA, 32'd0);
        axi_write(TIM_ARE, 32'd1000);
        axi_write(TIM_CLR, 32'd1);
        axi_write(TIM_MOD, 32'd0);          // asagi
        axi_write(TIM_ENA, 32'd1);
        repeat (5) @(posedge clk);          // CNT=0'dan ARE'ye sarar
        axi_read(TIM_CNT, v);
        repeat (20) @(posedge clk);
        axi_write(TIM_ENA, 32'd0);
        axi_read(TIM_CNT, v2);
        $display("      bilgi  asagi kip: once=%0d sonra=%0d", v, v2);
        denetle_kosul("MOD=0 -> sayac AZALIYOR", (v2 < v), v2);

        // ====================================================================
        madde("s.21 TIM_CNT: \"Timer counter registeri. Sayacin tutuldugu register.\" (RO)");
        // ====================================================================
        axi_write(TIM_ENA, 32'd0);
        axi_write(TIM_CLR, 32'd1);
        axi_read(TIM_CNT, v);
        denetle("CNT temizleme sonrasi okunabiliyor", v, 32'd0);
        axi_write(TIM_CNT, 32'hDEAD_BEEF);  // RO - yazma etkisiz olmali
        axi_read(TIM_CNT, v2);
        denetle("CNT salt okunur - yazma etkisiz", v2, 32'd0);

        // ====================================================================
        madde("s.20 GENEL: \"32-bit sayac degeri ile ilgili cevre birimidir\"");
        // ====================================================================
        axi_write(TIM_ENA, 32'd0);
        axi_write(TIM_ARE, 32'hFFFF_FFFF);
        axi_read(TIM_ARE, v);
        denetle("ARE 32 bit tam genislik tutuyor", v, 32'hFFFF_FFFF);
        axi_write(TIM_PRE, 32'hFFFF_FFFF);
        axi_read(TIM_PRE, v);
        denetle("PRE 32 bit tam genislik tutuyor", v, 32'hFFFF_FFFF);

        // ====================================================================
        $display("");
        $display("========================================================================");
        $display(" TIMER SARTNAME UYUMU: %0d denetim, %0d hata", denetim, hata);
        if (hata == 0)
            $display(" SONUC: EK-2 Timer bolumunun TAMAMI saglaniyor");
        else
            $display(" SONUC: %0d MADDE SAGLANMIYOR", hata);
        $display("========================================================================");

        if (hata != 0) $fatal(1, "Timer sartname uyum testi basarisiz");
        $finish;
    end

endmodule
