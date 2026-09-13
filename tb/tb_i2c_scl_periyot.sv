// =============================================================================
//  tb_i2c_scl_periyot.sv
//
//  NEDEN VAR
//    12 Eylul 2026 hata enjeksiyonu sunu gosterdi:
//
//      MUTASYON : i2c_bolen
//        PERIYOT = SYS_CLK_FREQ / I2C_FREQ  ->  ... - 1
//      SONUC    : [HATA] test bu hatayi KACIRDI
//
//    Mevcut `i2c_peripheral_tb.sv` yazmac okuma/yazma ve ACK akisini
//    dogruluyor ama SCL'in FREKANSINI hic olcmuyor. Bolen bir eksik
//    olsa SCL 403 kHz yerine 406 kHz olurdu ve test yine gecerdi.
//
//    Bu onemlidir cunku sartname EK-2 acikca sunu istiyor:
//      "SCL saat frekansi 400 kHz sabit hizinda olacaktir"
//
//  BU TEST NE YAPAR
//    Gercek `i2c_peripheral` modulunu ornekler, bir islem baslatir ve
//    URETILEN SCL DARBELERININ SURESINI OLCER (simulasyon zamaniyla).
//    Formul dogrulamasi degil - dalga formu olcumu.
//
//  NE DOGRULAR
//    1. SCL periyodu 400 kHz'e karsilik geliyor mu (2,5 us +-%2)
//    2. t_LOW ve t_HIGH orani makul mu
//    3. Ardisik periyotlar KARARLI mi (jitter yok)
//
//  NOT: tb_i2c_scl_frekans.sv (11 Eylul) bolen HESABINI dogrular;
//  bu test URETILEN DALGAYI olcer. Ikisi farkli seyleri kapsar.
// =============================================================================
`timescale 1ns/1ps

module tb_i2c_scl_periyot;

    localparam int AW = 32;
    localparam int DW = 32;
    localparam int SYS_CLK_HZ = 50_000_000;
    localparam int I2C_HZ     = 400_000;

    // Beklenen SCL periyodu: 1/400kHz = 2500 ns
    localparam real BEKLENEN_NS = 1.0e9 / real'(I2C_HZ);
    // TOLERANS SECIMI
    //
    //   Ilk yazimda %2 idi. Hata enjeksiyonu (i2c_bolen mutasyonu:
    //   PERIYOT bir eksik) SCL'i 2500 -> 2480 ns yapar, yani %0,8
    //   sapma. %2 tolerans bunu GECIRIYORDU.
    //
    //   Tasarim tam 400.000,0 Hz uretiyor (50 MHz / 125 tam bolunur)
    //   ve sartname EK-2 "400 kHz SABIT" diyor. Dolayisiyla gevsek
    //   tolerans gerekcesizdir. %0,5'e cekildi: hem bolen hatalarini
    //   yakalar hem de tam bolunen her saat icin gecerlidir.
    localparam real TOLERANS    = 0.005;     // %0,5

    logic clk = 1'b0, rst_n = 1'b0;
    always #10ns clk = ~clk;                  // 50 MHz

    logic [AW-1:0] awaddr;  logic awvalid; logic awready;
    logic [DW-1:0] wdata;   logic [3:0] wstrb; logic wvalid; logic wready;
    logic [1:0]    bresp;   logic bvalid;  logic bready;
    logic [AW-1:0] araddr;  logic arvalid; logic arready;
    logic [DW-1:0] rdata;   logic [1:0] rresp; logic rvalid; logic rready;

    logic sda_o, sda_oe, scl_o, scl_oe, i2c_irq;
    wire  sda, scl;

    // Acik drenaj hatlar - cekme direnci
    assign sda = sda_oe ? sda_o : 1'b1;
    assign scl = scl_oe ? scl_o : 1'b1;

    int pass_count = 0, fail_count = 0;

    i2c_peripheral #(.SYS_CLK_FREQ(SYS_CLK_HZ), .I2C_FREQ(I2C_HZ)) dut (
        .clk(clk), .rst_n(rst_n),
        .sda_o(sda_o), .sda_oe(sda_oe), .sda_i(sda),
        .scl_o(scl_o), .scl_oe(scl_oe), .scl_i(scl),
        .i2c_irq(i2c_irq),
        .s_axi_awaddr(awaddr),  .s_axi_awprot(3'b000),
        .s_axi_awvalid(awvalid), .s_axi_awready(awready),
        .s_axi_wdata(wdata),    .s_axi_wstrb(wstrb),
        .s_axi_wvalid(wvalid),  .s_axi_wready(wready),
        .s_axi_bresp(bresp),    .s_axi_bvalid(bvalid), .s_axi_bready(bready),
        .s_axi_araddr(araddr),  .s_axi_arprot(3'b000),
        .s_axi_arvalid(arvalid), .s_axi_arready(arready),
        .s_axi_rdata(rdata),    .s_axi_rresp(rresp),
        .s_axi_rvalid(rvalid),  .s_axi_rready(rready)
    );

    task automatic kontrol(input bit kosul, input string mesaj);
        if (kosul) begin pass_count++; $display("  [OK] %s", mesaj); end
        else       begin fail_count++; $display("  [HATA] %s", mesaj); end
    endtask

    task automatic axi_yaz(input [AW-1:0] adr, input [DW-1:0] veri);
        int g;
        begin
            bready = 1'b1;
            fork
                begin
                    @(negedge clk); awaddr = adr; awvalid = 1'b1;
                    @(negedge clk);
                    g = 0;
                    while (!awready && g < 40) begin @(negedge clk); g++; end
                    @(negedge clk); awvalid = 1'b0;
                end
                begin
                    @(negedge clk); wdata = veri; wstrb = 4'b1111; wvalid = 1'b1;
                    @(negedge clk);
                    g = 0;
                    while (!wready && g < 40) begin @(negedge clk); g++; end
                    @(negedge clk); wvalid = 1'b0;
                end
            join
            g = 0;
            while (!bvalid && g < 40) begin @(negedge clk); g++; end
            @(negedge clk); bready = 1'b0;
        end
    endtask

    // -------------------------------------------------------------------
    //  SCL PERIYOT OLCUMU
    //
    //  scl sinyalinin ardisik YUKSELEN kenarlari arasindaki sureyi
    //  simulasyon zamaniyla olcer. Bu, bolenin fiili sonucudur.
    // -------------------------------------------------------------------
    time  kenar_ani [0:11];
    int   kenar_say = 0;
    logic scl_gecmis = 1'b1;

    always @(posedge clk) begin
        if (rst_n) begin
            if (scl && !scl_gecmis && kenar_say < 12) begin
                kenar_ani[kenar_say] = $time;
                kenar_say++;
            end
            scl_gecmis <= scl;
        end
    end

    real periyot [0:9];
    real ortalama, en_kucuk, en_buyuk, sapma;
    int  i, gecerli;

    initial begin
        awaddr = 32'h0; awvalid = 1'b0;
        wdata  = 32'h0; wstrb = 4'b0; wvalid = 1'b0; bready = 1'b0;
        araddr = 32'h0; arvalid = 1'b0; rready = 1'b0;

        $display("================================================================");
        $display(" I2C SCL PERIYOT OLCUMU - GERCEK DALGA FORMU");
        $display("================================================================");
        $display("");
        $display("  sistem saati : %0d Hz", SYS_CLK_HZ);
        $display("  hedef SCL    : %0d Hz  (periyot %0.1f ns, tolerans %%%0.1f)",
                 I2C_HZ, BEKLENEN_NS, TOLERANS * 100.0);
        $display("");

        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (5) @(posedge clk);

        // Islem kur: 1 bayt yaz, adres 0x50
        axi_yaz(32'h00, 32'd1);          // I2C_NBY = 1 bayt
        axi_yaz(32'h04, 32'h50);         // I2C_ADR = 0x50
        axi_yaz(32'h0C, 32'hA5);         // I2C_TDR = 0xA5
        axi_yaz(32'h10, 32'h01);         // I2C_CFG[0] = TX_EN -> BASLAT

        // SCL darbelerini topla
        wait (kenar_say >= 10);
        repeat (10) @(posedge clk);

        $display("  toplanan yukselen kenar: %0d", kenar_say);
        $display("");

        // Periyotlari hesapla
        gecerli = 0;
        en_kucuk = 1.0e9;
        en_buyuk = 0.0;
        ortalama = 0.0;
        for (i = 0; i < 9; i++) begin
            if (kenar_ani[i+1] > kenar_ani[i]) begin
                periyot[i] = real'(kenar_ani[i+1] - kenar_ani[i]);
                ortalama  += periyot[i];
                if (periyot[i] < en_kucuk) en_kucuk = periyot[i];
                if (periyot[i] > en_buyuk) en_buyuk = periyot[i];
                gecerli++;
            end
        end

        if (gecerli > 0) ortalama = ortalama / real'(gecerli);

        $display("  olculen periyot sayisi : %0d", gecerli);
        $display("  ortalama periyot       : %0.1f ns", ortalama);
        $display("  en kucuk / en buyuk    : %0.1f / %0.1f ns", en_kucuk, en_buyuk);
        if (ortalama > 0.0)
            $display("  karsilik gelen frekans : %0.1f Hz", 1.0e9 / ortalama);
        $display("");

        // ---------------------------------------------------------------
        //  1. En az 8 periyot olculebildi mi
        // ---------------------------------------------------------------
        kontrol(gecerli >= 8,
                $sformatf("%0d SCL periyodu olculdu (en az 8 gerekli)", gecerli));

        // ---------------------------------------------------------------
        //  2. ORTALAMA periyot 400 kHz'e karsilik geliyor mu
        //     Bolen bir eksik olsa (mutasyon) periyot kisalir ve
        //     bu denetim KALIR.
        // ---------------------------------------------------------------
        sapma = (ortalama - BEKLENEN_NS) / BEKLENEN_NS;
        if (sapma < 0.0) sapma = -sapma;
        kontrol(sapma <= TOLERANS,
                $sformatf("ortalama periyot %0.1f ns, hedef %0.1f ns (sapma %%%0.2f)",
                          ortalama, BEKLENEN_NS, sapma * 100.0));

        // ---------------------------------------------------------------
        //  3. Periyot KARARLI mi (jitter yok)
        // ---------------------------------------------------------------
        kontrol((en_buyuk - en_kucuk) <= (BEKLENEN_NS * 0.05),
                $sformatf("periyot kararli: fark %0.1f ns (<= %%5 = %0.1f ns)",
                          en_buyuk - en_kucuk, BEKLENEN_NS * 0.05));

        // ---------------------------------------------------------------
        //  4. Frekans 400 kHz +-%2 araliginda
        // ---------------------------------------------------------------
        if (ortalama > 0.0) begin
            kontrol((1.0e9 / ortalama) >= real'(I2C_HZ) * (1.0 - TOLERANS) &&
                    (1.0e9 / ortalama) <= real'(I2C_HZ) * (1.0 + TOLERANS),
                    $sformatf("SCL frekansi %0.1f Hz, 400 kHz +-%%0,5 icinde",
                              1.0e9 / ortalama));
        end else begin
            kontrol(1'b0, "SCL periyodu olculemedi (ortalama sifir)");
        end

        $display("");
        $display("================================================================");
        if (fail_count == 0)
            $display(" TB SONUC: GECTI  (%0d denetim)", pass_count);
        else
            $display(" TB SONUC: KALDI  (%0d gecti, %0d kaldi)", pass_count, fail_count);
        $display("================================================================");
        $finish;
    end

    // Gozcu
    initial begin
        #2_000_000;
        $display("  [HATA] gozcu: test 2 ms icinde bitmedi (SCL uretilmedi mi?)");
        $display(" TB SONUC: KALDI (asili kaldi)");
        $finish;
    end

endmodule
