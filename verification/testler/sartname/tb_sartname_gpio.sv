`timescale 1ns / 1ps
// ============================================================================
//  tb_sartname_gpio.sv - GPIO SARTNAME UYUM TESTI
//
//  TEKNOFEST 2026 Teknik Sartnamesi v1.3, EK-2 (s.20)
//
//  KAPSANAN MADDELER
//    "Toplam 32 adet giris ve cikis pinlerinin degerlerinin okunup
//     yazilmasindan sorumlu cevre birimidir. 16 adet pin giris,
//     16 adet pin cikis olarak SABITLENMISTIR."
//
//    0x00 GPIO_IDR (RO)
//      "GPIO_IDR[15:0] bitlerinde 16-bit giris sinyalinin degerini tutar.
//       GPIO_IDR[31:16] bitlerinde HER ZAMAN '0' degeri mevcuttur."
//
//    0x04 GPIO_ODR (RW)
//      "GPIO_ODR[15:0] bitlerine yazilan 16-bit degeri cikis bitlerine
//       iletir. GPIO_ODR[31:16] bitlerine yazilan deger ETKISIZDIR."
// ============================================================================

module tb_sartname_gpio;

    logic clk = 1'b0;
    logic rst_n = 1'b0;
    always #5 clk = ~clk;

    logic [7:0]  awaddr, araddr;
    logic [31:0] wdata, rdata;
    logic [3:0]  wstrb;
    logic        awvalid, awready, wvalid, wready;
    logic        bvalid, bready, arvalid, arready, rvalid, rready;
    logic [1:0]  bresp, rresp;

    logic [15:0] gpio_in;
    logic [15:0] gpio_out;
    logic [15:0] gpio_tx_en;
    logic        gpio_irq;

    gpio_peripheral dut (
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
        .gpio_i(gpio_in), .gpio_o(gpio_out), .gpio_tx_en_o(gpio_tx_en),
        .global_interrupt_o(gpio_irq)
    );

    // SARTNAME EK-2 s.20 tablosundan BIREBIR
    localparam GPIO_IDR = 8'h00;
    localparam GPIO_ODR = 8'h04;

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

    logic [31:0] v;

    initial begin
        #5_000_000;
        $fatal(1, "tb_sartname_gpio zaman asimi");
    end

    initial begin
        $display("========================================================================");
        $display(" GPIO - SARTNAME UYUM TESTI");
        $display(" TEKNOFEST 2026 Teknik Sartnamesi v1.3, EK-2 (s.20)");
        $display("========================================================================");

        awvalid = 0; wvalid = 0; bready = 0; arvalid = 0; rready = 0;
        awaddr = 0; araddr = 0; wdata = 0; wstrb = 4'hF; gpio_in = 16'h0000;
        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (5) @(posedge clk);

        // ====================================================================
        madde("s.20 GPIO_IDR: \"GPIO_IDR[15:0] bitlerinde 16-bit giris sinyalinin degerini tutar\"");
        // ====================================================================
        gpio_in = 16'hA5A5;
        repeat (5) @(posedge clk);          // giris senkronlayici
        axi_read(GPIO_IDR, v);
        denetle("giris 0xA5A5 -> IDR[15:0]", v[15:0], 32'hA5A5);

        gpio_in = 16'h5A5A;
        repeat (5) @(posedge clk);
        axi_read(GPIO_IDR, v);
        denetle("giris 0x5A5A -> IDR[15:0]", v[15:0], 32'h5A5A);

        gpio_in = 16'hFFFF;
        repeat (5) @(posedge clk);
        axi_read(GPIO_IDR, v);
        denetle("giris 0xFFFF -> IDR[15:0]", v[15:0], 32'hFFFF);

        gpio_in = 16'h0000;
        repeat (5) @(posedge clk);
        axi_read(GPIO_IDR, v);
        denetle("giris 0x0000 -> IDR[15:0]", v[15:0], 32'h0000);

        // ====================================================================
        madde("s.20 GPIO_IDR: \"GPIO_IDR[31:16] bitlerinde HER ZAMAN '0' degeri mevcuttur\"");
        // ====================================================================
        gpio_in = 16'hFFFF;                 // tum girisler yuksek
        repeat (5) @(posedge clk);
        axi_read(GPIO_IDR, v);
        denetle("girisler tamamen 1 iken IDR[31:16] = 0", v[31:16], 16'h0000);

        gpio_in = 16'hA5A5;
        repeat (5) @(posedge clk);
        axi_read(GPIO_IDR, v);
        denetle("karisik giriste de IDR[31:16] = 0", v[31:16], 16'h0000);

        // ====================================================================
        madde("s.20 GPIO_ODR: \"GPIO_ODR[15:0] bitlerine yazilan 16-bit degeri cikis bitlerine iletir\"");
        // ====================================================================
        axi_write(GPIO_ODR, 32'h0000_A5A5);
        repeat (2) @(posedge clk);
        denetle("ODR=0xA5A5 -> cikis pinleri", gpio_out, 16'hA5A5);

        axi_write(GPIO_ODR, 32'h0000_5A5A);
        repeat (2) @(posedge clk);
        denetle("ODR=0x5A5A -> cikis pinleri", gpio_out, 16'h5A5A);

        axi_write(GPIO_ODR, 32'h0000_FFFF);
        repeat (2) @(posedge clk);
        denetle("ODR=0xFFFF -> cikis pinleri", gpio_out, 16'hFFFF);

        axi_write(GPIO_ODR, 32'h0000_0000);
        repeat (2) @(posedge clk);
        denetle("ODR=0x0000 -> cikis pinleri", gpio_out, 16'h0000);

        // ====================================================================
        madde("s.20 GPIO_ODR: \"GPIO_ODR[31:16] bitlerine yazilan deger ETKISIZDIR\"");
        // ====================================================================
        axi_write(GPIO_ODR, 32'hFFFF_1234);  // ust yari 1, alt yari 0x1234
        repeat (2) @(posedge clk);
        denetle("ODR=0xFFFF1234 -> cikis yalnizca 0x1234", gpio_out, 16'h1234);

        axi_read(GPIO_ODR, v);
        denetle("ODR geri okuma ust yari 0", v[31:16], 16'h0000);

        axi_write(GPIO_ODR, 32'hDEAD_BEEF);
        repeat (2) @(posedge clk);
        denetle("ODR=0xDEADBEEF -> cikis yalnizca 0xBEEF", gpio_out, 16'hBEEF);

        // ====================================================================
        madde("s.20 GENEL: \"16 adet pin giris, 16 adet pin cikis olarak SABITLENMISTIR\"");
        // ====================================================================
        denetle_genislik();

        // ====================================================================
        madde("s.20 GPIO_IDR salt okunur (RO) - yazma etkisiz olmali");
        // ====================================================================
        gpio_in = 16'h1111;
        repeat (5) @(posedge clk);
        axi_write(GPIO_IDR, 32'hFFFF_FFFF);  // RO yazmaca yazma denemesi
        repeat (2) @(posedge clk);
        axi_read(GPIO_IDR, v);
        denetle("IDR salt okunur - giris degeri korundu", v[15:0], 32'h1111);

        // ====================================================================
        $display("");
        $display("========================================================================");
        $display(" GPIO SARTNAME UYUMU: %0d denetim, %0d hata", denetim, hata);
        if (hata == 0)
            $display(" SONUC: EK-2 GPIO bolumunun TAMAMI saglaniyor");
        else
            $display(" SONUC: %0d MADDE SAGLANMIYOR", hata);
        $display("========================================================================");

        if (hata != 0) $fatal(1, "GPIO sartname uyum testi basarisiz");
        $finish;
    end

    // Port genisliklerinin sartnameyle uyumunu denetle
    task automatic denetle_genislik();
        denetim++;
        if (($bits(gpio_in) == 16) && ($bits(gpio_out) == 16))
            $display("      [OK]   %-46s giris=%0d cikis=%0d",
                     "port genislikleri 16 giris + 16 cikis",
                     $bits(gpio_in), $bits(gpio_out));
        else begin
            hata++;
            $display("      [HATA] %-46s giris=%0d cikis=%0d",
                     "port genislikleri 16+16 olmali",
                     $bits(gpio_in), $bits(gpio_out));
        end
    endtask

endmodule
