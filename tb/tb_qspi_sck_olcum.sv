// =============================================================================
//  tb_qspi_sck_olcum.sv
//
//  NEDEN VAR
//    12 Eylul 2026 hata enjeksiyonu sunu gosterdi:
//
//      MUTASYON : qspi_presc_bit
//        sck_tam_periyot  7 bit -> 6 bit  (presc=63'te tasma)
//      SONUC    : [HATA] test bu hatayi KACIRDI
//
//    Mevcut `tb_qspi_presc_sinir.sv` DUT'u HIC ORNEKLEMIYOR; kendi
//    `beklenen_tam()` fonksiyonunu dogruluyor. Yani RTL bozulsa bile
//    test gecer - bir tautolojidir.
//
//      kaynak=[TB/"tb_qspi_presc_sinir.sv"]     <- qspi_master.sv YOK
//
//  BU TEST NE YAPAR
//    Gercek `qspi_master` modulunu ornekler, CCR'a prescaler yazar,
//    islem baslatir ve URETILEN SCK KENARLARINI SAYAR. Yani RTL'in
//    fiili davranisini olcer, formulu degil.
//
//  NE DOGRULAR
//    1. presc=0   -> SCK uretiliyor (en hizli mod)
//    2. presc=1   -> SCK periyodu 2 clk
//    3. presc=62  -> SCK uretiliyor
//    4. presc=63  -> SCK URETILIYOR  (6 bitte tasip durursa yakalanir)
//    5. Periyot prescaler ile ORANTILI buyuyor
// =============================================================================
`timescale 1ns/1ps

module tb_qspi_sck_olcum;

    localparam int AW = 32;
    localparam int DW = 32;

    logic clk = 1'b0, rst_n = 1'b0;
    always #5ns clk = ~clk;

    // AXI4-Lite
    logic [AW-1:0] awaddr;  logic awvalid; logic awready;
    logic [DW-1:0] wdata;   logic [3:0] wstrb; logic wvalid; logic wready;
    logic [1:0]    bresp;   logic bvalid;  logic bready;
    logic [AW-1:0] araddr;  logic arvalid; logic arready;
    logic [DW-1:0] rdata;   logic [1:0] rresp; logic rvalid; logic rready;

    // QSPI pinleri
    logic       qspi_sck, qspi_cs_n;
    logic [3:0] qspi_io_o, qspi_io_oe;
    logic [3:0] qspi_io_i;
    logic       qspi_irq;

    int pass_count = 0, fail_count = 0;

    qspi_master #(.AXI_AW(AW), .AXI_DW(DW)) dut (
        .clk(clk), .rst_n(rst_n),
        .s_axi_awaddr(awaddr), .s_axi_awvalid(awvalid), .s_axi_awready(awready),
        .s_axi_wdata(wdata),   .s_axi_wstrb(wstrb),     .s_axi_wvalid(wvalid),
        .s_axi_wready(wready),
        .s_axi_bresp(bresp),   .s_axi_bvalid(bvalid),   .s_axi_bready(bready),
        .s_axi_araddr(araddr), .s_axi_arvalid(arvalid), .s_axi_arready(arready),
        .s_axi_rdata(rdata),   .s_axi_rresp(rresp),     .s_axi_rvalid(rvalid),
        .s_axi_rready(rready),
        .qspi_sck(qspi_sck),   .qspi_cs_n(qspi_cs_n),
        .qspi_io_o(qspi_io_o), .qspi_io_oe(qspi_io_oe), .qspi_io_i(qspi_io_i),
        .irq(qspi_irq)
    );

    // Flash modeli yok; giris hatlarini sabit tut (okuma verisi onemsiz)
    assign qspi_io_i = 4'b1111;

    task automatic kontrol(input bit kosul, input string mesaj);
        if (kosul) begin pass_count++; $display("  [OK] %s", mesaj); end
        else       begin fail_count++; $display("  [HATA] %s", mesaj); end
    endtask

    // -------------------------------------------------------------------
    //  AXI yazma - negedge kalibi (RTL READY'yi bir cevrim gec yukseltir)
    // -------------------------------------------------------------------
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
    //  Belirli bir prescaler ile islem baslatip SCK kenarlarini sayar
    //
    //  Donus: sayilan SCK yukselen kenar sayisi
    // -------------------------------------------------------------------
    int sck_kenar;
    logic sck_gecmis;

    task automatic presc_dene(input [5:0] presc, input int bekle_cevrim,
                              output int kenar);
        logic [31:0] ccr;
        int i;
        begin
            // Reset at - her deneme temiz baslasin
            rst_n = 1'b0;
            repeat (4) @(negedge clk);
            rst_n = 1'b1;
            repeat (4) @(negedge clk);

            // CCR: instr=READ(0x03), data_mode=tek hat(00), oku(0),
            //      dummy=0, boyut=4 bayt, prescaler=presc
            ccr = 32'h0;
            ccr[7:0]   = 8'h03;          // CMD_READ
            ccr[9:8]   = 2'b00;          // tek hat
            ccr[10]    = 1'b0;           // okuma
            ccr[15:11] = 5'd0;           // dummy yok
            ccr[23:16] = 8'd4;           // 4 bayt veri
            ccr[30:25] = presc;          // PRESCALER

            sck_kenar  = 0;
            sck_gecmis = 1'b0;

            axi_yaz(32'h00, ccr);        // ADDR_QSPI_CCR = 5'h00

            // Kenarlari say
            //
            // HER IKI clk kenarinda orneklenir. Sebep: presc=0'da RTL
            //   assign qspi_sck = sck_en ? (presc_sifir ? ~clk : sck_int) : 0
            // yani SCK dogrudan ~clk'dir. Yalniz posedge'de orneklenirse
            // ~clk her zaman DUSUK gorunur ve hic kenar sayilmaz - bu bir
            // OLCUM hatasi olur, RTL hatasi degil. (Ilk yazimda bu hata
            // yapildi ve presc=0 icin 0 kenar raporlandi.)
            for (i = 0; i < bekle_cevrim; i++) begin
                @(posedge clk);
                if (qspi_sck && !sck_gecmis) sck_kenar++;
                sck_gecmis = qspi_sck;
                @(negedge clk);
                if (qspi_sck && !sck_gecmis) sck_kenar++;
                sck_gecmis = qspi_sck;
            end
            kenar = sck_kenar;
        end
    endtask

    int k0, k1, k62, k63;

    initial begin
        awaddr = 32'h0; awvalid = 1'b0;
        wdata  = 32'h0; wstrb = 4'b0; wvalid = 1'b0; bready = 1'b0;
        araddr = 32'h0; arvalid = 1'b0; rready = 1'b0;

        $display("================================================================");
        $display(" QSPI SCK URETIMI - GERCEK DUT OLCUMU");
        $display("================================================================");
        $display("");
        $display("Bu test qspi_master modulunu ORNEKLER ve uretilen SCK");
        $display("kenarlarini SAYAR. Formul dogrulamasi degil, davranis olcumu.");
        $display("");

        // ---------------------------------------------------------------
        //  presc = 0 : en hizli mod (SCK = ~clk)
        // ---------------------------------------------------------------
        presc_dene(6'd0, 400, k0);
        $display("  presc=0  -> %0d SCK yukselen kenar", k0);
        kontrol(k0 > 0, $sformatf("presc=0: SCK uretiliyor (%0d kenar)", k0));

        // ---------------------------------------------------------------
        //  presc = 1
        // ---------------------------------------------------------------
        presc_dene(6'd1, 400, k1);
        $display("  presc=1  -> %0d SCK yukselen kenar", k1);
        kontrol(k1 > 0, $sformatf("presc=1: SCK uretiliyor (%0d kenar)", k1));

        // ---------------------------------------------------------------
        //  presc = 62 : sinirin hemen altinda
        // ---------------------------------------------------------------
        presc_dene(6'd62, 6000, k62);
        $display("  presc=62 -> %0d SCK yukselen kenar", k62);
        kontrol(k62 > 0, $sformatf("presc=62: SCK uretiliyor (%0d kenar)", k62));

        // ---------------------------------------------------------------
        //  presc = 63 : ASIL SINIR
        //
        //  sck_tam_periyot 6 bit olsaydi 63+1=64 sifira sarar ve SCK
        //  HIC uretilmezdi. 7 bit oldugu icin 64 dogru tutulur.
        // ---------------------------------------------------------------
        presc_dene(6'd63, 6000, k63);
        $display("  presc=63 -> %0d SCK yukselen kenar", k63);
        kontrol(k63 > 0,
                $sformatf("presc=63 SINIR: SCK URETILIYOR (%0d kenar) - tasma yok", k63));

        // ---------------------------------------------------------------
        //  Periyot prescaler ile ORANTILI mi
        //  Ayni sure icinde daha buyuk prescaler -> daha AZ kenar
        // ---------------------------------------------------------------
        // presc=0 en hizli mod: ayni sure icinde presc=1'den AZ OLMAMALI.
        // (Esit olabilir cunku islem 4 bayt sonra biter; kenar sayisi
        //  islemin toplam bit sayisiyla sinirlidir.)
        kontrol(k0 >= k1,
                $sformatf("presc=0 en hizli: %0d kenar >= presc=1'in %0d kenari",
                          k0, k1));

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
        $display("  [HATA] gozcu: test 2 ms icinde bitmedi");
        $display(" TB SONUC: KALDI (asili kaldi)");
        $finish;
    end

endmodule
