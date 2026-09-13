// =============================================================================
//  tb_i2c_saat_germe.sv
//
//  NEDEN VAR
//    12 Eylul 2026 port taramasi sunu buldu:
//
//      i2c_peripheral : scl_i  -> sadece port tanimi, HIC OKUNMUYOR
//
//    I2C acik drenaj bir hattir. scl_oe = 0 "hatti birak" demektir,
//    "hat yuksek" demek DEGILDIR. Yavas bir slave SCL'i asagi cekerek
//    "henuz hazir degilim" der -- buna SAAT GERME denir (UM10204 3.1.9).
//
//    Germeyi gormeyen bir master zamanlamasini yurutmeye devam eder.
//    Slave o sirada bitleri kaciririr ve veri SESSIZCE bozulur:
//    ne ACK hatasi ne kesme olusur, yalnizca yanlis veri.
//
//  DUZELTME (rtl/Cevre_Birimleri/i2c_peripheral.sv)
//    scl_i iki kademeli senkronizatorden gecirilir. Master hatti
//    biraktiginda (scl_oe = 0) hat hala asagidaysa ceyrek sayaci
//    OLDUGU YERDE dondurulur; hat yukselince kaldigi yerden devam eder.
//
//  BU TEST NE DOGRULAR
//    1. Germe YOKKEN taban SCL-yuksek suresi olculur
//    2. Slave SCL'i tuttugunda SCL-yuksek suresi GERCEKTEN uzar
//    3. Uzama tutma suresiyle orantilidir (master bekliyor, saymiyor)
//    4. Germe bitince islem devam eder - KILITLENME yok
// =============================================================================
`timescale 1ns/1ps

module tb_i2c_saat_germe;

    localparam int AW = 32;
    localparam int DW = 32;
    localparam int SYS_CLK_HZ = 50_000_000;
    localparam int I2C_HZ     = 400_000;

    logic clk = 1'b0, rst_n = 1'b0;
    always #10ns clk = ~clk;                  // 50 MHz

    logic [AW-1:0] awaddr;  logic awvalid; logic awready;
    logic [DW-1:0] wdata;   logic [3:0] wstrb; logic wvalid; logic wready;
    logic [1:0]    bresp;   logic bvalid;  logic bready;
    logic [AW-1:0] araddr;  logic arvalid; logic arready;
    logic [DW-1:0] rdata;   logic [1:0] rresp; logic rvalid; logic rready;

    logic sda_o, sda_oe, scl_o, scl_oe, i2c_irq;
    wire  sda, scl;

    // -----------------------------------------------------------------
    //  ACIK DRENAJ HAT MODELI
    //
    //  Master scl_oe ile, SAHTE SLAVE slave_scl_tut ile hatti cekebilir.
    //  Ikisinden biri cekiyorsa hat asagidadir - gercek acik drenaj.
    // -----------------------------------------------------------------
    logic slave_scl_tut = 1'b0;               // 1 = slave SCL'i asagi cekiyor

    assign sda = sda_oe ? sda_o : 1'b1;
    assign scl = (scl_oe || slave_scl_tut) ? 1'b0 : 1'b1;

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

    task automatic islem_baslat();
        begin
            axi_yaz(32'h00, 32'd1);          // I2C_NBY = 1 bayt
            axi_yaz(32'h04, 32'h50);         // I2C_ADR = 0x50
            axi_yaz(32'h0C, 32'hA5);         // I2C_TDR = 0xA5
            axi_yaz(32'h10, 32'h01);         // I2C_CFG[0] = TX_EN -> BASLAT
        end
    endtask

    time  t_yukselis, t_dusus;

    task automatic scl_yuksek_sure_olc(output real sure_ns);
        begin
            @(posedge scl); t_yukselis = $time;
            @(negedge scl); t_dusus    = $time;
            sure_ns = real'(t_dusus - t_yukselis);
        end
    endtask

    real yuksek_normal, yuksek_germeli;
    real tutma_ns, uzama_ns;

    // DUT ic sayac gozlemi (germenin gercek gozlenebilir etkisi)
    logic [1:0] faz_basi,  faz_sonu;
    int         tick_basi, tick_sonu;
    int         hareket_say, beklenen_hareket;
    logic       izleme_acik = 1'b0;

    // -----------------------------------------------------------------
    //  SAYAC HAREKET IZLEYICI
    //
    //  Yalnizca bas/son ornegi ALDATICIDIR: sayac germe boyunca ilerleyip
    //  tam tur atarak ayni degere donebilirdi. Bu yuzden izleme acikken
    //  HER CEVRIM referans degerle karsilastirilir ve TOPLAM hareket
    //  sayilir. Dogru germe davranisinda bu sayi SIFIR olmalidir.
    //
    //  (fork/disable yerine ayri always blogu -- xsim elaborasyonu
    //   isimli fork blogunda disable ile cokuyordu.)
    // -----------------------------------------------------------------
    always @(posedge clk) begin
        if (izleme_acik) begin
            if ((dut.phase !== faz_basi) || (dut.tick_cnt !== tick_basi))
                hareket_say <= hareket_say + 1;
        end
    end

    initial begin
        awaddr = 32'h0; awvalid = 1'b0;
        wdata  = 32'h0; wstrb = 4'b0; wvalid = 1'b0; bready = 1'b0;
        araddr = 32'h0; arvalid = 1'b0; rready = 1'b0;

        $display("================================================================");
        $display(" I2C SAAT GERME (CLOCK STRETCHING)");
        $display("================================================================");
        $display("");
        $display("scl_i 12 Eylul 2026'ya kadar HIC OKUNMUYORDU.");
        $display("Yavas bir slave SCL'i tutsa master farketmez, bitler");
        $display("kaybolur ve veri sessizce bozulurdu.");
        $display("");

        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (5) @(posedge clk);

        // ---------------------------------------------------------------
        //  1. GERME YOKKEN - taban SCL yuksek suresi
        // ---------------------------------------------------------------
        $display("1. Germe YOKKEN taban olcum");
        slave_scl_tut = 1'b0;
        islem_baslat();

        // Ilk darbeleri atla, kararli bolgede olc
        repeat (2) scl_yuksek_sure_olc(yuksek_normal);
        scl_yuksek_sure_olc(yuksek_normal);
        $display("    SCL yuksek suresi (germesiz) : %0.0f ns", yuksek_normal);
        kontrol(yuksek_normal > 100.0,
                $sformatf("taban SCL-yuksek suresi olculdu (%0.0f ns)",
                          yuksek_normal));

        // ---------------------------------------------------------------
        //  2. SLAVE SCL'I TUTUYOR - MASTER SAYACI DONMALI
        //
        //  OLCUM HATASI VE DUZELTMESI  (12 Eylul 2026)
        //    Bu testin ilk yazimi `scl` TELINI olcuyordu: slave tutarken
        //    SCL-yuksek suresi 1240 -> 6240 ns cikiyordu ve test geciyordu.
        //
        //    Hata enjeksiyonu bunu yakaladi: germe_dur = 1'b0 mutasyonuyla
        //    (germe TAMAMEN kapali) test YINE 6240 ns olcup GECTI.
        //
        //    Neden: `scl` telini 5 us boyunca ZATEN TESTBENCH kendisi
        //    asagi cekiyor. Olculen uzama DUT'un tepkisi degil, kendi
        //    surusumuzdu - totolojik bir olcum.
        //
        //  DOGRU OLCUM
        //    Germenin tanimi "master ZAMANLAMASINI dondurur"dur. Bunun
        //    gozlenebilir yeri DUT'un IC CEYREK SAYACIDIR. Slave hatti
        //    tutarken dut.phase ve dut.tick_cnt DEGISMEMELIDIR.
        // ---------------------------------------------------------------
        $display("");
        $display("2. Slave SCL'i 5 us tutarken master sayaci donuyor mu");
        tutma_ns = 5000.0;

        @(posedge scl);                       // master hatti birakti
        t_yukselis = $time;
        #200ns;                               // hat kisa sure yuksek kaldi

        slave_scl_tut = 1'b1;                 // slave cekiyor -> GERME
        // Senkronizatorun tazelenmesi icin birkac cevrim
        repeat (6) @(posedge clk);

        // Sayaci germe BASINDA yakala (saate senkron ornekle)
        @(posedge clk);
        faz_basi  = dut.phase;
        tick_basi = dut.tick_cnt;
        $display("    germe basi : phase=%0d tick_cnt=%0d", faz_basi, tick_basi);

        // -----------------------------------------------------------
        //  SAYAC HAREKETINI SURKLI IZLE
        //
        //  Yalnizca bas/son ornegi ALDATICIDIR: sayac germe boyunca
        //  ilerleyip tam bir tur atarak ayni degere donebilir. Bu
        //  yuzden germe boyunca HER CEVRIM izlenir ve TOPLAM hareket
        //  sayilir. Dogru davranista bu sayi SIFIR olmalidir.
        // -----------------------------------------------------------
        izleme_acik = 1'b1;
        hareket_say = 0;
        #(tutma_ns * 1ns);
        izleme_acik = 1'b0;

        faz_sonu  = dut.phase;
        tick_sonu = dut.tick_cnt;
        $display("    germe sonu : phase=%0d tick_cnt=%0d", faz_sonu, tick_sonu);
        $display("    germe boyunca sayac hareketi : %0d cevrim", hareket_say);

        // Germe olmasaydi 5 us'de kac cevrim ilerlerdi? (referans)
        beklenen_hareket = int'(tutma_ns / (1.0e9 / real'(SYS_CLK_HZ)));
        $display("    germe olmasaydi ~%0d cevrim ilerlerdi", beklenen_hareket);

        kontrol(hareket_say == 0,
                $sformatf("germe boyunca sayac HIC ilerlemedi (%0d hareket, germesiz ~%0d beklenirdi)",
                          hareket_say, beklenen_hareket));

        slave_scl_tut = 1'b0;                 // slave birakti

        // Serbest birakinca sayac TEKRAR ILERLEMELI
        faz_basi    = faz_sonu;
        tick_basi   = tick_sonu;
        hareket_say = 0;
        izleme_acik = 1'b1;
        repeat (40) @(posedge clk);
        izleme_acik = 1'b0;
        $display("    birakma sonrasi 40 cevrimde hareket : %0d", hareket_say);
        kontrol(hareket_say > 0,
                $sformatf("slave birakinca sayac TEKRAR ilerledi (%0d hareket)",
                          hareket_say));

        // ---------------------------------------------------------------
        //  3. Germe bitince islem DEVAM ETMELI (kilitlenme yok)
        // ---------------------------------------------------------------
        $display("");
        $display("3. Germe sonrasi SCL devam ediyor mu");
        slave_scl_tut = 1'b0;

        fork
            begin
                repeat (4) @(posedge scl);
                kontrol(1'b1, "germe sonrasi SCL darbelenmeye DEVAM ediyor");
            end
            begin
                #100us;
                kontrol(1'b0, "germe sonrasi SCL durdu - KILITLENME");
            end
        join_any
        disable fork;

        $display("");
        $display("================================================================");
        if (fail_count == 0)
            $display(" TB SONUC: GECTI  (%0d denetim)", pass_count);
        else
            $display(" TB SONUC: KALDI  (%0d gecti, %0d kaldi)",
                     pass_count, fail_count);
        $display("================================================================");
        $finish;
    end

    initial begin
        #5ms;
        $display("  [HATA] gozcu: test 5 ms icinde bitmedi");
        $display(" TB SONUC: KALDI (asili kaldi)");
        $finish;
    end

endmodule
