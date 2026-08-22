`timescale 1ns/1ps
// =============================================================================
//  tb_timer_peripheral.sv - Timer blok seviyesi self-checking testbench
//  TEKNOFEST 2026 - Takim Arkhe
//
//  NEDEN YAZILDI (22 Agustos 2026)
//
//    Dogrulama denetiminde cikti: Timer, 23 RTL modulu icinde HICBIR
//    denetimi olmayan tek moduldu. Sistem testi onu hic kullanmiyordu;
//    npu_hizlanma testi yalnizca ALET olarak kullaniyor, dogrulugunu
//    sinamiyordu.
//
//    Sartname EK-2 Timer'in sekiz yazmacini ayrintili tanimliyor
//    (prescaler, auto-reload, clear, enable, mode, counter, event,
//    event-clear). Hicbiri test edilmiyordu.
//
//  KAPSAM
//    - Reset degerleri
//    - Prescaler bolme orani (PRE = 0, 1, 3)
//    - Yukari ve asagi sayma
//    - Auto-reload ve event uretimi
//    - Kesme cikisi ve temizlenmesi
//    - TIM_CLR davranisi (ENA=1 ve ENA=0 iken)
//    - Salt-okunur yazmaclarin yazmaya direnci
// =============================================================================

module tb_timer_peripheral;

    // Yazmac ofsetleri - Sartname EK-2
    localparam logic [11:0] TIM_PRE = 12'h000;
    localparam logic [11:0] TIM_ARE = 12'h004;
    localparam logic [11:0] TIM_CLR = 12'h008;
    localparam logic [11:0] TIM_ENA = 12'h00C;
    localparam logic [11:0] TIM_MOD = 12'h010;
    localparam logic [11:0] TIM_CNT = 12'h014;
    localparam logic [11:0] TIM_EVN = 12'h018;
    localparam logic [11:0] TIM_EVC = 12'h01C;

    logic clk = 0;
    always #10 clk = ~clk;              // 50 MHz

    logic        rst_n;
    logic [11:0] awaddr, araddr;
    logic [31:0] wdata, rdata;
    logic [3:0]  wstrb;
    logic        awvalid, wvalid, bready, arvalid, rready;
    logic        awready, wready, bvalid, arready, rvalid;
    logic [1:0]  bresp, rresp;
    logic        timer_irq;

    timer_peripheral #(
        .S_AXI_ADDR_WIDTH (12),
        .S_AXI_DATA_WIDTH (32)
    ) dut (
        .s_axi_aclk    (clk),
        .s_axi_aresetn (rst_n),
        .s_axi_awaddr  (awaddr),
        .s_axi_awprot  (3'b000),
        .s_axi_awvalid (awvalid),
        .s_axi_awready (awready),
        .s_axi_wdata   (wdata),
        .s_axi_wstrb   (wstrb),
        .s_axi_wvalid  (wvalid),
        .s_axi_wready  (wready),
        .s_axi_bresp   (bresp),
        .s_axi_bvalid  (bvalid),
        .s_axi_bready  (bready),
        .s_axi_araddr  (araddr),
        .s_axi_arprot  (3'b000),
        .s_axi_arvalid (arvalid),
        .s_axi_arready (arready),
        .s_axi_rdata   (rdata),
        .s_axi_rresp   (rresp),
        .s_axi_rvalid  (rvalid),
        .s_axi_rready  (rready),
        .timer_irq     (timer_irq)
    );

    // =========================================================================
    // Self-checking altyapisi
    // =========================================================================
    int hata = 0;
    int denetim = 0;

    task automatic denetle(input string ad, input logic [31:0] gercek,
                                            input logic [31:0] beklenen);
        denetim++;
        if (gercek === beklenen)
            $display("      [OK]   %-38s = 0x%08h", ad, gercek);
        else begin
            hata++;
            $display("      [HATA] %-38s beklenen=0x%08h gercek=0x%08h",
                     ad, beklenen, gercek);
        end
    endtask

    initial begin
        #10_000_000;
        $display(" TIMER TESTI BASARISIZ - zaman asimi");
        $fatal(1, "tb_timer_peripheral zaman asimi");
    end

    // =========================================================================
    // AXI4-Lite gorevleri
    //
    // Timer'in awready/wready sinyalleri KOMBINATORYALDIR ve iki valid'in
    // birden yuksek olmasini bekler:
    //     assign s_axi_awready = s_axi_awvalid && s_axi_wvalid && !s_axi_bvalid;
    // Bu yuzden AW ve W birlikte surulur.
    // =========================================================================
    task automatic axi_write(input logic [11:0] adr, input logic [31:0] dat);
        @(posedge clk);
        awaddr  <= adr;  awvalid <= 1'b1;
        wdata   <= dat;  wvalid  <= 1'b1;  wstrb <= 4'hF;
        bready  <= 1'b1;
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

    logic [31:0] v, v2;
    int          i;

    initial begin
        awvalid = 0; wvalid = 0; bready = 0; arvalid = 0; rready = 0;
        awaddr = 0; araddr = 0; wdata = 0; wstrb = 4'hF;
        rst_n = 0;
        repeat (5) @(posedge clk);
        rst_n = 1;
        repeat (3) @(posedge clk);

        $display("================================================================");
        $display(" TIMER BLOK TESTI - Sartname EK-2");
        $display("================================================================");

        // ---------------------------------------------------------------------
        // 1. Reset degerleri
        // ---------------------------------------------------------------------
        $display("  -- 1. Reset degerleri");
        axi_read(TIM_PRE, v); denetle("reset TIM_PRE", v, 32'h0);
        axi_read(TIM_ARE, v); denetle("reset TIM_ARE", v, 32'hFFFFFFFF);
        axi_read(TIM_ENA, v); denetle("reset TIM_ENA", v, 32'h0);
        axi_read(TIM_CNT, v); denetle("reset TIM_CNT", v, 32'h0);
        axi_read(TIM_EVN, v); denetle("reset TIM_EVN", v, 32'h0);
        denetle("reset timer_irq", {31'b0, timer_irq}, 32'h0);

        // TIM_CLR ve TIM_EVC yan etkili yazma yazmaclaridir; okunduklarinda
        // 0 donerler (Sartname bu yazmaclar icin okuma degeri tanimlamiyor).
        axi_read(TIM_CLR, v); denetle("TIM_CLR okuma 0 doner", v, 32'h0);
        axi_read(TIM_EVC, v); denetle("TIM_EVC okuma 0 doner", v, 32'h0);

        // ---------------------------------------------------------------------
        // 2. ENA = 0 iken sayac ilerlemez
        // ---------------------------------------------------------------------
        $display("  -- 2. ENA=0 iken sayac durur");
        repeat (30) @(posedge clk);
        axi_read(TIM_CNT, v); denetle("ENA=0 sonrasi TIM_CNT", v, 32'h0);

        // ---------------------------------------------------------------------
        // 3. PRE = 0 -> her sistem saatinde bir artis
        //
        //    Sartname: "TIM_PRE '0' oldugu zaman sayac sistem saat hizinda
        //    artacak/azalacaktir."
        // ---------------------------------------------------------------------
        $display("  -- 3. PRE=0 (her cevrim)");
        axi_write(TIM_PRE, 32'h0);
        axi_write(TIM_ARE, 32'hFFFFFFFF);
        axi_write(TIM_MOD, 32'h1);            // yukari
        axi_write(TIM_CLR, 32'h1);
        axi_write(TIM_ENA, 32'h1);

        axi_read(TIM_CNT, v);
        repeat (20) @(posedge clk);
        axi_read(TIM_CNT, v2);
        // Iki okuma arasinda gecen cevrim sayisi okuma isleminin kendisine
        // de baglidir; kesin sayi yerine ARTIS OLDUGU dogrulanir.
        denetle("PRE=0 sayac ilerledi", (v2 > v) ? 32'h1 : 32'h0, 32'h1);

        // Artis hizini olc: 40 cevrimde en az 30 artmali (PRE=0)
        axi_read(TIM_CNT, v);
        repeat (40) @(posedge clk);
        axi_read(TIM_CNT, v2);
        denetle("PRE=0 hiz (40 cevrimde >=30)",
                ((v2 - v) >= 30) ? 32'h1 : 32'h0, 32'h1);

        // ---------------------------------------------------------------------
        // 4. PRE = 1 -> iki sistem saatinde bir artis
        //
        //    Sartname: "TIM_PRE '1' oldugu zaman sayac sistem saatinin
        //    2 periyodunda 1 degisecektir."
        // ---------------------------------------------------------------------
        $display("  -- 4. PRE=1 (iki cevrimde bir)");
        axi_write(TIM_ENA, 32'h0);
        axi_write(TIM_PRE, 32'h1);
        axi_write(TIM_CLR, 32'h1);
        axi_write(TIM_ENA, 32'h1);

        axi_read(TIM_CNT, v);
        repeat (40) @(posedge clk);
        axi_read(TIM_CNT, v2);
        // 40 cevrim / 2 = ~20 artis; okuma yuku icin pencere birakiliyor
        denetle("PRE=1 hiz (40 cevrimde 15..25 arasi)",
                (((v2 - v) >= 15) && ((v2 - v) <= 25)) ? 32'h1 : 32'h0, 32'h1);

        // ---------------------------------------------------------------------
        // 5. PRE = 3 -> dort sistem saatinde bir artis
        // ---------------------------------------------------------------------
        $display("  -- 5. PRE=3 (dort cevrimde bir)");
        axi_write(TIM_ENA, 32'h0);
        axi_write(TIM_PRE, 32'h3);
        axi_write(TIM_CLR, 32'h1);
        axi_write(TIM_ENA, 32'h1);

        axi_read(TIM_CNT, v);
        repeat (80) @(posedge clk);
        axi_read(TIM_CNT, v2);
        denetle("PRE=3 hiz (80 cevrimde 15..25 arasi)",
                (((v2 - v) >= 15) && ((v2 - v) <= 25)) ? 32'h1 : 32'h0, 32'h1);

        // ---------------------------------------------------------------------
        // 6. TIM_CLR sayaci sifirlar (ENA = 1 iken)
        // ---------------------------------------------------------------------
        $display("  -- 6. TIM_CLR");
        axi_write(TIM_ENA, 32'h0);
        axi_write(TIM_PRE, 32'h0);
        axi_write(TIM_ENA, 32'h1);
        repeat (50) @(posedge clk);
        axi_read(TIM_CNT, v);
        denetle("temizleme oncesi sayac > 0", (v > 0) ? 32'h1 : 32'h0, 32'h1);
        axi_write(TIM_CLR, 32'h1);
        axi_read(TIM_CNT, v);
        // Temizlemeden sonra bir kac cevrim gecer; kucuk bir deger olmali
        denetle("TIM_CLR sonrasi sayac kucuk", (v < 32'd20) ? 32'h1 : 32'h0, 32'h1);

        // ---------------------------------------------------------------------
        // 7. ENA = 0 iken TIM_CLR calisir
        //
        //    Sartname: "TIM_EN '0' iken TIM_CLR '1' ise sayac registeri
        //    sifirlanacaktir."
        // ---------------------------------------------------------------------
        $display("  -- 7. ENA=0 iken TIM_CLR");
        axi_write(TIM_ENA, 32'h1);
        repeat (40) @(posedge clk);
        axi_write(TIM_ENA, 32'h0);
        axi_read(TIM_CNT, v);
        denetle("ENA=0 oncesi sayac > 0", (v > 0) ? 32'h1 : 32'h0, 32'h1);
        axi_write(TIM_CLR, 32'h1);
        axi_read(TIM_CNT, v);
        denetle("ENA=0 iken TIM_CLR sifirladi", v, 32'h0);

        // Durdurulmus sayac degerini korur
        repeat (30) @(posedge clk);
        axi_read(TIM_CNT, v);
        denetle("ENA=0 sayac degerini korur", v, 32'h0);

        // ---------------------------------------------------------------------
        // 8. Auto-reload, event ve kesme  (yukari sayma)
        //
        //    Sartname: "Sayac registeri (TIM_CNT), TIM_AR degerine geldiginde
        //    0 degerini alacaktir" ve "TIM_CNT registeri, TIM_ARE degerine
        //    her ulastiginda [TIM_EVN] 1 artacaktir."
        // ---------------------------------------------------------------------
        $display("  -- 8. Auto-reload + event + IRQ (yukari)");
        axi_write(TIM_ENA, 32'h0);
        axi_write(TIM_PRE, 32'h0);
        axi_write(TIM_ARE, 32'd9);           // 0..9 -> 10 cevrimde bir olay
        axi_write(TIM_MOD, 32'h1);
        axi_write(TIM_CLR, 32'h1);
        axi_write(TIM_EVC, 32'h1);
        denetle("baslangicta IRQ dusuk", {31'b0, timer_irq}, 32'h0);

        axi_write(TIM_ENA, 32'h1);
        repeat (100) @(posedge clk);         // ~10 olay
        axi_write(TIM_ENA, 32'h0);

        axi_read(TIM_CNT, v);
        denetle("sayac ARE'yi asmadi (<=9)", (v <= 32'd9) ? 32'h1 : 32'h0, 32'h1);

        axi_read(TIM_EVN, v);
        denetle("event sayaci arttı (>0)", (v > 0) ? 32'h1 : 32'h0, 32'h1);
        denetle("event ~10 civari (5..15)",
                ((v >= 5) && (v <= 15)) ? 32'h1 : 32'h0, 32'h1);
        denetle("EVN>0 iken IRQ yuksek", {31'b0, timer_irq}, 32'h1);

        // ---------------------------------------------------------------------
        // 9. TIM_EVC event'i ve kesmeyi temizler
        // ---------------------------------------------------------------------
        $display("  -- 9. TIM_EVC");
        axi_write(TIM_EVC, 32'h1);
        axi_read(TIM_EVN, v);
        denetle("TIM_EVC sonrasi TIM_EVN", v, 32'h0);
        denetle("TIM_EVC sonrasi IRQ dustu", {31'b0, timer_irq}, 32'h0);

        // ---------------------------------------------------------------------
        // 10. Asagi sayma
        //
        //     Sartname: "TIM_MOD[0] biti '1' ise yukari dogru, '0' ise
        //     asagi dogru sayacaktir."
        // ---------------------------------------------------------------------
        $display("  -- 10. Asagi sayma");
        axi_write(TIM_ARE, 32'd20);
        axi_write(TIM_MOD, 32'h0);           // asagi
        axi_write(TIM_CLR, 32'h1);           // CNT = 0
        axi_write(TIM_EVC, 32'h1);
        axi_write(TIM_ENA, 32'h1);

        // CNT=0'dan asagi -> ARE'ye yuklenir ve event uretir
        repeat (10) @(posedge clk);
        axi_write(TIM_ENA, 32'h0);
        axi_read(TIM_EVN, v);
        denetle("asagi sayma event uretti", (v > 0) ? 32'h1 : 32'h0, 32'h1);

        axi_read(TIM_CNT, v);
        denetle("asagi sayma sayaci ARE icinde", (v <= 32'd20) ? 32'h1 : 32'h0, 32'h1);

        // Gercekten AZALDIGINI dogrula.
        //
        // DIKKAT: olcume baslamadan once sayacin YENIDEN YUKLENMIS olmasi
        // gerekir. Asagi modda CNT sifira dusunce ARE'ye yuklenir; kucuk bir
        // CNT degerinden olcume baslanirsa ikinci okuma yeniden yuklenmis
        // (cok buyuk) degeri yakalar ve "azalmiyor" gibi gorunur. Ilk
        // yazimda test tam bu yuzden dusmustu - RTL dogruydu.
        axi_write(TIM_ENA, 32'h0);
        axi_write(TIM_ARE, 32'hFFFFFFFF);
        axi_write(TIM_CLR, 32'h1);            // CNT = 0
        axi_write(TIM_EVC, 32'h1);
        axi_write(TIM_ENA, 32'h1);
        repeat (5) @(posedge clk);            // CNT 0 -> ARE yuklemesi olsun
        axi_read(TIM_CNT, v);
        denetle("asagi modda ARE'ye yuklendi",
                (v > 32'hFFFF0000) ? 32'h1 : 32'h0, 32'h1);
        repeat (30) @(posedge clk);
        axi_read(TIM_CNT, v2);
        denetle("asagi modda sayac azaliyor", (v2 < v) ? 32'h1 : 32'h0, 32'h1);
        axi_write(TIM_ENA, 32'h0);

        // ---------------------------------------------------------------------
        // 11. Salt-okunur yazmaclar yazmaya direnmeli
        //
        //     Sartname: TIM_CNT ve TIM_EVN "RO" olarak isaretlidir.
        // ---------------------------------------------------------------------
        $display("  -- 11. RO yazmaclar");
        axi_write(TIM_CLR, 32'h1);
        axi_write(TIM_CNT, 32'hDEADBEEF);
        axi_read(TIM_CNT, v);
        denetle("TIM_CNT yazmaya direnir", v, 32'h0);

        // EVN once temizlenmeli: onceki bolumlerdeki sayma zaten olay
        // uretmis olabilir. Ilk yazimda bu atlanmisti ve test dusmustu -
        // RTL yazmayi dogru sekilde reddediyordu.
        axi_write(TIM_EVC, 32'h1);
        axi_read(TIM_EVN, v);
        denetle("RO denetimi oncesi TIM_EVN temiz", v, 32'h0);
        axi_write(TIM_EVN, 32'hDEADBEEF);
        axi_read(TIM_EVN, v);
        denetle("TIM_EVN yazmaya direnir", v, 32'h0);

        // ---------------------------------------------------------------------
        // 12. Yazmaclar geri okunabiliyor
        // ---------------------------------------------------------------------
        $display("  -- 12. Yazmac geri okuma");
        axi_write(TIM_PRE, 32'h0000_1234);
        axi_read(TIM_PRE, v); denetle("TIM_PRE geri okuma", v, 32'h0000_1234);
        axi_write(TIM_ARE, 32'hCAFE_0001);
        axi_read(TIM_ARE, v); denetle("TIM_ARE geri okuma", v, 32'hCAFE_0001);
        axi_write(TIM_MOD, 32'h1);
        axi_read(TIM_MOD, v); denetle("TIM_MOD geri okuma", v, 32'h1);
        axi_write(TIM_ENA, 32'h1);
        axi_read(TIM_ENA, v); denetle("TIM_ENA geri okuma", v, 32'h1);
        axi_write(TIM_ENA, 32'h0);

        // ---------------------------------------------------------------------
        // Ozet
        // ---------------------------------------------------------------------
        $display("================================================================");
        if (hata != 0) begin
            $display(" TIMER TESTI BASARISIZ - %0d hata / %0d denetim", hata, denetim);
            $display("================================================================");
            $fatal(1, "Timer dogrulamasi basarisiz");
        end
        $display(" TIMER TESTI GECTI - %0d denetim, 0 hata", denetim);
        $display("================================================================");
        $finish;
    end

endmodule
