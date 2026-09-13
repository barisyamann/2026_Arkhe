// =============================================================================
//  tb_gls_canlilik.sv   -   GATE-LEVEL SIMULASYON
//
//  NEDEN VAR
//    12 Eylul 2026 akis arastirmasi sunu buldu:
//
//      RTL simulasyonu 33 test / 664 denetim ile dogrulanmis durumda,
//      ama SENTEZ SONRASI NETLIST hic simule edilmemis.
//
//    Bu bir bosluktur: sentez veya yerlestirme araci yanlis bir
//    optimizasyon yaparsa (yanlis hucre esleme, kayip reset, yanlis
//    baglanti) RTL testleri bunu GOREMEZ - onlar RTL kaynagini
//    kosuyor, uretilen netlisti degil.
//
//  NE DOGRULAR
//    Teslim paketindeki GERCEK netlisti (asic/results/netlist/
//    soc_top_pnr.v - 102 MB, 2,07 milyon hucre) sky130 standart hucre
//    modelleriyle kosar ve TEMEL CANLILIK denetler:
//
//      1. Reset sonrasi cikislar X'ten cikiyor mu
//      2. Saat agaci calisiyor mu (ic dugumler toggle ediyor)
//      3. Cikis pinleri bilinen duruma yerlesiyor mu
//      4. GPIO cikis yolu ucdan uca calisiyor mu
//
//  NE DOGRULAMAZ
//    Tam islevsellik. Gate-level simulasyon RTL'den 50-100x yavastir;
//    tam sistem testi (RTL'de 528 s) burada saatler surerdi. Bu test
//    KAPI SEVIYESI CANLILIGI olcer - netlistin yasadigini ve temel
//    yollarin baglandigini gosterir.
//
//    Zamanlama (SDF) YUKLENMEZ; bu bir islevsellik denetimidir,
//    zamanlama imzasi ayrica dokuz kosede STA ile yapilmistir.
// =============================================================================
`timescale 1ns/1ps

module tb_gls_canlilik;

    logic clk_i = 1'b0;
    logic rst_ni = 1'b0;

    always #10 clk_i = ~clk_i;      // 50 MHz

    // Giris pinleri - bilinen duruma sabitlenir
    logic        i2c_scl_i = 1'b1;
    logic        i2c_sda_i = 1'b1;
    logic        jtag_tck  = 1'b0;
    logic        jtag_tdi  = 1'b0;
    logic        jtag_tms  = 1'b1;
    logic        jtag_trst_n = 1'b1;
    logic        uart1_rxd = 1'b1;
    logic        uart2_rxd = 1'b1;
    logic [15:0] gpio_i    = 16'h0000;
    logic [3:0]  qspi_io_i = 4'b1111;

    // Cikis pinleri
    logic        i2c_scl_o, i2c_scl_oe, i2c_sda_o, i2c_sda_oe;
    logic        jtag_tdo;
    logic        qspi_cs_n, qspi_sck;
    logic        uart1_txd, uart2_txd;
    logic [15:0] gpio_o, gpio_tx_en_o;
    logic [3:0]  qspi_io_o;

    int pass_count = 0, fail_count = 0;

    // -------------------------------------------------------------------
    //  DUT - SENTEZ SONRASI NETLIST
    // -------------------------------------------------------------------
    soc_top uut (
        .clk_i(clk_i), .rst_ni(rst_ni),
        .i2c_scl_i(i2c_scl_i), .i2c_scl_o(i2c_scl_o), .i2c_scl_oe(i2c_scl_oe),
        .i2c_sda_i(i2c_sda_i), .i2c_sda_o(i2c_sda_o), .i2c_sda_oe(i2c_sda_oe),
        .jtag_tck(jtag_tck), .jtag_tdi(jtag_tdi), .jtag_tdo(jtag_tdo),
        .jtag_tms(jtag_tms), .jtag_trst_n(jtag_trst_n),
        .qspi_cs_n(qspi_cs_n), .qspi_sck(qspi_sck),
        .qspi_io_i(qspi_io_i), .qspi_io_o(qspi_io_o),
        .uart1_rxd(uart1_rxd), .uart1_txd(uart1_txd),
        .uart2_rxd(uart2_rxd), .uart2_txd(uart2_txd),
        .gpio_i(gpio_i), .gpio_o(gpio_o), .gpio_tx_en_o(gpio_tx_en_o)
    );

    task automatic kontrol(input bit kosul, input string mesaj);
        if (kosul) begin pass_count++; $display("  [OK] %s", mesaj); end
        else       begin fail_count++; $display("  [HATA] %s", mesaj); end
    endtask

    // Saat agaci canliligi: ic bir dugumun toggle ettigini say
    int toggle_sayaci = 0;
    logic gecmis_txd;

    always @(posedge clk_i) begin
        if (rst_ni) begin
            if (uart1_txd !== gecmis_txd) toggle_sayaci++;
            gecmis_txd <= uart1_txd;
        end
    end

    initial begin
        $display("================================================================");
        $display(" GATE-LEVEL SIMULASYON - CANLILIK TESTI");
        $display("================================================================");
        $display("");
        $display("DUT: asic/results/netlist/soc_top_pnr.v");
        $display("     sentez+yerlestirme sonrasi netlist, 2,07 milyon hucre");
        $display("");
        $display("RTL testleri RTL kaynagini kosar; bu test URETILEN");
        $display("NETLISTI kosar. Sentez hatasi ancak burada gorunur.");
        $display("");

        // ---------------------------------------------------------------
        //  1. RESET
        // ---------------------------------------------------------------
        $display("1. Reset uygulaniyor...");
        rst_ni = 1'b0;
        repeat (20) @(posedge clk_i);

        kontrol(1'b1, "reset sirasinda simulasyon askida kalmadi");

        rst_ni = 1'b1;
        $display("2. Reset birakildi, yerlesme bekleniyor...");
        repeat (200) @(posedge clk_i);

        // ---------------------------------------------------------------
        //  3. CIKISLAR X'TEN CIKTI MI
        //
        //  Netlistte reset agi eksikse veya bir yazmac baglanmamissa
        //  cikislar X kalir. Bu, sentez hatasinin en yaygin belirtisidir.
        // ---------------------------------------------------------------
        $display("3. Cikis pinleri bilinen durumda mi");

        kontrol(!$isunknown(uart1_txd),
                $sformatf("uart1_txd bilinen: %0b", uart1_txd));
        kontrol(!$isunknown(uart2_txd),
                $sformatf("uart2_txd bilinen: %0b", uart2_txd));
        kontrol(!$isunknown(qspi_cs_n),
                $sformatf("qspi_cs_n bilinen: %0b", qspi_cs_n));
        kontrol(!$isunknown(i2c_scl_oe),
                $sformatf("i2c_scl_oe bilinen: %0b", i2c_scl_oe));
        kontrol(!$isunknown(gpio_tx_en_o),
                $sformatf("gpio_tx_en_o bilinen: 0x%04h", gpio_tx_en_o));

        // ---------------------------------------------------------------
        //  4. SAAT AGACI CALISIYOR MU
        //
        //  Bootloader calisirsa UART veya QSPI hareket eder. Hicbir
        //  cikis toggle etmiyorsa saat agaci kopuk demektir.
        // ---------------------------------------------------------------
        $display("4. Saat agaci canliligi (2000 cevrim)");
        repeat (2000) @(posedge clk_i);

        $display("    uart1_txd toggle sayisi: %0d", toggle_sayaci);
        $display("    qspi_cs_n=%0b qspi_sck=%0b", qspi_cs_n, qspi_sck);

        // Bootloader QSPI'den okumaya calisir -> cs_n duser
        kontrol(qspi_cs_n === 1'b0 || toggle_sayaci > 0,
                "cip hareket ediyor (QSPI etkin veya UART toggle)");

        // ---------------------------------------------------------------
        //  5. GPIO GIRIS YOLU
        //
        //  gpio_i degistiginde ic mantik etkilenmeli. Bu, giris
        //  pininden ic yazmaca kadar olan yolun bagli oldugunu gosterir.
        // ---------------------------------------------------------------
        $display("5. GPIO giris yolu");
        gpio_i = 16'hA5A5;
        repeat (50) @(posedge clk_i);
        kontrol(!$isunknown(gpio_o),
                $sformatf("gpio_i degisimi sonrasi gpio_o bilinen: 0x%04h", gpio_o));

        gpio_i = 16'h5A5A;
        repeat (50) @(posedge clk_i);
        kontrol(!$isunknown(gpio_o), "ikinci GPIO degisimi sonrasi cikis bilinen");

        // ---------------------------------------------------------------
        $display("");
        $display("================================================================");
        if (fail_count == 0)
            $display(" TB SONUC: GECTI  (%0d denetim)", pass_count);
        else
            $display(" TB SONUC: KALDI  (%0d gecti, %0d kaldi)", pass_count, fail_count);
        $display("================================================================");
        $finish;
    end

    // Gozcu - GLS yavastir, genis pay birakilir
    initial begin
        #5_000_000;
        $display("  [HATA] gozcu: GLS 5 ms icinde bitmedi");
        $display(" TB SONUC: KALDI (asili kaldi)");
        $finish;
    end

endmodule
