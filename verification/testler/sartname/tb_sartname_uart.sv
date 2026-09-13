`timescale 1ns / 1ps
// ============================================================================
//  tb_sartname_uart.sv - UART SARTNAME UYUM TESTI
//
//  TEKNOFEST 2026 Teknik Sartnamesi v1.3, EK-2 (s.21-22)
//
//  KAPSANAN MADDELER
//    "UART modulunun programlanabilir baud hizi 1 Mbps veri aktarim hizini
//     desteklemeli ve EN AZ IKI FARKLI baud hizini desteklemelidir."
//
//    0x00 UART_CPB  "UART baud rate, (sistem saat frekansi)/UART_CPB seklinde
//                    hesaplanacaktir. Tasarlanacak olan UART cevrebirimi bu
//                    sekilde calismalidir."
//    0x04 UART_STP  "00: Stop-bit 1 | 01: Stop-bit 1.5 | 1X: Stop-bit 2"
//    0x08 UART_RDR  "1 bayt veriyi UART_RDR[7:0] bitlerine kaydeder.
//                    Diger bitler etkisizdir." (RO)
//    0x0C UART_TDR  "UART_TDR[7:0] bitlerindeki veriyi UART_CFG[0] biti '1'
//                    olduginca karsi tarafa gonderir."
//    0x10 UART_CFG  [0] Transmit start  - "Gonderim tamamlandiginda bu bit,
//                       LOJIK DEVRENIN KENDISI tarafindan '0'a cekilmelidir."
//                       (v1.3'te netlestirilen madde)
//                   [1] Data received   - HW '1' yapar, SW '0'a ceker
//                   [2] Transmit completed - HW '1' yapar, SW '0'a ceker
// ============================================================================

module tb_sartname_uart;

    localparam int SYS_CLK_HZ = 50_000_000;

    logic clk = 1'b0;
    logic rst_n = 1'b0;
    always #10 clk = ~clk;                  // 50 MHz

    logic [7:0]  awaddr, araddr;
    logic [31:0] wdata, rdata;
    logic [3:0]  wstrb;
    logic        awvalid, awready, wvalid, wready;
    logic        bvalid, bready, arvalid, arready, rvalid, rready;
    logic [1:0]  bresp, rresp;

    logic uart_rxd = 1'b1;
    logic uart_txd;
    logic uart_irq;

    uart_peripheral #(.SYS_CLK_HZ(SYS_CLK_HZ)) dut (
        .clk(clk), .rst_n(rst_n),
        .s_axil_awaddr(awaddr),
        .s_axil_awvalid(awvalid), .s_axil_awready(awready),
        .s_axil_wdata(wdata), .s_axil_wstrb(wstrb),
        .s_axil_wvalid(wvalid), .s_axil_wready(wready),
        .s_axil_bresp(bresp), .s_axil_bvalid(bvalid), .s_axil_bready(bready),
        .s_axil_araddr(araddr),
        .s_axil_arvalid(arvalid), .s_axil_arready(arready),
        .s_axil_rdata(rdata), .s_axil_rresp(rresp),
        .s_axil_rvalid(rvalid), .s_axil_rready(rready),
        .uart_rxd(uart_rxd), .uart_txd(uart_txd),
        .uart_irq(uart_irq)
    );

    // SARTNAME EK-2 s.21-22 tablosundan BIREBIR
    localparam UART_CPB = 8'h00;
    localparam UART_STP = 8'h04;
    localparam UART_RDR = 8'h08;
    localparam UART_TDR = 8'h0C;
    localparam UART_CFG = 8'h10;

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
            $display("      [OK]   %-46s   (0x%08h)", ad, bilgi);
        else begin
            hata++;
            $display("      [HATA] %-46s   (0x%08h)", ad, bilgi);
        end
    endtask

    task automatic axi_write(input logic [7:0] adr, input logic [31:0] dat);
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

    task automatic axi_read(input logic [7:0] adr, output logic [31:0] dat);
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

    // TX hattindaki bir bitin suresini olc (cevrim cinsinden)
    task automatic olc_bit_suresi(output int cevrim);
        time t0, t1;
        begin
            @(negedge uart_txd);            // start biti
            t0 = $time;
            @(posedge clk);
            // Bir sonraki kenari bekle; start biti tam bir bit suresi surer
            wait (uart_txd == 1'b1);
            t1 = $time;
            cevrim = (t1 - t0) / 20;        // 20 ns = 1 cevrim @ 50 MHz
        end
    endtask

    logic [31:0] v, v2;
    int          bit_cevrim;

    initial begin
        #50_000_000;
        $fatal(1, "tb_sartname_uart zaman asimi");
    end

    initial begin
        $display("========================================================================");
        $display(" UART - SARTNAME UYUM TESTI");
        $display(" TEKNOFEST 2026 Teknik Sartnamesi v1.3, EK-2 (s.21-22)");
        $display("========================================================================");

        awvalid = 0; wvalid = 0; bready = 0; arvalid = 0; rready = 0;
        awaddr = 0; araddr = 0; wdata = 0; wstrb = 4'hF;
        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (5) @(posedge clk);

        // ====================================================================
        madde("s.21 UART_CPB: \"UART baud rate, (sistem saat frekansi)/UART_CPB seklinde hesaplanacaktir\"");
        // ====================================================================
        // 1 Mbps: 50e6 / 1e6 = 50
        axi_write(UART_CPB, 32'd50);
        axi_read(UART_CPB, v);
        denetle("CPB=50 yazildi ve geri okundu (1 Mbps)", v, 32'd50);

        // 115200: 50e6 / 115200 = 434
        axi_write(UART_CPB, 32'd434);
        axi_read(UART_CPB, v);
        denetle("CPB=434 yazildi ve geri okundu (115200 baud)", v, 32'd434);

        // 9600: 50e6 / 9600 = 5208
        axi_write(UART_CPB, 32'd5208);
        axi_read(UART_CPB, v);
        denetle("CPB=5208 yazildi ve geri okundu (9600 baud)", v, 32'd5208);

        // ====================================================================
        madde("s.21 UART: \"programlanabilir baud hizi 1 Mbps veri aktarim hizini DESTEKLEMELI\"");
        // ====================================================================
        axi_write(UART_CPB, 32'd50);        // 1 Mbps
        axi_write(UART_STP, 32'd0);
        repeat (5) @(posedge clk);
        axi_write(UART_TDR, 32'h55);        // 0x55 = 01010101, kenar bol
        axi_write(UART_CFG, 32'h1);         // TX baslat
        olc_bit_suresi(bit_cevrim);
        $display("      bilgi  CPB=50 ile olculen start biti = %0d cevrim", bit_cevrim);
        denetle_kosul("1 Mbps: bit suresi ~50 cevrim",
                      (bit_cevrim >= 48) && (bit_cevrim <= 52), bit_cevrim);
        // Gonderimin bitmesini bekle
        repeat (600) @(posedge clk);
        axi_write(UART_CFG, 32'h0);
        repeat (20) @(posedge clk);

        // ====================================================================
        madde("s.21 UART: \"EN AZ IKI FARKLI baud hizini desteklemelidir\"");
        // ====================================================================
        axi_write(UART_CPB, 32'd100);       // 500 kbps - ikinci hiz
        repeat (5) @(posedge clk);
        axi_write(UART_TDR, 32'h55);
        axi_write(UART_CFG, 32'h1);
        olc_bit_suresi(bit_cevrim);
        $display("      bilgi  CPB=100 ile olculen start biti = %0d cevrim", bit_cevrim);
        denetle_kosul("ikinci baud hizi: bit suresi ~100 cevrim",
                      (bit_cevrim >= 96) && (bit_cevrim <= 104), bit_cevrim);
        repeat (1200) @(posedge clk);
        axi_write(UART_CFG, 32'h0);
        repeat (20) @(posedge clk);

        // ====================================================================
        madde("s.22 UART_STP: \"00: Stop-bit 1 | 01: Stop-bit 1.5 | 1X: Stop-bit 2\"");
        // ====================================================================
        axi_write(UART_STP, 32'b00);
        axi_read(UART_STP, v);
        denetle("STP=00 (1 stop bit) kabul edildi", v[1:0], 2'b00);

        axi_write(UART_STP, 32'b01);
        axi_read(UART_STP, v);
        denetle("STP=01 (1.5 stop bit) kabul edildi", v[1:0], 2'b01);

        axi_write(UART_STP, 32'b10);
        axi_read(UART_STP, v);
        denetle("STP=10 (2 stop bit) kabul edildi", v[1:0], 2'b10);

        axi_write(UART_STP, 32'b11);
        axi_read(UART_STP, v);
        denetle("STP=11 (1X -> 2 stop bit) kabul edildi", v[1:0], 2'b11);

        // ====================================================================
        madde("s.22 UART_TDR: \"UART_TDR[7:0] bitlerindeki veriyi ... gonderir\"");
        // ====================================================================
        axi_write(UART_STP, 32'd0);
        axi_write(UART_TDR, 32'hA5);
        axi_read(UART_TDR, v);
        denetle("TDR[7:0] yazildi ve geri okundu", v[7:0], 8'hA5);

        // ====================================================================
        madde("s.22 UART_CFG[0]: \"'1' yazildigi zaman UART_TDR yazmacinda bulunan verinin gonderimine baslar\"");
        // ====================================================================
        axi_write(UART_CPB, 32'd50);
        repeat (5) @(posedge clk);
        axi_write(UART_TDR, 32'h3C);
        axi_read(UART_CFG, v);
        denetle_kosul("gonderim oncesi TX bosta (txd yuksek)", (uart_txd == 1'b1), uart_txd);
        axi_write(UART_CFG, 32'h1);         // baslat
        // Start biti gelmeli
        fork
            begin : bekle_start
                @(negedge uart_txd);
                denetle_kosul("CFG[0]=1 -> gonderim basladi (start biti)", 1'b1, 32'd1);
            end
            begin : zaman_asimi
                repeat (500) @(posedge clk);
                denetle_kosul("CFG[0]=1 -> gonderim basladi (start biti)", 1'b0, 32'd0);
            end
        join_any
        disable fork;

        // ====================================================================
        madde("s.22 UART_CFG[0]: \"Gonderim tamamlandiginda bu bit, LOJIK DEVRENIN KENDISI tarafindan '0'a cekilmelidir\" (v1.3)");
        // ====================================================================
        // Gonderimin bitmesini bekle (10 bit x 50 cevrim + pay)
        repeat (700) @(posedge clk);
        axi_read(UART_CFG, v);
        denetle("gonderim sonrasi CFG[0] donanimca sifirlandi", v[0], 1'b0);

        // ====================================================================
        madde("s.22 UART_CFG[2]: \"UART_TDR'de bulunan verinin gonderimi tamamlandiginda HW tarafindan '1' yapilir\"");
        // ====================================================================
        denetle("gonderim tamamlandi bayragi CFG[2]=1", v[2], 1'b1);

        // ====================================================================
        madde("s.22 UART_CFG[2]: \"SW tarafindan '0'a cekilmesi gerekmektedir\"");
        // ====================================================================
        axi_write(UART_CFG, 32'h0);         // SW temizler
        repeat (5) @(posedge clk);
        axi_read(UART_CFG, v);
        denetle("SW yazmasiyla CFG[2] temizlendi", v[2], 1'b0);

        // ====================================================================
        madde("s.22 UART_RDR: \"UART receiver tarafindan 1 bayt veriyi UART_RDR[7:0] bitlerine kaydeder\"");
        // ====================================================================
        // RX'e 0x5A gonder (CPB=50, 1 Mbps)
        axi_write(UART_CPB, 32'd50);
        axi_write(UART_STP, 32'd0);
        repeat (10) @(posedge clk);
        seri_gonder(8'h5A, 50);
        repeat (200) @(posedge clk);
        axi_read(UART_RDR, v);
        denetle("RX ile alinan bayt RDR[7:0]'de", v[7:0], 8'h5A);

        // ====================================================================
        madde("s.22 UART_RDR: \"Veri alimi tamamlandiginda UART_CFG[1] bitini '1'e ceker\"");
        // ====================================================================
        axi_read(UART_CFG, v);
        denetle("veri alindi bayragi CFG[1]=1", v[1], 1'b1);

        // ====================================================================
        madde("s.22 UART_CFG[1]: \"SW tarafindan '0'a cekilmesi gerekmektedir\"");
        // ====================================================================
        axi_write(UART_CFG, 32'h0);
        repeat (5) @(posedge clk);
        axi_read(UART_CFG, v);
        denetle("SW yazmasiyla CFG[1] temizlendi", v[1], 1'b0);

        // ====================================================================
        madde("s.22 UART_RDR: \"Diger bitler etkisizdir\" (RDR[31:8])");
        // ====================================================================
        seri_gonder(8'hFF, 50);
        repeat (200) @(posedge clk);
        axi_read(UART_RDR, v);
        denetle("RDR[7:0] = 0xFF", v[7:0], 8'hFF);
        denetle("RDR[31:8] etkisiz (sifir)", v[31:8], 24'h000000);

        // ====================================================================
        $display("");
        $display("========================================================================");
        $display(" UART SARTNAME UYUMU: %0d denetim, %0d hata", denetim, hata);
        if (hata == 0)
            $display(" SONUC: EK-2 UART bolumunun TAMAMI saglaniyor");
        else
            $display(" SONUC: %0d MADDE SAGLANMIYOR", hata);
        $display("========================================================================");

        if (hata != 0) $fatal(1, "UART sartname uyum testi basarisiz");
        $finish;
    end

    // Seri hattan bir bayt gonder (8N1)
    task automatic seri_gonder(input logic [7:0] bayt, input int cpb);
        int i;
        begin
            uart_rxd = 1'b0;                        // start
            repeat (cpb) @(posedge clk);
            for (i = 0; i < 8; i++) begin
                uart_rxd = bayt[i];                 // LSB once
                repeat (cpb) @(posedge clk);
            end
            uart_rxd = 1'b1;                        // stop
            repeat (cpb) @(posedge clk);
        end
    endtask

endmodule
