`timescale 1ns/1ps
// =============================================================================
//  tb_gpio_peripheral.sv - GPIO blok seviyesi self-checking testbench
//  TEKNOFEST 2026 - Takim Arkhe
//
//  NEDEN YAZILDI (22 Agustos 2026)
//
//    GPIO'nun HIC blok testi yoktu. Sistem testi yalnizca cikis yazmacini
//    (ODR) kullaniyordu; kapsama olcumunde modul %67,2 statement ile dusuk
//    ciktı. Kesme mekanizmasinin dort modu - yukselen kenar, dusen kenar,
//    seviye-yuksek, seviye-dusuk - hicbir testte calismamisti.
//
//    Sartname EK-2 GPIO icin GPIO_IDR (RO) ve GPIO_ODR yazmaclarini zorunlu
//    tutuyor; tasarim bunlara ek olarak SET/CLEAR/TOGGLE, MODE ve dort
//    kesme modu sunuyor. Zorunlu ikisi sistem testinde dolayli olarak
//    calisiyordu, gerisi hic.
//
//  KAPSAM
//    - Reset degerleri
//    - GPIO_ODR yazma ve pine yansima
//    - SET / CLEAR / TOGGLE yan etkili yazmaclar
//    - GPIO_IDR okuma (iki asamali senkronizator gecikmesiyle)
//    - GPIO_IDR ust 16 bitinin her zaman 0 olmasi (Sartname EK-2)
//    - Kesme: yukselen kenar, dusen kenar, seviye-yuksek, seviye-dusuk
//    - Kesme durum temizleme ve global_interrupt_o
// =============================================================================

module tb_gpio_peripheral;

    // Yazmac ofsetleri
    localparam logic [7:0] GPIO_IDR       = 8'h00;
    localparam logic [7:0] GPIO_ODR       = 8'h04;
    localparam logic [7:0] GPIO_MODE      = 8'h08;
    localparam logic [7:0] GPIO_SET       = 8'h0C;
    localparam logic [7:0] GPIO_CLEAR     = 8'h10;
    localparam logic [7:0] GPIO_TOGGLE    = 8'h14;
    localparam logic [7:0] INTR_RISE_EN   = 8'h18;
    localparam logic [7:0] INTR_FALL_EN   = 8'h1C;
    localparam logic [7:0] INTR_HIGH_EN   = 8'h20;
    localparam logic [7:0] INTR_LOW_EN    = 8'h24;
    localparam logic [7:0] INTR_STATUS    = 8'h28;

    logic clk = 0;
    always #10 clk = ~clk;                    // 50 MHz

    logic        rst_n;
    logic [15:0] gpio_i = 16'h0000;
    logic [15:0] gpio_o;
    logic [15:0] gpio_tx_en_o;
    logic        irq;

    logic [7:0]  awaddr, araddr;
    logic [31:0] wdata, rdata;
    logic [3:0]  wstrb;
    logic        awvalid, wvalid, bready, arvalid, rready;
    logic        awready, wready, bvalid, arready, rvalid;
    logic [1:0]  bresp, rresp;

    gpio_peripheral #(
        .AXI_ADDR_W (8),
        .AXI_DATA_W (32)
    ) dut (
        .clk                (clk),
        .rst_n              (rst_n),
        .gpio_i             (gpio_i),
        .gpio_o             (gpio_o),
        .gpio_tx_en_o       (gpio_tx_en_o),
        .global_interrupt_o (irq),
        .s_axil_awaddr      (awaddr),
        .s_axil_awvalid     (awvalid),
        .s_axil_awready     (awready),
        .s_axil_wdata       (wdata),
        .s_axil_wstrb       (wstrb),
        .s_axil_wvalid      (wvalid),
        .s_axil_wready      (wready),
        .s_axil_bresp       (bresp),
        .s_axil_bvalid      (bvalid),
        .s_axil_bready      (bready),
        .s_axil_araddr      (araddr),
        .s_axil_arvalid     (arvalid),
        .s_axil_arready     (arready),
        .s_axil_rdata       (rdata),
        .s_axil_rresp       (rresp),
        .s_axil_rvalid      (rvalid),
        .s_axil_rready      (rready)
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
            $display("      [OK]   %-36s = 0x%08h", ad, gercek);
        else begin
            hata++;
            $display("      [HATA] %-36s beklenen=0x%08h gercek=0x%08h",
                     ad, beklenen, gercek);
        end
    endtask

    initial begin
        #5_000_000;
        $display(" GPIO TESTI BASARISIZ - zaman asimi");
        $fatal(1, "tb_gpio_peripheral zaman asimi");
    end

    // =========================================================================
    // AXI4-Lite gorevleri
    // =========================================================================
    // DIKKAT: gpio_peripheral okuma kanalinda arready ve rvalid AYNI
    // cevrimde yukselir. Once arready'yi, sonra ayri bir donguyle rvalid'i
    // beklemek pencereyi KACIRIR - rready zaten yuksek oldugu icin rvalid
    // bir cevrim sonra duser ve test asili kalir. Ilk yazimda tam olarak
    // bu oldu. Bu yuzden tek dongude rvalid bekleniyor.
    task automatic axi_write(input logic [7:0] adr, input logic [31:0] dat);
        @(posedge clk);
        awaddr <= adr; awvalid <= 1'b1;
        wdata  <= dat; wvalid  <= 1'b1; wstrb <= 4'hF;
        bready <= 1'b1;
        forever begin
            @(posedge clk);
            if (bvalid) begin
                awvalid <= 1'b0; wvalid <= 1'b0; bready <= 1'b0;
                break;
            end
        end
        @(posedge clk);
    endtask

    task automatic axi_read(input logic [7:0] adr, output logic [31:0] dat);
        @(posedge clk);
        araddr <= adr; arvalid <= 1'b1; rready <= 1'b1;
        forever begin
            @(posedge clk);
            if (rvalid) begin
                dat     = rdata;
                arvalid <= 1'b0;
                rready  <= 1'b0;
                break;
            end
        end
        @(posedge clk);
    endtask

    // Tum kesme kaynaklarini kapat ve durumu temizle
    task automatic kesmeleri_kapat();
        axi_write(INTR_RISE_EN, 32'h0);
        axi_write(INTR_FALL_EN, 32'h0);
        axi_write(INTR_HIGH_EN, 32'h0);
        axi_write(INTR_LOW_EN,  32'h0);
        axi_write(INTR_STATUS,  32'hFFFF);   // yaz-ile-temizle
        repeat (4) @(posedge clk);
    endtask

    logic [31:0] v;

    initial begin
        awvalid = 0; wvalid = 0; bready = 0; arvalid = 0; rready = 0;
        awaddr = 0; araddr = 0; wdata = 0; wstrb = 4'hF;
        rst_n = 0;
        repeat (5) @(posedge clk);
        rst_n = 1;
        repeat (5) @(posedge clk);

        $display("================================================================");
        $display(" GPIO BLOK TESTI - Sartname EK-2");
        $display("================================================================");

        // ---------------------------------------------------------------------
        $display("  -- 1. Reset degerleri");
        axi_read(GPIO_ODR, v); denetle("reset GPIO_ODR", v, 32'h0);
        denetle("reset gpio_o", {16'h0, gpio_o}, 32'h0);
        denetle("reset IRQ", {31'b0, irq}, 32'h0);
        axi_read(INTR_STATUS, v); denetle("reset INTR_STATUS", v, 32'h0);

        // ---------------------------------------------------------------------
        // Sartname: "GPIO_IDR[15:0] bitlerinde 16-bit giris sinyalinin
        // degerini tutar. GPIO_IDR[31:16] bitlerinde her zaman '0'."
        // ---------------------------------------------------------------------
        $display("  -- 2. GPIO_IDR giris okuma");
        gpio_i = 16'h1234;
        repeat (5) @(posedge clk);            // iki asamali senkronizator
        axi_read(GPIO_IDR, v);
        denetle("GPIO_IDR = 0x1234", v, 32'h0000_1234);
        denetle("GPIO_IDR[31:16] her zaman 0", {16'h0, v[31:16]}, 32'h0);

        gpio_i = 16'hA5A5;
        repeat (5) @(posedge clk);
        axi_read(GPIO_IDR, v);
        denetle("GPIO_IDR = 0xA5A5", v, 32'h0000_A5A5);

        // ---------------------------------------------------------------------
        $display("  -- 3. GPIO_ODR ve pin yansimasi");
        axi_write(GPIO_MODE, 32'hFFFF_FFFF);  // hepsi cikis
        axi_write(GPIO_ODR, 32'h0000_BEEF);
        repeat (2) @(posedge clk);
        axi_read(GPIO_ODR, v); denetle("GPIO_ODR geri okuma", v, 32'h0000_BEEF);
        denetle("gpio_o pinlerine yansidi", {16'h0, gpio_o}, 32'h0000_BEEF);

        // ---------------------------------------------------------------------
        $display("  -- 4. SET / CLEAR / TOGGLE");
        axi_write(GPIO_ODR, 32'h0000_0000);
        axi_write(GPIO_SET, 32'h0000_00FF);
        repeat (2) @(posedge clk);
        axi_read(GPIO_ODR, v); denetle("SET sonrasi", v, 32'h0000_00FF);

        axi_write(GPIO_CLEAR, 32'h0000_000F);
        repeat (2) @(posedge clk);
        axi_read(GPIO_ODR, v); denetle("CLEAR sonrasi", v, 32'h0000_00F0);

        axi_write(GPIO_TOGGLE, 32'h0000_FFFF);
        repeat (2) @(posedge clk);
        axi_read(GPIO_ODR, v); denetle("TOGGLE sonrasi", v, 32'h0000_FF0F);

        // ---------------------------------------------------------------------
        // 5. YUKSELEN KENAR KESMESI
        // ---------------------------------------------------------------------
        $display("  -- 5. Yukselen kenar kesmesi");
        gpio_i = 16'h0000;
        repeat (5) @(posedge clk);
        kesmeleri_kapat();
        denetle("temizlik sonrasi IRQ dusuk", {31'b0, irq}, 32'h0);

        axi_write(INTR_RISE_EN, 32'h0000_0001);   // yalnizca pin 0
        repeat (2) @(posedge clk);

        gpio_i[0] = 1'b1;                          // 0 -> 1 kenari
        repeat (6) @(posedge clk);
        axi_read(INTR_STATUS, v);
        denetle("yukselen kenar durumu pin0", v, 32'h0000_0001);
        denetle("yukselen kenar IRQ yuksek", {31'b0, irq}, 32'h1);

        axi_write(INTR_STATUS, 32'h0000_0001);     // yaz-ile-temizle
        repeat (3) @(posedge clk);
        axi_read(INTR_STATUS, v);
        denetle("temizleme sonrasi durum", v, 32'h0);
        denetle("temizleme sonrasi IRQ dustu", {31'b0, irq}, 32'h0);

        // Etkin OLMAYAN pin kesme uretmemeli
        gpio_i[1] = 1'b1;
        repeat (6) @(posedge clk);
        axi_read(INTR_STATUS, v);
        denetle("etkinlestirilmemis pin kesme yok", v, 32'h0);

        // ---------------------------------------------------------------------
        // 6. DUSEN KENAR KESMESI
        // ---------------------------------------------------------------------
        $display("  -- 6. Dusen kenar kesmesi");
        kesmeleri_kapat();
        axi_write(INTR_FALL_EN, 32'h0000_0004);    // pin 2
        gpio_i[2] = 1'b1;
        repeat (6) @(posedge clk);
        axi_read(INTR_STATUS, v);
        denetle("dusen mod: yukselen kenar tetiklemedi", v, 32'h0);

        gpio_i[2] = 1'b0;                          // 1 -> 0 kenari
        repeat (6) @(posedge clk);
        axi_read(INTR_STATUS, v);
        denetle("dusen kenar durumu pin2", v, 32'h0000_0004);
        denetle("dusen kenar IRQ yuksek", {31'b0, irq}, 32'h1);

        // ---------------------------------------------------------------------
        // 7. SEVIYE-YUKSEK KESMESI
        // ---------------------------------------------------------------------
        $display("  -- 7. Seviye-yuksek kesmesi");
        gpio_i = 16'h0000;
        repeat (5) @(posedge clk);
        kesmeleri_kapat();

        axi_write(INTR_HIGH_EN, 32'h0000_0008);    // pin 3
        repeat (3) @(posedge clk);
        axi_read(INTR_STATUS, v);
        denetle("seviye-yuksek: pin dusukken kesme yok", v, 32'h0);

        gpio_i[3] = 1'b1;
        repeat (6) @(posedge clk);
        axi_read(INTR_STATUS, v);
        denetle("seviye-yuksek durumu pin3", v, 32'h0000_0008);
        denetle("seviye-yuksek IRQ yuksek", {31'b0, irq}, 32'h1);

        // ---------------------------------------------------------------------
        // 8. SEVIYE-DUSUK KESMESI
        // ---------------------------------------------------------------------
        $display("  -- 8. Seviye-dusuk kesmesi");
        gpio_i = 16'hFFFF;
        repeat (5) @(posedge clk);
        kesmeleri_kapat();

        axi_write(INTR_LOW_EN, 32'h0000_0010);     // pin 4
        repeat (3) @(posedge clk);
        axi_read(INTR_STATUS, v);
        denetle("seviye-dusuk: pin yuksekken kesme yok", v, 32'h0);

        gpio_i[4] = 1'b0;
        repeat (6) @(posedge clk);
        axi_read(INTR_STATUS, v);
        denetle("seviye-dusuk durumu pin4", v, 32'h0000_0010);
        denetle("seviye-dusuk IRQ yuksek", {31'b0, irq}, 32'h1);

        // ---------------------------------------------------------------------
        // 9. Coklu pin ve global kesme
        // ---------------------------------------------------------------------
        $display("  -- 9. Coklu kaynak");
        gpio_i = 16'h0000;
        repeat (5) @(posedge clk);
        kesmeleri_kapat();

        axi_write(INTR_RISE_EN, 32'h0000_0300);    // pin 8 ve 9
        repeat (2) @(posedge clk);
        gpio_i[9:8] = 2'b11;
        repeat (6) @(posedge clk);
        axi_read(INTR_STATUS, v);
        denetle("iki pin birlikte tetikledi", v, 32'h0000_0300);

        axi_write(INTR_STATUS, 32'h0000_0100);     // yalnizca pin 8 temizle
        repeat (3) @(posedge clk);
        axi_read(INTR_STATUS, v);
        denetle("kismi temizleme, pin9 kaldi", v, 32'h0000_0200);
        denetle("kalan kaynak IRQ'yu yuksek tutuyor", {31'b0, irq}, 32'h1);

        axi_write(INTR_STATUS, 32'h0000_0200);
        repeat (3) @(posedge clk);
        denetle("hepsi temizlenince IRQ dustu", {31'b0, irq}, 32'h0);

        // ---------------------------------------------------------------------
        $display("================================================================");
        if (hata != 0) begin
            $display(" GPIO TESTI BASARISIZ - %0d hata / %0d denetim", hata, denetim);
            $display("================================================================");
            $fatal(1, "GPIO dogrulamasi basarisiz");
        end
        $display(" GPIO TESTI GECTI - %0d denetim, 0 hata", denetim);
        $display("================================================================");
        $finish;
    end

endmodule
